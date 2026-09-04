from __future__ import annotations

import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from app_server import (
    CODEX_EXECUTABLE_ENV,
    AppServerClient,
    AppServerError,
    codex_executable,
)
from codex_thread_manager import (
    WORKER_MODEL,
    canonical_working_directory,
    mcp,
    thread_list_params,
    thread_start_params,
    turn_start_params,
)


class FakeWriter:
    def __init__(self) -> None:
        self.messages: list[dict[str, Any]] = []

    def write(self, data: bytes) -> None:
        self.messages.append(json.loads(data))

    async def drain(self) -> None:
        await asyncio.sleep(0)


class AppServerClientTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.reader = asyncio.StreamReader()
        self.writer = FakeWriter()
        self.client = AppServerClient(self.reader, self.writer)

    async def asyncTearDown(self) -> None:
        await self.client.close()

    async def test_routes_responses_by_request_id(self) -> None:
        request = asyncio.create_task(self.client.request("thread/list", {"limit": 1}))
        await asyncio.sleep(0)
        request_id = self.writer.messages[-1]["id"]
        self.reader.feed_data(
            json.dumps({"id": request_id, "result": {"data": []}}).encode() + b"\n"
        )

        self.assertEqual(await request, {"data": []})

    async def test_converts_json_rpc_errors(self) -> None:
        request = asyncio.create_task(
            self.client.request("thread/read", {"threadId": "bad"})
        )
        await asyncio.sleep(0)
        request_id = self.writer.messages[-1]["id"]
        self.reader.feed_data(
            json.dumps(
                {
                    "id": request_id,
                    "error": {"code": -32602, "message": "bad params"},
                }
            ).encode()
            + b"\n"
        )

        with self.assertRaisesRegex(AppServerError, "bad params"):
            await request

    async def test_rejects_unsupported_server_callbacks(self) -> None:
        self.reader.feed_data(
            b'{"id":"approval-1","method":"item/commandExecution/requestApproval"}\n'
        )
        await asyncio.sleep(0)

        self.assertEqual(self.writer.messages[-1]["id"], "approval-1")
        self.assertEqual(self.writer.messages[-1]["error"]["code"], -32601)


class ContractTests(unittest.TestCase):
    def test_new_threads_are_persistent_sol_xhigh_workers(self) -> None:
        thread = thread_start_params("/tmp/worktree", False)
        turn = turn_start_params("thread-1", "implement it")

        self.assertFalse(thread["ephemeral"])
        self.assertEqual(thread["model"], "gpt-5.6-sol")
        self.assertEqual(thread["sandbox"], "workspace-write")
        self.assertEqual(turn["model"], WORKER_MODEL)
        self.assertEqual(turn["effort"], "xhigh")

    def test_working_directory_must_be_absolute_and_exist(self) -> None:
        with self.assertRaisesRegex(ValueError, "absolute"):
            canonical_working_directory("relative/worktree")

        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(
                Path(canonical_working_directory(directory)),
                Path(directory).resolve(),
            )

    def test_thread_list_uses_the_interactive_source_filter(self) -> None:
        # app-server persists our threads as source "vscode"; an explicit
        # sourceKinds=["appServer"] filter silently returned nothing.
        params = thread_list_params(50, False, None, None)
        self.assertEqual(params, {"limit": 50, "archived": False})

        with tempfile.TemporaryDirectory() as directory:
            narrowed = thread_list_params(5, True, "probe", directory)
        self.assertNotIn("sourceKinds", narrowed)
        self.assertEqual(narrowed["searchTerm"], "probe")
        self.assertEqual(Path(narrowed["cwd"]), Path(directory).resolve())

    def test_prefers_the_desktop_codex_binary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bundled = Path(directory) / "codex"
            bundled.write_text("#!/bin/sh\n")
            bundled.chmod(0o755)
            missing = str(Path(directory) / "absent" / "codex")

            self.assertEqual(
                codex_executable({}, (missing, str(bundled))), str(bundled)
            )
            self.assertEqual(codex_executable({}, (missing,)), "codex")
            self.assertEqual(
                codex_executable(
                    {CODEX_EXECUTABLE_ENV: "/opt/custom/codex"}, (str(bundled),)
                ),
                "/opt/custom/codex",
            )

    def test_registers_the_thread_lifecycle_tools(self) -> None:
        tools = mcp._tool_manager.list_tools()
        names = {tool.name for tool in tools}
        self.assertEqual(
            names,
            {
                "codex_thread_archive",
                "codex_thread_fork",
                "codex_thread_interrupt",
                "codex_thread_list",
                "codex_thread_read",
                "codex_thread_rename",
                "codex_thread_resume",
                "codex_thread_send",
                "codex_thread_start",
                "codex_thread_steer",
                "codex_thread_unarchive",
            },
        )
        for tool in tools:
            self.assertNotIn("ctx", tool.parameters["properties"])


if __name__ == "__main__":
    unittest.main()
