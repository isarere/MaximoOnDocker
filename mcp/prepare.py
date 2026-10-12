#!/usr/bin/env python3
"""Prepare ignored MCP runtime files; never print credential values."""
import base64
import json
import os
from pathlib import Path
import subprocess
import argparse

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / "mcp/.local"
IMAGE = "cp.icr.io/cp/mas/mas-mcp-framework@sha256:d81d459c1936efc8560d6c72578bf0f3fbbe152389e249c001c1c18b1b51f34f"


def resource(kind, name):
    return json.loads(subprocess.check_output([
        "oc", "get", kind, name, "-n", "mas-adp-manage", "-o", "json"
    ]))


def export_files(resource_data, directory):
    target = LOCAL / directory
    target.mkdir(mode=0o755, exist_ok=True)
    for key, value in resource_data.get("data", {}).items():
        if Path(key).name != key or key in (".", ".."):
            raise ValueError("Invalid configuration filename")
        data = base64.b64decode(value) if resource_data["kind"] == "Secret" else value.encode()
        file = target / key
        file.write_bytes(data)
        file.chmod(0o644)
    for key, value in resource_data.get("binaryData", {}).items():
        if Path(key).name != key or key in (".", ".."):
            raise ValueError("Invalid configuration filename")
        file = target / key
        file.write_bytes(base64.b64decode(value))
        file.chmod(0o644)


def prepare_tls():
    tls = LOCAL / "local-tls"
    tls.mkdir(mode=0o755, exist_ok=True)
    if not (tls / "tls.key").exists() or not (tls / "tls.crt").exists():
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "365",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "-keyout", str(tls / "tls.key"), "-out", str(tls / "tls.crt")
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for file in tls.iterdir():
        file.chmod(0o644)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--local", action="store_true", help="Prepare local TLS/API-key files without OpenShift access")
    args = parser.parse_args()
    LOCAL.mkdir(mode=0o700, parents=True, exist_ok=True)
    LOCAL.chmod(0o700)
    prepare_tls()
    if args.local:
        api_env = LOCAL / "local-api.env"
        if not api_env.exists():
            api_env.write_text("MAXIMO_API_KEY=\n")
        api_env.chmod(0o600)
        print("Prepared local MCP TLS. Set MAXIMO_API_KEY in mcp/.local/local-api.env.")
        return
    # Only this internal mTLS identity is exported; public route private keys stay in the cluster.
    export_files(resource("secret", "adp-internal-manage-tls"), "mas-certs")
    export_files(resource("configmap", "adp-mas-truststore-cfg"), "truststore")
    public = resource("secret", "adp-mas-cert-public-81")
    public["data"] = {k: v for k, v in public["data"].items() if k in ("tls.crt", "ca.crt")}
    export_files(public, "public-certs")
    oauth = resource("secret", "adp-credentials-oauth-manage")["data"]
    credentials = []
    for variable, key in (("CLIENT_ID", "username"), ("CLIENT_SECRET", "password")):
        value = base64.b64decode(oauth[key]).decode()
        if "\n" in value or "\r" in value:
            raise ValueError("Multiline OAuth credentials are unsupported")
        credentials.append(f"{variable}={value}\n")
    credentials_file = LOCAL / "credentials.env"
    credentials_file.write_text("".join(credentials))
    credentials_file.chmod(0o600)
    host_ip = os.environ.get("MCP_HOST_IP")
    if not host_ip:
        host_ip = subprocess.check_output([
            "docker", "run", "--rm", "--platform", "linux/amd64", "--entrypoint", "python3",
            IMAGE, "-c", "import socket; print(socket.gethostbyname('host.lima.internal'))"
        ], text=True).strip()
    import ipaddress
    ipaddress.IPv4Address(host_ip)
    (LOCAL / "compose.env").write_text(f"MCP_HOST_IP={host_ip}\n")
    print("Prepared MCP credentials, mTLS files, localhost TLS, and Colima host mapping.")


if __name__ == "__main__":
    main()
