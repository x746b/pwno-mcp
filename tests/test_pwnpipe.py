import base64
import sys
import time

from pwnomcp.pwnpipe import PwnPipe


def wait_for_exit(pipe: PwnPipe, timeout: float = 2.0) -> None:
    deadline = time.monotonic() + timeout
    while pipe.is_alive() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert not pipe.is_alive()


def test_binary_input_and_prompt_without_newline_round_trip():
    code = (
        "import sys; "
        "sys.stdout.buffer.write(b'> '); sys.stdout.buffer.flush(); "
        "data = sys.stdin.buffer.read(3); "
        "sys.stdout.buffer.write(data); sys.stdout.buffer.flush()"
    )
    pipe = PwnPipe([sys.executable, "-u", "-c", code])

    try:
        startup = pipe.wait_ready(timeout=1)
        assert startup["ready"] is True
        assert startup["reason"] == "output"
        assert pipe.release_bytes() == b"> "

        payload = b"\xff\x00A"
        assert pipe.send(payload) is True
        wait_for_exit(pipe)
        assert pipe.release_bytes() == payload

        output_events = [
            event for event in pipe.release_events() if event["type"] == "out"
        ]
        assert base64.b64decode(output_events[-1]["data_b64"]) == payload
    finally:
        pipe.kill()


def test_attach_marker_is_parsed_and_not_returned_as_output():
    marker = 'PWNCLI_ATTACH_RESULT:{"successful": true, "pid": 123}\n'
    code = f"import sys, time; sys.stdout.write({marker!r}); sys.stdout.flush(); time.sleep(1)"
    pipe = PwnPipe([sys.executable, "-u", "-c", code])

    try:
        startup = pipe.wait_ready(timeout=1)
        assert startup["ready"] is True
        assert startup["reason"] == "attached"
        assert pipe.get_attach_result() == {"successful": True, "pid": 123}
        assert pipe.release_bytes() == b""
    finally:
        pipe.kill()


def test_unsuccessful_attach_marker_is_not_ready():
    marker = 'PWNCLI_ATTACH_RESULT:{"successful": false}\n'
    code = f"import sys, time; sys.stdout.write({marker!r}); sys.stdout.flush(); time.sleep(1)"
    pipe = PwnPipe([sys.executable, "-u", "-c", code])

    try:
        startup = pipe.wait_ready(timeout=1)
        assert startup["ready"] is False
        assert startup["reason"] == "attached"
    finally:
        pipe.kill()


def test_output_then_nonzero_exit_is_not_reported_ready():
    code = (
        "import sys; sys.stderr.write('boom'); sys.stderr.flush(); raise SystemExit(7)"
    )
    pipe = PwnPipe([sys.executable, "-u", "-c", code])

    try:
        startup = pipe.wait_ready(timeout=1)
        assert startup["ready"] is False
        assert startup["reason"] == "exited"
        assert startup["exit_code"] == 7
        assert pipe.release_bytes() == b"boom"
    finally:
        pipe.kill()
