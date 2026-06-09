#!/usr/bin/env python3
import json
import re
import shlex
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures" / "legacy"
REQUIRED_FIXTURES = (
    "argov.pre-supply-chain.conf",
    "argov.users.v1.json",
    "config.multi-protocol.json",
    "custom_links.txt",
    "warp_domains.txt",
)


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def parse_shell_assignments(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        require(re.match(r"^[A-Z][A-Z0-9_]*=", line) is not None, f"invalid shell assignment in {path.name}: {raw}")
        key, value = line.split("=", 1)
        require("$(" not in value and "${" not in value, f"unsafe expansion in {path.name}: {key}")
        try:
            parts = shlex.split(value, posix=True)
        except ValueError as exc:
            fail(f"cannot parse {key} in {path.name}: {exc}")
        require(len(parts) <= 1, f"unexpected multi-token value in {path.name}: {key}")
        values[key] = parts[0] if parts else ""
    return values


def assert_legacy_conf(path: Path) -> None:
    values = parse_shell_assignments(path)
    preserved = {
        "NODE_NAME": "ArgoV Legacy Node",
        "ARGO_PORT": "18080",
        "VLESS_WS_PORT": "18081",
        "VMESS_WS_PORT": "18082",
        "CDN_DOMAIN": "legacy.example.com",
        "SUB_TOKEN": "legacytoken001",
        "RELAY_MODE": "split",
    }
    for key, expected in preserved.items():
        require(values.get(key) == expected, f"legacy conf fixture must preserve {key}")

    for new_key in ("XRAY_VERSION", "XRAY_SHA256", "CLOUDFLARED_VERSION", "CLOUDFLARED_SHA256"):
        require(new_key not in values, f"legacy conf fixture should model old installs without {new_key}")

    defaults = {
        "XRAY_VERSION": values.get("XRAY_VERSION", "latest"),
        "XRAY_SHA256": values.get("XRAY_SHA256", ""),
        "CLOUDFLARED_VERSION": values.get("CLOUDFLARED_VERSION", "latest"),
        "CLOUDFLARED_SHA256": values.get("CLOUDFLARED_SHA256", ""),
    }
    require(defaults["XRAY_VERSION"] == "latest", "old configs must default XRAY_VERSION to latest")
    require(defaults["CLOUDFLARED_VERSION"] == "latest", "old configs must default CLOUDFLARED_VERSION to latest")
    require(defaults["XRAY_SHA256"] == "", "old configs must default XRAY_SHA256 to empty")
    require(defaults["CLOUDFLARED_SHA256"] == "", "old configs must default CLOUDFLARED_SHA256 to empty")


def assert_users(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(data, dict), "users fixture must be a JSON object")
    users = data.get("users")
    require(isinstance(users, list) and len(users) >= 2, "users fixture must contain multiple users")
    default = next((u for u in users if u.get("name") == "default"), None)
    require(default is not None, "users fixture must include the default user")
    require(default.get("token") == "legacytoken001", "default subscription token must be preserved")
    require(default.get("uuid") == "11111111-1111-4111-8111-111111111111", "default UUID must be preserved")
    for user in users:
        require("quota_bytes" in user, f"user {user.get('name')} must track quota_bytes")
        require("used_up" in user and "used_down" in user, f"user {user.get('name')} must track bidirectional usage")
        require("enabled" in user, f"user {user.get('name')} must track enabled state")


def assert_xray_config(path: Path) -> None:
    config = json.loads(path.read_text(encoding="utf-8"))
    tags = {inbound.get("tag") for inbound in config.get("inbounds", [])}
    expected_tags = {"argo-in", "vless-ws", "vmess-ws", "reality", "hy2", "ss"}
    require(expected_tags.issubset(tags), "Xray fixture must cover all built-in protocol tags")
    require(config.get("api", {}).get("services") == ["StatsService"], "Xray fixture must keep StatsService enabled")
    require(config.get("stats") == {}, "Xray fixture must keep stats enabled")
    policy = config.get("policy", {}).get("levels", {}).get("0", {})
    require(policy.get("statsUserUplink") is True, "Xray fixture must keep uplink stats")
    require(policy.get("statsUserDownlink") is True, "Xray fixture must keep downlink stats")
    for inbound in config.get("inbounds", []):
        if inbound.get("tag") in expected_tags:
            sniffing = inbound.get("sniffing", {})
            require(sniffing.get("routeOnly") is True, f"{inbound.get('tag')} must keep route-only sniffing")


def assert_line_fixture(path: Path, minimum: int, expected: set[str]) -> None:
    items = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    require(len(items) >= minimum, f"{path.name} must include enough sample lines")
    for item in expected:
        require(item in items, f"{path.name} must include {item}")


def main() -> None:
    require(FIXTURES.is_dir(), "missing tests/fixtures/legacy compatibility samples")
    for name in REQUIRED_FIXTURES:
        require((FIXTURES / name).is_file(), f"missing legacy fixture: {name}")

    assert_legacy_conf(FIXTURES / "argov.pre-supply-chain.conf")
    assert_users(FIXTURES / "argov.users.v1.json")
    assert_xray_config(FIXTURES / "config.multi-protocol.json")
    assert_line_fixture(
        FIXTURES / "custom_links.txt",
        minimum=3,
        expected={"hysteria2://hy2pass@2001:db8::10:443?sni=hy2.example.com&insecure=1&allowInsecure=1&alpn=h3#Legacy-Hy2"},
    )
    assert_line_fixture(
        FIXTURES / "warp_domains.txt",
        minimum=5,
        expected={"google.com", "youtube.com", "openai.com"},
    )


if __name__ == "__main__":
    main()
