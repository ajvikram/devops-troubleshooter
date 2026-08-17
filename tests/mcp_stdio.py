#!/usr/bin/env python3
"""Minimal MCP stdio client (JSON-RPC). Supports NDJSON and Content-Length."""

from __future__ import annotations

import argparse
import json
import os
import select
import subprocess
import sys
import time
from typing import Any


class McpError(RuntimeError):
    pass


class McpClient:
    def __init__(self, cmd: list[str], env: dict[str, str] | None = None, timeout: float = 30.0):
        self.timeout = timeout
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            bufsize=0,
        )
        self._mode: str | None = None  # "ndjson" | "lsp"
        self._id = 0

    def close(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    def _send(self, msg: dict[str, Any]) -> None:
        assert self.proc.stdin is not None
        body = json.dumps(msg, separators=(",", ":")).encode("utf-8")
        if self._mode == "lsp":
            header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
            self.proc.stdin.write(header + body)
        else:
            self.proc.stdin.write(body + b"\n")
        self.proc.stdin.flush()

    def _wait_readable(self, remaining: float) -> None:
        assert self.proc.stdout is not None
        ready, _, _ = select.select([self.proc.stdout], [], [], remaining)
        if not ready:
            err = b""
            if self.proc.stderr:
                err = self.proc.stderr.read() if self.proc.poll() is not None else b""
            raise McpError(f"timeout waiting for MCP response; stderr={err[:2000]!r}")

    def _read_exact(self, n: int, deadline: float) -> bytes:
        assert self.proc.stdout is not None
        buf = b""
        while len(buf) < n:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise McpError("timeout reading MCP body")
            self._wait_readable(remaining)
            chunk = self.proc.stdout.read(n - len(buf))
            if not chunk:
                raise McpError("MCP stdout closed")
            buf += chunk
        return buf

    def _read_line(self, deadline: float) -> bytes:
        assert self.proc.stdout is not None
        buf = b""
        while not buf.endswith(b"\n"):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise McpError("timeout reading MCP line")
            self._wait_readable(remaining)
            ch = self.proc.stdout.read(1)
            if not ch:
                raise McpError("MCP stdout closed")
            buf += ch
        return buf

    def _recv(self) -> dict[str, Any]:
        deadline = time.monotonic() + self.timeout
        first = self._read_line(deadline)
        if first.lower().startswith(b"content-length:"):
            self._mode = "lsp"
            headers = first.decode("ascii", errors="replace")
            while True:
                line = self._read_line(deadline)
                if line in (b"\r\n", b"\n"):
                    break
                headers += line.decode("ascii", errors="replace")
            length = None
            for raw in headers.splitlines():
                if raw.lower().startswith("content-length:"):
                    length = int(raw.split(":", 1)[1].strip())
            if length is None:
                raise McpError(f"missing Content-Length: {headers!r}")
            body = self._read_exact(length, deadline)
            return json.loads(body.decode("utf-8"))
        self._mode = "ndjson"
        line = first.strip()
        if not line:
            return self._recv()
        return json.loads(line.decode("utf-8"))

    def request(self, method: str, params: dict[str, Any] | None = None) -> Any:
        req: dict[str, Any] = {"jsonrpc": "2.0", "id": self._next_id(), "method": method}
        if params is not None:
            req["params"] = params
        self._send(req)
        while True:
            msg = self._recv()
            if msg.get("id") != req["id"] and "method" in msg and "id" not in msg:
                continue
            if "error" in msg:
                raise McpError(json.dumps(msg["error"]))
            if msg.get("id") == req["id"]:
                return msg.get("result")

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        msg: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self._send(msg)

    def initialize(self) -> Any:
        result = self.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "dto-e2e", "version": "1.0"},
            },
        )
        self.notify("notifications/initialized")
        return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list-tools", action="store_true")
    parser.add_argument("--call", metavar="TOOL")
    parser.add_argument("--args", default="{}", help="JSON object of tool arguments")
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument(
        "server_cmd",
        nargs=argparse.REMAINDER,
        help="MCP server command after --  e.g. -- /path/kubernetes-mcp-server --read-only",
    )
    args = parser.parse_args()
    cmd = [c for c in args.server_cmd if c != "--"]
    if not cmd:
        parser.error("pass the MCP server command after --")

    env = os.environ.copy()
    client = McpClient(cmd, env=env, timeout=args.timeout)
    try:
        client.initialize()
        if args.list_tools:
            result = client.request("tools/list")
            tools = result.get("tools", []) if isinstance(result, dict) else result
            names = [t.get("name") if isinstance(t, dict) else str(t) for t in tools]
            json.dump({"tools": names, "count": len(names)}, sys.stdout)
            sys.stdout.write("\n")
            return 0
        if args.call:
            result = client.request(
                "tools/call",
                {"name": args.call, "arguments": json.loads(args.args)},
            )
            json.dump(result, sys.stdout, default=str)
            sys.stdout.write("\n")
            return 0
        print("initialized", file=sys.stderr)
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except McpError as exc:
        print(f"mcp error: {exc}", file=sys.stderr)
        raise SystemExit(2)
