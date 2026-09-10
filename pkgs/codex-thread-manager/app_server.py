"""Async client for Codex app-server's JSON-lines protocol."""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from typing import Any, Protocol

CODEX_EXECUTABLE_ENV = "CODEX_THREAD_MANAGER_CODEX"

# Codex Desktop ships its own app-server binary. Preferring it keeps this
# bridge and the Desktop on one Codex version so both write the same thread
# store format; a stale Homebrew `codex` on PATH is the fallback.
DESKTOP_CODEX_CANDIDATES = (
    "/Applications/ChatGPT.app/Contents/Resources/codex",
    "/Applications/Codex.app/Contents/Resources/codex",
)


def codex_executable(
    environ: os._Environ[str] | dict[str, str] | None = None,
    candidates: tuple[str, ...] = DESKTOP_CODEX_CANDIDATES,
) -> str:
    """Pick the Codex binary: explicit override, Desktop bundle, then PATH."""
    env = os.environ if environ is None else environ
    override = env.get(CODEX_EXECUTABLE_ENV, "").strip()
    if override:
        return override
    for candidate in candidates:
        if Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return "codex"


class AsyncLineWriter(Protocol):
    def write(self, data: bytes) -> None: ...

    async def drain(self) -> None: ...


class AppServerError(RuntimeError):
    """Raised when Codex app-server cannot fulfill a request."""


class AppServerClient:
    REQUEST_TIMEOUT_SECONDS = 60

    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: AsyncLineWriter,
        process: asyncio.subprocess.Process | None = None,
    ) -> None:
        self._reader = reader
        self._writer = writer
        self._process = process
        self._next_request_id = 1
        self._pending: dict[int, asyncio.Future[dict[str, Any]]] = {}
        self._write_lock = asyncio.Lock()
        self._reader_task = asyncio.create_task(self._read_messages())

    @classmethod
    async def connect(cls, executable: str | None = None) -> AppServerClient:
        if executable is None:
            executable = codex_executable()
        try:
            process = await asyncio.create_subprocess_exec(
                executable,
                "app-server",
                "--stdio",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
            )
        except OSError as error:
            raise AppServerError(
                f"failed to start {executable} app-server: {error}"
            ) from error

        if process.stdin is None or process.stdout is None:
            process.kill()
            await process.wait()
            raise AppServerError("codex app-server did not provide stdio pipes")

        client = cls(process.stdout, process.stdin, process)
        try:
            await client.initialize()
        except BaseException:
            await client.close()
            raise
        return client

    async def initialize(self) -> None:
        await self.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "codex-thread-manager",
                    "title": "Claude Codex thread manager",
                    "version": "0.1.0",
                },
                "capabilities": {"experimentalApi": False},
            },
        )
        await self.notify("initialized")

    async def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request_id = self._next_request_id
        self._next_request_id += 1
        response = asyncio.get_running_loop().create_future()
        self._pending[request_id] = response

        try:
            await self._write_message(
                {"id": request_id, "method": method, "params": params}
            )
            return await asyncio.wait_for(
                response, timeout=self.REQUEST_TIMEOUT_SECONDS
            )
        except TimeoutError as error:
            raise AppServerError(
                f"codex app-server timed out handling {method}"
            ) from error
        finally:
            self._pending.pop(request_id, None)

    async def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        message: dict[str, Any] = {"method": method}
        if params is not None:
            message["params"] = params
        await self._write_message(message)

    async def close(self) -> None:
        process = self._process
        self._process = None
        if process is not None and process.returncode is None:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=5)
            except TimeoutError:
                process.kill()
                await process.wait()

        self._reader_task.cancel()
        await asyncio.gather(self._reader_task, return_exceptions=True)
        self._fail_pending("codex app-server closed")

    async def _write_message(self, message: dict[str, Any]) -> None:
        encoded = json.dumps(message, separators=(",", ":")).encode() + b"\n"
        async with self._write_lock:
            try:
                self._writer.write(encoded)
                await self._writer.drain()
            except (BrokenPipeError, ConnectionError, OSError) as error:
                raise AppServerError("codex app-server input stream closed") from error

    async def _read_messages(self) -> None:
        try:
            while line := await self._reader.readline():
                try:
                    message = json.loads(line)
                except json.JSONDecodeError as error:
                    self._fail_pending(
                        f"codex app-server emitted invalid JSON: {error}"
                    )
                    return
                if not isinstance(message, dict):
                    self._fail_pending("codex app-server emitted a non-object message")
                    return

                if "method" in message:
                    if "id" in message:
                        await self._write_message(
                            {
                                "id": message["id"],
                                "error": {
                                    "code": -32601,
                                    "message": (
                                        "codex-thread-manager does not support "
                                        "app-server callbacks"
                                    ),
                                },
                            }
                        )
                    continue

                request_id = message.get("id")
                if not isinstance(request_id, int):
                    continue
                response = self._pending.get(request_id)
                if response is None or response.done():
                    continue

                result = message.get("result")
                if isinstance(result, dict):
                    response.set_result(result)
                elif "error" in message:
                    response.set_exception(
                        AppServerError(f"codex app-server error: {message['error']}")
                    )
                else:
                    response.set_exception(
                        AppServerError(
                            "codex app-server response omitted result and error"
                        )
                    )
        except asyncio.CancelledError:
            raise
        except (ConnectionError, OSError) as error:
            self._fail_pending(f"codex app-server output failed: {error}")
        else:
            self._fail_pending("codex app-server exited")

    def _fail_pending(self, message: str) -> None:
        for response in self._pending.values():
            if not response.done():
                response.set_exception(AppServerError(message))
