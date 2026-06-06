"""FastAPI bridge + MCP client.

Recibe tool calls HTTP (del LLM/MCP server) y las reenvía al Godot MCPReceiver
vía TCP JSON-RPC 2.0 en localhost:9876.

Endpoints (HTTP):
  POST /tools/call
    headers: X-Auth-Token: <BRIDGE_AUTH_TOKEN> (if BRIDGE_AUTH_TOKEN env set)
    body: {"method": "ping" | "grant_skill_points" | ...,
           "params": {...},
           "id": 1}
    response: JSON-RPC response

  GET /health
    response: {"status": "ok", "godot_connected": true/false}

Env:
  BRIDGE_HOST (default 0.0.0.0)
  BRIDGE_PORT (default 8000)
  BRIDGE_AUTH_TOKEN  -- if set, /tools/call requires X-Auth-Token header
  BRIDGE_RATE_LIMIT  -- max requests per minute per IP (default 120, 0 = off)
  BRIDGE_LOG_LEVEL   -- "info" (default) or "debug"

Uso:
  uvicorn bridge:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import json
import os
import socket
import threading
import time
from collections import defaultdict, deque
from typing import Any, Deque, Optional

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

GODOT_HOST = "127.0.0.1"
GODOT_PORT = 9876
CONNECT_TIMEOUT = 2.0
RECV_TIMEOUT = 5.0

BRIDGE_HOST = os.environ.get("BRIDGE_HOST", "0.0.0.0")
BRIDGE_PORT = int(os.environ.get("BRIDGE_PORT", "8000"))
AUTH_TOKEN = os.environ.get("BRIDGE_AUTH_TOKEN", "").strip()
RATE_LIMIT = int(os.environ.get("BRIDGE_RATE_LIMIT", "120"))
LOG_LEVEL = os.environ.get("BRIDGE_LOG_LEVEL", "info").lower()

app = FastAPI(title="MCP Souls Game — Bridge", version="0.2.0")


class ToolCall(BaseModel):
    method: str
    params: dict[str, Any] = {}
    id: Optional[Any] = 1


_lock = threading.Lock()
_last_conn: Optional[socket.socket] = None
_last_conn_time: float = 0.0
CONN_TTL = 30.0  # Reconnect every 30s to avoid stale sockets

# Rate limiter: per-IP sliding window
_rate_lock = threading.Lock()
_rate_buckets: dict[str, Deque[float]] = defaultdict(deque)


def _log(level: str, msg: str) -> None:
    if LOG_LEVEL == "debug" or level in ("warn", "error"):
        print(f"[bridge][{level}] {msg}", flush=True)


def _check_rate(ip: str) -> bool:
    """Sliding-window rate limiter. Returns True if OK, False if over limit."""
    if RATE_LIMIT <= 0:
        return True
    now = time.time()
    with _rate_lock:
        bucket = _rate_buckets[ip]
        # Drop entries older than 60s
        cutoff = now - 60.0
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= RATE_LIMIT:
            return False
        bucket.append(now)
        return True


def _check_auth(request: Request) -> None:
    if not AUTH_TOKEN:
        return  # auth disabled
    token = request.headers.get("X-Auth-Token", "")
    if token != AUTH_TOKEN:
        _log("warn", f"auth rejected for {request.client.host if request.client else '?'}")
        raise HTTPException(status_code=401, detail="invalid or missing X-Auth-Token")


def _get_conn() -> socket.socket:
    """Devuelve una conexión TCP al MCPReceiver de Godot. Crea una nueva si la anterior expiró."""
    global _last_conn, _last_conn_time
    with _lock:
        now = time.time()
        if _last_conn is not None and (now - _last_conn_time) < CONN_TTL:
            try:
                _last_conn.sendall(b"")
                return _last_conn
            except OSError:
                try:
                    _last_conn.close()
                except Exception:
                    pass
                _last_conn = None
        # Nueva conexión
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(CONNECT_TIMEOUT)
        s.connect((GODOT_HOST, GODOT_PORT))
        s.settimeout(RECV_TIMEOUT)
        _last_conn = s
        _last_conn_time = now
        return s


def _call_godot(method: str, params: dict, id_v: Any) -> dict:
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": id_v}
    try:
        conn = _get_conn()
    except (ConnectionRefusedError, socket.timeout, OSError) as e:
        raise HTTPException(status_code=503, detail=f"godot not reachable: {e}")
    try:
        conn.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        # Lee una línea
        buf = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                line, _, _ = buf.partition(b"\n")
                return json.loads(line.decode("utf-8"))
        raise HTTPException(status_code=504, detail="no response from godot")
    except (socket.timeout, OSError) as e:
        # Invalida la conexión
        global _last_conn
        with _lock:
            if _last_conn is not None:
                try:
                    _last_conn.close()
                except Exception:
                    pass
                _last_conn = None
        raise HTTPException(status_code=504, detail=f"socket error: {e}")


@app.get("/health")
def health() -> dict:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1.0)
        s.connect((GODOT_HOST, GODOT_PORT))
        s.close()
        return {"status": "ok", "godot_connected": True, "auth_enabled": bool(AUTH_TOKEN)}
    except Exception as e:
        return {"status": "degraded", "godot_connected": False, "error": str(e)}


@app.post("/tools/call")
def tool_call(call: ToolCall, request: Request) -> dict:
    _check_auth(request)
    ip = request.client.host if request.client else "?"
    if not _check_rate(ip):
        _log("warn", f"rate limit exceeded for {ip}")
        raise HTTPException(status_code=429, detail="rate limit exceeded")
    t0 = time.time()
    result = _call_godot(call.method, call.params, call.id)
    dt_ms = (time.time() - t0) * 1000.0
    _log("info", f"{ip} {call.method} {dt_ms:.0f}ms")
    return result


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=BRIDGE_HOST, port=BRIDGE_PORT, log_level=LOG_LEVEL or "info")
