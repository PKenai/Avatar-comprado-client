import sys
import os
import re
import subprocess

def get_next_version(repo_dir):
    try:
        cmd = ["git", "log", "-1", "--pretty=%s"]
        res = subprocess.check_output(cmd, cwd=repo_dir, text=True, stderr=subprocess.DEVNULL)
        last_commit = res.strip()
    except Exception:
        last_commit = ""

    # Match UpdateX.Y (e.g. Update1.0, Update1.1, etc.)
    m = re.search(r"Update(\d+)\.(\d+)", last_commit, re.IGNORECASE)
    if m:
        major = int(m.group(1))
        minor = int(m.group(2)) + 1
        if minor >= 10:
            major += 1
            minor = 0
    else:
        # Default starting version
        major = 1
        minor = 0

    return f"Update{major}.{minor}"

if __name__ == "__main__":
    repo = sys.argv[1] if len(sys.argv) > 1 else "."
    print(get_next_version(repo))
