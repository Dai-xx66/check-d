"""Isolated HTTP route tests for the opt-in user MCP integration."""
import json
import os
import socket
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.dirname(HERE)
APP = os.path.join(SRC_DIR, "app.py")
MOCK_DIR = os.path.abspath(os.path.join(SRC_DIR, "..", "m1-mock"))


def _port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class UserMcpRouteTests(unittest.TestCase):
    def setUp(self):
        self.port = _port()
        env = dict(os.environ)
        for name in ("CHECKD_USER_SUPABASE_URL", "CHECKD_USER_SUPABASE_PUBLISHABLE_KEY",
                     "CHECKD_USER_MCP_PUBLIC_URL", "CHECKD_USER_MCP_OAUTH_CLIENT_IDS"):
            env.pop(name, None)
        env.update({
            "CHECKD_DEMO_TOKEN": "route-test-demo-token",
            "CHECKD_USER_MCP_ENABLED": "1",
            "CHECKD_SNAPSHOT_MODE": "off",
            "PORT": str(self.port),
            "BIND": "127.0.0.1",
            "PYTHONPATH": os.pathsep.join([MOCK_DIR, SRC_DIR]),
        })
        self.process = subprocess.Popen([sys.executable, APP], cwd=SRC_DIR, env=env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 15
        while time.time() < deadline:
            if self.process.poll() is not None:
                self.fail("M1 app exited before listening")
            try:
                with socket.create_connection(("127.0.0.1", self.port), timeout=.2):
                    break
            except OSError:
                time.sleep(.05)
        else:
            self.fail("M1 app did not start")

    def tearDown(self):
        if self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)

    def post(self, path, payload, headers=None):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=json.dumps(payload).encode(), method="POST",
            headers={"Content-Type": "application/json", **(headers or {})})
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_missing_user_mcp_configuration_fails_closed_without_legacy_fallback(self):
        status, body = self.post("/mcp/user", {"jsonrpc": "2.0", "id": 1,
            "method": "tools/list"}, {"Authorization": "Bearer opaque-user-token",
                                        "X-Demo-Token": "route-test-demo-token",
                                        "Accept": "application/json, text/event-stream"})
        self.assertEqual(status, 503)
        self.assertEqual(body["error"]["code"], "DEPENDENCY_UNAVAILABLE")

    def test_legacy_mcp_still_registers_the_original_seven_tools(self):
        status, body = self.post("/mcp", {"jsonrpc": "2.0", "id": 2,
            "method": "tools/list"}, {"X-Demo-Token": "route-test-demo-token"})
        self.assertEqual(status, 200)
        names = {tool["name"] for tool in body["result"]["tools"]}
        self.assertEqual(names, {
            "list_tasks", "get_calendar_events", "generate_schedule",
            "validate_schedule", "apply_approved_changes", "request_approval",
            "get_approval_status",
        })


if __name__ == "__main__":
    unittest.main()
