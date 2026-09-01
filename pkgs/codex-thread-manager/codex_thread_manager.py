"""MCP tools for persistent Codex App thread orchestration."""

import asyncio
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from app_server import AppServerClient
from mcp.server.fastmcp import Context, FastMCP

WORKER_MODEL = "gpt-5.6-sol"
WORKER_EFFORT = "xhigh"


@dataclass(frozen=True)
class AppContext:
    client: AppServerClient


@asynccontextmanager
async def lifespan(_: FastMCP) -> AsyncIterator[AppContext]:
    client = await AppServerClient.connect()
    try:
        yield AppContext(client)
    finally:
        await client.close()


mcp = FastMCP(
    "codex-threads",
    instructions=(
        "Manage persistent Codex App threads. New implementation turns always "
        "use gpt-5.6-sol with xhigh reasoning."
    ),
    lifespan=lifespan,
)


def client_from(ctx: Context) -> AppServerClient:
    state = ctx.request_context.lifespan_context
    if not isinstance(state, AppContext):
        raise TypeError("codex-threads lifespan is unavailable")
    return state.client


def require_nonempty(value: str, name: str) -> None:
    if not value.strip():
        raise ValueError(f"{name} must not be empty")


def canonical_working_directory(cwd: str) -> str:
    path = Path(cwd)
    if not path.is_absolute():
        raise ValueError("cwd must be an absolute path")
    try:
        canonical = path.resolve(strict=True)
    except OSError as error:
        raise ValueError(f"cwd does not resolve: {error}") from error
    if not canonical.is_dir():
        raise ValueError("cwd must resolve to a directory")
    return str(canonical)


def sandbox(read_only: bool) -> str:
    return "read-only" if read_only else "workspace-write"


def text_input(prompt: str) -> list[dict[str, str]]:
    return [{"type": "text", "text": prompt}]


def thread_start_params(cwd: str, read_only: bool) -> dict[str, Any]:
    return {
        "cwd": cwd,
        "model": WORKER_MODEL,
        "sandbox": sandbox(read_only),
        "approvalPolicy": "on-request",
        "approvalsReviewer": "auto_review",
        "ephemeral": False,
        "serviceName": "claude-code",
    }


def thread_resume_params(thread_id: str, read_only: bool) -> dict[str, Any]:
    return {
        "threadId": thread_id,
        "model": WORKER_MODEL,
        "sandbox": sandbox(read_only),
        "approvalPolicy": "on-request",
        "approvalsReviewer": "auto_review",
        "excludeTurns": True,
    }


def thread_fork_params(thread_id: str, cwd: str, read_only: bool) -> dict[str, Any]:
    return {
        "threadId": thread_id,
        "cwd": cwd,
        "model": WORKER_MODEL,
        "sandbox": sandbox(read_only),
        "approvalPolicy": "on-request",
        "approvalsReviewer": "auto_review",
        "ephemeral": False,
    }


def turn_start_params(thread_id: str, prompt: str) -> dict[str, Any]:
    return {
        "threadId": thread_id,
        "input": text_input(prompt),
        "model": WORKER_MODEL,
        "effort": WORKER_EFFORT,
    }


def thread_id_from(result: dict[str, Any]) -> str:
    thread = result.get("thread")
    if not isinstance(thread, dict) or not isinstance(thread.get("id"), str):
        raise TypeError("app-server response omitted thread.id")
    return thread["id"]


async def resume(
    client: AppServerClient, thread_id: str, read_only: bool
) -> dict[str, Any]:
    require_nonempty(thread_id, "thread_id")
    return await client.request(
        "thread/resume", thread_resume_params(thread_id, read_only)
    )


@mcp.tool()
async def codex_thread_start(
    cwd: str,
    prompt: str,
    title: str,
    ctx: Context,
    read_only: bool = False,
) -> dict[str, Any]:
    """Create a persistent Codex thread and start a Sol xhigh turn."""
    canonical_cwd = canonical_working_directory(cwd)
    require_nonempty(prompt, "prompt")
    require_nonempty(title, "title")
    client = client_from(ctx)

    started = await client.request(
        "thread/start", thread_start_params(canonical_cwd, read_only)
    )
    thread_id = thread_id_from(started)
    await client.request("thread/name/set", {"threadId": thread_id, "name": title})
    turn = await client.request("turn/start", turn_start_params(thread_id, prompt))
    return {"thread": started["thread"], "turn": turn.get("turn")}


@mcp.tool()
async def codex_thread_list(
    ctx: Context,
    limit: int = 50,
    archived: bool = False,
    search_term: str | None = None,
) -> dict[str, Any]:
    """List persistent Codex threads created through app-server."""
    if not 1 <= limit <= 100:
        raise ValueError("limit must be between 1 and 100")
    return await client_from(ctx).request(
        "thread/list",
        {
            "limit": limit,
            "archived": archived,
            "searchTerm": search_term,
            "sourceKinds": ["appServer"],
        },
    )


@mcp.tool()
async def codex_thread_read(
    thread_id: str, ctx: Context, include_turns: bool = True
) -> dict[str, Any]:
    """Read a Codex thread, optionally including turns and items."""
    require_nonempty(thread_id, "thread_id")
    return await client_from(ctx).request(
        "thread/read",
        {"threadId": thread_id, "includeTurns": include_turns},
    )


@mcp.tool()
async def codex_thread_resume(thread_id: str, ctx: Context) -> dict[str, Any]:
    """Resume a persisted Codex thread in this app-server process."""
    return await resume(client_from(ctx), thread_id, False)


@mcp.tool()
async def codex_thread_fork(
    thread_id: str,
    cwd: str,
    title: str,
    ctx: Context,
    read_only: bool = False,
) -> dict[str, Any]:
    """Fork a Codex thread into an existing isolated worktree."""
    require_nonempty(thread_id, "thread_id")
    require_nonempty(title, "title")
    canonical_cwd = canonical_working_directory(cwd)
    client = client_from(ctx)

    forked = await client.request(
        "thread/fork",
        thread_fork_params(thread_id, canonical_cwd, read_only),
    )
    forked_id = thread_id_from(forked)
    await client.request("thread/name/set", {"threadId": forked_id, "name": title})
    return forked


@mcp.tool()
async def codex_thread_send(
    thread_id: str,
    prompt: str,
    ctx: Context,
    read_only: bool = False,
) -> dict[str, Any]:
    """Resume a Codex thread and start a new Sol xhigh turn."""
    require_nonempty(prompt, "prompt")
    client = client_from(ctx)
    await resume(client, thread_id, read_only)
    return await client.request("turn/start", turn_start_params(thread_id, prompt))


@mcp.tool()
async def codex_thread_steer(
    thread_id: str,
    expected_turn_id: str,
    prompt: str,
    ctx: Context,
) -> dict[str, Any]:
    """Steer the active Codex turn, guarded by its expected turn ID."""
    require_nonempty(thread_id, "thread_id")
    require_nonempty(expected_turn_id, "expected_turn_id")
    require_nonempty(prompt, "prompt")
    return await client_from(ctx).request(
        "turn/steer",
        {
            "threadId": thread_id,
            "expectedTurnId": expected_turn_id,
            "input": text_input(prompt),
        },
    )


@mcp.tool()
async def codex_thread_interrupt(
    thread_id: str, turn_id: str, ctx: Context
) -> dict[str, Any]:
    """Interrupt an active Codex turn."""
    require_nonempty(thread_id, "thread_id")
    require_nonempty(turn_id, "turn_id")
    return await client_from(ctx).request(
        "turn/interrupt", {"threadId": thread_id, "turnId": turn_id}
    )


@mcp.tool()
async def codex_thread_rename(
    thread_id: str, name: str, ctx: Context
) -> dict[str, Any]:
    """Set the user-facing name of a Codex thread."""
    require_nonempty(thread_id, "thread_id")
    require_nonempty(name, "name")
    return await client_from(ctx).request(
        "thread/name/set", {"threadId": thread_id, "name": name}
    )


@mcp.tool()
async def codex_thread_archive(thread_id: str, ctx: Context) -> dict[str, Any]:
    """Archive a finished Codex thread."""
    require_nonempty(thread_id, "thread_id")
    return await client_from(ctx).request("thread/archive", {"threadId": thread_id})


@mcp.tool()
async def codex_thread_unarchive(thread_id: str, ctx: Context) -> dict[str, Any]:
    """Restore an archived Codex thread."""
    require_nonempty(thread_id, "thread_id")
    return await client_from(ctx).request("thread/unarchive", {"threadId": thread_id})


async def check() -> None:
    client = await AppServerClient.connect()
    try:
        await client.request("thread/list", {"limit": 1, "sourceKinds": ["appServer"]})
    finally:
        await client.close()


def main() -> None:
    if sys.argv[1:] == ["--check"]:
        asyncio.run(check())
        print("Codex app-server connection succeeded.")
        return
    if sys.argv[1:]:
        raise SystemExit("usage: codex-thread-manager [--check]")
    mcp.run()


if __name__ == "__main__":
    main()
