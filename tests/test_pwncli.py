import sys
import time

from pwnomcp.pwnpipe import PwnPipe
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
