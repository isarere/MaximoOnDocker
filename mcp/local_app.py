"""Run the pinned IBM MCP framework against local Maximo with API-key auth."""
import ast
import logging
import os
from pathlib import Path
import sys
import types

api_key = os.environ.get("MAXIMO_API_KEY", "")
if not api_key:
    raise RuntimeError("Set MAXIMO_API_KEY in mcp/.local/local-api.env before starting MCP")

# Load definitions without the vendor's automatic production-mode startup.
# Its CLI/ASGI entry point would configure mTLS or hardcoded demo credentials.
vendor_path = Path(__file__).with_name("mas-mcp-framework.py")
tree = ast.parse(vendor_path.read_text(), filename=str(vendor_path))
entry = tree.body[-1]
if not isinstance(entry, ast.If) or ast.unparse(entry.test) != "__name__ == '__main__'":
    raise RuntimeError("Unexpected MCP entry point; review the image before using it")
tree.body.pop()
vendor = types.ModuleType("maximo_local_vendor")
vendor.__file__ = str(vendor_path)
sys.modules[vendor.__name__] = vendor
exec(compile(tree, str(vendor_path), "exec"), vendor.__dict__)


class OmitCredentialDetails(logging.Filter):
    def filter(self, record):
        # The vendor logs authentication headers in extraction and request logs.
        message = record.getMessage()
        return not (
            message.startswith(("Extracted headers from HTTP request:", "OIDC Data:"))
            or (message.startswith("Sending ") and " with headers " in message)
        )


vendor.logger.addFilter(OmitCredentialDetails())
server = vendor.MasFrameworkMcpServer(
    local_mode=True,
    base_url=os.environ["APP_API_URL"],
    disable_auth=False,
)
# Clear demo credentials before any polling or request occurs.
server.shared_params = {}
server.headers["apikey"] = api_key
app = server.setup_server()
