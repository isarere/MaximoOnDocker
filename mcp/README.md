# MCP connected to local Maximo

`docker-compose.mcp` connects to the Maximo instance exposed on your Mac at
`http://localhost:9080/maximo/api`. Inside Docker it uses the equivalent
`http://maximo:9080/maximo/api` on the existing Maximo network. Container
loopback (`localhost`) would point back to MCP itself.

Start the Oracle/Maximo stack first, then prepare local MCP files:

```bash
python3 mcp/prepare.py --local
```

Set `MAXIMO_API_KEY` in `mcp/.local/local-api.env` to an API key from **local
Maximo**. This file is Git-ignored and mode 600. Local preparation does not read
OpenShift secrets or export cluster credentials.

```bash
docker compose -f docker-compose.mcp config --quiet
./mcp/up.sh
```

MCP is exposed at `https://localhost:9443/mcp`. Configure the MCP client to trust
`mcp/.local/local-tls/tls.crt` and include its local Maximo API key in the
`apikey` request header. The configured bootstrap key loads tool metadata;
tool calls retain the vendor framework's per-request API-key authentication.

The pinned image normally starts in cluster mode with mTLS and `ccm=1`. Its
built-in local CLI also embeds demo login credentials. `local_app.py` loads the
vendor definitions without either automatic startup path, then configures
local mode with API-key headers and no demo username/password parameters.
Uvicorn serves local TLS directly; nginx and cluster port forwards are not
needed for this stack.

The external network defaults to `maximoondocker_default`. Set `MAXIMO_NETWORK`
if you used a custom Compose project name. The image runs with AMD64 emulation
on ARM Colima and retains the pod's CPU/memory limits and non-root user.

```bash
docker compose -f docker-compose.mcp ps
docker compose -f docker-compose.mcp logs --tail 100 mcp
curl --cacert mcp/.local/local-tls/tls.crt https://localhost:9443/probes/ready
```

The original pod-equivalent cluster setup is retained in
[docker-compose.mcp.openshift](../docker-compose.mcp.openshift). See
[OPENSHIFT.md](OPENSHIFT.md) for its certificate preparation and tunnel helper.

See [AUTHENTICATION.md](AUTHENTICATION.md) for the source inspection, IDP dependency,
and local startup validation.

## Add to Codex

With the container running, register its stdio proxy:

```bash
codex mcp add maximo-mcp -- /usr/bin/python3 "$(pwd)/mcp/codex_proxy.py"
```

The proxy runs inside the existing container, uses its API key, and verifies
the HTTPS certificate against the mounted local certificate. The Codex config
contains no API key. Docker must be running and `maximo-mcp-mcp-1` must be up.
Restart the MCP connection in Codex after registration to load its tools.
