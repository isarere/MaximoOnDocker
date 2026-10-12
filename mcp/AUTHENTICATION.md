# Authentication in the pinned Maximo MCP image

Inspected on 2026-10-12 from container `maximo-mcp-mcp-1`, image
`cp.icr.io/cp/mas/mas-mcp-framework@sha256:d81d459c1936efc8560d6c72578bf0f3fbbe152389e249c001c1c18b1b51f34f`.
Recovered vendor files are kept locally in ignored `mcp/.local/vendor-source/`,
including image provenance. They are not included in the PR.

## Client authentication

The tool handler reads credentials from the incoming MCP HTTP request.

| Client header | Framework behavior | MAS IDP needed? |
| --- | --- | --- |
| `apikey` | Forward the key in the `apikey` header to Manage. Manage authenticates and authorizes the associated user. | No, for the standalone local API-key setup. |
| `x-access-token` | POST the token to `COREIDP_OIDC_URL` with `CLIENT_ID`/`CLIENT_SECRET` HTTP Basic authentication. Read `sub` from the result and send it to Manage as the `foruser` query parameter. | Yes, for this image's configured MAS JWT path. |
| Neither | Reject a tool call with request context before making an outbound request. | — |

If both credentials are present, `x-access-token` takes precedence. The
implementation checks for `sub` in the introspection result; it does not contain
an explicit `active` check. This describes the inspected code, not a new JWT
validation layer added by the local adapter.

Source: `mas-mcp-framework.py`, lines 412–488 (credential extraction and
introspection), 495–555 (requests to Manage).

## MCP service identity and local adaptation

Cluster mode uses `/etc/mas/certs/tls.crt`, `tls.key`, and `ca.crt` for outbound
mTLS and appends `ccm=1` to requests. This service identity is separate from the
client's API key or JWT. The JWT path relies on the cluster's authenticated
service connection to forward the resolved user identity.

The vendor local mode skips mTLS but initially supplies `_lid`/`_lpwd` demo
credentials. Our adapter clears those parameters before starting polling,
omits `ccm=1`, and uses `MAXIMO_API_KEY` only for bootstrap metadata requests.
Each tool call still requires the client's own `apikey` header. The bootstrap
key is not substituted for a missing client credential.

The bootstrap requests fetch `/oas?aitools=1&lean=1` and
`/service/MCPTools?action=wsmethod:getLastUpdate`. Without a valid local API key,
the adapter refuses to start. `APP_API_URL` points to local Manage at
`http://maximo:9080/maximo/api`; no IDP URL, OAuth client secret, cluster mTLS
identity, or cluster tunnel is needed for that API-key path.

Source: vendor lines 65–112 and 136–157 (modes/TLS), 960–1028 (metadata polling),
and `local_app.py` (bootstrap key and removal of demo credentials).

The image does not install global authentication middleware in `setup_server`.
Its `/api/tools` listing and probe routes do not perform the tool handler's
credential checks. Probe success alone therefore does not prove authenticated
tool loading. The Compose endpoint remains bound to Mac loopback with local
TLS. The adapter suppresses vendor INFO logs that would expose authentication
headers or introspection data.

## Validation and current startup status

- Created and started the real Compose container. It exited with the explicit
  missing `MAXIMO_API_KEY` error because the ignored local file is empty. Stopped
  it to avoid repeated restarts; authenticated metadata/tool loading is pending.
- Exercised the recovered tool handler inside the pinned image with synthetic
  credentials and mocked HTTP clients: API-key forwarding made no IDP request;
  JWT introspection supplied `foruser`; missing client headers were rejected.
- Verified the expanded credential-log filter in the same image.
- Earlier network checks reached local Manage from the MCP image: unauthenticated
  metadata returned HTTP 401; the public ping endpoint returned HTTP 200.

To finish startup, set a key from local Manage in `mcp/.local/local-api.env`, then:

```bash
docker compose -f docker-compose.mcp up -d
```

IBM documents [API-key and JWT headers for external MCP agents](https://www.ibm.com/docs/en/masv-and-l/cd?topic=developing-connecting-external-agents)
and [Manage API-key authentication and user permissions](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=apis-api-keys).
