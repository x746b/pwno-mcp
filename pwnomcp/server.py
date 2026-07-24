import logging
from typing import Optional

from fastmcp import FastMCP

from pwnomcp import __version__
from pwnomcp.http.health import register_health_routes
from pwnomcp.lifespan import create_lifespan
from pwnomcp.services import AppServices
from pwnomcp.tools import register_all_tools
from pwnomcp.utils.paths import DEFAULT_WORKSPACE

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)


def build_server_instructions(services: Optional[AppServices] = None) -> str:
    runtime_paths = getattr(services, "runtime_paths", None)
    workspace_root = getattr(runtime_paths, "workspace_root", DEFAULT_WORKSPACE)
    return f"""\
Use an explicit session_id and call create_debug_session before debugger or pwncli
tools. The configured workspace root is {workspace_root}; relative paths resolve
there, and get_session_info reports the active workspace_root and Python interpreter.
Use set_file plus run for the target binary, run_command for build/helper commands,
and pwncli for an interactive exploit driver. sendinput does not append a newline.
For arbitrary bytes, send data_b64 and decode current_output_b64/output_b64 instead
of relying on display text. pwncli startup readiness is not process completion: drain
checkoutput and checkevents, polling until exit_code is non-null or alive is false.
Both output and event calls drain the data they return. Persist scripts in the
workspace only when the user explicitly asks; inline pwncli scripts belong in the
session runtime directory."""


def create_mcp(services: Optional[AppServices] = None) -> FastMCP:
    mcp = FastMCP(
        name="pwno-mcp",
        version=__version__,
        instructions=build_server_instructions(services),
        lifespan=create_lifespan(services=services),
    )
    register_health_routes(mcp)
    register_all_tools(mcp)
    return mcp


mcp = create_mcp()
