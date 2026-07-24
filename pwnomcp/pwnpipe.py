import base64
import json
import os
import queue
import signal
import subprocess
import threading
import time
from typing import Any, Dict, List, Optional, Sequence


class PwnPipe:
    """Binary-safe subprocess I/O pipeline with queued output and events."""

    _ATTACH_PREFIX = b"PWNCLI_ATTACH_RESULT:"
    _IPC_PREFIX = b"PWNO_IPC:"
    _MARKER_PREFIXES = (_ATTACH_PREFIX, _IPC_PREFIX)

    def __init__(
        self,
        command: Sequence[str],
        cwd: Optional[str] = None,
        env: Optional[Dict[str, str]] = None,
    ):
        self.command = list(command)
        self.cwd = cwd
        self.env = env or {}
        env_full = os.environ.copy()
        env_full.update(self.env)

        self.proc = subprocess.Popen(
            self.command,
            cwd=self.cwd,
            shell=False,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            env=env_full,
            start_new_session=True,
        )
        self._q: "queue.Queue[bytes]" = queue.Queue()
        self._events: "queue.Queue[Dict[str, Any]]" = queue.Queue()
        self._alive = True
        self._lock = threading.Lock()
        self._attach_result = None
        self._exit_code: Optional[int] = None

        self._attach_event = threading.Event()
        self._output_event = threading.Event()
        self._exit_event = threading.Event()
        self._activity_event = threading.Event()

        assert self.proc.stdout is not None
        assert self.proc.stderr is not None
        self._t_out = threading.Thread(
            target=self._reader, args=(self.proc.stdout, "out"), daemon=True
        )
        self._t_err = threading.Thread(
            target=self._reader, args=(self.proc.stderr, "err"), daemon=True
        )
        self._t_out.start()
        self._t_err.start()

        self._t_wait = threading.Thread(target=self._waiter, daemon=True)
        self._t_wait.start()

    def _emit_output(self, data: bytes, stream: str) -> None:
        if not data:
            return
        self._q.put(data)
        self._events.put(
            {
                "type": stream,
                "data": data.decode("utf-8", errors="replace"),
                "data_b64": base64.b64encode(data).decode("ascii"),
            }
        )
        self._output_event.set()
        self._activity_event.set()

    def _handle_marker(self, line: bytes) -> bool:
        stripped = line.rstrip(b"\r\n")
        if stripped.startswith(self._ATTACH_PREFIX):
            payload = stripped[len(self._ATTACH_PREFIX) :]
            try:
                result = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                return False
            with self._lock:
                self._attach_result = result
            self._attach_event.set()
            self._activity_event.set()
            self._events.put(
                {
                    "type": "attached",
                    "ok": bool(
                        result.get("successful") if isinstance(result, dict) else False
                    ),
                    "result": result,
                }
            )
            return True

        if stripped.startswith(self._IPC_PREFIX):
            payload = stripped[len(self._IPC_PREFIX) :]
            try:
                event = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                return False
            if not isinstance(event, dict):
                return False
            self._events.put(event)
            self._output_event.set()
            self._activity_event.set()
            return True

        return False

    def _reader(self, pipe, stream: str) -> None:
        pending = bytearray()
        at_line_start = True

        while True:
            chunk = os.read(pipe.fileno(), 4096)
            if not chunk:
                break
            pending.extend(chunk)

            while pending:
                current = bytes(pending)
                if at_line_start:
                    if any(
                        prefix.startswith(current) for prefix in self._MARKER_PREFIXES
                    ):
                        break
                    if any(
                        current.startswith(prefix) for prefix in self._MARKER_PREFIXES
                    ):
                        newline = pending.find(b"\n")
                        if newline == -1:
                            break
                        line = bytes(pending[: newline + 1])
                        del pending[: newline + 1]
                        if not self._handle_marker(line):
                            self._emit_output(line, stream)
                        at_line_start = True
                        continue

                newline = pending.find(b"\n")
                if newline == -1:
                    data = bytes(pending)
                    pending.clear()
                    self._emit_output(data, stream)
                    at_line_start = False
                else:
                    data = bytes(pending[: newline + 1])
                    del pending[: newline + 1]
                    self._emit_output(data, stream)
                    at_line_start = True

        if pending:
            data = bytes(pending)
            if not self._handle_marker(data):
                self._emit_output(data, stream)
        pipe.close()

    def _waiter(self) -> None:
        self.proc.wait()
        with self._lock:
            self._alive = False
            self._exit_code = self.proc.returncode
        self._exit_event.set()
        self._activity_event.set()
        self._events.put({"type": "exit", "code": self._exit_code})

    def is_alive(self) -> bool:
        alive = self.proc.poll() is None
        if not alive:
            with self._lock:
                self._alive = False
                self._exit_code = self.proc.returncode
        return alive

    def send(self, data: bytes) -> bool:
        if not self.is_alive():
            return False
        try:
            assert self.proc.stdin is not None
            self.proc.stdin.write(data)
            self.proc.stdin.flush()
            return True
        except (BrokenPipeError, OSError):
            return False

    def release_bytes(self) -> bytes:
        chunks: List[bytes] = []
        try:
            while True:
                chunks.append(self._q.get_nowait())
        except queue.Empty:
            pass
        return b"".join(chunks)

    def release(self) -> str:
        """Return buffered output as display-safe text for compatibility."""
        return self.release_bytes().decode("utf-8", errors="replace")

    def release_events(self) -> List[Dict[str, Any]]:
        events: List[Dict[str, Any]] = []
        try:
            while True:
                events.append(self._events.get_nowait())
        except queue.Empty:
            pass
        return events

    def get_attach_result(self):
        with self._lock:
            return self._attach_result

    def get_exit_code(self) -> Optional[int]:
        self.is_alive()
        with self._lock:
            return self._exit_code

    def get_pid(self) -> Optional[int]:
        return self.proc.pid

    def wait_ready(self, timeout: float = 3.0) -> Dict[str, Any]:
        start = time.monotonic()
        if not self._activity_event.is_set():
            self._activity_event.wait(timeout)

        # Give short-lived failures time to publish their exit status.
        if self._output_event.is_set() and not self._attach_event.is_set():
            elapsed = time.monotonic() - start
            self._exit_event.wait(max(0.0, min(0.05, timeout - elapsed)))

        if self._attach_event.is_set():
            reason = "attached"
        elif self._exit_event.is_set() or not self.is_alive():
            reason = "exited"
        elif self._output_event.is_set():
            reason = "output"
        elif self._activity_event.is_set():
            reason = "activity"
        else:
            reason = "timeout"

        alive = self.is_alive()
        attach_result = self.get_attach_result()
        attach_ok = bool(
            attach_result.get("successful")
            if isinstance(attach_result, dict)
            else False
        )
        ready = (reason == "attached" and attach_ok) or (
            reason in {"output", "activity"} and alive
        )
        wait_ms = int((time.monotonic() - start) * 1000)
        return {
            "ready": ready,
            "reason": reason,
            "wait_ms": wait_ms,
            "alive": alive,
            "exit_code": self.get_exit_code(),
        }

    def kill(self) -> None:
        try:
            if self.proc.poll() is None:
                try:
                    os.killpg(self.proc.pid, signal.SIGTERM)
                    self.proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                    self.proc.wait(timeout=1.0)
                except ProcessLookupError:
                    pass
        finally:
            with self._lock:
                self._alive = False
                self._exit_code = self.proc.poll()
