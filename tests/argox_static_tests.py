#!/usr/bin/env python3
import re
import sys
from pathlib import Path


script = Path(sys.argv[1])
text = script.read_text(encoding="utf-8")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def require(pattern: str, message: str, flags: int = 0) -> None:
    if not re.search(pattern, text, flags):
        fail(message)


def forbid(pattern: str, message: str, flags: int = 0) -> None:
    if re.search(pattern, text, flags):
        fail(message)


require(
    r'\*\)\s+command systemctl "\$cmd" "\$@"',
    "non-Alpine systemctl wrapper must call command systemctl to avoid recursion",
)
require(r"save_var\(\)", "save_conf must use a shell-escaping save_var helper")
require(
    r"save_var NODE_NAME \"\$NODE_NAME\"",
    "NODE_NAME must be persisted through save_var so quotes cannot break argox.conf",
)
require(
    r"get_cdn\(\)[\s\S]*\[\s+-n \"\$v\"\s+\].*\[\s+\"\$v\"\s+!= \"null\"\s+\]",
    "get_cdn must fall back when current_cdn is empty or null",
)
require(
    r"interactive_install\(\)[\s\S]*select_protocols[\s\S]*do_install",
    "interactive install must call select_protocols before do_install",
)
require(
    r"ENABLE_REALITY.*gen_reality_shortid",
    "Reality install path must generate REALITY_SHORTID",
)
require(
    r'"shortIds":\["\'"\$\{REALITY_SHORTID\}"\'"\]',
    "initial Reality inbound must write REALITY_SHORTID into shortIds",
)
require(
    r'"fingerprint":"chrome"',
    "initial Reality inbound must include a Reality fingerprint",
)
require(
    r"json_array_from_file\(\)",
    "WARP domain lists must be converted with json_array_from_file",
)
forbid(
    r"DOMAINS = \[\$\{domains_list\}\]",
    "WARP apply must not splice raw domain text into Python code",
)
forbid(
    r'domain":\[\$\{all_domains\}\]',
    "WARP mode switch must not splice raw domain text into Python code",
)
require(
    r"warp_auto_install_socks \|\| return",
    "WARP routing must stop when SOCKS installation fails",
)
require(
    r"节点与线路",
    "main menu should expose a clearer node/route group",
)
require(
    r"基础配置",
    "change_config menu should be narrowed to base configuration",
)
