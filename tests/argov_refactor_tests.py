#!/usr/bin/env python3
"""Behavior checks for shared persistence, services, entry and traffic collection."""
import json
import hashlib
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = Path(os.environ.get("ARGOV_TEST_SCRIPT", ROOT / "argov.sh"))


@unittest.skipUnless(all(shutil.which(t) for t in ("bash", "jq", "openssl")), "Bash tools required")
class RefactorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="argov-refactor-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()

    def shell(self, body, success=True, inputs=""):
        prefix = f"source {shlex.quote(str(SCRIPT))}\nexport TEST_ROOT={shlex.quote(str(self.root))}\n"
        prefix += r'''
WORK_DIR="$TEST_ROOT"; USER_CONF="$TEST_ROOT/argov.conf"; CONFIG_FILE="$TEST_ROOT/config.json"
ARGOV_USERS_FILE="$TEST_ROOT/users.json"; TUNNEL_LOG="$TEST_ROOT/argo.log"; SCRIPT_PATH="$TEST_ROOT/ag"
WARP_DOMAIN_FILE="$TEST_ROOT/warp_domains.txt"
SB_WORK_DIR="$TEST_ROOT/sb"; SB_CONFIG_FILE="$SB_WORK_DIR/config.json"
HY2_CERT_FILE="$TEST_ROOT/hy2.crt"; HY2_KEY_FILE="$TEST_ROOT/hy2.key"
SB_CERT_FILE="$TEST_ROOT/sb.crt"; SB_KEY_FILE="$TEST_ROOT/sb.key"
SB_HY2_CERT_FILE="$TEST_ROOT/sb-hy2.crt"; SB_HY2_KEY_FILE="$TEST_ROOT/sb-hy2.key"
export PATH="$TEST_ROOT/bin:$PATH"
'''
        result = subprocess.run(["bash", "-c", prefix + body], input=inputs, text=True, capture_output=True, timeout=20)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def fake(self, name, content):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + content, encoding="utf-8")
        path.chmod(0o755)

    def test_source_has_no_startup_and_file_or_pipe_execution_runs_entry(self):
        source = SCRIPT.read_text(encoding="utf-8")
        marker = '# 可作为函数库加载；'
        self.assertIn(marker, source)
        before, guard = source.rsplit(marker, 1)
        # Override only the entry body, so a regression cannot install services.
        entry = self.root / "entry.sh"
        entry.write_text(before + '\nargov_main() { printf "boot:%s\\n" "$*"; }\n# ' + marker + guard, encoding="utf-8")
        quoted = shlex.quote(str(entry))
        sourced = subprocess.run(["bash", "-c", f"source {quoted}"], capture_output=True, text=True, timeout=5)
        self.assertEqual((sourced.returncode, sourced.stdout, sourced.stderr), (0, "", ""))
        direct = subprocess.run(["bash", str(entry), "arg"], capture_output=True, text=True, timeout=5)
        self.assertEqual(direct.stdout, "boot:arg\n")
        piped = subprocess.run(["bash"], input=entry.read_text(), capture_output=True, text=True, timeout=5)
        self.assertEqual(piped.stdout, "boot:\n")
        substitution = subprocess.run(["bash", "-c", f"bash <(cat {quoted})"], capture_output=True, text=True, timeout=5)
        self.assertEqual(substitution.stdout, "boot:\n")

    def test_entry_dispatch_preserves_existing_install_and_cancel_paths(self):
        for existing, canceled, expected in ((True, False, ["migrate", "load", "menu"]),
                                              (False, False, ["migrate", "load", "install", "menu"]),
                                              (False, True, ["migrate", "load", "install"])):
            with self.subTest(existing=existing, canceled=canceled):
                cfg = self.root / "config.json"
                cfg.unlink(missing_ok=True)
                if existing:
                    cfg.write_text("{}")
                result = self.shell(r'''
migrate_argox_to_argov() { echo migrate; }
load_conf() { echo load; }
main_menu() { echo menu; }
interactive_install() { echo install; return ''' + str(int(canceled)) + r'''; }
argov_main
''', success=not canceled)
                self.assertEqual(result.stdout.splitlines(), expected)

    def test_all_saved_fields_round_trip_and_unknown_keys_stay_rejected(self):
        self.shell(r'''
load_conf
for key in "${ARGOV_CONF_KEYS[@]}"; do printf -v "$key" '%s' "saved-$key"; done
NODE_NAME=$'节点 O\x27Reilly "quoted" #1\\path\nline2'
unset XRAY_SHA256
save_conf || exit 1
is_safe_conf_file "$USER_CONF" || exit 2
expected="$NODE_NAME"
NODE_NAME=changed
. "$USER_CONF"
[ "$NODE_NAME" = "$expected" ] && [ -z "$XRAY_SHA256" ] || exit 3
for key in "${ARGOV_CONF_KEYS[@]}"; do
    case "$key" in NODE_NAME|XRAY_SHA256) continue ;; esac
    [ "${!key}" = "saved-$key" ] || exit 4
done
printf 'UNKNOWN_ARGOV_FIELD=value\n' >> "$USER_CONF"
if is_safe_conf_file "$USER_CONF"; then exit 5; fi
''')

    def test_historical_config_fixtures_are_accepted(self):
        fixtures = ROOT / "tests" / "fixtures" / "legacy"
        files = sorted(fixtures.glob("*.conf"))
        self.assertGreater(len(files), 3)
        for path in files:
            with self.subTest(path=path.name):
                self.shell("is_safe_conf_file " + shlex.quote(str(path)))

    def test_persistent_values_cannot_execute_shell(self):
        for value in ("$(touch owned)", "`touch owned`", "${PATH}", "value; touch owned"):
            (self.root / "argov.conf").write_text("NODE_NAME=" + value + "\n")
            self.shell('if is_safe_conf_file "$USER_CONF"; then exit 1; fi\n')
            self.assertFalse((self.root / "owned").exists())

    def setup_service_fakes(self):
        self.fake("systemctl", 'printf "systemd %s\\n" "$*" >> "$TEST_ROOT/services"\n')
        self.fake("rc-service", 'printf "openrc %s\\n" "$*" >> "$TEST_ROOT/services"\n[ "$2" != status ] || echo started\n')
        self.fake("rc-update", 'printf "rc-update %s\\n" "$*" >> "$TEST_ROOT/services"\n')

    def test_lifecycle_calls_each_backend_once_per_service(self):
        self.setup_service_fakes()
        for alpine in (0, 1):
            with self.subTest(alpine=alpine):
                (self.root / "services").unlink(missing_ok=True)
                self.shell(f"IS_ALPINE={alpine}\n" + r'''
SKIP_ARGO=0; SB_ENABLE=true; ARGO_MODE=fixed-token; ARGO_FIXED_DOMAIN=fixed.example.com
singbox_runtime_config_ready() { :; }
sleep() { :; }
setup_traffic_counters() { :; }
save_conf() { :; }
start_services; restart_services; stop_services
''')
                lines = (self.root / "services").read_text().splitlines()
                self.assertTrue(all(line.startswith("openrc " if alpine else "systemd ") for line in lines))
                for action in ("start", "restart", "stop"):
                    if alpine:
                        for service in ("xray", "argov-stats", "argov-sb-stats", "argov-tunnel", "sing-box"):
                            self.assertEqual(lines.count(f"openrc {service} {action}"), 1)
                    else:
                        self.assertEqual(lines.count(f"systemd {action} xray argov-stats argov-sb-stats"), 1)
                        self.assertEqual(lines.count(f"systemd {action} argov-tunnel"), 1)
                        self.assertEqual(lines.count(f"systemd {action} sing-box"), 1)

    def test_disabled_cores_are_not_started_and_backend_failure_propagates(self):
        self.setup_service_fakes()
        self.shell(r'''
IS_ALPINE=1; SKIP_ARGO=1; SB_ENABLE=false
control_runtime_services restart || exit 1
rc-service() { echo "$1" >> "$TEST_ROOT/attempted"; [ "$1" != xray ]; }
if systemctl start xray argov-stats; then exit 2; fi
''')
        lines = (self.root / "services").read_text().splitlines()
        self.assertFalse(any("argov-tunnel" in line or "sing-box" in line for line in lines))
        self.assertEqual((self.root / "attempted").read_text().splitlines(), ["xray", "argov-stats"])

    def test_openrc_crashed_service_is_not_reported_as_running(self):
        result = self.shell(r'''
IS_ALPINE=1; SB_ENABLE=false
rc-service() { echo crashed; return 1; }
pgrep() { return 0; }
get_status
printf '%s %s\n' "$XRAY_RAW" "$TUNNEL_RAW"
''')
        self.assertEqual(result.stdout.strip(), "stopped stopped")

    def setup_collection(self):
        data = {"version": 1, "users": [
            {"name": "default", "uuid": "default-uuid", "token": "keep-token", "used_up": 1, "used_down": 2},
            {"name": "alice", "uuid": "alice-uuid", "enabled": True, "quota_bytes": 250,
             "used_up": 50, "used_down": 100, "sb_prev_in": 200, "sb_prev_out": 100,
             "sb_ports": {"hy2": 80, "tuic": 443}},
            {"name": "bob", "enabled": True, "quota_bytes": 0, "used_up": 0, "used_down": 0,
             "sb_ports": {"ss": 8080}},
        ]}
        (self.root / "users.json").write_text(json.dumps(data))
        self.rules(130, 240)
        self.fake("iptables", r'''
printf '%s\n' "$*" >> "$TEST_ROOT/iptables-calls"
[ ! -f "$TEST_ROOT/fail-iptables" ] || exit 1
case "$*" in
    *INPUT*) cat "$TEST_ROOT/input" ;;
    *OUTPUT*) cat "$TEST_ROOT/output" ;;
    *) exit 1 ;;
esac
''')
        return data

    def rules(self, incoming, outgoing):
        (self.root / "input").write_text(
            f"1 {incoming} ACCEPT tcp -- any any anywhere anywhere tcp dpt:80 /* argov-traffic-in */\n"
            "1 20 ACCEPT udp -- any any anywhere anywhere udp dpt:443 /* argov-traffic-in */\n"
            "1 1000 ACCEPT tcp -- any any anywhere anywhere tcp dpt:8080 /* argov-traffic-in */\n"
            "1 99999 ACCEPT tcp -- any any anywhere anywhere tcp dpt:80 /* unrelated */\n")
        (self.root / "output").write_text(
            f"1 {outgoing} ACCEPT tcp -- any any anywhere anywhere tcp spt:80 /* argov-traffic-out */\n"
            "1 30 ACCEPT udp -- any any anywhere anywhere udp spt:443 /* argov-traffic-out */\n"
            "1 2000 ACCEPT tcp -- any any anywhere anywhere tcp spt:8080 /* argov-traffic-out */\n")

    def test_collector_exact_ports_deltas_quota_and_shared_entry(self):
        before = self.setup_collection()
        self.shell('sb_collect_user_traffic || exit 1\nemit_sb_collect_script > "$TEST_ROOT/collect.sh"\n')
        first = json.loads((self.root / "users.json").read_text())
        self.assertEqual(first["users"][0], before["users"][0])
        alice, bob = first["users"][1:]
        self.assertEqual((alice["used_up"], alice["used_down"], alice["sb_prev_in"], alice["sb_prev_out"]), (100, 170, 270, 150))
        self.assertFalse(alice["enabled"])
        self.assertEqual((bob["used_up"], bob["used_down"]), (1000, 2000))
        self.assertEqual(len((self.root / "iptables-calls").read_text().splitlines()), 2)
        self.shell('ARGOV_USERS_FILE="$ARGOV_USERS_FILE" bash "$TEST_ROOT/collect.sh"\n')
        self.assertEqual(json.loads((self.root / "users.json").read_text()), first)
        self.rules(140, 260)
        self.shell('sb_collect_user_traffic\n')
        third = json.loads((self.root / "users.json").read_text())
        self.assertEqual((third["users"][1]["used_up"], third["users"][1]["used_down"]), (110, 190))
        self.assertFalse(list(self.root.glob(".sb-users.*")))

    def test_failed_sampling_keeps_user_file_and_error_output_usable(self):
        self.setup_collection()
        before = (self.root / "users.json").read_bytes()
        (self.root / "fail-iptables").touch()
        result = self.shell('if sb_collect_user_traffic; then exit 1; fi\necho visible-error >&2\n')
        self.assertEqual((self.root / "users.json").read_bytes(), before)
        self.assertIn("visible-error", result.stderr)

    def test_counter_reset_and_concurrent_collection_do_not_duplicate_usage(self):
        self.setup_collection()
        self.shell('sb_collect_user_traffic\n')
        self.rules(1, 2)
        self.shell('sb_collect_user_traffic\nsb_collect_user_traffic\n')
        current = json.loads((self.root / "users.json").read_text())
        self.assertEqual((current["users"][1]["used_up"], current["users"][1]["used_down"]), (100, 170))
        self.rules(11, 22)
        self.shell('sb_collect_user_traffic &\na=$!\nsb_collect_user_traffic &\nb=$!\nwait "$a" && wait "$b"\n')
        current = json.loads((self.root / "users.json").read_text())
        self.assertEqual((current["users"][1]["used_up"], current["users"][1]["used_down"]), (110, 190))

    def setup_warp(self):
        config = {
            "log": {"loglevel": "warning"}, "current_cdn": "preserved.example.com",
            "api": {"tag": "api", "services": ["StatsService"]}, "stats": {},
            "inbounds": [
                {"tag": "ss", "protocol": "shadowsocks", "listen": "127.0.0.1", "port": 19080,
                 "settings": {"method": "aes-128-gcm", "password": "keep-secret", "network": "tcp,udp"}},
                {"tag": "api-in", "protocol": "dokodemo-door", "listen": "127.0.0.1", "port": 19085,
                 "settings": {"address": "127.0.0.1"}},
            ],
            "outbounds": [
                {"tag": "direct", "protocol": "freedom"}, {"tag": "preserved", "protocol": "blackhole"},
                {"tag": "warp-out", "protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": 40000}]}},
                {"tag": "v6-direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv6"}},
            ],
            "routing": {"domainStrategy": "AsIs", "rules": [
                {"type": "field", "inboundTag": ["api-in"], "outboundTag": "api"},
                {"type": "field", "domain": ["old.example.com"], "outboundTag": "warp-out"},
                {"type": "field", "domain": ["old-v6.example.com"], "outboundTag": "v6-direct"},
                {"type": "field", "domain": ["preserved.example.com"], "outboundTag": "preserved"},
            ]},
        }
        (self.root / "config.json").write_text(json.dumps(config))
        (self.root / "warp_domains.txt").write_text("example.com\nexample.org\n")
        return config

    def test_basic_warp_application_preserves_ipv6_and_other_settings(self):
        before = self.setup_warp()
        self.shell('write_warp_routes socks5 preserve-ipv6\n')
        after = json.loads((self.root / "config.json").read_text())
        self.assertEqual(after["inbounds"], before["inbounds"])
        self.assertEqual(after["api"], before["api"])
        self.assertEqual(after["current_cdn"], before["current_cdn"])
        self.assertEqual(after["outbounds"][:-1], [o for o in before["outbounds"] if o["tag"] != "warp-out"])
        expected = {"type": "field", "outboundTag": "warp-out", "domain": ["example.com", "example.org"]}
        self.assertEqual(after["routing"]["rules"], [expected] + [r for r in before["routing"]["rules"] if r["outboundTag"] != "warp-out"])

    def test_warp_mode_switches_are_idempotent_and_validate_with_optional_xray(self):
        binary = shutil.which("xray")
        if binary:
            (self.root / "xray").symlink_to(binary)
        for mode, expected_tags in (("socks5", ["warp-out"]), ("ipv6", ["v6-direct"]), ("smart", ["v6-direct", "warp-out"])):
            with self.subTest(mode=mode):
                before = self.setup_warp()
                self.shell(f'write_warp_routes {mode} replace\n')
                first = json.loads((self.root / "config.json").read_text())
                self.shell(f'write_warp_routes {mode} replace\n')
                self.assertEqual(json.loads((self.root / "config.json").read_text()), first)
                self.assertEqual(first["inbounds"], before["inbounds"])
                self.assertEqual([o["tag"] for o in first["outbounds"]], ["direct", "preserved"] + expected_tags)
                rules = first["routing"]["rules"]
                self.assertEqual([r["outboundTag"] for r in rules[:len(expected_tags)]], expected_tags)
                self.assertEqual([r["outboundTag"] for r in rules[len(expected_tags):]], ["api", "preserved"])
                if mode == "smart":
                    self.assertIn("google.com", rules[0]["domain"])
                    self.assertEqual(rules[1]["domain"], ["youtube.com", "ytimg.com", "googlevideo.com"])

    def test_warp_validation_rejection_keeps_configuration_and_cleans_candidates(self):
        self.setup_warp()
        before = (self.root / "config.json").read_bytes()
        (self.root / "config.json.bak").write_text("existing-backup")
        self.shell('write_warp_routes invalid replace\n', success=False)
        self.assertEqual((self.root / "config.json.bak").read_text(), "existing-backup")
        binary = self.root / "xray"
        binary.write_text("#!/bin/sh\nexit 1\n")
        binary.chmod(0o755)
        self.shell('write_warp_routes socks5 replace\n', success=False)
        self.assertEqual((self.root / "config.json").read_bytes(), before)
        self.assertFalse(list(self.root.glob("config.json.warp.*")))

    def test_warp_restart_failure_restores_original_bytes(self):
        self.setup_warp()
        before = (self.root / "config.json").read_bytes()
        self.shell(r'''
write_warp_routes ipv6 replace || exit 1
restart_protocol_runtime() { echo "$1" >> "$TEST_ROOT/restarts"; [ -f "$TEST_ROOT/failed" ] && return 0; touch "$TEST_ROOT/failed"; return 1; }
get_status() { :; }
sleep() { :; }
if restart_warp_runtime; then exit 2; fi
''')
        self.assertEqual((self.root / "config.json").read_bytes(), before)
        self.assertEqual((self.root / "restarts").read_text().splitlines(), ["xray", "xray"])

    def test_both_warp_menus_select_their_original_update_policy(self):
        self.setup_warp()
        self.shell(r'''
clear() { :; }
warp_auto_install_socks() { :; }
write_warp_routes() { printf '%s %s\n' "$1" "$2" >> "$TEST_ROOT/policies"; }
restart_warp_runtime() { :; }
warp_apply_routing
warp_py_apply socks5
warp_py_apply ipv6
warp_py_apply smart
''', inputs="\n")
        self.assertEqual((self.root / "policies").read_text().splitlines(), ["socks5 preserve-ipv6", "socks5 replace", "ipv6 replace", "smart replace"])

    def test_warp_writer_handles_quoted_paths_as_data(self):
        before = self.setup_warp()
        path = self.root / "config's copy.json"
        path.write_text(json.dumps(before))
        self.shell('CONFIG_FILE=' + shlex.quote(str(path)) + '\nwrite_warp_routes ipv6 replace\n')
        self.assertEqual(json.loads(path.read_text())["inbounds"], before["inbounds"])

    def prepare_upgrade(self):
        self.setup_warp()
        self.setup_collection()
        self.shell(r'''
load_conf
NODE_NAME='existing-node'; SUB_TOKEN=existing-token; SUB_PATH=/existing-path; SUB_PORT=2096
UUID_CUSTOM=11111111-1111-4111-8111-111111111111
save_conf || exit 1
printf 'existing-xray-binary' > "$WORK_DIR/xray"
printf 'existing-argo-binary' > "$WORK_DIR/argo"
printf 'existing-certificate' > "$HY2_CERT_FILE"
printf 'existing-private-key' > "$HY2_KEY_FILE"
''')
        for name in ("sub_gen.sh", "sb_collect.sh"):
            (self.root / name).write_text("#!/bin/bash\necho legacy-helper\n")
        protected = ("argov.conf", "config.json", "users.json", "xray", "argo", "hy2.crt", "hy2.key")
        return {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in protected}

    def assert_upgrade_preserved(self, before):
        for name, expected in before.items():
            self.assertEqual(hashlib.sha256((self.root / name).read_bytes()).hexdigest(), expected, name)

    def test_existing_helpers_upgrade_atomically_without_restarting_or_changing_nodes(self):
        before = self.prepare_upgrade()
        self.shell(r'''
systemctl() { echo unexpected-service-action >&2; return 1; }
restart_protocol_runtime() { echo unexpected-restart >&2; return 1; }
refresh_generated_helpers || exit 1
''')
        self.assert_upgrade_preserved(before)
        self.assertIn('any(.inbounds[]?; .tag=="vmess-ws")', (self.root / "sub_gen.sh").read_text())
        self.assertIn('for line in os.fdopen(3):', (self.root / "sb_collect.sh").read_text())
        metadata = {name: (self.root / name).stat().st_mtime_ns for name in ("sub_gen.sh", "sb_collect.sh")}
        self.shell('refresh_generated_helpers\n')
        self.assertEqual({name: (self.root / name).stat().st_mtime_ns for name in metadata}, metadata)
        self.assertFalse(list(self.root.glob("*.new.*")))

    def test_invalid_upgrade_payload_keeps_old_helper_and_does_not_create_missing_services(self):
        before = self.prepare_upgrade()
        previous = (self.root / "sub_gen.sh").read_bytes()
        self.shell(r'''
emit_sub_generator() { printf '#!/bin/bash\nif'; }
if refresh_generated_helpers; then exit 1; fi
''')
        self.assertEqual((self.root / "sub_gen.sh").read_bytes(), previous)
        self.assert_upgrade_preserved(before)
        self.assertFalse(list(self.root.glob("*.new.*")))
        (self.root / "sub_gen.sh").unlink()
        (self.root / "sb_collect.sh").unlink()
        self.shell('refresh_generated_helpers\n')
        self.assertFalse((self.root / "sub_gen.sh").exists())
        self.assertFalse((self.root / "sb_collect.sh").exists())

    def test_panel_entry_refreshes_helpers_and_update_hands_off_without_old_writers(self):
        before = self.prepare_upgrade()
        common = r'''
clear() { :; }
logo() { :; }
setup_traffic_counters() { :; }
collect_traffic() { :; }
refresh_certificate_pins() { return 1; }
get_status() { XRAY_RAW=stopped; TUNNEL_RAW=stopped; XRAY_ST=stopped; TUNNEL_ST=stopped; SB_ST=''; }
start_sub_server() { echo unexpected-old-writer >&2; exit 9; }
start_sb_stats_service() { echo unexpected-old-writer >&2; exit 9; }
download_script_checked() { printf '#!/bin/bash\necho updated-panel\n' > "$2"; }
main_menu
'''
        self.shell(common, inputs="0\n")
        self.assertNotIn("legacy-helper", (self.root / "sub_gen.sh").read_text())
        result = self.shell(common, inputs="8\n")
        self.assertIn("updated-panel", result.stdout)
        self.assertNotIn("unexpected-old-writer", result.stderr)
        self.assert_upgrade_preserved(before)


if __name__ == "__main__":
    unittest.main()
