#!/usr/bin/env python3
"""Exercise the relay config writer with a SIP002 Shadowsocks link."""

import base64
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "argov.sh"
FIXTURE = ROOT / "tests" / "fixtures" / "legacy" / "config.multi-protocol.json"


def relay_python() -> str:
    script = SCRIPT.read_text(encoding="utf-8")
    marker = 'RELAY_LINK_ENV="$RELAY_LINK" RELAY_MODE_ENV="$RELAY_MODE" SB_CONFIG_ENV="$SB_CONFIG_FILE" SB_ENABLED_ENV="${SB_ENABLE:-false}" python3 2>"$py_err" << PYEOF\n'
    return script.split(marker, 1)[1].split("\nPYEOF", 1)[0]


def test_ss_relay() -> None:
    encoded = base64.urlsafe_b64encode(
        b"chacha20-ietf-poly1305:test-password"
    ).decode("ascii").rstrip("=")
    link = f"ss://{encoded}@192.0.2.15:3076?#landing-SS"

    with tempfile.TemporaryDirectory() as directory:
        config_path = Path(directory) / "xray.json"
        singbox_path = Path(directory) / "sing-box.json"
        config_path.write_bytes(FIXTURE.read_bytes())
        singbox_path.write_text(json.dumps({
            "inbounds": [{"type": "hysteria2", "tag": "sb-hy2-in"}],
            "outbounds": [{"type": "direct", "tag": "direct-out"}],
        }), encoding="utf-8")
        program = relay_python().replace("'${CONFIG_FILE}'", repr(str(config_path)))
        program = program.replace("${domains_json}", "[]")
        env = os.environ.copy()
        env.update(RELAY_LINK_ENV=link, RELAY_MODE_ENV="all", SB_CONFIG_ENV=str(singbox_path),
                   SB_ENABLED_ENV="true")
        result = subprocess.run(
            [sys.executable, "-c", program], env=env, capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr

        config = json.loads(config_path.read_text(encoding="utf-8"))
        relay = next(o for o in config["outbounds"] if o["tag"] == "relay-out")
        assert config["outbounds"][0]["tag"] == "relay-out"
        server = relay["settings"]["servers"][0]
        assert server == {
            "address": "192.0.2.15",
            "port": 3076,
            "method": "chacha20-ietf-poly1305",
            "password": "test-password",
        }
        rules = config["routing"]["rules"]
        assert rules[0]["inboundTag"] == ["api"]
        assert rules[1]["outboundTag"] == "relay-out"
        assert rules[1]["network"] == "tcp,udp"

        singbox = json.loads(singbox_path.read_text(encoding="utf-8"))
        singbox_relay = next(o for o in singbox["outbounds"] if o["tag"] == "argov-relay")
        assert singbox_relay == {
            "type": "shadowsocks", "tag": "argov-relay", "server": "192.0.2.15",
            "server_port": 3076, "method": "chacha20-ietf-poly1305",
            "password": "test-password",
        }
        assert singbox["route"]["final"] == "argov-relay"
        assert singbox["route"]["rules"][0] == {
            "action": "route", "outbound": "argov-relay"
        }
        sing_box_bin = os.environ.get("SING_BOX_BIN")
        if sing_box_bin:
            checked = subprocess.run(
                [sing_box_bin, "check", "-c", str(singbox_path)],
                capture_output=True, text=True,
            )
            assert checked.returncode == 0, checked.stdout + checked.stderr


def test_xray_uses_relay(xray_bin: str) -> None:
    upstream = socket.socket()
    upstream.bind(("127.0.0.1", 0))
    upstream.listen(1)
    upstream_port = upstream.getsockname()[1]
    seen = threading.Event()

    def accept_relay() -> None:
        upstream.settimeout(8)
        try:
            connection, _ = upstream.accept()
            with connection:
                seen.set()
        except (socket.timeout, OSError):
            pass

    worker = threading.Thread(target=accept_relay, daemon=True)
    worker.start()
    with tempfile.TemporaryDirectory() as directory:
        reserve = socket.socket()
        reserve.bind(("127.0.0.1", 0))
        socks_port = reserve.getsockname()[1]
        reserve.close()
        reserve = socket.socket()
        reserve.bind(("127.0.0.1", 0))
        api_port = reserve.getsockname()[1]
        reserve.close()
        config_path = Path(directory) / "xray.json"
        base = {
            "log": {"loglevel": "warning"},
            "api": {"tag": "api", "services": ["StatsService"]},
            "stats": {},
            "inbounds": [{
                "tag": "proxy-in", "listen": "127.0.0.1", "port": socks_port,
                "protocol": "socks", "settings": {"auth": "noauth"},
            }, {
                "tag": "api-in", "listen": "127.0.0.1", "port": api_port,
                "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"},
            }],
            "outbounds": [{"tag": "direct", "protocol": "freedom"}],
            "routing": {"rules": [{"type": "field", "inboundTag": ["api-in"],
                                   "outboundTag": "api"}]},
        }
        config_path.write_text(json.dumps(base), encoding="utf-8")
        encoded = base64.urlsafe_b64encode(
            b"chacha20-ietf-poly1305:test-password"
        ).decode("ascii").rstrip("=")
        program = relay_python().replace("'${CONFIG_FILE}'", repr(str(config_path)))
        program = program.replace("${domains_json}", "[]")
        env = os.environ.copy()
        env.update(
            RELAY_LINK_ENV=f"ss://{encoded}@127.0.0.1:{upstream_port}?#landing-SS",
            RELAY_MODE_ENV="all",
        )
        result = subprocess.run(
            [sys.executable, "-c", program], env=env, capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr
        check = subprocess.run(
            [xray_bin, "run", "-test", "-c", str(config_path)],
            capture_output=True, text=True,
        )
        assert check.returncode == 0, check.stdout + check.stderr

        process = subprocess.Popen(
            [xray_bin, "run", "-c", str(config_path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(50):
                if process.poll() is not None:
                    raise AssertionError(f"Xray exited: {process.returncode}")
                try:
                    client = socket.create_connection(("127.0.0.1", socks_port), 0.2)
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError("Xray SOCKS inbound did not start")
            with client:
                client.settimeout(3)
                client.sendall(b"\x05\x01\x00")
                assert client.recv(2) == b"\x05\x00"
                host = b"example.com"
                client.sendall(b"\x05\x01\x00\x03" + bytes([len(host)]) + host + b"\x00\x50")
                assert seen.wait(5), "Xray did not dial the Shadowsocks relay"
                query = subprocess.run(
                    [xray_bin, "api", "statsquery", f"--server=127.0.0.1:{api_port}"],
                    capture_output=True, text=True, timeout=5,
                )
                assert query.returncode == 0, query.stdout + query.stderr
        finally:
            process.terminate()
            process.wait(timeout=5)
            upstream.close()
            worker.join(timeout=1)


def test_hy2_uses_relay(xray_bin: str, openssl_bin: str) -> None:
    upstream = socket.socket()
    upstream.bind(("127.0.0.1", 0))
    upstream.listen(1)
    upstream_port = upstream.getsockname()[1]
    seen = threading.Event()

    def accept_relay() -> None:
        upstream.settimeout(12)
        try:
            connection, _ = upstream.accept()
            with connection:
                seen.set()
        except (socket.timeout, OSError):
            pass

    worker = threading.Thread(target=accept_relay, daemon=True)
    worker.start()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        cert = root / "cert.pem"
        key = root / "key.pem"
        made = subprocess.run([
            openssl_bin, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "1", "-subj", "/CN=localhost", "-addext",
            "subjectAltName=DNS:localhost", "-keyout", str(key), "-out", str(cert),
        ], capture_output=True, text=True)
        assert made.returncode == 0, made.stderr
        fingerprint = subprocess.check_output(
            [openssl_bin, "x509", "-in", str(cert), "-noout", "-fingerprint", "-sha256"],
            text=True,
        ).split("=", 1)[1].strip().replace(":", "")
        with socket.socket(type=socket.SOCK_DGRAM) as reserve:
            reserve.bind(("127.0.0.1", 0))
            hy2_port = reserve.getsockname()[1]
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            socks_port = reserve.getsockname()[1]
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            api_port = reserve.getsockname()[1]
        server_path = root / "server.json"
        server = {
            "log": {"loglevel": "debug"},
            "api": {"tag": "api", "services": ["StatsService"]},
            "stats": {},
            "inbounds": [{
                "tag": "hy2", "listen": "127.0.0.1", "port": hy2_port,
                "protocol": "hysteria", "settings": {
                    "version": 2, "users": [{"auth": "hy2-test-password", "email": "test"}],
                    "clients": [{"auth": "hy2-test-password", "email": "test"}],
                },
                "streamSettings": {
                    "network": "hysteria", "security": "tls",
                    "tlsSettings": {"alpn": ["h3"], "serverName": "localhost",
                                    "certificates": [{"certificateFile": str(cert),
                                                      "keyFile": str(key)}]},
                    "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60},
                },
                "sniffing": {"enabled": True,
                             "destOverride": ["http", "tls", "quic"],
                             "routeOnly": True},
            }, {
                "tag": "api-in", "listen": "127.0.0.1", "port": api_port,
                "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"},
            }],
            "outbounds": [{"tag": "direct", "protocol": "freedom"}],
            "routing": {"rules": [{"type": "field", "inboundTag": ["api-in"],
                                   "outboundTag": "api"}]},
        }
        server_path.write_text(json.dumps(server), encoding="utf-8")
        encoded = base64.urlsafe_b64encode(
            b"chacha20-ietf-poly1305:test-password"
        ).decode("ascii").rstrip("=")
        program = relay_python().replace("'${CONFIG_FILE}'", repr(str(server_path)))
        program = program.replace("${domains_json}", "[]")
        env = os.environ.copy()
        env.update(
            RELAY_LINK_ENV=f"ss://{encoded}@127.0.0.1:{upstream_port}?#landing-SS",
            RELAY_MODE_ENV="all",
        )
        configured = subprocess.run(
            [sys.executable, "-c", program], env=env, capture_output=True, text=True
        )
        assert configured.returncode == 0, configured.stderr
        client_path = root / "client.json"
        client = {
            "log": {"loglevel": "debug"},
            "inbounds": [{"tag": "socks-in", "listen": "127.0.0.1", "port": socks_port,
                          "protocol": "socks", "settings": {"auth": "noauth"}}],
            "outbounds": [{
                "tag": "hy2-out", "protocol": "hysteria",
                "settings": {"version": 2, "address": "127.0.0.1", "port": hy2_port},
                "streamSettings": {
                    "network": "hysteria", "security": "tls",
                    "tlsSettings": {"serverName": "localhost",
                                    "pinnedPeerCertSha256": fingerprint, "alpn": ["h3"]},
                    "hysteriaSettings": {"version": 2, "auth": "hy2-test-password"},
                },
            }],
        }
        client_path.write_text(json.dumps(client), encoding="utf-8")
        for path in (server_path, client_path):
            check = subprocess.run(
                [xray_bin, "run", "-test", "-c", str(path)],
                capture_output=True, text=True,
            )
            assert check.returncode == 0, check.stdout + check.stderr
        server_log = root / "server.log"
        client_log = root / "client.log"
        with server_log.open("w", encoding="utf-8") as output:
            server_process = subprocess.Popen(
                [xray_bin, "run", "-c", str(server_path)],
                stdout=output, stderr=subprocess.STDOUT,
            )
        with client_log.open("w", encoding="utf-8") as output:
            client_process = subprocess.Popen(
                [xray_bin, "run", "-c", str(client_path)],
                stdout=output, stderr=subprocess.STDOUT,
            )
        try:
            for _ in range(80):
                if server_process.poll() is not None or client_process.poll() is not None:
                    raise AssertionError("Xray HY2 server or client exited")
                try:
                    connection = socket.create_connection(("127.0.0.1", socks_port), 0.2)
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError("Xray HY2 client did not start")
            with connection:
                connection.settimeout(4)
                connection.sendall(b"\x05\x01\x00")
                assert connection.recv(2) == b"\x05\x00"
                host = b"example.com"
                connection.sendall(
                    b"\x05\x01\x00\x03" + bytes([len(host)]) + host + b"\x00\x50"
                )
                if not seen.wait(8):
                    raise AssertionError(
                        "Xray HY2 request did not dial the SS relay\n"
                        + server_log.read_text(encoding="utf-8", errors="replace")
                        + client_log.read_text(encoding="utf-8", errors="replace")
                    )
        finally:
            for process in (client_process, server_process):
                process.terminate()
                process.wait(timeout=5)
            upstream.close()
            worker.join(timeout=1)


def test_singbox_hy2_uses_relay(sing_box_bin: str, openssl_bin: str) -> None:
    upstream = socket.socket()
    upstream.bind(("127.0.0.1", 0))
    upstream.listen(1)
    upstream_port = upstream.getsockname()[1]
    seen = threading.Event()

    def accept_relay() -> None:
        upstream.settimeout(12)
        try:
            connection, _ = upstream.accept()
            with connection:
                seen.set()
        except (socket.timeout, OSError):
            pass

    worker = threading.Thread(target=accept_relay, daemon=True)
    worker.start()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        cert, key = root / "cert.pem", root / "key.pem"
        made = subprocess.run([
            openssl_bin, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "1", "-subj", "/CN=localhost", "-addext",
            "subjectAltName=DNS:localhost", "-keyout", str(key), "-out", str(cert),
        ], capture_output=True, text=True)
        assert made.returncode == 0, made.stderr
        with socket.socket(type=socket.SOCK_DGRAM) as reserve:
            reserve.bind(("127.0.0.1", 0))
            hy2_port = reserve.getsockname()[1]
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            socks_port = reserve.getsockname()[1]

        server_config = {
            "log": {"level": "error"},
            "inbounds": [{
                "type": "hysteria2", "tag": "sb-hy2", "listen": "127.0.0.1",
                "listen_port": hy2_port, "users": [{"password": "hy2-test-password"}],
                "tls": {"enabled": True, "alpn": ["h3"],
                        "certificate_path": str(cert), "key_path": str(key)},
            }],
            "outbounds": [{
                "type": "shadowsocks", "tag": "argov-relay", "server": "127.0.0.1",
                "server_port": upstream_port, "method": "chacha20-ietf-poly1305",
                "password": "test-password",
            }],
            "route": {
                "rules": [{"action": "route", "outbound": "argov-relay"}],
                "final": "argov-relay",
            },
        }
        client_config = {
            "log": {"level": "error"},
            "inbounds": [{
                "type": "socks", "tag": "socks-in", "listen": "127.0.0.1",
                "listen_port": socks_port,
            }],
            "outbounds": [{
                "type": "hysteria2", "tag": "hy2-out", "server": "127.0.0.1",
                "server_port": hy2_port, "password": "hy2-test-password",
                "tls": {"enabled": True, "server_name": "localhost",
                        "insecure": True, "alpn": ["h3"]},
            }],
            "route": {"final": "hy2-out"},
        }
        server_path, client_path = root / "server.json", root / "client.json"
        server_path.write_text(json.dumps(server_config), encoding="utf-8")
        client_path.write_text(json.dumps(client_config), encoding="utf-8")
        for path in (server_path, client_path):
            check = subprocess.run(
                [sing_box_bin, "check", "-c", str(path)],
                capture_output=True, text=True,
            )
            assert check.returncode == 0, check.stdout + check.stderr

        server_log, client_log = root / "server.log", root / "client.log"
        with server_log.open("w", encoding="utf-8") as output:
            server_process = subprocess.Popen(
                [sing_box_bin, "run", "-c", str(server_path)],
                stdout=output, stderr=subprocess.STDOUT,
            )
        with client_log.open("w", encoding="utf-8") as output:
            client_process = subprocess.Popen(
                [sing_box_bin, "run", "-c", str(client_path)],
                stdout=output, stderr=subprocess.STDOUT,
            )
        try:
            for _ in range(60):
                if server_process.poll() is not None or client_process.poll() is not None:
                    raise AssertionError("sing-box HY2 test core exited")
                try:
                    connection = socket.create_connection(("127.0.0.1", socks_port), 0.2)
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError("sing-box SOCKS inbound did not start")
            with connection:
                connection.settimeout(3)
                connection.sendall(b"\x05\x01\x00")
                assert connection.recv(2) == b"\x05\x00"
                host = b"example.com"
                connection.sendall(b"\x05\x01\x00\x03" + bytes([len(host)]) + host + b"\x00\x50")
                if not seen.wait(8):
                    raise AssertionError(
                        "sing-box HY2 did not dial the SS relay\n"
                        + server_log.read_text(encoding="utf-8", errors="replace")
                        + client_log.read_text(encoding="utf-8", errors="replace")
                    )
        finally:
            for process in (client_process, server_process):
                process.terminate()
                process.wait(timeout=5)
            upstream.close()
            worker.join(timeout=1)


if __name__ == "__main__":
    test_ss_relay()
    if len(sys.argv) > 1:
        test_xray_uses_relay(sys.argv[1])
    if len(sys.argv) > 2:
        test_hy2_uses_relay(sys.argv[1], sys.argv[2])
    if len(sys.argv) > 3:
        test_singbox_hy2_uses_relay(sys.argv[3], sys.argv[2])
    print("relay tests passed")
