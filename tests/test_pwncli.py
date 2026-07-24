import asyncio
import base64
import sys
import threading
import time
from types import SimpleNamespace

import pytest
from fastmcp import Client

from pwnomcp.pwnpipe import PwnPipe
from pwnomcp.server import create_mcp
from pwnomcp.tools import common
from pwnomcp.tools.pwncli import build_driver_command, missing_driver_modules


def test_build_driver_command_uses_server_python_without_shell():
    command = build_driver_command(
        "/tmp/session/exp.py",
        "/workspace/chal",
        "--flag 'two words'; touch /tmp/unexpected",
    )

    assert command == [
        sys.executable,
        "/tmp/session/exp.py",
        "debug",
        "/workspace/chal",
        "--flag",
        "two words;",
        "touch",
        "/tmp/unexpected",
    ]


def test_driver_command_uses_environment_with_locked_modules(tmp_path):
    script = tmp_path / "driver.py"
    script.write_text(
        "import pwn, pwncli; print('driver-imports-ok', flush=True)",
        encoding="utf-8",
    )
    assert missing_driver_modules() == []

    pipe = PwnPipe(build_driver_command(str(script), "/workspace/chal"), cwd=tmp_path)
    try:
        deadline = time.monotonic() + 2
        while pipe.is_alive() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert not pipe.is_alive()
        assert pipe.get_exit_code() == 0
        assert b"driver-imports-ok" in pipe.release_bytes()
    finally:
        pipe.kill()


class _SessionRegistry:
    def __init__(self, session):
        self.session = session

    def get_session(self, session_id):
        if session_id == self.session.session_id:
            return self.session
        return None


@pytest.mark.asyncio
async def test_mcp_pwncli_binary_round_trip_and_exit_event(tmp_path, monkeypatch):
    session_id = "binary-io"
    runtime_dir = tmp_path / "runtime"
    binary = tmp_path / "target"
    binary.write_bytes(b"")
    session = SimpleNamespace(
        session_id=session_id,
        runtime_dir=str(runtime_dir),
        state=SimpleNamespace(binary_path=None),
        driver_pid=None,
    )
    services = SimpleNamespace(
        session_registry=_SessionRegistry(session),
        default_session_id=session_id,
        pwnpipe_sessions={},
        pwnpipe_lock=threading.Lock(),
    )
    monkeypatch.setattr(common, "DEFAULT_WORKSPACE", str(tmp_path))

    script = """\
import os
import sys

print("READY", flush=True)
payload = os.read(sys.stdin.fileno(), 3)
os.write(sys.stdout.fileno(), payload)
"""
    payload = b"\xff\x00A"
    output = bytearray()
    events = []

    try:
        async with Client(create_mcp(services)) as client:
            started = await client.call_tool(
                "pwncli",
                {
                    "file": script,
                    "session_id": session_id,
                    "binary_path": str(binary),
                    "wait_timeout": 1.0,
                },
            )
            assert started.data["success"] is True
            assert (
                base64.b64decode(started.data["io"]["current_output_b64"]) == b"READY\n"
            )

            sent = await client.call_tool(
                "sendinput",
                {
                    "session_id": session_id,
                    "data_b64": base64.b64encode(payload).decode("ascii"),
                },
            )
            assert sent.data["success"] is True
            assert sent.data["bytes_sent"] == len(payload)

            deadline = time.monotonic() + 2
            exit_code = None
            while time.monotonic() < deadline:
                checked = await client.call_tool(
                    "checkoutput", {"session_id": session_id}
                )
                output.extend(base64.b64decode(checked.data["output_b64"]))

                checked_events = await client.call_tool(
                    "checkevents", {"session_id": session_id}
                )
                events.extend(checked_events.data["events"])
                exit_code = checked_events.data["exit_code"]
                if exit_code is not None:
                    break
                await asyncio.sleep(0.01)

            final_output = await client.call_tool(
                "checkoutput", {"session_id": session_id}
            )
            output.extend(base64.b64decode(final_output.data["output_b64"]))
            final_events = await client.call_tool(
                "checkevents", {"session_id": session_id}
            )
            events.extend(final_events.data["events"])
            if exit_code is None:
                exit_code = final_events.data["exit_code"]

            assert bytes(output) == payload
            assert exit_code == 0
            assert any(event == {"type": "exit", "code": 0} for event in events)
            assert any(
                event.get("type") == "out"
                and base64.b64decode(event["data_b64"]) == payload
                for event in events
            )

            stopped = await client.call_tool("pwncli_stop", {"session_id": session_id})
            assert stopped.data["success"] is True
    finally:
        for pipe in services.pwnpipe_sessions.values():
            pipe.kill()
