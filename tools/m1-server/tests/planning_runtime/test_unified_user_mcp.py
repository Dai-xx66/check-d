import os
import unittest
from unittest.mock import patch

from unified_user_mcp import build_from_env


BASE = {
    "CHECKD_USER_SUPABASE_URL": "https://supabase.invalid",
    "CHECKD_USER_SUPABASE_PUBLISHABLE_KEY": "test-publishable-only",
    "CHECKD_USER_MCP_PUBLIC_URL": "https://mcp.invalid",
}


class UnifiedUserMcpConfigTests(unittest.TestCase):
    def test_user_route_requires_explicit_enable_at_http_layer_but_builds_with_public_key(self):
        with patch.dict(os.environ, BASE, clear=True):
            app = build_from_env()
        self.assertEqual(app.audience, "https://mcp.invalid/mcp/user")
        self.assertEqual(app.verifier.publishable_key, "test-publishable-only")
        self.assertEqual(app.snapshot_provider.publishable_key, "test-publishable-only")

    def test_production_requires_https_and_oauth_client_allowlist(self):
        with patch.dict(os.environ, {**BASE, "CHECKD_USER_MCP_ENV": "production"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "client IDs"):
                build_from_env()
        config = {**BASE, "CHECKD_USER_MCP_ENV": "production",
                  "CHECKD_USER_MCP_OAUTH_CLIENT_IDS": "workbuddy-test-client"}
        with patch.dict(os.environ, config, clear=True):
            app = build_from_env()
        self.assertEqual(app.verifier.allowed_oauth_client_ids,
                         frozenset({"workbuddy-test-client"}))

    def test_production_rejects_http_public_url(self):
        config = {**BASE, "CHECKD_USER_MCP_ENV": "production",
                  "CHECKD_USER_MCP_PUBLIC_URL": "http://mcp.invalid",
                  "CHECKD_USER_MCP_OAUTH_CLIENT_IDS": "workbuddy-test-client"}
        with patch.dict(os.environ, config, clear=True):
            with self.assertRaisesRegex(RuntimeError, "HTTPS"):
                build_from_env()


if __name__ == "__main__":
    unittest.main()
