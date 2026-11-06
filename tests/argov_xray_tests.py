#!/usr/bin/env python3
"""Check every Xray preflight path and direct-protocol edits in isolation.

Real-core checks use xray from PATH; downloads and service/firewall commands are
never run against the test host. Run under each binary with run_xray_matrix.py.
"""
import json
import shlex
import shutil
import unittest

import argov_argo_tests as argo_fixture


HAS_TOOLS = all(shutil.which(tool) for tool in ("bash", "jq", "openssl"))
HAS_XRAY = HAS_TOOLS and shutil.which("xray")


@unittest.skipUnless(HAS_TOOLS, "Bash tools required")
class XrayTests(unittest.TestCase):
    def setUp(self):
        self.reset_fixture()

    def reset_fixture(self):
        self.fixture = argo_fixture.ArgoTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root

    def shell(self, body, inputs=""):
        binary = shlex.quote(shutil.which("xray") or "/missing-xray")
        prefix = r'''
sleep() { :; }
get_status() { :; }
get_ip() { printf '192.0.2.25'; }
get_argo_domain() { printf 'argo.example.com'; }
port_in_use() { return 1; }
find_free_port() { [ "${1:-0}" -gt 0 ] && printf '%s' "$1" || printf '18123'; }
apply_hy2_hop_rules() { printf 'apply %s %s\n' "$1" "$2" >> "$TEST_ROOT/hop-events"; }
disable_hy2_hop_rules() { printf 'disable %s %s\n' "$1" "$2" >> "$TEST_ROOT/hop-events"; }
seed_real() {
    seed
    rm "$WORK_DIR/xray"
    ln -s ''' + binary + r''' "$WORK_DIR/xray"
}
'''
        return self.fixture.shell(prefix + body, inputs)

    def assert_no_candidates(self):
        self.assertFalse(list(self.root.glob("config.json.edit.*")))

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_validator_accepts_canonical_and_unusual_paths_without_changing_files(self):
        self.shell(r'''
seed_real
path="$WORK_DIR/config's copy.edit.random"
cp "$CONFIG_FILE" "$path"
validate_xray_config "$CONFIG_FILE" || exit 1
validate_xray_config "$path" || exit 2
cmp "$CONFIG_FILE" "$path" || exit 3
printf '{invalid' > "$path"
if validate_xray_config "$path"; then exit 4; fi
if validate_xray_config "$CONFIG_FILE" "$WORK_DIR/missing-binary"; then exit 5; fi
if validate_xray_config "$WORK_DIR/missing-config"; then exit 6; fi
''')

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_install_templates_accept_all_ss_methods_and_hy2_modes(self):
        self.shell(r'''
seed_real
ENABLE_REALITY=1; ENABLE_HY2=1
REALITY_PORT=18110; REALITY_SNI=www.tesla.com; REALITY_SHORTID=11223344
HY2_PORT=18111; HY2_SNI=hy2.example.com; HY2_MPORT=47000-48000
gen_reality_keys
[ "$REALITY_PRIV" != REPLACE_ME ] && [ -n "$REALITY_PUB" ] || exit 1
gen_hy2_cert || exit 2
for method in "${SS_METHODS[@]}"; do
    SS_METHOD="$method"
    if [[ "$method" = 2022-* ]]; then pass=$(gen_ss2022_pass "$method"); else pass="$UUID_CUSTOM"; fi
    for mode in auto bbr brutal reno; do
        HY2_CONGESTION="$mode"; HY2_UP_MBPS=80; HY2_DOWN_MBPS=120
        build_xray_config "$UUID_CUSTOM" "$pass" || exit 3
        sync_xray_users || exit 4
        validate_xray_config "$CONFIG_FILE" || exit 5
    done
done
''')

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_reality_add_edit_delete_preserves_other_protocols(self):
        self.shell(r'''
seed_real
cp "$CONFIG_FILE" "$TEST_ROOT/before.json"
add_single_protocol reality || exit 1
validate_xray_config "$CONFIG_FILE" || exit 2
edit_protocol reality Reality || exit 3
validate_xray_config "$CONFIG_FILE" || exit 4
cp "$CONFIG_FILE" "$TEST_ROOT/edited.json"
delete_protocol || exit 5
validate_xray_config "$CONFIG_FILE" || exit 6
''', "\n18100\n11223344\n\n\n\ny\n\nc\nreality.example.com\n18101\nnew\nnew\n2\ny\n\n1\ny\n")
        edited = json.loads((self.root / "edited.json").read_text())
        reality = next(i for i in edited["inbounds"] if i["tag"] == "reality")
        self.assertEqual(reality["port"], 18101)
        self.assertEqual(reality["streamSettings"]["realitySettings"]["target"], "reality.example.com:443")
        self.assertEqual(len(reality["settings"]["clients"]), 2)
        self.assertEqual(self.fixture.config(), json.loads((self.root / "before.json").read_text()))
        self.assert_no_candidates()

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_ss2022_add_edit_delete_preserves_other_protocols(self):
        self.shell(r'''
seed_real
jq '.inbounds |= map(select(.tag!="ss"))' "$CONFIG_FILE" > "$TEST_ROOT/without-ss.json"
mv "$TEST_ROOT/without-ss.json" "$CONFIG_FILE"
ENABLE_SS=0; save_conf
cp "$CONFIG_FILE" "$TEST_ROOT/before.json"
add_single_protocol ss || exit 1
validate_xray_config "$CONFIG_FILE" || exit 2
edit_protocol ss Shadowsocks || exit 3
validate_xray_config "$CONFIG_FILE" || exit 4
cp "$CONFIG_FILE" "$TEST_ROOT/edited.json"
delete_protocol || exit 5
validate_xray_config "$CONFIG_FILE" || exit 6
''', "5\n\n18110\n2\ny\n\n6\nnew\n18111\n1\ny\n\n3\ny\n")
        edited = json.loads((self.root / "edited.json").read_text())
        ss = next(i for i in edited["inbounds"] if i["tag"] == "ss")
        self.assertEqual(ss["port"], 18111)
        self.assertEqual(ss["settings"]["method"], "2022-blake3-aes-256-gcm")
        self.assertEqual(self.fixture.config(), json.loads((self.root / "before.json").read_text()))
        self.assert_no_candidates()

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_hy2_add_edit_delete_uses_core_preflight(self):
        self.shell(r'''
seed_real
cp "$CONFIG_FILE" "$TEST_ROOT/before.json"
prompt_xray_hy2() { HY2_SNI=hy2.example.com; HY2_PORT=18120; HY2_CONGESTION=bbr; HY2_MPORT=47000-48000; }
add_hy2_protocol || exit 1
validate_xray_config "$CONFIG_FILE" || exit 2
prompt_xray_hy2() { HY2_SNI=changed.example.com; HY2_PORT=18121; HY2_CONGESTION=brutal; HY2_UP_MBPS=80; HY2_DOWN_MBPS=120; HY2_MPORT=47000-48000; }
edit_hy2_protocol || exit 3
validate_xray_config "$CONFIG_FILE" || exit 4
cp "$CONFIG_FILE" "$TEST_ROOT/edited.json"
delete_protocol || exit 5
validate_xray_config "$CONFIG_FILE" || exit 6
''', "y\ny\n2\ny\n")
        edited = json.loads((self.root / "edited.json").read_text())
        hy2 = next(i for i in edited["inbounds"] if i["tag"] == "hy2")
        self.assertEqual(hy2["port"], 18121)
        self.assertEqual(hy2["streamSettings"]["finalmask"]["quicParams"]["congestion"], "brutal")
        self.assertEqual(self.fixture.config(), json.loads((self.root / "before.json").read_text()))
        self.assert_no_candidates()

    def test_legacy_protocol_validation_and_restart_failures_restore_all_state(self):
        for proto, action, inputs in (
            ("ss", "add", "\n\n18110\n\ny\n"),
            ("ss", "edit", "\n\n18111\n\ny\n"),
            ("ss", "delete", "3\ny\n"),
            ("reality", "add", "\n18100\n11223344\n\n\n\ny\n"),
            ("reality", "edit", "\n18101\n\n\n\ny\n"),
            ("reality", "delete", "1\ny\n"),
        ):
            for failure in ("reject-config", "reject-restart"):
                with self.subTest(proto=proto, action=action, failure=failure):
                    self.reset_fixture()
                    prepare = 'seed\nREALITY_PRIV=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nREALITY_PUB=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'
                    if proto == "reality" and action != "add":
                        prepare += 'ENABLE_REALITY=1; REALITY_PORT=18100; REALITY_SHORTID=11223344\nbuild_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM"; sync_xray_users\n'
                    if proto == "ss" and action == "add":
                        prepare += 'jq \'del(.inbounds[]|select(.tag=="ss"))\' "$CONFIG_FILE" > "$TEST_ROOT/without-ss.json"\nmv "$TEST_ROOT/without-ss.json" "$CONFIG_FILE"; ENABLE_SS=0\n'
                    call = "delete_protocol" if action == "delete" else f'{"add_single_protocol" if action == "add" else "edit_protocol"} {proto} {proto}'
                    result = self.shell('rm -f "$TEST_ROOT/reject-config" "$TEST_ROOT/reject-restart"\n' + prepare + r'''
save_conf
cp "$CONFIG_FILE" "$TEST_ROOT/config.before"
cp "$USER_CONF" "$TEST_ROOT/conf.before"
cp "$ARGOV_USERS_FILE" "$TEST_ROOT/users.before"
touch "$TEST_ROOT/''' + failure + '"\nif ' + call + r'''; then exit 1; fi
cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 2
cmp "$USER_CONF" "$TEST_ROOT/conf.before" || exit 3
cmp "$ARGOV_USERS_FILE" "$TEST_ROOT/users.before" || exit 4
''', inputs)
                    self.assertIn("已恢复原配置", result.stdout)
                    self.assert_no_candidates()

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_invalid_ss2022_key_rejected_before_replacing_configuration(self):
        result = self.shell(r'''
seed_real
cp "$CONFIG_FILE" "$TEST_ROOT/config.before"; cp "$USER_CONF" "$TEST_ROOT/conf.before"
if edit_protocol ss Shadowsocks; then exit 1; fi
cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 2
cmp "$USER_CONF" "$TEST_ROOT/conf.before" || exit 3
''', "5\ninvalid-key\n18110\n\ny\n")
        self.assertIn("Xray 配置验证失败", result.stdout)
        self.assert_no_candidates()

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_invalid_reality_short_id_rejected_before_replacing_configuration(self):
        result = self.shell(r'''
seed_real
ENABLE_REALITY=1; REALITY_PORT=18100; REALITY_SHORTID=11223344
gen_reality_keys; build_xray_config "$UUID_CUSTOM" "$UUID_CUSTOM"; sync_xray_users; save_conf
cp "$CONFIG_FILE" "$TEST_ROOT/config.before"; cp "$USER_CONF" "$TEST_ROOT/conf.before"
if edit_protocol reality Reality; then exit 1; fi
cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 2
cmp "$USER_CONF" "$TEST_ROOT/conf.before" || exit 3
''', "\n\n\nbad-id\n\ny\n")
        self.assertIn("Xray 配置验证失败", result.stdout)
        self.assert_no_candidates()

    @unittest.skipUnless(HAS_XRAY, "Real Xray required")
    def test_upgrade_preflight_uses_candidate_binary_and_unusual_config_suffix(self):
        self.shell(r'''
seed_real
path="$WORK_DIR/deployed config.custom"
cp "$CONFIG_FILE" "$path"
printf '#!/bin/sh\nexit 23\n' > "$TEST_ROOT/old-core"; chmod +x "$TEST_ROOT/old-core"
cp "$TEST_ROOT/old-core" "$TEST_ROOT/old-before"
core_service_active() { return 1; }
activate_core_binary xray "$WORK_DIR/xray" "$TEST_ROOT/old-core" "$path" || exit 1
cmp "$TEST_ROOT/old-core" "$WORK_DIR/xray" || exit 2
cmp "$TEST_ROOT/old-core.argov-previous" "$TEST_ROOT/old-before" || exit 3
cmp "$CONFIG_FILE" "$path" || exit 4
''')


if __name__ == "__main__":
    unittest.main()
