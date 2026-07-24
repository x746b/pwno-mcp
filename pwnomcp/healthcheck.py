"""Deployment health check for a running pwno-mcp server."""

from __future__ import annotations

import argparse
import asyncio
import importlib
import json
import os
import sys
from typing import Any, Sequence

from fastmcp import Client

REQUIRED_MODULES = ("pwn", "pwncli")
REQUIRED_TOOLS = {
    "create_debug_session",
    "get_session_info",
    "pwncli",
    "sendinput",
    "checkoutput",
}


def validate_runtime() -> None:
    """Raise when exploit-driver dependencies cannot be imported."""
    os.environ.setdefault("PWNLIB_NOTERM", "1")
    failures = []
    for module in REQUIRED_MODULES:
        try:
            importlib.import_module(module)
        except Exception as exc:
            failures.append(f"{module} ({exc})")
    if failures:
        raise RuntimeError(f"runtime import failures: {', '.join(failures)}")


async def check_server(url: str) -> dict[str, Any]:
    """Verify protocol negotiation, required tools, and interpreter identity."""
    async with Client(url, timeout=15) as client:
        tools = await client.list_tools()
        tool_names = {tool.name for tool in tools}
        missing_tools = sorted(REQUIRED_TOOLS - tool_names)
        if missing_tools:
            raise RuntimeError(f"missing MCP tools: {', '.join(missing_tools)}")

        result = await client.call_tool("get_session_info", {"session_id": "default"})
        if not isinstance(result.data, dict):
            raise RuntimeError("get_session_info returned no structured data")
        server_python = result.data.get("python_executable")
        if not isinstance(server_python, str):
            raise RuntimeError("server did not report its Python interpreter")
        if os.path.realpath(server_python) != os.path.realpath(sys.executable):
            raise RuntimeError(
                f"interpreter mismatch: server={server_python}, check={sys.executable}"
            )

        return {
            "status": "ok",
            "url": url,
            "python_executable": server_python,
            "tool_count": len(tool_names),
        }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--url", default="http://127.0.0.1:5500/mcp", help="MCP endpoint URL"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        validate_runtime()
        result = asyncio.run(check_server(args.url))
    except Exception as exc:
        print(json.dumps({"status": "error", "error": str(exc)}), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
