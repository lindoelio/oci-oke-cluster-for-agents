import json, os, sys

# Merges the OpenCode Go provider key into an opencode auth.json file.
# Used as an initContainer by both the OpenCode deployment and Paperclip
# (which bundles the opencode CLI for its OpenCode adapter sessions).

auth_path = os.environ.get("AUTH_PATH", "")
key = os.environ.get("OPENCODE_GO_API_KEY", "")

if not auth_path:
    print("[opencode-go] AUTH_PATH not set, skipping")
    sys.exit(0)

if not key:
    print("[opencode-go] no API key configured, skipping")
    sys.exit(0)

data = {}
if os.path.exists(auth_path):
    try:
        with open(auth_path) as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        print("[opencode-go] existing auth.json unreadable, recreating")

data["opencode-go"] = {"type": "api", "key": key}

os.makedirs(os.path.dirname(auth_path), exist_ok=True)
tmp = auth_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, auth_path)

uid = int(os.environ.get("AUTH_UID", "0"))
gid = int(os.environ.get("AUTH_GID", "0"))
if uid or gid:
    for path in (os.path.dirname(auth_path), auth_path):
        try:
            os.chown(path, uid, gid)
        except (PermissionError, OSError):
            pass

print("[opencode-go] auth.json updated at " + auth_path)
