from importlib.metadata import version
from typing import cast

from pwnomcp import __version__
from pwnomcp.http.attach import create_attach_app
from pwnomcp.services import AppServices


def test_package_version_matches_release_metadata():
    assert __version__ == "0.3.0"
    assert version("pwno-mcp") == __version__


def test_attach_api_uses_release_version():
    app = create_attach_app(cast(AppServices, None))

    assert app.version == __version__
