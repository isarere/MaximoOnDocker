# Maximo MCP on Mac / Colima

This stack reproduces the MCP deployment in `mas-adp-manage` using its exact
image digest, AMD64 platform, MAS authentication, mTLS, API paths, polling
settings, non-root user, and 0.3 CPU / 400 MiB resource limits.
It connects to **OpenShift Maximo**, independently of `docker-compose.ora`.

Prepare with an active `oc` login and the existing IBM Docker registry login:

```bash
python3 mcp/prepare.py
docker compose --env-file mcp/.local/compose.env -f docker-compose.mcp config --quiet
./mcp/up.sh
```

The helper forwards the three cluster services and keeps the forwards alive.
Leave its terminal open. Ctrl-C stops this MCP service and the forwards.
The MCP endpoint is `https://localhost:9443/mcp`. Use a valid MAS bearer token
or the authentication supported by your MCP client; OAuth client credentials
are used for introspection and do not replace a user token.

```bash
docker compose --env-file mcp/.local/compose.env -f docker-compose.mcp ps
docker compose --env-file mcp/.local/compose.env -f docker-compose.mcp logs --tail 100 mcp
curl --cacert mcp/.local/local-tls/tls.crt https://localhost:9443/probes/ready
```

Mac adaptations:

- The image runs under AMD64 emulation on ARM Colima.
- Cluster DNS names map to the Colima Mac host IP, with upstream ports
  18443–18445. Names are preserved for TLS hostname checks.
- Nginx uses a separate self-signed localhost server certificate; the MAS
  client certificate and CA remain in `/etc/mas/certs` for upstream mTLS.
  Configure the MCP client to trust `mcp/.local/local-tls/tls.crt`.
- OAuth credentials, internal mTLS keys, truststore, and logs are under ignored
  `mcp/.local/`. Its parent directory is mode 700; mounted certificate files
  are readable by the container's OpenShift UID. Do not share this directory.
- The forwarding helper listens on all Mac interfaces on ports 18443–18445
  because Colima cannot reach a loopback-only listener. Run on a trusted
  network or restrict these ports with the Mac firewall; upstream TLS and
  authentication are retained.
- Compose has one healthcheck, combining startup, liveness, and readiness,
  with up to a one-hour startup grace period. An unhealthy state does not
  automatically restart a Docker container as Kubernetes liveness does.
- Kubernetes service-account tokens, SELinux labels, and CPU scheduling
  requests are not copied. The bundled MCP source uses TLS and OAuth for
  upstream access. The 64 MiB memory request maps to a memory reservation.

`prepare.py` refreshes credentials from the current cluster; rerun after
certificate or OAuth rotation. It defaults to `host.lima.internal`; set
`MCP_HOST_IP` when using a different Docker runtime. Namespace and secret
names reflect the inspected `adp` deployment.
