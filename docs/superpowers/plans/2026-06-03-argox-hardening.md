# ArgoX Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden `argox_mini.sh` against configuration, Reality, WARP, service-control, and menu-flow bugs without changing the one-file installer shape.

**Architecture:** Keep the script as a single Bash entrypoint. Add small helper functions for escaping, validation, and JSON-safe domain handling, then update the existing install, node, WARP, and menu functions to use them.

**Tech Stack:** Bash, jq, Python3 for JSON rewriting, systemd/OpenRC service templates, static shell/Python tests.

---

### Task 1: Static Regression Tests

**Files:**
- Modify: `tests/argox_static_tests.sh`
- Create: `tests/argox_static_tests.py`

- [ ] Add tests that fail until the script fixes service recursion, config escaping, Reality shortId generation, install protocol selection, CDN fallback, WARP domain JSON handling, and menu wording.
- [ ] Run `bash tests/argox_static_tests.sh argox_mini.sh` and confirm failure before production changes.

### Task 2: Core Safety Helpers

**Files:**
- Modify: `argox_mini.sh`

- [ ] Fix the non-Alpine `systemctl()` shim to call `command systemctl`.
- [ ] Add `save_var`, `is_port`, and `json_array_from_file` helpers.
- [ ] Use `save_var` in `save_conf`.
- [ ] Make `get_cdn` and `get_cdn_port` fall back when JSON fields are empty or null.

### Task 3: Install and Reality Fixes

**Files:**
- Modify: `argox_mini.sh`

- [ ] Call `select_protocols` from `interactive_install`.
- [ ] Generate `REALITY_SHORTID` during install whenever Reality is enabled and missing.
- [ ] Write `REALITY_SHORTID` and `fingerprint` into the initial Reality inbound.
- [ ] Pass fingerprint to generated Reality links.

### Task 4: WARP Hardening

**Files:**
- Modify: `argox_mini.sh`

- [ ] Stop applying WARP routing if WARP SOCKS installation fails.
- [ ] Pass the domain list to Python via JSON from `json_array_from_file`, not string-built Python literals.
- [ ] Keep existing routing modes and output text.

### Task 5: Menu Cleanup

**Files:**
- Modify: `argox_mini.sh`

- [ ] Rename main menu groups to links, nodes/routes, services, and maintenance.
- [ ] Remove misleading SS/Reality global edits from `change_config`.
- [ ] Keep node-specific SS/Reality editing under menu `a`.

### Task 6: Verification

**Files:**
- Test: `tests/argox_static_tests.sh`

- [ ] Run `bash -n argox_mini.sh`.
- [ ] Run `bash tests/argox_static_tests.sh argox_mini.sh`.
- [ ] Inspect `git diff` for accidental unrelated changes.
