"""State management for Pwno MCP"""

from .session import SessionState

__all__ = ["DebugSession", "DebugSessionRegistry", "SessionState"]


def __getattr__(name: str):
    if name in {"DebugSession", "DebugSessionRegistry"}:
        from .registry import DebugSession, DebugSessionRegistry

        return {
            "DebugSession": DebugSession,
            "DebugSessionRegistry": DebugSessionRegistry,
        }[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
