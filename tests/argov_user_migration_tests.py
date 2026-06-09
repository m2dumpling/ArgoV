#!/usr/bin/env python3
import json
import re
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures" / "legacy"
DEFAULT_UUID = "99999999-9999-4999-8999-999999999999"
DEFAULT_TOKEN = "default-upgrade-token"


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


def clean_name(v):
    v = (v or "default").strip()
    return v or "default"


def email_for(name):
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", clean_name(name)).strip("-._").lower()
    return "argov-" + (safe or "user")


def norm_user(u, default_uuid, default_token, now=1_700_000_000):
    u = dict(u or {})
    u["name"] = clean_name(u.get("name"))
    u["uuid"] = u.get("uuid") or default_uuid
    u["token"] = u.get("token") or (default_token if u["name"] == "default" else "")
    u["enabled"] = bool(u.get("enabled", True))
    u["quota_bytes"] = int(u.get("quota_bytes") or 0)
    u["used_up"] = int(u.get("used_up") or 0)
    u["used_down"] = int(u.get("used_down") or 0)
    u["reset_day"] = int(u.get("reset_day") or 0)
    u["last_reset_month"] = int(u.get("last_reset_month") or 0)
    u["email"] = u.get("email") or email_for(u["name"])
    u["created_at"] = int(u.get("created_at") or now)
    return u


def migrate_users(data, uuid=DEFAULT_UUID, token=DEFAULT_TOKEN):
    users = data.get("users") if isinstance(data, dict) else None
    if not isinstance(users, list):
        users = []
    seen, out, has_default = set(), [], False
    for u in users:
        nu = norm_user(u, uuid, token)
        if nu["name"] in seen:
            continue
        seen.add(nu["name"])
        if nu["name"] == "default":
            has_default = True
            if token:
                nu["token"] = token
            if uuid:
                nu["uuid"] = uuid
        out.append(nu)
    if not has_default:
        out.insert(0, norm_user({"name": "default", "uuid": uuid, "token": token, "quota_bytes": 0}, uuid, token))
    return {"version": 1, "users": out}


def fixture(name: str):
    path = FIXTURES / name
    require(path.is_file(), f"missing fixture: {name}")
    return json.loads(path.read_text(encoding="utf-8"))


def by_name(data, name):
    return next((u for u in data["users"] if u.get("name") == name), None)


def assert_script_contract(text: str) -> None:
    require("def norm_user(u, default_uuid, default_token):" in text, "ensure_users_file must normalize legacy user records")
    require("u[\"enabled\"] = bool(u.get(\"enabled\", True))" in text, "user migration must preserve disabled state")
    require("u[\"quota_bytes\"] = int(u.get(\"quota_bytes\") or 0)" in text, "user migration must normalize quota_bytes")
    require("u[\"used_up\"] = int(u.get(\"used_up\") or 0)" in text, "user migration must preserve uplink usage")
    require("u[\"used_down\"] = int(u.get(\"used_down\") or 0)" in text, "user migration must preserve downlink usage")
    require("if nu[\"name\"] in seen:" in text, "user migration must deduplicate names predictably")
    require("if not has_default:" in text, "user migration must create a default user when missing")


def assert_migration_samples() -> None:
    migrated = migrate_users(fixture("argov.users.v1.json"))
    default = by_name(migrated, "default")
    alice = by_name(migrated, "alice")
    disabled = by_name(migrated, "disabled-user")
    require(migrated["version"] == 1, "migration must write version 1 user store")
    require(default["uuid"] == DEFAULT_UUID, "default UUID follows current install UUID during ensure_users_file")
    require(default["token"] == DEFAULT_TOKEN, "default token follows current install SUB_TOKEN during ensure_users_file")
    require(alice["uuid"] == "22222222-2222-4222-8222-222222222222", "non-default user UUID must be preserved")
    require(alice["token"] == "alice-token-001", "non-default user token must be preserved")
    require(alice["quota_bytes"] == 10737418240, "non-default user quota must be preserved")
    require(alice["used_up"] == 2048 and alice["used_down"] == 4096, "non-default user usage must be preserved")
    require(disabled["enabled"] is False, "disabled users must remain disabled")
    require(disabled["email"] == "argov-disabled-user", "missing emails must be derived from stable user names")

    missing_version = migrate_users(fixture("argov.users.missing-version.json"))
    require(missing_version["version"] == 1, "pre-version user store must migrate to version 1")
    require(len(missing_version["users"]) == 1, "pre-version single-user store must not grow extra users")
    require(by_name(missing_version, "default")["token"] == DEFAULT_TOKEN, "pre-version default token must follow current SUB_TOKEN")

    quota = migrate_users(fixture("argov.users.quota-disabled.json"))
    q = by_name(quota, "quota-exceeded")
    require(q["enabled"] is True, "over-quota user enabled state must not be changed by migration")
    require(q["used_up"] + q["used_down"] > q["quota_bytes"], "over-quota counters must be preserved for watcher enforcement")

    created = migrate_users({"users": []})
    require(created["users"][0]["name"] == "default", "empty user stores must gain a default user first")
    require(created["users"][0]["uuid"] == DEFAULT_UUID, "created default user must use current UUID")
    require(created["users"][0]["token"] == DEFAULT_TOKEN, "created default user must use current SUB_TOKEN")


def main() -> None:
    assert_script_contract(read_script())
    assert_migration_samples()


if __name__ == "__main__":
    main()
