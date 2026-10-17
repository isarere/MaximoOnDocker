#!/usr/bin/env python3
"""Expose the local HTTPS MCP service over stdio without copying its API key."""
import os
from pathlib import Path
import shutil
import sys

if '--container' not in sys.argv:
    docker = shutil.which('docker') or '/opt/homebrew/bin/docker'
    os.execv(docker, [
        docker, 'exec', '-i', 'maximo-mcp-mcp-1', 'python3', '-c',
        Path(__file__).read_text(), '--container',
    ])

import ssl
import httpx
from fastmcp import Client, FastMCP
from fastmcp.client.transports import StreamableHttpTransport

key = os.environ.get('MAXIMO_API_KEY')
if not key:
    raise RuntimeError('The MCP container needs its local Manage API key')
context = ssl.create_default_context(cafile='/etc/mcp-local-tls/tls.crt')


def http_client(**kwargs):
    return httpx.AsyncClient(verify=context, **kwargs)


transport = StreamableHttpTransport(
    'https://localhost:9443/mcp',
    headers={'apikey': key},
    httpx_client_factory=http_client,
)
backend = Client(transport, timeout=600)
proxy = FastMCP.as_proxy(backend, name='Local Maximo MCP')
proxy.run(transport='stdio', show_banner=False)
