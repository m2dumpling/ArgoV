import sys

def rename_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Order matters. Replace more specific strings first if needed.
    replacements = {
        "ArgoX-Mini": "ArgoV",
        "ArgoX": "ArgoV",
        "argox_mini.sh": "argov.sh",
        "argox.conf": "argov.conf",
        "argox-tunnel": "argov-tunnel",
        "argox-sub": "argov-sub",
        "/etc/xray/argox": "/etc/xray/argov",
        'SCRIPT_PATH="/usr/bin/argov"': 'SCRIPT_PATH="/usr/bin/ag"',
        "argov": "ag", # Wait, we must be careful with "argov" replacement globally.
    }
    
    # We should not globally replace "argov" with "ag" because it might replace "argov.sh" to "ag.sh", or "argov.conf" to "ag.conf"!
    # Let's do selective replacements instead.
    
    content = content.replace("ArgoX-Mini", "ArgoV")
    content = content.replace("ArgoX", "ArgoV")
    content = content.replace("argox_mini.sh", "argov.sh")
    content = content.replace("argox.conf", "argov.conf")
    content = content.replace("argox-tunnel", "argov-tunnel")
    content = content.replace("argox-sub", "argov-sub")
    content = content.replace("/etc/xray/argox", "/etc/xray/argov")
    content = content.replace('SCRIPT_PATH="/usr/bin/argov"', 'SCRIPT_PATH="/usr/bin/ag"')
    content = content.replace("命令行输入 argov", "命令行输入 ag")
    content = content.replace("输入 argov", "输入 ag")
    content = content.replace("输入 \`argov\`", "输入 \`ag\`")
    content = content.replace(" argov ", " ag ")
    content = content.replace("📋 argov ", "📋 ag ")
    content = content.replace("argox", "argov") # Remaining internal vars like argox.XXXXXX
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

rename_file("argov.sh")
rename_file("README.md")
rename_file("README_CN.md")
