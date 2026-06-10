#!/usr/bin/env python3
import base64
import json
import re
import sys
import urllib.parse
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures" / "legacy"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def read_script() -> str:
    script = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "argov.sh"
    require(script.is_file(), f"missing script: {script}")
    return script.read_text(encoding="utf-8")


def extract_block(text: str, start: str, end: str) -> str:
    start_idx = text.find(start)
    require(start_idx >= 0, f"missing block start: {start}")
    end_idx = text.find(end, start_idx + len(start))
    require(end_idx > start_idx, f"missing block end after: {start}")
    return text[start_idx:end_idx]


def load_build_clash(text: str):
    py = extract_block(text, "def to_yaml(data, level=0):", "def load_users():")
    ns = {"base64": base64, "json": json, "urllib": urllib}
    exec(py, ns)
    require(callable(ns.get("build_clash")), "subscription server must expose build_clash")
    return ns["build_clash"]


def fixture_lines(*names: str) -> list[str]:
    lines: list[str] = []
    for name in names:
        path = FIXTURES / name
        require(path.is_file(), f"missing fixture: {name}")
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line and not line.startswith("#"):
                lines.append(line)
    return lines


def assert_clash_conversion(text: str) -> None:
    build_clash = load_build_clash(text)
    yaml = build_clash(fixture_lines("custom_links.txt", "relay_links.txt"))
    require(yaml, "legacy share links must produce a Clash/Mihomo profile")

    expected_fragments = {
        'name: "Legacy-VLESS"': "VLESS link name must be preserved",
        'type: "vless"': "VLESS links must convert to vless proxies",
        'encryption: "none"': "VLESS proxies must keep encryption none",
        'network: "ws"': "WS transport must be preserved",
        'path: "/vless-argo"': "WS path must be URL-decoded",
        'type: "vmess"': "VMess links must convert to vmess proxies",
        'type: "trojan"': "Trojan links must convert to trojan proxies",
        'server: "2001:db8::55"': "bracketed IPv6 relay hosts must survive host parsing",
        'name: "Relay-Reality-Vision"': "Reality relay name must be preserved",
        'flow: "xtls-rprx-vision"': "Reality/Vision flow must be preserved",
        'client-fingerprint: "chrome"': "Reality fingerprint must be preserved",
        'public-key: "relaypubkey"': "Reality public key must be preserved",
        'short-id: "abcd1234"': "Reality short id must be preserved",
        'type: "hysteria2"': "Hysteria2 links must convert to hysteria2 proxies",
        'ports: "25000-25010"': "Hysteria2 mport must map to Mihomo ports",
        'hop-interval: 30': "Hysteria2 port hopping must set hop-interval",
        'alpn:': "Hysteria2 ALPN must be preserved as a list",
        'name: "Proxy"': "airport-style Proxy group must be present",
        'name: "AIChat"': "AIChat routing group must be present",
        '- "MATCH,Final"': "unmatched traffic must route through Final",
    }
    for fragment, message in expected_fragments.items():
        require(fragment in yaml, message)


def assert_subscription_server_contract(text: str) -> None:
    py = extract_block(text, "def resolve_token(path, qs):", "# ")
    require("if path == '${SUB_PATH}' or tok == '${SUB_TOKEN}':" in py, "legacy SUB_PATH and SUB_TOKEN access must remain valid")
    require("u.get('token') == tok and u.get('enabled', True)" in py, "disabled users must not resolve subscription tokens")
    require("safe_name = up.quote('${NODE_NAME}', safe='')" in text, "profile names must percent-encode NODE_NAME")
    require("filename*=UTF-8''{safe_name}" in text, "subscription responses must expose UTF-8 filename metadata")
    require("filename=\"{safe_name}.yaml\"" not in text, "subscription filenames must not force a .yaml suffix")


def assert_sub_generator_contract(text: str) -> None:
    sub_gen = extract_block(text, "cat > \"${WORK_DIR}/sub_gen.sh\" << 'SUBEOF'", "SUBEOF")
    require("USER_TOKEN=\"${1:-}\"" in sub_gen, "sub_gen must accept an explicit per-user token")
    require("($tok == \"\" or $tok == $dtok)" in sub_gen, "empty/default token must resolve to default user")
    require(".users[]|select(.token==$tok and (.enabled//true))" in sub_gen, "per-user token lookup must ignore disabled users")
    require(re.search(r'if \[ "\$IS_DEFAULT_USER" = "1" \]; then\s+INCLUDE_CUSTOM=1\s+fi', sub_gen), "only default subscription may include custom links")
    require("[ \"$IS_DEFAULT_USER\" = \"1\" ] && printf '%s' \"$out\" > /etc/xray/sub.txt" in sub_gen, "only default subscription may refresh global sub.txt")
    require("mport=${hmport}" in sub_gen, "built-in Hysteria2 mport must be emitted in subscription links")
    require("allowInsecure=1" in sub_gen, "self-signed Hysteria2 compatibility must keep allowInsecure")


def main() -> None:
    text = read_script()
    assert_clash_conversion(text)
    assert_subscription_server_contract(text)
    assert_sub_generator_contract(text)


if __name__ == "__main__":
    main()
