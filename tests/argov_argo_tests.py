#!/usr/bin/env python3
"""Exercise independent Argo lifecycle and the emitted subscription generator.

All writes, binaries and service definitions are redirected into temporary
directories. Service and download commands never operate on the test host.
"""
import base64
import http.server
import json
import os
import shlex
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = Path(os.environ.get("ARGOV_TEST_SCRIPT", ROOT / "argov.sh"))
UUID = "11111111-1111-4111-8111-111111111111"


@unittest.skipUnless(all(shutil.which(t) for t in ("bash", "jq", "openssl")), "Bash tools required")
class ArgoTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="argov-argo-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = SCRIPT.read_text(encoding="utf-8")
        library = self.source.split("\nmigrate_argox_to_argov\nload_conf\n", 1)[0]
        library = library.replace("/etc/systemd/system/argov-tunnel.service", "${WORK_DIR}/tunnel.service")
        library = library.replace("/etc/init.d/argov-tunnel", "${WORK_DIR}/tunnel.init")
        library = library.replace("/etc/systemd/system/xray.service", "${WORK_DIR}/xray.service")
        library = library.replace("/etc/init.d/xray", "${WORK_DIR}/xray.init")
        self.library = self.root / "library.sh"
        self.library.write_text(library, encoding="utf-8")

    def shell(self, body, inputs=""):
        prefix = f"source {shlex.quote(str(self.library))}\nexport TEST_ROOT={shlex.quote(str(self.root))}\n"
        prefix += r'''
WORK_DIR="$TEST_ROOT"; CONFIG_FILE="$WORK_DIR/config.json"; USER_CONF="$WORK_DIR/argov.conf"
ARGOV_USERS_FILE="$WORK_DIR/argov_users.json"; TUNNEL_LOG="$WORK_DIR/argo.log"
SB_WORK_DIR="$WORK_DIR/sb"; SB_CONFIG_FILE="$SB_WORK_DIR/config.json"
HY2_CERT_FILE="$WORK_DIR/hy2.crt"; HY2_KEY_FILE="$WORK_DIR/hy2.key"
SB_CERT_FILE="$WORK_DIR/sb.crt"; SB_KEY_FILE="$WORK_DIR/sb.key"
SB_HY2_CERT_FILE="$WORK_DIR/sb-hy2.crt"; SB_HY2_KEY_FILE="$WORK_DIR/sb-hy2.key"
IS_ALPINE=0
clear() { :; }
port_in_use_any() { [ "$1" = 19999 ]; }
systemctl() {
    printf '%s\n' "$*" >> "$TEST_ROOT/services"
    [ "$1" != is-active ] || [ -f "$TEST_ROOT/tunnel-active" ]
}
restart_protocol_runtime() {
    printf 'restart %s\n' "$1" >> "$TEST_ROOT/services"
    if [ -f "$TEST_ROOT/reject-restart" ]; then rm "$TEST_ROOT/reject-restart"; return 1; fi
}
start_sub_server() { printf 'refresh\n' >> "$TEST_ROOT/subscriptions"; }
download_cloudflared_checked() { echo 'unexpected download' >&2; return 1; }
seed() {
    ARGO_MODE=fixed-token; ARGO_FIXED_DOMAIN=argo.example.com
    ARGO_PORT=18080; VLESS_WS_PORT=18081; VMESS_WS_PORT=18082
    ENABLE_VLESS_ARGO=1; ENABLE_VMESS_ARGO=1
    VLESS_WS_PATH=/deployed-vless; VMESS_WS_PATH=/deployed-vmess
    UUID_CUSTOM=11111111-1111-4111-8111-111111111111; SUB_TOKEN=default-token
    CDN_DOMAIN=cdn.example.com; CDN_PORT=443
    ENABLE_SS=1; SS_PORT=18083; ENABLE_REALITY=0; ENABLE_HY2=0
    load_conf
    build_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM" || exit 1
    save_conf || exit 2
    ensure_users_file || exit 3
    jq '.users += [{name:"alice",uuid:"22222222-2222-4222-8222-222222222222",token:"alice-token",enabled:true}]' "$ARGOV_USERS_FILE" > "$TEST_ROOT/users.tmp"
    mv "$TEST_ROOT/users.tmp" "$ARGOV_USERS_FILE"
    sync_xray_users || exit 4
    jq '.outbounds += [{tag:"preserved",protocol:"blackhole"}]' "$CONFIG_FILE" > "$TEST_ROOT/cfg.tmp"
    mv "$TEST_ROOT/cfg.tmp" "$CONFIG_FILE"
    cat > "$WORK_DIR/xray" <<'BIN'
#!/bin/sh
[ ! -f "$TEST_ROOT/reject-config" ]
BIN
    chmod +x "$WORK_DIR/xray"
    touch "$TEST_ROOT/tunnel-active" "$WORK_DIR/argo"; chmod +x "$WORK_DIR/argo"
}
'''
        result = subprocess.run(["bash", "-c", prefix + body], input=inputs, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def config(self):
        return json.loads((self.root / "config.json").read_text())

    def assert_fallbacks(self, cfg):
        inbounds = {i["tag"]: i for i in cfg["inbounds"]}
        ws = [i for i in cfg["inbounds"] if i["tag"] in ("vless-ws", "vmess-ws")]
        if not ws:
            self.assertNotIn("argo-in", inbounds)
            return
        expected = [{"path": i["streamSettings"]["wsSettings"]["path"], "dest": i["port"]} for i in ws]
        expected.append({"dest": ws[0]["port"]})
        self.assertEqual(inbounds["argo-in"]["settings"]["fallbacks"], expected)
        for inbound in [inbounds["argo-in"]] + ws:
            self.assertEqual(inbound["listen"], "127.0.0.1")
            self.assertTrue(inbound["sniffing"]["routeOnly"])
            self.assertEqual(inbound["sniffing"]["destOverride"], ["http", "tls", "quic"])

    def test_template_protocol_matrix(self):
        for mode, vl, vm in [("temp", 1, 1), ("temp", 1, 0), ("temp", 0, 1), ("temp", 0, 0), ("skip", 1, 1)]:
            with self.subTest(mode=mode, vl=vl, vm=vm):
                self.shell(f'ARGO_MODE={mode}; ENABLE_VLESS_ARGO={vl}; ENABLE_VMESS_ARGO={vm}\n'
                           f'build_xray_config {UUID} {UUID} || exit 1\n')
                cfg = self.config()
                tags = [i["tag"] for i in cfg["inbounds"]]
                self.assertEqual("vless-ws" in tags, mode != "skip" and bool(vl))
                self.assertEqual("vmess-ws" in tags, mode != "skip" and bool(vm))
                self.assert_fallbacks(cfg)

    def test_delete_vmess_preserves_vless_users_and_routing(self):
        self.shell(r'''
seed
cp "$CONFIG_FILE" "$TEST_ROOT/before.json"; cp "$ARGOV_USERS_FILE" "$TEST_ROOT/users-before.json"
configure_argo_protocol delete vmess-ws || exit 1
cmp "$ARGOV_USERS_FILE" "$TEST_ROOT/users-before.json" || exit 2
load_conf
[ "$ENABLE_VLESS_ARGO:$ENABLE_VMESS_ARGO" = 1:0 ] || exit 3
is_safe_conf_file "$USER_CONF" || exit 4
''', "y\n")
        cfg = self.config()
        before = json.loads((self.root / "before.json").read_text())
        self.assertNotIn("vmess-ws", [i["tag"] for i in cfg["inbounds"]])
        for tag in ("vless-ws", "ss", "api-in"):
            self.assertEqual(next(i for i in cfg["inbounds"] if i["tag"] == tag), next(i for i in before["inbounds"] if i["tag"] == tag))
        for key in ("outbounds", "routing"):
            self.assertEqual(cfg[key], before[key])
        self.assert_fallbacks(cfg)
        self.assertNotIn("restart argov-tunnel", (self.root / "services").read_text())

    def test_delete_vless_routes_default_to_vmess(self):
        self.shell("seed\nconfigure_argo_protocol delete vless-ws || exit 1\n", "y\n")
        self.assert_fallbacks(self.config())
        self.assertNotIn("vless-ws", [i["tag"] for i in self.config()["inbounds"]])

    def test_readd_only_missing_protocol_preserves_other_settings(self):
        self.shell(r'''
seed
configure_argo_protocol delete vmess-ws || exit 1
configure_argo_protocol add vmess-ws || exit 2
''', "y\n18092\n/new-vmess\ny\n")
        cfg = self.config()
        self.assert_fallbacks(cfg)
        vl = next(i for i in cfg["inbounds"] if i["tag"] == "vless-ws")
        vm = next(i for i in cfg["inbounds"] if i["tag"] == "vmess-ws")
        self.assertEqual((vl["port"], vl["streamSettings"]["wsSettings"]["path"]), (18081, "/deployed-vless"))
        self.assertEqual((vm["port"], vm["streamSettings"]["wsSettings"]["path"]), (18092, "/new-vmess"))
        self.assertEqual(len(vm["settings"]["clients"]), 2)
        self.assertNotIn("restart argov-tunnel", (self.root / "services").read_text())

    def test_repeat_edit_updates_every_fallback_and_reinstall_keeps_selection(self):
        self.shell(r'''
seed
configure_argo_protocol delete vless-ws || exit 1
configure_argo_protocol edit vmess-ws || exit 2
edit_protocol vmess-ws VMess || exit 3
load_conf
# Run the actual reinstall flow with package/download/service operations stubbed.
apt-get() { :; }
download_xray_zip_checked() { touch "$2"; }
download_cloudflared_checked() { touch "$2"; }
unzip() { :; }
install_qrencode() { :; }
install_ag_wrapper() { :; }
start_stats_service() { :; }
setup_traffic_counters() { :; }
show_qr() { :; }
get_ip() { printf '192.0.2.25'; }
sleep() { :; }
WARP_DOMAIN_FILE="$TEST_ROOT/unused-warp-domains.txt"
do_install || exit 4
''', "y\n18092\n/first\ny\n18093\n/second\ny\n")
        cfg = self.config()
        self.assert_fallbacks(cfg)
        self.assertNotIn("vless-ws", [i["tag"] for i in cfg["inbounds"]])
        vm = next(i for i in cfg["inbounds"] if i["tag"] == "vmess-ws")
        self.assertEqual((vm["port"], vm["streamSettings"]["wsSettings"]["path"]), (18093, "/second"))

    def test_individual_view_shows_actual_settings_and_link(self):
        result = self.shell("seed\nshow_argo_protocol vmess-ws || exit 1\n")
        self.assertIn("/deployed-vmess", result.stdout)
        link = next(line for line in result.stdout.splitlines() if line.startswith("vmess://"))
        data = json.loads(base64.b64decode(link[8:]))
        self.assertEqual(data["host"], "argo.example.com")
        self.assertEqual(data["path"], "/deployed-vmess?ed=2560")

    def test_last_delete_stops_tunnel_and_readd_restores_it(self):
        self.shell(r'''
seed
configure_argo_protocol delete vless-ws || exit 1
configure_argo_protocol delete vmess-ws || exit 2
cp "$CONFIG_FILE" "$TEST_ROOT/disabled.json"
load_conf
build_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM" || exit 3
cp "$CONFIG_FILE" "$TEST_ROOT/reinstalled.json"
configure_argo_protocol add vmess-ws || exit 4
''', "y\ny\n18080\n18082\n/deployed-vmess\ny\n")
        for name in ("disabled.json", "reinstalled.json"):
            cfg = json.loads((self.root / name).read_text())
            self.assertFalse({"argo-in", "vless-ws", "vmess-ws"} & {i["tag"] for i in cfg["inbounds"]})
        self.assert_fallbacks(self.config())
        services = (self.root / "services").read_text()
        self.assertIn("stop argov-tunnel", services)
        self.assertIn("disable argov-tunnel", services)
        self.assertIn("restart argov-tunnel", services)

    def test_cancel_and_validation_or_restart_failure_restore_state(self):
        for failure in ("cancel", "reject-config", "reject-restart"):
            with self.subTest(failure=failure):
                marker = "" if failure == "cancel" else f'touch "$TEST_ROOT/{failure}"\n'
                self.shell(r'''
seed
cp "$CONFIG_FILE" "$TEST_ROOT/config.before"
cp "$USER_CONF" "$TEST_ROOT/conf.before"
cp "$ARGOV_USERS_FILE" "$TEST_ROOT/users.before"
''' + marker + r'''
if configure_argo_protocol edit vmess-ws; then exit 1; fi
cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 2
cmp "$USER_CONF" "$TEST_ROOT/conf.before" || exit 3
cmp "$ARGOV_USERS_FILE" "$TEST_ROOT/users.before" || exit 4
''', "cancel\n" if failure == "cancel" else "18092\n/new-vmess\ny\n")
                for name in ("reject-config", "reject-restart"):
                    (self.root / name).unlink(missing_ok=True)

    def test_form_retries_conflicting_ports_and_paths(self):
        result = self.shell("seed\nconfigure_argo_protocol edit vmess-ws || exit 1\n",
                            "bad\n18081\n19999\n18092\nmissing-slash\n/deployed-vless\n/valid\ny\n")
        self.assertIn("路径已被另一种", result.stdout)
        self.assert_fallbacks(self.config())
        self.assertIn("/valid", (self.root / "config.json").read_text())

    def test_menu_independent_delete_and_dynamic_summary(self):
        result = self.shell("seed\nmanage_protocols\nprintf '__SUMMARY__'; get_proto_summary\n", "d2\ny\n0\n")
        self.assertIn("a5", result.stdout)
        self.assertIn("添加 VMess + Argo", result.stdout)
        self.assertEqual(result.stdout.split("__SUMMARY__")[1].strip(), "VL-Argo SS")

    def test_legacy_migration_uses_real_inbounds(self):
        self.shell(r'''
seed
jq '.inbounds |= map(select(.tag!="vmess-ws"))' "$CONFIG_FILE" > "$TEST_ROOT/cfg.tmp"
mv "$TEST_ROOT/cfg.tmp" "$CONFIG_FILE"
sed -i '/^ENABLE_VLESS_ARGO=/d; /^ENABLE_VMESS_ARGO=/d; /^VLESS_WS_PATH=/d; /^VMESS_WS_PATH=/d' "$USER_CONF"
load_conf
[ "$ENABLE_VLESS_ARGO:$ENABLE_VMESS_ARGO:$VLESS_WS_PATH" = 1:0:/deployed-vless ] || exit 1
build_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM" || exit 2
''')
        self.assertNotIn("vmess-ws", [i["tag"] for i in self.config()["inbounds"]])
        self.assert_fallbacks(self.config())

    def test_enable_one_protocol_from_legacy_skipped_tunnel(self):
        self.shell(r'''
seed
ARGO_MODE=skip; save_conf
configure_argo_protocol add vmess-ws || exit 1
''', "\n\n\n\ny\n")
        tags = {i["tag"] for i in self.config()["inbounds"]}
        self.assertIn("vmess-ws", tags)
        self.assertNotIn("vless-ws", tags)
        self.assert_fallbacks(self.config())

    def test_failed_tunnel_start_restores_configuration_and_service_definition(self):
        self.shell(r'''
seed
ARGO_MODE=skip; save_conf; rm "$TEST_ROOT/tunnel-active"
printf 'previous service\n' > "$WORK_DIR/tunnel.service"
cp "$CONFIG_FILE" "$TEST_ROOT/config.before"; cp "$USER_CONF" "$TEST_ROOT/conf.before"
restart_protocol_runtime() { [ "$1" != argov-tunnel ]; }
if configure_argo_protocol add vmess-ws; then exit 1; fi
cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 2
cmp "$USER_CONF" "$TEST_ROOT/conf.before" || exit 3
grep -qx 'previous service' "$WORK_DIR/tunnel.service" || exit 4
''', "\n\n\n\ny\n")

    def test_declining_delete_keeps_protocol_and_state(self):
        self.shell(r'''
seed
cp "$CONFIG_FILE" "$TEST_ROOT/config.before"; cp "$USER_CONF" "$TEST_ROOT/conf.before"
if configure_argo_protocol delete vmess-ws; then exit 1; fi
cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 2
cmp "$USER_CONF" "$TEST_ROOT/conf.before" || exit 3
''', "n\n")

    @unittest.skipUnless(shutil.which("xray"), "Optional Xray binary is not on PATH")
    def test_crud_candidates_pass_real_core_validation(self):
        binary = shlex.quote(shutil.which("xray"))
        self.shell('seed\nrm "$WORK_DIR/xray"\nln -s ' + binary + ' "$WORK_DIR/xray"\n' + r'''
configure_argo_protocol delete vmess-ws || exit 1
configure_argo_protocol edit vless-ws || exit 2
configure_argo_protocol add vmess-ws || exit 3
configure_argo_protocol delete vless-ws || exit 4
''', "y\n18091\n/custom-vless\ny\n18092\n/custom-vmess\ny\ny\n")
        self.assert_fallbacks(self.config())
        self.assertNotIn("vless-ws", [i["tag"] for i in self.config()["inbounds"]])

    @unittest.skipUnless(shutil.which("xray"), "Optional Xray binary is not on PATH")
    def test_real_xray_websocket_fallback_traffic(self):
        binary = shutil.which("xray")

        class Origin(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"argov-fallback-ok")

            def log_message(self, *args):
                pass

        origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        self.addCleanup(origin.server_close)
        self.addCleanup(origin.shutdown)

        def free_port():
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                return sock.getsockname()[1]

        def wait_port(port, process):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                self.assertIsNone(process.poll(), "Xray exited before opening the listener")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                        return
                except OSError:
                    time.sleep(0.03)
            self.fail("Xray listener did not become ready")

        def stop(process):
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)

        for vl, vm in ((1, 1), (1, 0), (0, 1)):
            with self.subTest(vless=vl, vmess=vm):
                self.shell(f'seed\nENABLE_VLESS_ARGO={vl}; ENABLE_VMESS_ARGO={vm}\nbuild_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM" || exit 1\n')
                cfg = self.config()
                ports = set()
                for inbound in cfg["inbounds"]:
                    port = free_port()
                    while port in ports:
                        port = free_port()
                    ports.add(port)
                    inbound["port"] = port
                ws = [i for i in cfg["inbounds"] if i["tag"] in ("vless-ws", "vmess-ws")]
                entry = next(i for i in cfg["inbounds"] if i["tag"] == "argo-in")
                entry["settings"]["fallbacks"] = [{"path": i["streamSettings"]["wsSettings"]["path"], "dest": i["port"]} for i in ws] + [{"dest": ws[0]["port"]}]
                server_cfg = self.root / "real-server.json"
                server_cfg.write_text(json.dumps(cfg))
                check = subprocess.run([binary, "run", "-test", "-c", str(server_cfg)], capture_output=True, text=True, timeout=10)
                self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
                with (self.root / "server.log").open("w") as log:
                    server = subprocess.Popen([binary, "run", "-c", str(server_cfg)], stdout=log, stderr=log)
                    try:
                        wait_port(entry["port"], server)
                        for inbound in ws:
                            protocol = inbound["protocol"]
                            socks_port = free_port()
                            user = {"id": UUID, "encryption": "none"} if protocol == "vless" else {"id": UUID, "alterId": 0, "security": "auto"}
                            client_cfg = {"log": {"loglevel": "warning"}, "inbounds": [{"port": socks_port, "listen": "127.0.0.1", "protocol": "socks", "settings": {"auth": "noauth"}}],
                                          "outbounds": [{"protocol": protocol, "settings": {"vnext": [{"address": "127.0.0.1", "port": entry["port"], "users": [user]}]},
                                                         "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": inbound["streamSettings"]["wsSettings"]["path"]}}}]}
                            client_path = self.root / "real-client.json"
                            client_path.write_text(json.dumps(client_cfg))
                            with (self.root / "client.log").open("w") as client_log:
                                client = subprocess.Popen([binary, "run", "-c", str(client_path)], stdout=client_log, stderr=client_log)
                                try:
                                    wait_port(socks_port, client)
                                    with socket.create_connection(("127.0.0.1", socks_port), timeout=5) as conn:
                                        def exact(size):
                                            data = b""
                                            while len(data) < size:
                                                chunk = conn.recv(size-len(data))
                                                self.assertTrue(chunk, "SOCKS handshake ended early")
                                                data += chunk
                                            return data
                                        conn.sendall(b"\x05\x01\x00")
                                        self.assertEqual(exact(2), b"\x05\x00")
                                        conn.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + struct.pack("!H", origin.server_port))
                                        reply = exact(4)
                                        self.assertEqual(reply[:2], b"\x05\x00")
                                        exact(6 if reply[3] == 1 else 18)
                                        conn.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
                                        response = b""
                                        while True:
                                            chunk = conn.recv(4096)
                                            if not chunk:
                                                break
                                            response += chunk
                                        self.assertIn(b"argov-fallback-ok", response)
                                finally:
                                    stop(client)
                    finally:
                        stop(server)

    def test_emitted_subscription_only_contains_present_argo_protocols(self):
        marker = 'cat << \'SUBEOF\'\n'
        generator = self.source.split(marker, 1)[1].split("\nSUBEOF", 1)[0]
        generator = generator.replace("/etc/xray/", str(self.root) + "/").replace("/etc/sing-box/", str(self.root / "sb") + "/")
        generator = generator.replace('USER_TOKEN="${1:-}"', 'curl() { printf "192.0.2.25"; }\nUSER_TOKEN="${1:-}"')
        generated = self.root / "sub_gen.sh"
        generated.write_text(generator, encoding="utf-8")
        for vl, vm in ((1, 1), (1, 0), (0, 1), (0, 0)):
            with self.subTest(vl=vl, vm=vm):
                self.shell(f'seed\nENABLE_VLESS_ARGO={vl}; ENABLE_VMESS_ARGO={vm}\nbuild_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM" || exit 1\nsave_conf\n')
                result = subprocess.run(["bash", str(generated)], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                links = base64.b64decode(result.stdout).decode().splitlines()
                vless = [urlsplit(line) for line in links if line.startswith("vless://")]
                vmess = [json.loads(base64.b64decode(line[8:])) for line in links if line.startswith("vmess://")]
                self.assertEqual(len(vless), vl)
                self.assertEqual(len(vmess), vm)
                if vl:
                    self.assertEqual(parse_qs(vless[0].query)["path"], ["/deployed-vless?ed=2560"])
                if vm:
                    self.assertEqual(vmess[0]["path"], "/deployed-vmess?ed=2560")


if __name__ == "__main__":
    unittest.main()
