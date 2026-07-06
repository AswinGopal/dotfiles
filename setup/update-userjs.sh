#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${1:-}"
PROFILES_INI="${HOME}/.config/mozilla/firefox/profiles.ini"
GITHUB_API="https://api.github.com/repos/yokoffing/Betterfox/releases/latest"

# --- Validate input ---
if [[ -z "$PROFILE_NAME" ]]; then
  echo "Usage: $0 <profile-name>"
  echo "Example: $0 default-release"
  exit 1
fi

# --- Find profile path from profiles.ini ---
if [[ ! -f "$PROFILES_INI" ]]; then
  echo "Error: profiles.ini not found at $PROFILES_INI"
  exit 1
fi

# Parse the ini: find the section with Name=<PROFILE_NAME>, grab its Path
PROFILE_REL_PATH=$(python3 - <<EOF
import configparser, sys

ini = configparser.ConfigParser()
ini.read("$PROFILES_INI")

for section in ini.sections():
    if ini.get(section, "Name", fallback=None) == "$PROFILE_NAME":
        path = ini.get(section, "Path", fallback=None)
        is_relative = ini.get(section, "IsRelative", fallback="0")
        if path:
            print(is_relative + "|" + path)
            sys.exit(0)

print("NOT_FOUND")
EOF
)

if [[ "$PROFILE_REL_PATH" == "NOT_FOUND" ]]; then
  echo "Error: Profile '$PROFILE_NAME' not found in profiles.ini"
  exit 1
fi

IS_RELATIVE="${PROFILE_REL_PATH%%|*}"
RAW_PATH="${PROFILE_REL_PATH##*|}"

if [[ "$IS_RELATIVE" == "1" ]]; then
  PROFILE_DIR="$(dirname "$PROFILES_INI")/${RAW_PATH}"
else
  PROFILE_DIR="$RAW_PATH"
fi

echo "Profile directory: $PROFILE_DIR"

# --- Fetch latest release tarball URL from GitHub API ---
echo "Fetching latest Betterfox release info..."
TARBALL_URL=$(curl -sf "$GITHUB_API" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['tarball_url'])
")

if [[ -z "$TARBALL_URL" ]]; then
  echo "Error: Could not fetch release info from GitHub API"
  exit 1
fi

echo "Downloading: $TARBALL_URL"

# --- Download and extract in a temp dir ---
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -sL "$TARBALL_URL" -o "$TMP_DIR/betterfox.tar.gz"
tar -xzf "$TMP_DIR/betterfox.tar.gz" -C "$TMP_DIR"

# Find user.js inside the extracted folder (folder name is dynamic)
USER_JS_SRC=$(find "$TMP_DIR" -maxdepth 2 -name "user.js" | head -n 1)

if [[ -z "$USER_JS_SRC" ]]; then
  echo "Error: user.js not found in the release archive"
  exit 1
fi

# --- Write user.js to profile ---
cp "$USER_JS_SRC" "$PROFILE_DIR/user.js"
echo "user.js updated successfully"

# --- Inject user-overrides.js after marker line ---
OVERRIDES="$PROFILE_DIR/user-overrides.js"
MARKER="// Enter your personal overrides below this line:"

if [[ -f "$OVERRIDES" ]]; then
  python3 - <<EOF
import sys

marker = "$MARKER"
with open("$PROFILE_DIR/user.js", "r") as f:
    lines = f.readlines()

insert_at = None
for i, line in enumerate(lines):
    if marker in line:
        insert_at = i + 1
        break

if insert_at is None:
    print("Error: marker line not found in user.js")
    sys.exit(1)

with open("$PROFILE_DIR/user-overrides.js", "r") as f:
    overrides = f.readlines()

while overrides and overrides[-1].strip() == "":
    overrides.pop()
overrides.append("\n")

rest = lines[insert_at:]
while rest and rest[0].strip() == "":
    rest.pop(0)

lines = lines[:insert_at] + ["\n"] + overrides + ["\n"] + rest

with open("$PROFILE_DIR/user.js", "w") as f:
    f.writelines(lines)

print("user-overrides.js injected successfully")
EOF
else
  echo "Warning: user-overrides.js not found in profile directory — skipping"
fi

echo "Done!"
