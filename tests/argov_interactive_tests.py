#!/usr/bin/env python3
"""Exercise real Bash forms and config writers in temporary directories.

Optional Xray/sing-box binaries on PATH also validate generated configurations.
No installation, service restart or firewall command is run on the test host.
"""
import base64
import json
import os
import shlex
import shutil
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = Path(os.environ.get("ARGOV_TEST_SCRIPT", ROOT / "argov.sh"))
HAS_TOOLS = all(shutil.which(tool) for tool in ("bash", "jq", "openssl"))


@unittest.skipUnless(HAS_TOOLS, "Bash, jq and openssl are needed for interactive tests")
class InteractiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library_dir = tempfile.TemporaryDirectory(prefix="argov-library-")
        cls.library = Path(cls.library_dir.name) / "library.sh"
        source = SCRIPT.read_text(encoding="utf-8")
        source = source.split("\nmigrate_argox_to_argov\nload_conf\n", 1)[0]
        cls.library.write_text(source, encoding="utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.library_dir.cleanup()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="argov-form-")
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def run_shell(self, body, inputs="", success=True):
        prefix = f"source {shlex.quote(str(self.library))}\nTEST_ROOT={shlex.quote(str(self.root))}\n"
        prefix += r'''
WORK_DIR="$TEST_ROOT"
USER_CONF="$TEST_ROOT/argov.conf"
CONFIG_FILE="$TEST_ROOT/xray.json"
ARGOV_USERS_FILE="$TEST_ROOT/users.json"
SB_WORK_DIR="$TEST_ROOT/sb"
SB_CONFIG_FILE="$SB_WORK_DIR/config.json"
HY2_CERT_FILE="$TEST_ROOT/hy2.crt"; HY2_KEY_FILE="$TEST_ROOT/hy2.key"
SB_CERT_FILE="$TEST_ROOT/tuic.crt"; SB_KEY_FILE="$TEST_ROOT/tuic.key"
SB_HY2_CERT_FILE="$TEST_ROOT/sb-hy2.crt"; SB_HY2_KEY_FILE="$TEST_ROOT/sb-hy2.key"
ARGO_MODE=skip
clear() { :; }
load_conf
'''
        result = subprocess.run(
            ["bash", "-c", prefix + body], input=inputs, text=True, capture_output=True, timeout=30
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def result_json(self, result):
        return json.loads(result.stdout.rsplit("__RESULT__\n", 1)[1])

    def test_domain_validation_and_normalization(self):
        result = self.run_shell(r'''
printf '__RESULT__\n'
normalize_domain ' HTTPS://Example.COM/ '
''')
        self.assertEqual(result.stdout.split("__RESULT__\n")[1], "example.com")
        for invalid in ("", "a..com", "-bad.com", "a.com/path", "a.com:443", "127.0.0.1", "a.com?x", "x" * 64 + ".com"):
            with self.subTest(invalid=invalid):
                result = self.run_shell("normalize_domain " + shlex.quote(invalid), success=False)
                self.assertNotEqual(result.returncode, 0)

    def test_required_domain_retries_and_cancel_keeps_value(self):
        result = self.run_shell(r'''
target=old.example.com
prompt_domain target "" SNI || exit 1
printf '\n__RESULT__\n'
jq -n --arg value "$target" '{value:$value}'
''', "\ninvalid/host\nHTTPS://Chosen.Example.COM/\n")
        self.assertEqual(self.result_json(result)["value"], "chosen.example.com")
        for inputs in ("0\n", ""):
            result = self.run_shell(r'''
target=old.example.com
if prompt_domain target "" SNI; then exit 9; fi
printf '\n__RESULT__\n'; jq -n --arg value "$target" '{value:$value}'
''', inputs)
            self.assertEqual(self.result_json(result)["value"], "old.example.com")

    def test_fresh_hy2_install_asks_domain_and_brutal_bandwidth(self):
        result = self.run_shell(r'''
select_protocols || exit 1
printf '\n__RESULT__\n'
build_hy2_inbound "$HY2_PORT" "$HY2_SNI" test-auth default "$HY2_MPORT" "$HY2_CONGESTION" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS"
''', "2\n0\nuser.example.com\n24567\nbrutal\n80\n120\noff\ny\n")
        inbound = self.result_json(result)
        self.assertEqual(inbound["streamSettings"]["tlsSettings"]["serverName"], "user.example.com")
        params = inbound["streamSettings"]["finalmask"]["quicParams"]
        self.assertEqual(params, {"congestion": "brutal", "brutalUp": "80 mbps", "brutalDown": "120 mbps"})
        self.assertFalse((self.root / "argov.conf").exists(), "The form must not persist before the complete installer confirms")

    def test_congestion_invalid_input_retries_and_switch_clears_bandwidth(self):
        result = self.run_shell(r'''
prompt_hy2_congestion mode up down xray bbr "" "" || exit 1
prompt_hy2_congestion mode up down xray "$mode" "$up" "$down" || exit 1
printf '\n__RESULT__\n'; jq -n --arg mode "$mode" --arg up "$up" --arg down "$down" '{mode:$mode,up:$up,down:$down}'
''', "bad\n2\n-1\nfoo\n0\n80\n120\n1\n")
        self.assertEqual(self.result_json(result), {"mode": "bbr", "up": "", "down": ""})
        result = self.run_shell(r'''
mode=bbr; up=""; down=""
if prompt_hy2_congestion mode up down xray bbr "" ""; then exit 2; fi
printf '\n__RESULT__\n'; jq -n --arg mode "$mode" '{mode:$mode}'
''', "2\ncancel\n")
        self.assertEqual(self.result_json(result)["mode"], "bbr")

    def test_port_retries_and_preserves_current_listener(self):
        result = self.run_shell(r'''
SUB_PORT=24567
port_in_use_any() { [ "$1" = 24568 ]; }
prompt_port result 25000 HY2 HY2_PORT || exit 1
prompt_port unchanged 24568 HY2 HY2_PORT 24568 || exit 1
printf '\n__RESULT__\n'; jq -n --arg value "$result" --arg current "$unchanged" '{value:$value,current:$current}'
''', "65536\nabc\n24567\n24568\n025000\n25000\n\n")
        self.assertEqual(self.result_json(result), {"value": "25000", "current": "24568"})

    def test_free_port_exhaustion_reports_failure(self):
        result = self.run_shell(r'''
port_in_use() { return 0; }
port_in_use_any() { return 0; }
if find_free_port 65535; then exit 7; fi
if find_free_any_port 65535; then exit 8; fi
''')
        self.assertEqual(result.returncode, 0)

    def test_ipv6_port_detection(self):
        if not socket.has_ipv6:
            self.skipTest("IPv6 is unavailable")
        with socket.socket(socket.AF_INET6, socket.SOCK_STREAM) as listener:
            try:
                listener.bind(("::1", 0)); listener.listen()
            except OSError:
                self.skipTest("IPv6 loopback is unavailable")
            port = listener.getsockname()[1]
            self.run_shell(f"port_in_use_tcp {port}")
        with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as listener:
            listener.bind(("::1", 0))
            self.run_shell(f"port_in_use_udp {listener.getsockname()[1]}")

    def test_hopping_retries_and_can_be_disabled(self):
        result = self.run_shell(r'''
prompt_hy2_hopping range "" || exit 1
prompt_hy2_hopping range "$range" || exit 1
printf '\n__RESULT__\n'; jq -n --arg value "$range" '{value:$value}'
''', "60000-1000\nabc\n47000-48000\noff\n")
        self.assertEqual(self.result_json(result)["value"], "")

    def test_new_singbox_form_and_independent_domains(self):
        result = self.run_shell(r'''
singbox_supports_bbr_profile() { return 1; }
configure_sb_protocol HY2 || exit 1
SB_ANYTLS_SNI=anytls.example.com; SB_REALITY_SNI=reality.example.com
printf '\n__RESULT__\n'; jq -n --arg hy "$SB_HY2_SNI" --arg shared "$SB_SNI" --arg mode "$SB_HY2_CONGESTION" '{hy:$hy,shared:$shared,mode:$mode}'
''', "24567\nmy-hy2.example.com\nbrutal\n80\n120\noff\npassword-with-@&\\quotes\n")
        self.assertEqual(self.result_json(result), {"hy": "my-hy2.example.com", "shared": "addons.mozilla.org", "mode": "brutal"})

    def test_singbox_congestion_emitted_and_binary_accepts(self):
        for mode in ("bbr", "brutal", "auto", "reno"):
            with self.subTest(mode=mode):
                result = self.run_shell(f"SB_HY2_CONGESTION={mode}\n" + r'''
SB_HY2_ENABLE=true; SB_HY2_PORT=24567; SB_HY2_SNI=hy2.example.com
SB_HY2_PSK='password-"&|\@'
SB_HY2_UP_MBPS=80; SB_HY2_DOWN_MBPS=120
sb_sync_users() { :; }
generate_singbox_hy2_cert || exit 1
build_singbox_config || exit 1
printf '\n__RESULT__\n'; cat "$SB_CONFIG_FILE"
''')
                config = self.result_json(result)
                inbound = config["inbounds"][0]
                self.assertEqual(inbound["users"][0]["password"], 'password-"&|\\@')
                if mode == "brutal":
                    self.assertEqual(inbound["up_mbps"], 80)
                    self.assertEqual(inbound["down_mbps"], 120)
                    self.assertFalse(inbound["ignore_client_bandwidth"])
                else:
                    self.assertNotIn("up_mbps", inbound)
                    self.assertNotIn("down_mbps", inbound)
                    if mode == "bbr":
                        self.assertTrue(inbound["ignore_client_bandwidth"])
                    else:
                        self.assertNotIn("ignore_client_bandwidth", inbound)

    def test_singbox_validation_failure_keeps_previous_config(self):
        result = self.run_shell(r'''
mkdir -p "$SB_WORK_DIR"
printf '{"inbounds":[],"outbounds":[{"type":"direct","tag":"previous"}]}\n' > "$SB_CONFIG_FILE"
cp "$SB_CONFIG_FILE" "$TEST_ROOT/before.json"
SB_HY2_ENABLE=true; SB_HY2_PORT=24567; SB_HY2_CONGESTION=brutal
SB_HY2_UP_MBPS=bad; SB_HY2_DOWN_MBPS=80
sb_sync_users() { :; }
if build_singbox_config; then exit 7; fi
cmp "$SB_CONFIG_FILE" "$TEST_ROOT/before.json"
''')
        self.assertEqual(result.returncode, 0)

    def test_certificate_reuse_and_domain_rotation(self):
        result = self.run_shell(r'''
HY2_SNI=first.example.com
gen_hy2_cert || exit 1
first="$HY2_PIN_SHA256"
gen_hy2_cert || exit 1
[ "$first" = "$HY2_PIN_SHA256" ] || exit 2
HY2_SNI=second.example.com
gen_hy2_cert || exit 1
[ "$first" != "$HY2_PIN_SHA256" ] || exit 3
openssl x509 -in "$HY2_CERT_FILE" -noout -ext subjectAltName
''')
        self.assertIn("DNS:second.example.com", result.stdout)

    def test_new_settings_round_trip_and_legacy_inheritance(self):
        result = self.run_shell(r'''
SB_HY2_ENABLE=true; SB_HY2_SNI=hy2.example.com; SB_TUIC_SNI=tuic.example.com
SB_ANYTLS_SNI=anytls.example.com; SB_REALITY_SNI=reality.example.com
SB_SS_METHOD=chacha20-ietf-poly1305; SB_HY2_PSK='safe-"&|\@'
save_conf || exit 1
is_safe_conf_file "$USER_CONF" || exit 2
SB_HY2_SNI=changed; SB_TUIC_SNI=changed; SB_SS_METHOD=changed
load_conf
printf '\n__RESULT__\n'; jq -n --arg hy "$SB_HY2_SNI" --arg tuic "$SB_TUIC_SNI" --arg ss "$SB_SS_METHOD" '{hy:$hy,tuic:$tuic,ss:$ss}'
''')
        self.assertEqual(self.result_json(result), {"hy": "hy2.example.com", "tuic": "tuic.example.com", "ss": "chacha20-ietf-poly1305"})
        (self.root / "argov.conf").write_text('SB_HY2_ENABLE=true\nSB_SNI=legacy.example.com\nSS_METHOD=aes-128-gcm\n', encoding="utf-8")
        result = self.run_shell(r'''
printf '\n__RESULT__\n'; jq -n --arg hy "$SB_HY2_SNI" --arg anytls "$SB_ANYTLS_SNI" --arg ss "$SB_SS_METHOD" '{hy:$hy,anytls:$anytls,ss:$ss}'
''')
        self.assertEqual(self.result_json(result), {"hy": "legacy.example.com", "anytls": "legacy.example.com", "ss": "aes-128-gcm"})

    def test_failed_edit_restores_files(self):
        before = {"argov.conf": b"NODE_NAME=previous\n", "xray.json": b'{"inbounds":[]}\n', "users.json": b'{"users":[]}\n'}
        for filename, content in before.items():
            (self.root / filename).write_bytes(content)
        self.run_shell(r'''
restart_protocol_runtime() { :; }
begin_protocol_edit xray || exit 2
printf changed > "$USER_CONF"; printf changed > "$CONFIG_FILE"; printf changed > "$ARGOV_USERS_FILE"
printf new-cert > "$HY2_CERT_FILE"
exit 1
''', success=False)
        for filename, content in before.items():
            self.assertEqual((self.root / filename).read_bytes(), content)
        self.assertFalse((self.root / "hy2.crt").exists())

    def test_encoded_password_and_ipv6_link(self):
        result = self.run_shell(r'''
SB_HY2_PIN_SHA256=""
printf '__RESULT__\n'
gen_sb_hy2_link 'p@ss:"&|\word' '2001:db8::1' 24567 hy2.example.com '测试节点' ""
''')
        from urllib.parse import unquote, urlsplit
        link = urlsplit(result.stdout.split("__RESULT__\n")[1])
        self.assertEqual(link.hostname, "2001:db8::1")
        self.assertEqual(unquote(link.username), 'p@ss:"&|\\word')
        self.assertEqual(unquote(link.fragment), "测试节点")

    def test_selection_eof_cancels_and_singbox_rejects_reno(self):
        self.run_shell("if select_protocols; then exit 7; fi", "")
        result = self.run_shell(r'''
prompt_hy2_congestion mode up down singbox bbr "" "" || exit 1
printf '\n__RESULT__\n'; jq -n --arg mode "$mode" '{mode:$mode}'
''', "reno\nbbr\n")
        self.assertEqual(self.result_json(result)["mode"], "bbr")
        self.assertIn("不支持 Reno", result.stdout)

    def test_hopping_ranges_cannot_overlap_other_protocols(self):
        self.run_shell(r'''
ARGO_MODE=skip; ARGO_PORT=8080
configured_port_conflict 8080 SB_REALITY_PORT || exit 5
ENABLE_HY2=1; HY2_PORT=24567; HY2_MPORT=47000-48000
SB_HY2_ENABLE=true; SB_HY2_PORT=24568
SB_HY2_HOP_ENABLE=true; SB_HY2_HOP_START=49000; SB_HY2_HOP_END=50000
configured_port_conflict 47500 SB_TUIC_PORT || exit 1
configured_port_conflict 49500 HY2_PORT || exit 2
configured_port_conflict 48000 SB_HY2_PORT 49000 || exit 3
if configured_port_conflict 51000 SB_HY2_PORT 52000; then exit 4; fi
''')

    def test_bbr_profile_only_emitted_for_supported_version(self):
        for version in ("1.13.0", "1.14.3"):
            with self.subTest(version=version):
                result = self.run_shell(f"singbox_version_string() {{ echo {version}; }}\n" + r'''
SB_HY2_ENABLE=true; SB_HY2_PORT=24567; SB_HY2_SNI=hy2.example.com
SB_HY2_PSK=test-password; SB_HY2_CONGESTION=bbr; SB_HY2_BBR_PROFILE=aggressive
generate_singbox_hy2_cert || exit 1
build_singbox_config || exit 1
printf '\n__RESULT__\n'; cat "$SB_CONFIG_FILE"
''')
                inbound = self.result_json(result)["inbounds"][0]
                if version == "1.14.3":
                    self.assertEqual(inbound["bbr_profile"], "aggressive")
                else:
                    self.assertNotIn("bbr_profile", inbound)

    def test_singbox_rebuild_preserves_relay_and_rejects_broken_snapshot(self):
        (self.root / "sb").mkdir()
        before = {
            "inbounds": [],
            "outbounds": [
                {"type": "direct", "tag": "direct"},
                {"type": "socks", "tag": "argov-relay", "server": "127.0.0.1", "server_port": 1080}
            ],
            "route": {"final": "argov-relay"}
        }
        config = self.root / "sb" / "config.json"
        config.write_text(json.dumps(before), encoding="utf-8")
        result = self.run_shell(r'''
SB_ENABLE=true; RELAY_ENABLED=1
build_singbox_config || exit 1
printf '\n__RESULT__\n'; cat "$SB_CONFIG_FILE"
''')
        after = self.result_json(result)
        self.assertEqual(after["route"]["final"], "argov-relay")
        self.assertIn(before["outbounds"][1], after["outbounds"])
        config.write_text("broken-previous-config", encoding="utf-8")
        self.run_shell(r'''
SB_ENABLE=true; RELAY_ENABLED=1
if build_singbox_config; then exit 2; fi
[ "$(cat "$SB_CONFIG_FILE")" = broken-previous-config ]
''')
        self.assertEqual(list(config.parent.glob("config.json.tmp.*")), [])

    def test_ss2022_user_keys_and_independent_inbound_domains(self):
        users = {"users": [
            {"name": "default", "uuid": "11111111-1111-4111-8111-111111111111"},
            {"name": "alice", "uuid": "22222222-2222-4222-8222-222222222222", "sb_creds": {"ss_pass": "legacy-invalid"}}
        ]}
        (self.root / "users.json").write_text(json.dumps(users), encoding="utf-8")
        for method, size in (("2022-blake3-aes-128-gcm", 16), ("2022-blake3-aes-256-gcm", 32)):
            with self.subTest(method=method):
                result = self.run_shell(f"SB_SS_METHOD={method}\n" + r'''
SB_ENABLE=true
SB_TUIC_ENABLE=true; SB_TUIC_PORT=24001; SB_TUIC_SNI=tuic.example.com
SB_TUIC_UUID=33333333-3333-4333-8333-333333333333; SB_TUIC_PSK='tuic-p@"'
SB_ANYTLS_ENABLE=true; SB_ANYTLS_PORT=24101; SB_ANYTLS_SNI=anytls.example.com; SB_ANYTLS_PSK='anytls-p@"'
SB_REALITY_ENABLE=true; SB_REALITY_PORT=24201; SB_REALITY_SNI=reality.example.com
SB_SS_ENABLE=true; SB_SS_PORT=24301; SB_SS_PSK=$(gen_ss2022_pass "$SB_SS_METHOD")
SB_REALITY_PRIV=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; SB_REALITY_SID=11223344
generate_singbox_cert || exit 1
build_singbox_config || exit 1
cp "$ARGOV_USERS_FILE" "$TEST_ROOT/users-before.json"
sb_sync_users || exit 1
cmp "$ARGOV_USERS_FILE" "$TEST_ROOT/users-before.json" || exit 2
printf '\n__RESULT__\n'; cat "$SB_CONFIG_FILE"
''')
                inbounds = self.result_json(result)["inbounds"]
                ss = [i for i in inbounds if i["type"] == "shadowsocks"]
                self.assertEqual(len(ss), 2)
                for inbound in ss:
                    self.assertEqual(len(base64.b64decode(inbound["password"], validate=True)), size)
                    self.assertEqual(inbound["method"], method)
                for inbound in inbounds:
                    if inbound["type"] == "anytls":
                        self.assertEqual(inbound["tls"]["server_name"], "anytls.example.com")
                    if inbound["type"] == "vless":
                        self.assertEqual(inbound["tls"]["server_name"], "reality.example.com")

    def test_actual_hy2_editor_rolls_back_when_restart_fails(self):
        self.run_shell(r'''
ENABLE_HY2=1; HY2_PORT=24567; HY2_SNI=previous.example.com; HY2_CONGESTION=bbr; HY2_MPORT=""
gen_hy2_cert || exit 1
build_hy2_inbound "$HY2_PORT" "$HY2_SNI" test-auth default "" bbr "" "" |
    jq '{inbounds:[.],outbounds:[{protocol:"freedom"}]}' > "$CONFIG_FILE"
printf '{"users":[]}\n' > "$ARGOV_USERS_FILE"
save_conf || exit 1
for file in argov.conf xray.json users.json hy2.crt hy2.key; do
    cp "$TEST_ROOT/$file" "$TEST_ROOT/$file.before" || exit 2
done
restart_protocol_runtime() { echo attempted >> "$TEST_ROOT/restarts"; return 1; }
start_sub_server() { echo unexpected > "$TEST_ROOT/sub-started"; }
if edit_hy2_protocol; then exit 9; fi
for file in argov.conf xray.json users.json hy2.crt hy2.key; do
    cmp "$TEST_ROOT/$file" "$TEST_ROOT/$file.before" || exit 3
done
[ "$(wc -l < "$TEST_ROOT/restarts")" -eq 2 ] || exit 4
[ ! -f "$TEST_ROOT/sub-started" ]
''', "changed.example.com\n\nbrutal\n80\n120\noff\ny\n")

    def test_standalone_subscription_generates_hy2_settings(self):
        # Execute the exact emitted sub_gen.sh, redirecting only host paths/IP discovery.
        source = SCRIPT.read_text(encoding="utf-8")
        marker = 'cat > "${WORK_DIR}/sub_gen.sh" << \'SUBEOF\'\n'
        generator = source.split(marker, 1)[1].split("\nSUBEOF", 1)[0]
        generator = generator.replace("/etc/xray/", str(self.root) + "/")
        generator = generator.replace("/etc/sing-box/", str(self.root / "sb") + "/")
        generator = generator.replace("/usr/bin/jq", shutil.which("jq"))
        generator = generator.replace('USER_TOKEN="${1:-}"', 'curl() { printf "192.0.2.25"; }\nUSER_TOKEN="${1:-}"')
        generated = self.root / "sub_gen.sh"
        generated.write_text(generator, encoding="utf-8")
        self.run_shell(r'''
NODE_NAME='测试 "节点"&'
ARGO_MODE=fixed-token; ARGO_FIXED_DOMAIN=argo.example.com
ENABLE_HY2=1; HY2_PORT=24567; HY2_SNI=xray.example.com; HY2_CONGESTION=brutal
HY2_UP_MBPS=80; HY2_DOWN_MBPS=120; HY2_PIN_SHA256=$(printf 'ab%.0s' {1..32})
build_hy2_inbound "$HY2_PORT" "$HY2_SNI" 11111111-1111-4111-8111-111111111111 default "" brutal 80 120 |
    jq '{inbounds:[.],current_cdn:"cdn.example.com",current_cdn_port:443}' > "$WORK_DIR/config.json"
SB_ENABLE=true; SB_HY2_ENABLE=true; SB_HY2_PORT=24568; SB_HY2_SNI=sb.example.com
SB_HY2_PSK='p@ss:"&\word'; SB_HY2_CONGESTION=brutal
SB_HY2_UP_MBPS=40; SB_HY2_DOWN_MBPS=60; SB_HY2_PIN_SHA256=$(printf 'cd%.0s' {1..32})
mkdir -p "$SB_WORK_DIR"; printf '{"inbounds":[]}' > "$SB_CONFIG_FILE"
printf '{"users":[{"name":"default","uuid":"11111111-1111-4111-8111-111111111111","token":"default-token"}]}' > "$ARGOV_USERS_FILE"
cp "$ARGOV_USERS_FILE" "$WORK_DIR/argov_users.json"
save_conf || exit 1
''')
        result = subprocess.run(["bash", str(generated)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "", "The standalone generator must not call local outside functions")
        links = base64.b64decode(result.stdout).decode().splitlines()
        from urllib.parse import parse_qs, unquote, urlsplit
        hy2 = [urlsplit(link) for link in links if link.startswith(("hysteria2://", "hy2://"))]
        self.assertEqual(len(hy2), 2)
        self.assertEqual(parse_qs(hy2[0].query)["up"], ["120mbps"])
        self.assertEqual(parse_qs(hy2[0].query)["down"], ["80mbps"])
        self.assertEqual(parse_qs(hy2[1].query)["sni"], ["sb.example.com"])
        self.assertEqual(parse_qs(hy2[1].query)["up"], ["60mbps"])
        self.assertEqual(parse_qs(hy2[1].query)["down"], ["40mbps"])
        self.assertEqual(unquote(hy2[1].username), 'p@ss:"&\\word')
        self.assertEqual(unquote(hy2[1].fragment), '测试 "节点"&-SingBox-HY2')
        vmess = next(link for link in links if link.startswith("vmess://"))
        self.assertEqual(json.loads(base64.b64decode(vmess[8:]))["ps"], '测试 "节点"&-VMess')
        ns = {"base64": base64, "json": json, "urllib": __import__("urllib.parse")}
        converter = source.split("def to_yaml(data, level=0):", 1)[1].split("def load_users():", 1)[0]
        exec("def to_yaml(data, level=0):" + converter, ns)
        yaml = ns["build_clash"](links)
        self.assertIn('up: "60mbps"', yaml)
        self.assertIn('fingerprint: "' + "cd" * 32 + '"', yaml)
        # Exercise the independent per-user branch too; no global declarations
        # may be mistaken for commands, and deleted protocols must disappear.
        self.run_shell(r'''
SB_TUIC_ENABLE=true; SB_TUIC_PORT=24001; SB_TUIC_SNI=tuic.example.com
SB_TUIC_UUID=33333333-3333-4333-8333-333333333333; SB_TUIC_PSK=default-tuic
SB_ANYTLS_ENABLE=true; SB_ANYTLS_PORT=24101; SB_ANYTLS_SNI=anytls.example.com; SB_ANYTLS_PSK=default-anytls
SB_REALITY_ENABLE=true; SB_REALITY_PORT=24201; SB_REALITY_SNI=reality.example.com
SB_SS_ENABLE=true; SB_SS_PORT=24301; SB_SS_METHOD=aes-256-gcm; SB_SS_PSK=default-ss
save_conf || exit 1
''')
        users = json.loads((self.root / "argov_users.json").read_text(encoding="utf-8"))
        users["users"].append({
            "name": "alice", "uuid": "22222222-2222-4222-8222-222222222222", "token": "alice-token",
            "sb_ports": {"tuic": 25001, "anytls": 25101, "reality": 25201, "ss": 25301},
            "sb_creds": {"tuic_uuid": "33333333-3333-4333-8333-333333333333",
                         "tuic_pass": 'tuic@"&', "anytls_pass": 'anytls@"&', "ss_pass": 'ss@"&'}
        })
        (self.root / "argov_users.json").write_text(json.dumps(users), encoding="utf-8")
        result = subprocess.run(["bash", str(generated), "alice-token"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        user_links = base64.b64decode(result.stdout).decode().splitlines()
        tuic = urlsplit(next(link for link in user_links if link.startswith("tuic://")))
        self.assertEqual(tuic.port, 25001)
        self.assertEqual(unquote(tuic.password), 'tuic@"&')
        anytls = urlsplit(next(link for link in user_links if link.startswith("anytls://")))
        self.assertEqual(parse_qs(anytls.query)["sni"], ["anytls.example.com"])
        self.assertEqual(unquote(anytls.username), 'anytls@"&')
        ss = urlsplit(next(link for link in user_links if link.startswith("ss://")))
        self.assertEqual(base64.b64decode(ss.username).decode(), 'aes-256-gcm:ss@"&')
        with (self.root / "argov.conf").open("a", encoding="utf-8") as conf:
            conf.write("\nSB_TUIC_ENABLE=false\nSB_ANYTLS_ENABLE=false\nSB_REALITY_ENABLE=false\nSB_SS_ENABLE=false\n")
        result = subprocess.run(["bash", str(generated), "alice-token"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        disabled_links = base64.b64decode(result.stdout).decode().splitlines()
        self.assertFalse(any(link.startswith(("tuic://", "anytls://", "ss://")) for link in disabled_links))
        self.assertFalse(any("@192.0.2.25:25201?" in link for link in disabled_links))

    @unittest.skipUnless(shutil.which("xray"), "Optional Xray binary is not on PATH")
    def test_xray_accepts_generated_algorithms(self):
        for mode in ("bbr", "brutal", "reno", "auto", "cubic"):
            with self.subTest(mode=mode):
                self.run_shell(f"HY2_CONGESTION={mode}\n" + r'''
HY2_SNI=hy2.example.com; HY2_UP_MBPS=80; HY2_DOWN_MBPS=120
gen_hy2_cert || exit 1
UUID_CUSTOM=11111111-1111-4111-8111-111111111111
inbound=$(build_hy2_inbound 24567 "$HY2_SNI" "$UUID_CUSTOM" default "" "$HY2_CONGESTION" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS")
jq -n --argjson inbound "$inbound" '{inbounds:[$inbound,{tag:"vless-ws",protocol:"vless",listen:"127.0.0.1",port:24568,settings:{clients:[],decryption:"none"}}],outbounds:[{protocol:"freedom"}]}' > "$CONFIG_FILE"
printf '{"users":[{"name":"default","uuid":"11111111-1111-4111-8111-111111111111","token":"default-token"},{"name":"alice","uuid":"22222222-2222-4222-8222-222222222222","token":"alice-token"}]}' > "$ARGOV_USERS_FILE"
sync_xray_users || exit 2
jq -e '(.inbounds[]|select(.tag=="hy2")|.settings.users|length)==2 and (.inbounds[]|select(.tag=="vless-ws")|.settings.clients|length)==2' "$CONFIG_FILE" >/dev/null || exit 3
[ "$(get_uuid)" = "$UUID_CUSTOM" ] || exit 4
xray run -test -config "$CONFIG_FILE"
''')


if __name__ == "__main__":
    unittest.main()
