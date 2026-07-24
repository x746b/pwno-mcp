import pytest

from pwnomcp import healthcheck


def test_validate_runtime_imports_driver_modules(monkeypatch):
    imported = []
    monkeypatch.delenv("PWNLIB_NOTERM", raising=False)
    monkeypatch.setattr(
        healthcheck.importlib,
        "import_module",
        lambda module: imported.append(module),
    )

    healthcheck.validate_runtime()

    assert imported == list(healthcheck.REQUIRED_MODULES)
    assert healthcheck.os.environ["PWNLIB_NOTERM"] == "1"


def test_validate_runtime_reports_import_failures(monkeypatch):
    def fail_pwncli(module):
        if module == "pwncli":
            raise ImportError("broken dependency")

    monkeypatch.setattr(healthcheck.importlib, "import_module", fail_pwncli)

    with pytest.raises(RuntimeError, match=r"pwncli \(broken dependency\)"):
        healthcheck.validate_runtime()
