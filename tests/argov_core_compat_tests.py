#!/usr/bin/env python3
"""Validate subscription fidelity and preservation of deployed configurations."""
import base64
import hashlib
import json
import os
import re
import shlex
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse
from pathlib import Path

sys.dont_write_bytecode = True
from argov_relay_tests import relay_python
from argov_subscription_tests import load_build_clash

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "argov.sh").read_text(encoding="utf-8")
UUID = "11111111-1111-4111-8111-111111111111"
PIN = "ab" * 32


def clash_config(links):
    converter = load_build_clash(SOURCE)
    converter.__globals__["to_yaml"] = lambda data: data
    return converter(links)


class SubscriptionTests(unittest.TestCase):
    def test_vless_preserves_encryption_xhttp_and_extra(self):
        extra = {"noGRPCHeader": True, "scMaxEachPostBytes": 1000000,
                 "xPaddingBytes": "100-200", "headers": {"User-Agent": "chosen"},
                 "xmux": {"maxConcurrency": "8-16", "hKeepAlivePeriod": 30}}
        query = urllib.parse.urlencode({
            "security": "tls", "sni": "chosen.example.com", "type": "xhttp", "mode": "packet-up",
            "host": "chosen.example.com", "path": "/custom%2Fpath", "extra": json.dumps(extra),
            "encryption": "mlkem768x25519plus.native.1rtt.test", "alpn": "h2,http/1.1", "pcs": PIN,
        })
        p = clash_config([f"vless://{UUID}@192.0.2.15:443?{query}#custom"])["proxies"][0]
        self.assertEqual(p["encryption"], "mlkem768x25519plus.native.1rtt.test")
        self.assertEqual(p["network"], "xhttp")
        self.assertEqual(p["xhttp-opts"]["path"], "/custom%2Fpath")
        self.assertEqual(p["xhttp-opts"]["sc-max-each-post-bytes"], "1000000")
        self.assertEqual(p["xhttp-opts"]["reuse-settings"], {"max-concurrency": "8-16", "h-keep-alive-period": 30})
        self.assertEqual(p["fingerprint"], PIN)
        self.assertEqual(p["alpn"], ["h2", "http/1.1"])

    def test_tuic_pin_algorithm_and_legacy_skip_are_preserved(self):
        links = [f"tuic://{UUID}:p%40ss@192.0.2.15:24567?sni=old.example.com&insecure=1&pinSHA256={PIN}&congestion_control=cubic&udp_relay_mode=native#pinned",
                 f"tuic://{UUID}:old@192.0.2.16:24568?insecure=1&congestion_control=bbr#legacy"]
        pinned, legacy = clash_config(links)["proxies"]
        self.assertEqual(pinned["fingerprint"], PIN)
        self.assertFalse(pinned["skip-cert-verify"])
        self.assertEqual(pinned["congestion-controller"], "cubic")
        self.assertEqual(pinned["udp-relay-mode"], "native")
        self.assertTrue(legacy["skip-cert-verify"])
        self.assertNotIn("congestion-control", pinned)

    def test_legacy_and_grpc_links_keep_connection_parameters(self):
        links = [f"vless://{UUID}@192.0.2.15:443?type=ws&path=%2Fold&host=old.example.com#old",
                 f"vless://{UUID}@192.0.2.16:443?type=grpc&serviceName=chosen&security=reality&sni=old.example.com&pbk=key&sid=1234#grpc"]
        old, grpc = clash_config(links)["proxies"]
        self.assertEqual(old["encryption"], "none")
        self.assertEqual(old["ws-opts"]["path"], "/old")
        self.assertEqual(grpc["grpc-opts"]["grpc-service-name"], "chosen")
        self.assertEqual(grpc["reality-opts"]["public-key"], "key")

    def test_unsupported_xhttp_details_have_explicit_reason(self):
        extra = urllib.parse.quote(json.dumps({"downloadSettings": {"address": "download.example.com"}}))
        links = [f"vless://{UUID}@192.0.2.15:443?type=xhttp&extra={extra}#complex",
                 f"vless://{UUID}@192.0.2.16:443?type=ws&path=%2Fold#old"]
        yaml = load_build_clash(SOURCE)(links)
        self.assertIn("downloadSettings", yaml)
        self.assertIn("请使用原始链接", yaml)
        self.assertIn('name: "old"', yaml)
        self.assertNotIn('name: "complex"', yaml)

    @unittest.skipUnless(shutil.which("mihomo") and shutil.which("xray"), "optional Mihomo consumer check")
    def test_actual_mihomo_accepts_exported_protocol_options(self):
        result = subprocess.run(["xray", "vlessenc"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        encryption = re.search(r'"encryption": "([^\"]+)"', result.stdout).group(1)
        extra = urllib.parse.quote(json.dumps({"noGRPCHeader": True, "scMaxEachPostBytes": 1000000, "xmux": {"maxConcurrency": "8-16"}}))
        links = [f"vless://{UUID}@192.0.2.15:443?type=xhttp&security=tls&sni=chosen.example.com&encryption={encryption}&path=%2Fcustom&mode=packet-up&extra={extra}#xhttp",
                 f"tuic://{UUID}:old@192.0.2.16:24567?sni=chosen.example.com&insecure=1&pinSHA256={PIN}&congestion_control=bbr#tuic",
                 f"hy2://old@192.0.2.17:24568?sni=chosen.example.com&insecure=1&pinSHA256={PIN}&up=120mbps&down=80mbps#hy2"]
        cfg = clash_config(links)
        converter = load_build_clash(SOURCE)
        yaml = converter.__globals__["to_yaml"]({"proxies": cfg["proxies"], "rules": ["MATCH,DIRECT"]})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.yaml"
            path.write_text(yaml)
            result = subprocess.run(["mihomo", "-t", "-d", directory, "-f", str(path)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class RelayTests(unittest.TestCase):
    def run_relay(self, link, enabled=False, version="1.14.3"):
        with tempfile.TemporaryDirectory() as directory:
            xray = Path(directory) / "xray.json"
            sb = Path(directory) / "sb.json"
            # The older multi-protocol fixture uses placeholder REALITY keys.
            # Use a valid deployed listener so the real core can check the relay.
            xray.write_text(json.dumps({
                "inbounds": [{"protocol": "socks", "tag": "proxy-in", "listen": "127.0.0.1", "port": 10808, "settings": {}}],
                "outbounds": [{"protocol": "freedom", "tag": "direct"}],
                "routing": {"rules": []},
            }))
            sb.write_text(json.dumps({"inbounds": [], "outbounds": [{"type": "direct", "tag": "direct-out"}]}))
            old = xray.read_bytes(), sb.read_bytes()
            program = relay_python().replace("'${CONFIG_FILE}'", repr(str(xray))).replace("${domains_json}", "[]")
            env = dict(os.environ, RELAY_LINK_ENV=link, RELAY_MODE_ENV="all", SB_CONFIG_ENV=str(sb),
                       SB_ENABLED_ENV=str(enabled).lower(), SB_VERSION_ENV=version)
            result = subprocess.run([sys.executable, "-c", program], env=env, capture_output=True, text=True)
            if result.returncode:
                self.assertEqual((xray.read_bytes(), sb.read_bytes()), old, "failed parsing must not change either deployed config")
                return result, None, None
            xr, sr = json.loads(xray.read_text()), json.loads(sb.read_text())
            if shutil.which("xray"):
                check = subprocess.run(["xray", "run", "-test", "-config", str(xray)], capture_output=True, text=True)
                self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
            if enabled and version == "1.14.3" and shutil.which("sing-box"):
                check = subprocess.run(["sing-box", "check", "-c", str(sb)], capture_output=True, text=True)
                self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
            return result, next(o for o in xr["outbounds"] if o["tag"] == "relay-out"), next((o for o in sr["outbounds"] if o["tag"] == "argov-relay"), None)

    def test_tls_pin_replaces_removed_xray_option(self):
        result, xray, _ = self.run_relay(f"trojan://old-password@192.0.2.15:443?sni=old.example.com&allowInsecure=1&pcs={PIN}&alpn=h2,http%2F1.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        tls = xray["streamSettings"]["tlsSettings"]
        self.assertEqual(tls["pinnedPeerCertSha256"], PIN)
        self.assertNotIn("allowInsecure", tls)
        self.assertEqual(tls["alpn"], ["h2", "http/1.1"])

    def test_missing_pin_rejected_without_changing_existing_configs(self):
        result, _, _ = self.run_relay("trojan://old@192.0.2.15:443?sni=old.example.com&insecure=1", True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("请在链接中提供", result.stderr)

    def test_stable_singbox_uses_public_key_digest_separately(self):
        spki = base64.b64encode(b"\xcd" * 32).decode()
        query = urllib.parse.urlencode({"sni": "old.example.com", "insecure": "1", "pcs": PIN, "certificate_public_key_sha256": spki})
        result, xray, sb = self.run_relay(f"trojan://old@192.0.2.15:443?{query}", True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(xray["streamSettings"]["tlsSettings"]["pinnedPeerCertSha256"], PIN)
        self.assertEqual(sb["tls"]["certificate_public_key_sha256"], [spki])
        self.assertNotIn("certificate_sha256", sb["tls"])

    def test_unsupported_singbox_pinning_does_not_partially_write(self):
        result, _, _ = self.run_relay(f"trojan://old@192.0.2.15:443?pcs={PIN}", True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("公钥指纹", result.stderr)

    def test_singbox_new_certificate_digest_is_base64(self):
        result, _, sb = self.run_relay(f"trojan://old@192.0.2.15:443?pcs={PIN}", True, "1.15.0-alpha.12")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sb["tls"]["certificate_sha256"], [base64.b64encode(bytes.fromhex(PIN)).decode()])

    def test_xhttp_preserved_in_xray_and_rejected_for_dual_core(self):
        link = f"vless://{UUID}@192.0.2.15:443?type=xhttp&security=tls&sni=old.example.com&mode=packet-up&path=%2Fcustom%252Fpath"
        result, xray, _ = self.run_relay(link)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(xray["streamSettings"]["xhttpSettings"]["path"], "/custom%2Fpath")
        result, _, _ = self.run_relay(link, True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("不支持该中继传输", result.stderr)

    def test_trojan_defaults_to_tls_without_sni(self):
        result, xray, sb = self.run_relay("trojan://old@192.0.2.15:443", True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(xray["streamSettings"]["security"], "tls")
        self.assertTrue(sb["tls"]["enabled"])

    @unittest.skipUnless(all(shutil.which(tool) for tool in ("sing-box", "mihomo", "openssl")), "optional TUIC consumer handshake")
    def test_mihomo_pin_connects_to_self_signed_singbox_tuic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cert, key = root / "cert.pem", root / "key.pem"
            made = subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj", "/CN=localhost",
                                   "-addext", "subjectAltName=DNS:localhost", "-keyout", str(key), "-out", str(cert)], capture_output=True, text=True)
            self.assertEqual(made.returncode, 0, made.stderr)
            pin = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest()
            upstream = socket.socket()
            upstream.bind(("127.0.0.1", 0))
            upstream.listen(1)
            upstream.settimeout(8)
            payload = b"deployed-node-still-connects"
            echo_confirmed = threading.Event()
            echo_trace = []

            def echo_payload():
                try:
                    connection, _ = upstream.accept()
                    echo_trace.append("accepted upstream connection")
                    with connection:
                        connection.settimeout(5)
                        data = b""
                        while len(data) < len(payload):
                            chunk = connection.recv(len(payload) - len(data))
                            if not chunk:
                                break
                            data += chunk
                        echo_trace.append(f"received {data!r}")
                        if data == payload:
                            connection.sendall(data)
                            # Keep the stream open until the client has read the
                            # response; immediate close races QUIC relay teardown.
                            if connection.recv(1) == b"\x01":
                                echo_confirmed.set()
                except OSError as error:
                    echo_trace.append(str(error))

            worker = threading.Thread(target=echo_payload, daemon=True)
            worker.start()
            reserve = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            reserve.bind(("127.0.0.1", 0))
            tuic_port = reserve.getsockname()[1]
            reserve.close()
            reserve = socket.socket()
            reserve.bind(("127.0.0.1", 0))
            socks_port = reserve.getsockname()[1]
            reserve.close()
            server_file = root / "server.json"
            server_file.write_text(json.dumps({
                "log": {"level": "debug"},
                "inbounds": [{"type": "tuic", "tag": "deployed-tuic", "listen": "127.0.0.1", "listen_port": tuic_port,
                              "users": [{"uuid": UUID, "password": "deployed@password"}], "congestion_control": "bbr",
                              "tls": {"enabled": True, "server_name": "localhost", "alpn": ["h3"], "certificate_path": str(cert), "key_path": str(key)}}],
                "outbounds": [{"type": "direct", "tag": "direct"}], "route": {"final": "direct"},
            }))
            link = f"tuic://{UUID}:deployed%40password@127.0.0.1:{tuic_port}?sni=localhost&insecure=1&pinSHA256={pin}&alpn=h3&congestion_control=bbr#pinned-tuic"
            proxy = clash_config([link])["proxies"][0]
            converter = load_build_clash(SOURCE)
            client_file = root / "client.yaml"
            client_file.write_text(converter.__globals__["to_yaml"]({
                "mixed-port": socks_port, "bind-address": "127.0.0.1", "allow-lan": False, "log-level": "debug",
                "proxies": [proxy], "rules": ["MATCH,pinned-tuic"],
            }))
            processes = []
            try:
                for name, command in (("server", ["sing-box", "run", "-c", str(server_file)]),
                                      ("client", ["mihomo", "-d", directory, "-f", str(client_file)])):
                    with (root / (name + ".log")).open("w") as log:
                        processes.append(subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT))
                    if name == "server":
                        # Popen only confirms process creation. Dialing before
                        # the QUIC listener binds can produce an immediate ICMP
                        # refusal even after Mihomo's TCP listener is ready.
                        for _ in range(100):
                            if "sing-box started" in (root / "server.log").read_text(errors="replace"):
                                break
                            self.assertIsNone(processes[-1].poll(), "local sing-box exited before readiness")
                            time.sleep(0.05)
                        else:
                            self.fail("local sing-box did not finish startup")
                    else:
                        for _ in range(100):
                            if "Mixed(http+socks) proxy listening at:" in (root / "client.log").read_text(errors="replace"):
                                break
                            self.assertIsNone(processes[-1].poll(), "local Mihomo exited before readiness")
                            time.sleep(0.05)
                        else:
                            self.fail("local Mihomo did not finish listener startup")
                for _ in range(50):
                    try:
                        client = socket.create_connection(("127.0.0.1", socks_port), 0.1)
                        break
                    except OSError:
                        self.assertTrue(all(p.poll() is None for p in processes), "a local proxy exited")
                        time.sleep(0.05)
                else:
                    self.fail("local Mihomo listener did not start")
                with client:
                    client.settimeout(5)

                    def read_exact(length):
                        data = b""
                        while len(data) < length:
                            chunk = client.recv(length - len(data))
                            self.assertTrue(chunk, "SOCKS connection closed")
                            data += chunk
                        return data

                    client.sendall(b"\x05\x01\x00")
                    self.assertEqual(read_exact(2), b"\x05\x00")
                    client.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("127.0.0.1") + upstream.getsockname()[1].to_bytes(2, "big"))
                    reply = read_exact(4)
                    self.assertEqual(reply[:2], b"\x05\x00")
                    if reply[3] == 1:
                        read_exact(6)
                    elif reply[3] == 4:
                        read_exact(18)
                    else:
                        read_exact(read_exact(1)[0] + 2)
                    client.sendall(payload)
                    self.assertEqual(read_exact(len(payload)), payload)
                    client.sendall(b"\x01")
                    self.assertTrue(echo_confirmed.wait(5), "upstream did not receive client acknowledgement")
            except Exception:
                print("echo trace: " + repr(echo_trace), file=sys.stderr)
                for name in ("server", "client"):
                    log = root / (name + ".log")
                    if log.exists():
                        print(log.read_text(errors="replace"), file=sys.stderr)
                raise
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=5)
                upstream.close()
                worker.join(timeout=1)

    @unittest.skipUnless(shutil.which("xray") and shutil.which("openssl"), "real TLS test needs Xray and openssl")
    def test_tls_relay_accepts_matching_certificate_and_rejects_wrong_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cert, key = root / "cert.pem", root / "key.pem"
            made = subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                                   "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                                   "-keyout", str(key), "-out", str(cert)], capture_output=True, text=True)
            self.assertEqual(made.returncode, 0, made.stderr)
            pin = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest()
            for expected_pin, should_connect in ((pin, True), ("00" * 32, False)):
                upstream = socket.socket()
                upstream.bind(("127.0.0.1", 0))
                upstream.listen(1)
                upstream.settimeout(5)
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(cert, key)
                seen = threading.Event()
                received = []

                def receive_trojan_header():
                    try:
                        connection, _ = upstream.accept()
                        with context.wrap_socket(connection, server_side=True) as stream:
                            stream.settimeout(3)
                            data = stream.recv(128)
                            if data:
                                received.append(data)
                                seen.set()
                    except (ssl.SSLError, OSError):
                        pass

                worker = threading.Thread(target=receive_trojan_header, daemon=True)
                worker.start()
                reserve = socket.socket()
                reserve.bind(("127.0.0.1", 0))
                socks_port = reserve.getsockname()[1]
                reserve.close()
                config = root / "relay.json"
                config.write_text(json.dumps({
                    "log": {"loglevel": "warning"},
                    "inbounds": [{"listen": "127.0.0.1", "port": socks_port, "tag": "proxy-in", "protocol": "socks", "settings": {}}],
                    "outbounds": [{"protocol": "freedom", "tag": "direct"}],
                }))
                program = relay_python().replace("'${CONFIG_FILE}'", repr(str(config))).replace("${domains_json}", "[]")
                link = f"trojan://deployed-password@127.0.0.1:{upstream.getsockname()[1]}?sni=localhost&allowInsecure=1&pcs={expected_pin}"
                result = subprocess.run([sys.executable, "-c", program], capture_output=True, text=True,
                                        env=dict(os.environ, RELAY_LINK_ENV=link, RELAY_MODE_ENV="all", SB_ENABLED_ENV="false"))
                self.assertEqual(result.returncode, 0, result.stderr)
                process = subprocess.Popen(["xray", "run", "-config", str(config)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    for _ in range(50):
                        try:
                            client = socket.create_connection(("127.0.0.1", socks_port), 0.1)
                            break
                        except OSError:
                            self.assertIsNone(process.poll(), "Xray exited during startup")
                            time.sleep(0.05)
                    else:
                        self.fail("local SOCKS listener did not start")
                    with client:
                        client.settimeout(3)
                        client.sendall(b"\x05\x01\x00")
                        self.assertEqual(client.recv(2), b"\x05\x00")
                        domain = b"example.invalid"
                        client.sendall(b"\x05\x01\x00\x03" + bytes([len(domain)]) + domain + b"\x00\x50")
                        self.assertEqual(seen.wait(3 if should_connect else 1.5), should_connect)
                    if should_connect:
                        self.assertTrue(received[0].startswith(hashlib.sha224(b"deployed-password").hexdigest().encode()))
                finally:
                    process.terminate()
                    process.wait(timeout=5)
                    upstream.close()
                    worker.join(timeout=1)


@unittest.skipUnless(all(shutil.which(tool) for tool in ("bash", "jq", "openssl")), "Bash tools are required")
class DeployedStateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="argov-core-compat-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.library = self.root / "library.sh"
        self.library.write_text(SOURCE.split("\nmigrate_argox_to_argov\nload_conf\n", 1)[0])

    def shell(self, body):
        prefix = f"source {shlex.quote(str(self.library))}\nTEST_ROOT={shlex.quote(str(self.root))}\n"
        prefix += '''
WORK_DIR="$TEST_ROOT"; USER_CONF="$TEST_ROOT/argov.conf"; CONFIG_FILE="$TEST_ROOT/xray.json"
SB_WORK_DIR="$TEST_ROOT/sb"; SB_CONFIG_FILE="$TEST_ROOT/sb.json"; ARGOV_USERS_FILE="$TEST_ROOT/users.json"
HY2_CERT_FILE="$TEST_ROOT/xray.crt"; HY2_KEY_FILE="$TEST_ROOT/xray.key"
SB_CERT_FILE="$TEST_ROOT/tuic.crt"; SB_KEY_FILE="$TEST_ROOT/tuic.key"
SB_HY2_CERT_FILE="$TEST_ROOT/sb-hy2.crt"; SB_HY2_KEY_FILE="$TEST_ROOT/sb-hy2.key"
load_conf
'''
        result = subprocess.run(["bash", "-c", prefix + body], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def start_local_singbox(self, options, cwd=None):
        binary = self.root / "running-sing-box"
        shutil.copyfile(shutil.which("sing-box"), binary)
        binary.chmod(0o755)
        log = self.root / "running.log"
        with log.open("wb") as stream:
            process = subprocess.Popen([str(binary), "run", *options], cwd=cwd or self.root,
                                       stdout=stream, stderr=subprocess.STDOUT)

        def stop():
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)

        self.addCleanup(stop)
        for _ in range(100):
            self.assertIsNone(process.poll(), log.read_text(errors="replace"))
            if "sing-box started" in log.read_text(errors="replace"):
                return binary, process
            time.sleep(0.02)
        self.fail("local sing-box did not finish startup: " + log.read_text(errors="replace"))

    @unittest.skipUnless(shutil.which("sing-box"), "deleted-running-binary test needs sing-box")
    def test_running_deleted_singbox_binary_cannot_be_replaced_or_restarted(self):
        config = self.root / "runtime.json"
        config.write_text('{"log":{"level":"info"},"outbounds":[{"type":"direct"}]}')
        binary, process = self.start_local_singbox(["-c", str(config)])
        binary.unlink(); config.unlink()
        output = self.shell(f"singbox_service_pid() {{ printf '{process.pid}'; }}\n" + r'''
core_service_active() { return 0; }
singbox_binary_path() { return 1; }
install_singbox_archive() { touch "$TEST_ROOT/downloaded"; return 1; }
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
clear() { :; }
if install_singbox update; then exit 1; fi
[ ! -e "$TEST_ROOT/downloaded" ] && [ ! -e "$TEST_ROOT/restarted" ] || exit 2
printf 's0\n' | sb_menu
''')
        self.assertIsNone(process.poll(), "A deleted binary must leave its existing process running")
        self.assertIn("安装文件丢失", output)
        self.assertNotIn("下载失败", output)
        self.assertNotIn("未安装", output)

    @unittest.skipUnless(shutil.which("sing-box"), "runtime-config test needs sing-box")
    def test_singbox_preflight_uses_running_directory_config_and_rejects_invalid_changes(self):
        directory = self.root / "work" / "runtime-parts"
        directory.mkdir(parents=True)
        config = directory / "node.json"
        config.write_text('{"log":{"level":"info"},"outbounds":[{"type":"direct"}]}')
        binary, process = self.start_local_singbox(["-D", "work", "-C", "runtime-parts"])
        prefix = f"singbox_service_pid() {{ printf '{process.pid}'; }}\ncore_service_active() {{ return 0; }}\n"
        self.shell(prefix + "candidate=" + shlex.quote(shutil.which("sing-box")) + r'''
[ "$(singbox_binary_path)" = "$TEST_ROOT/running-sing-box" ] || exit 1
singbox_preflight_current_config "$candidate" "$SB_CONFIG_FILE" || exit 2
''')
        config.write_text("invalid-json")
        before = binary.read_bytes()
        self.shell(prefix + "candidate=" + shlex.quote(shutil.which("sing-box")) + r'''
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
if activate_core_binary sing-box "$candidate" "$TEST_ROOT/running-sing-box" "$SB_CONFIG_FILE"; then exit 1; fi
[ ! -e "$TEST_ROOT/restarted" ] || exit 2
''')
        self.assertEqual(binary.read_bytes(), before)
        self.assertIsNone(process.poll())

    def test_running_singbox_with_unknown_missing_config_cannot_upgrade(self):
        self.shell(r'''
printf '#!/bin/sh\n# old\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
cp "$TEST_ROOT/old" "$TEST_ROOT/before"
printf '#!/bin/sh\n# new\nexit 0\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
core_service_active() { return 0; }
singbox_service_pid() { return 1; }
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
if activate_core_binary sing-box "$TEST_ROOT/new" "$TEST_ROOT/old" "$SB_CONFIG_FILE"; then exit 1; fi
cmp "$TEST_ROOT/old" "$TEST_ROOT/before" && [ ! -e "$TEST_ROOT/restarted" ] || exit 2
''')

    def test_core_only_singbox_can_update_without_creating_config_or_starting_service(self):
        self.shell(r'''
printf '#!/bin/sh\n# old\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
printf '#!/bin/sh\n# new\nexit 0\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
core_service_active() { return 1; }
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
activate_core_binary sing-box "$TEST_ROOT/new" "$TEST_ROOT/old" "$SB_CONFIG_FILE" || exit 1
cmp "$TEST_ROOT/old" "$TEST_ROOT/new" || exit 2
[ ! -e "$SB_CONFIG_FILE" ] && [ ! -e "$TEST_ROOT/restarted" ] || exit 3
''')

    def test_certificate_refresh_uses_actual_files_and_keeps_identity(self):
        self.shell(r'''
HY2_SNI=old.example.com; SB_HY2_SNI=hy2.example.com; SB_TUIC_SNI=tuic.example.com
HY2_PORT=24567; SB_HY2_PORT=24568; SB_TUIC_PORT=24569; SB_HY2_ENABLE=true; SB_TUIC_ENABLE=true
UUID_CUSTOM=11111111-1111-4111-8111-111111111111; SB_TUIC_PSK=deployed-password
gen_hy2_cert || exit 1
generate_singbox_hy2_cert || exit 1
generate_singbox_cert || exit 1
jq -n --arg cert "$SB_HY2_CERT_FILE" '{inbounds:[{tag:"sb-hy2",tls:{certificate_path:$cert}}]}' > "$SB_CONFIG_FILE"
printf '{"inbounds":[]}' > "$CONFIG_FILE"
sha256sum "$HY2_CERT_FILE" "$HY2_KEY_FILE" "$SB_CERT_FILE" "$SB_KEY_FILE" "$SB_HY2_CERT_FILE" "$SB_HY2_KEY_FILE" "$CONFIG_FILE" "$SB_CONFIG_FILE" > "$TEST_ROOT/before"
correct=$(cert_pin_sha256 "$SB_HY2_CERT_FILE")
SB_HY2_CERT_FILE="$SB_CERT_FILE"; SB_HY2_PIN_SHA256=wrong; SB_TUIC_PIN_SHA256=""
refresh_certificate_pins || exit 1
[ "$SB_HY2_PIN_SHA256" = "$correct" ] && [ "$SB_TUIC_PIN_SHA256" != "$SB_HY2_PIN_SHA256" ] || exit 1
save_conf || exit 1
unset SB_TUIC_PIN_SHA256; load_conf
[ "$SB_TUIC_PIN_SHA256" = "$(cert_pin_sha256 "$SB_CERT_FILE")" ] || exit 1
[ "$HY2_PORT" = 24567 ] && [ "$UUID_CUSTOM" = 11111111-1111-4111-8111-111111111111 ] && [ "$SB_TUIC_PSK" = deployed-password ] || exit 1
sha256sum -c "$TEST_ROOT/before" || exit 1
''')

    def test_upgrade_preflight_rejection_does_not_restart_or_replace(self):
        self.shell(r'''
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
cp "$TEST_ROOT/old" "$TEST_ROOT/before"
printf '#!/bin/sh\n[ "$1" = version ] && exit 0\nexit 23\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
printf '{"unchanged":true}' > "$CONFIG_FILE"
core_service_active() { return 0; }
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
activate_core_binary xray "$TEST_ROOT/new" "$TEST_ROOT/old" "$CONFIG_FILE" && exit 1
cmp "$TEST_ROOT/old" "$TEST_ROOT/before" && [ ! -e "$TEST_ROOT/restarted" ] || exit 1
''')

    def test_service_detection_handles_native_systemctl_and_openrc(self):
        self.shell(r'''
mkdir "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/systemctl" <<'MOCK'
#!/bin/sh
[ "$1" = is-active ] && [ "$2" = --quiet ] && [ "$#" = 3 ] || exit 2
case "$3" in xray|sing-box) [ "$TEST_SERVICE_STATE" = started ] ;; *) exit 2 ;; esac
MOCK
cat > "$TEST_ROOT/bin/rc-service" <<'MOCK'
#!/bin/sh
case "$1" in xray|sing-box) ;; *) exit 2 ;; esac
[ "$2" = status ] || exit 2
printf ' * status: %s\n' "$TEST_SERVICE_STATE"
MOCK
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH" TEST_SERVICE_STATE=started
for IS_ALPINE in 0 1; do
    TEST_SERVICE_STATE=started
    core_service_active xray && core_service_active sing-box || exit 1
    TEST_SERVICE_STATE=stopped
    core_service_active xray && exit 1
    TEST_SERVICE_STATE=crashed
    core_service_active sing-box && exit 1
done
exit 0
''')

    def test_upgrade_uses_actual_service_adapter_and_rolls_back(self):
        self.shell(r'''
mkdir "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/systemctl" <<'MOCK'
#!/bin/sh
case "$1" in
    is-active) [ "$2" = --quiet ] && [ "$3" = "$TEST_CORE" ] && [ "$#" = 3 ] ;;
    restart)
        [ "$2" = "$TEST_CORE" ] || exit 2
        printf 'restart\n' >> "$TEST_ROOT/restarts"
        [ "$(wc -l < "$TEST_ROOT/restarts")" -gt 1 ] ;;
    *) exit 2 ;;
esac
MOCK
chmod +x "$TEST_ROOT/bin/systemctl"
export PATH="$TEST_ROOT/bin:$PATH" TEST_ROOT TEST_CORE
IS_ALPINE=0
for TEST_CORE in xray sing-box; do
    printf '#!/bin/sh\n# old\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
    cp "$TEST_ROOT/old" "$TEST_ROOT/before"
    printf '#!/bin/sh\n# new\nexit 0\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
    printf '{"unchanged":true}' > "$CONFIG_FILE"; cp "$CONFIG_FILE" "$TEST_ROOT/config.before"
    rm -f "$TEST_ROOT/restarts"
    activate_core_binary "$TEST_CORE" "$TEST_ROOT/new" "$TEST_ROOT/old" "$CONFIG_FILE" && exit 1
    [ "$(wc -l < "$TEST_ROOT/restarts")" = 2 ] && cmp "$TEST_ROOT/old" "$TEST_ROOT/before" && cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 1
done
''')

    def test_failed_restart_rolls_back_binary_and_preserves_config(self):
        self.shell(r'''
printf '#!/bin/sh\n# old\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
cp "$TEST_ROOT/old" "$TEST_ROOT/before"
printf '#!/bin/sh\n# new\nexit 0\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
printf '{"unchanged":true}' > "$CONFIG_FILE"; cp "$CONFIG_FILE" "$TEST_ROOT/config.before"
core_service_active() { return 0; }
restarts=0
restart_protocol_runtime() { restarts=$((restarts+1)); [ "$restarts" -gt 1 ]; }
activate_core_binary xray "$TEST_ROOT/new" "$TEST_ROOT/old" "$CONFIG_FILE" && exit 1
[ "$restarts" = 2 ] && cmp "$TEST_ROOT/old" "$TEST_ROOT/before" && cmp "$CONFIG_FILE" "$TEST_ROOT/config.before" || exit 1
''')

    def test_missing_config_cannot_interrupt_running_service(self):
        self.shell(r'''
printf '#!/bin/sh\n# old\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
cp "$TEST_ROOT/old" "$TEST_ROOT/before"
printf '#!/bin/sh\n# new\nexit 0\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
core_service_active() { return 0; }
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
activate_core_binary xray "$TEST_ROOT/new" "$TEST_ROOT/old" "$CONFIG_FILE" && exit 1
cmp "$TEST_ROOT/old" "$TEST_ROOT/before" && [ ! -e "$TEST_ROOT/restarted" ] || exit 1
''')

    def test_stopped_service_stays_stopped_and_old_binary_is_saved(self):
        self.shell(r'''
printf '#!/bin/sh\n# old\nexit 0\n' > "$TEST_ROOT/old"; chmod +x "$TEST_ROOT/old"
cp "$TEST_ROOT/old" "$TEST_ROOT/before"
printf '#!/bin/sh\n# new\nexit 0\n' > "$TEST_ROOT/new"; chmod +x "$TEST_ROOT/new"
printf '{"unchanged":true}' > "$CONFIG_FILE"
core_service_active() { return 1; }
restart_protocol_runtime() { touch "$TEST_ROOT/restarted"; }
activate_core_binary sing-box "$TEST_ROOT/new" "$TEST_ROOT/old" "$CONFIG_FILE" || exit 1
cmp "$TEST_ROOT/old" "$TEST_ROOT/new" && cmp "$TEST_ROOT/old.argov-previous" "$TEST_ROOT/before" && [ ! -e "$TEST_ROOT/restarted" ] || exit 1
''')

    def test_ws_export_reads_deployed_path_without_changing_it(self):
        output = self.shell(r'''
jq -n '{inbounds:[{tag:"vless-ws",streamSettings:{wsSettings:{path:"/deployed%2Fvless"}}},{tag:"vmess-ws",streamSettings:{wsSettings:{path:"/deployed-vmess"}}}]}' > "$CONFIG_FILE"
cp "$CONFIG_FILE" "$TEST_ROOT/before"
gen_vless_link deployed-uuid argo.example.com cdn.example.com 443; printf '\n'
gen_vmess_link deployed-uuid argo.example.com cdn.example.com 443 '旧 "节点"'; printf '\n'
cmp "$CONFIG_FILE" "$TEST_ROOT/before" || exit 1
''')
        vless, vmess = output.strip().splitlines()
        self.assertEqual(urllib.parse.parse_qs(urllib.parse.urlsplit(vless).query)["path"], ["/deployed%2Fvless?ed=2560"])
        vm = json.loads(base64.b64decode(vmess[8:]))
        self.assertEqual(vm["path"], "/deployed-vmess?ed=2560")
        self.assertEqual(vm["ps"], '旧 "节点"')

    def test_emitted_python_preserves_quoted_names_tokens_and_old_cache(self):
        start = SOURCE.index("    local sub_settings sub_settings_literal sub_candidate\n")
        end = SOURCE.index("\nPYEOF", start) + len("\nPYEOF")
        emitter = SOURCE[start:end]
        name = "旧节点's \\\"name\\\"\n第二行"
        token = "old'token\\with\nnewline"
        self.shell("NODE_NAME=" + shlex.quote(name) + "\nSUB_TOKEN=" + shlex.quote(token) + "\nSUB_PATH='/old-path'\nSUB_PORT=23456\nAGG_TOKEN='unchanged-agg'\n"
                   + "emit() {\n" + emitter + "\n}\nemit\n")
        generated = next(self.root.glob("sub.py.new.*")).read_text()
        ns = {}
        # Define handlers without starting the network server or refresh thread.
        exec(generated.split("# 后台定时刷新", 1)[0], ns)
        self.assertEqual(ns["NODE_NAME"], name)
        self.assertEqual(ns["SUB_TOKEN"], token)
        self.assertEqual(ns["resolve_token"]("/old-path", {}), (token, True))
        old_cache = (b"deployed-raw", b"deployed-clash")
        ns["CACHE"][token] = old_cache
        invalid = base64.b64encode(f"vless://{UUID}@192.0.2.15:443?type=unsupported".encode())
        class FakeSubprocess:
            @staticmethod
            def run(*args, **kwargs):
                return type("Result", (), {"stdout": invalid})()
        ns["subprocess"] = FakeSubprocess
        self.assertEqual(ns["refresh_cache"](token), old_cache)


if __name__ == "__main__":
    unittest.main()
