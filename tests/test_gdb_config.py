from pwnomcp.tools.backends.gdb import GdbController


def _initialize_with_commands(monkeypatch, value=None):
    if value is None:
        monkeypatch.delenv("PWNO_GDB_DEBUGINFOD", raising=False)
    else:
        monkeypatch.setenv("PWNO_GDB_DEBUGINFOD", value)

    controller = object.__new__(GdbController)
    controller._initialized = False
    console_commands = []
    controller.execute_mi_command = lambda command: {"command": command}
    controller.execute_command = lambda command: console_commands.append(command) or {}

    result = controller.initialize()
    return result, console_commands


def test_gdb_initialization_disables_debuginfod_by_default(monkeypatch):
    result, commands = _initialize_with_commands(monkeypatch)

    assert result["status"] == "initialized"
    assert commands == ["set debuginfod enabled off"]


def test_gdb_initialization_uses_configured_debuginfod_mode(monkeypatch):
    _, commands = _initialize_with_commands(monkeypatch, "ON")

    assert commands == ["set debuginfod enabled on"]


def test_gdb_initialization_rejects_invalid_debuginfod_mode(monkeypatch):
    _, commands = _initialize_with_commands(monkeypatch, "sometimes")

    assert commands == ["set debuginfod enabled off"]
