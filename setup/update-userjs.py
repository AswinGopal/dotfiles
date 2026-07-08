#!/usr/bin/env python3
"""
update-userjs.py

Update user.js from the latest Betterfox release for one or more Firefox
profiles. Any user-overrides.js and/or user-overrides-erase_all.js found in
a profile directory are injected after the designated marker line, in that
order.

Usage:
    ./update-userjs.py <profile-name> [profile-name2 ...]

Example:
    ./update-userjs.py brave edge
"""

import configparser
import json
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

GITHUB_API   = "https://api.github.com/repos/yokoffing/Betterfox/releases/latest"
MARKER       = "// Enter your personal overrides below this line:"

# Injected in this order; files absent from the profile directory are skipped.
OVERRIDE_FILES = [
    "user-overrides.js",
    "user-overrides-erase_all.js",
]

# profiles.ini location per distro — mirrors browser_profiles.sh conventions.
_PROFILES_INI_PATHS: dict[str, Path] = {
    "arch":   Path.home() / ".mozilla/firefox/profiles.ini",
    "fedora": Path.home() / ".config/mozilla/firefox/profiles.ini",
    "ubuntu": Path.home() / "snap/firefox/common/.mozilla/firefox/profiles.ini",
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

def _detect_os_id() -> str:
    os_release = Path("/etc/os-release")
    if os_release.exists():
        for line in os_release.read_text().splitlines():
            if line.startswith("ID="):
                return line.split("=", 1)[1].strip('"')
    return ""


def detect_profiles_ini() -> Path:
    """
    Return the path to profiles.ini for the current distro.

    Primary: match /etc/os-release ID against the known map.
    Fallback: probe each known path in declaration order and return the first
              that exists. Handles non-standard installs where the ID is
              unrecognised but the path is conventional.
    """
    os_id = _detect_os_id()

    if os_id in _PROFILES_INI_PATHS:
        return _PROFILES_INI_PATHS[os_id]

    for path in _PROFILES_INI_PATHS.values():
        if path.exists():
            return path

    print(
        "Error: Could not locate profiles.ini.\n"
        "       Unsupported OS or non-standard Firefox install.\n"
        "       Known locations:\n"
        + "\n".join(f"         {p}" for p in _PROFILES_INI_PATHS.values()),
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# Profile resolution
# ---------------------------------------------------------------------------

def resolve_profile_dir(
    ini: configparser.ConfigParser,
    profile_name: str,
    profiles_ini: Path,
) -> Path | None:
    """
    Look up a profile by name in the parsed profiles.ini.
    Returns the resolved absolute directory path, or None if not found.
    """
    for section in ini.sections():
        if ini.get(section, "Name", fallback=None) == profile_name:
            raw_path = ini.get(section, "Path", fallback=None)
            is_relative = ini.get(section, "IsRelative", fallback="0") == "1"
            if raw_path:
                if is_relative:
                    return (profiles_ini.parent / raw_path).resolve()
                return Path(raw_path).resolve()
    return None

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

def fetch_tarball_url() -> str:
    print("Fetching latest Betterfox release info...")
    try:
        with urllib.request.urlopen(GITHUB_API) as resp:
            data = json.load(resp)
    except Exception as exc:
        print(f"Error: Failed to fetch release info from GitHub API: {exc}", file=sys.stderr)
        sys.exit(1)

    url = data.get("tarball_url", "")
    if not url:
        print("Error: tarball_url missing from API response.", file=sys.stderr)
        sys.exit(1)

    return url


def download_and_extract_userjs(tarball_url: str, tmp_dir: Path) -> Path:
    """
    Download the Betterfox release tarball and return the path to user.js
    inside the extracted tree.
    """
    tarball_path = tmp_dir / "betterfox.tar.gz"

    print(f"Downloading: {tarball_url}")
    try:
        urllib.request.urlretrieve(tarball_url, tarball_path)
    except Exception as exc:
        print(f"Error: Failed to download tarball: {exc}", file=sys.stderr)
        sys.exit(1)

    try:
        with tarfile.open(tarball_path) as tf:
            tf.extractall(tmp_dir)
    except Exception as exc:
        print(f"Error: Failed to extract tarball: {exc}", file=sys.stderr)
        sys.exit(1)

    matches = list(tmp_dir.glob("*/user.js"))
    if not matches:
        print("Error: user.js not found in the release archive.", file=sys.stderr)
        sys.exit(1)

    return matches[0]

# ---------------------------------------------------------------------------
# Override injection
# ---------------------------------------------------------------------------

def inject_overrides(lines: list[str], override_paths: list[Path]) -> list[str]:
    """
    Inject the contents of each override file, in order, immediately after
    the marker line. Each chunk is stripped of trailing blank lines and
    separated from the next by a single blank line.

    The rest of the original file after the marker (skipping any leading
    blank lines) is appended last.

    Raises ValueError if the marker line is not found.
    """
    marker_idx = next(
        (i for i, line in enumerate(lines) if MARKER in line),
        None,
    )
    if marker_idx is None:
        raise ValueError(f"Marker line not found in user.js: {MARKER!r}")

    to_inject: list[str] = []
    for path in override_paths:
        chunk = path.read_text().splitlines(keepends=True)
        # Strip trailing blank lines; end each chunk with exactly one blank line
        # so the injected blocks are visually separated.
        while chunk and chunk[-1].strip() == "":
            chunk.pop()
        chunk.append("\n")
        to_inject.extend(chunk)

    # Skip leading blank lines in the original content following the marker.
    rest = lines[marker_idx + 1:]
    while rest and rest[0].strip() == "":
        rest.pop(0)

    return lines[: marker_idx + 1] + to_inject + rest

# ---------------------------------------------------------------------------
# Per-profile update
# ---------------------------------------------------------------------------

def update_profile(
    profile_name: str,
    profile_dir: Path,
    user_js_src: Path,
) -> bool:
    """
    Update user.js for a single profile. Returns True on success, False on
    any failure (original user.js is preserved on failure).
    """
    print(f"--- Updating profile: {profile_name} ---")
    print(f"Profile directory: {profile_dir}")

    user_js_dest = profile_dir / "user.js"

    # Backup existing user.js before touching anything.
    if user_js_dest.exists():
        backup = profile_dir / "user.js.bak"
        shutil.copy2(user_js_dest, backup)
        print("Backed up existing user.js to user.js.bak")

    # Collect whichever override files are present in this profile directory.
    present_overrides = [
        profile_dir / name
        for name in OVERRIDE_FILES
        if (profile_dir / name).exists()
    ]

    # Read the fresh upstream user.js.
    lines = user_js_src.read_text().splitlines(keepends=True)

    # Inject overrides if any are present.
    if present_overrides:
        names = ", ".join(p.name for p in present_overrides)
        print(f"Injecting: {names}")
        try:
            lines = inject_overrides(lines, present_overrides)
        except ValueError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return False
    else:
        print("No override files found — installing plain user.js")

    # Atomic write: write to a temp file in the same directory (same filesystem),
    # then rename. The rename is atomic on POSIX; partial writes never land.
    fd, tmp_path_str = tempfile.mkstemp(dir=profile_dir, prefix="user.js.tmp.")
    tmp_path = Path(tmp_path_str)
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write("".join(lines))
        tmp_path.replace(user_js_dest)
    except Exception as exc:
        print(f"Error: Failed to write user.js: {exc}", file=sys.stderr)
        tmp_path.unlink(missing_ok=True)
        return False

    print("user.js updated successfully")
    return True

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <profile-name> [profile-name2 ...]")
        print(f"Example: {sys.argv[0]} brave edge")
        sys.exit(1)

    profile_names: list[str] = sys.argv[1:]

    # Locate and parse profiles.ini.
    profiles_ini = detect_profiles_ini()
    if not profiles_ini.exists():
        print(f"Error: profiles.ini not found at {profiles_ini}", file=sys.stderr)
        sys.exit(1)

    ini = configparser.ConfigParser()
    ini.read(profiles_ini)

    # Validate every requested profile before any network activity.
    print("Validating profiles...")
    profile_dirs: dict[str, Path] = {}
    for name in profile_names:
        profile_dir = resolve_profile_dir(ini, name, profiles_ini)
        if profile_dir is None:
            print(f"Error: Profile '{name}' not found in profiles.ini", file=sys.stderr)
            sys.exit(1)
        if not profile_dir.is_dir():
            print(
                f"Error: Profile directory does not exist for '{name}': {profile_dir}",
                file=sys.stderr,
            )
            sys.exit(1)
        profile_dirs[name] = profile_dir
        print(f"  ✓ {name} → {profile_dir}")

    print()

    # Fetch release metadata and download the tarball once, shared across all profiles.
    tarball_url = fetch_tarball_url()

    with tempfile.TemporaryDirectory() as tmp_str:
        user_js_src = download_and_extract_userjs(tarball_url, Path(tmp_str))
        print()

        failed: list[str] = []
        for name in profile_names:
            success = update_profile(name, profile_dirs[name], user_js_src)
            if not success:
                failed.append(name)
            print()

    # Summary.
    if failed:
        print("Completed with errors. The following profiles failed:")
        for name in failed:
            print(f"  - {name}")
        sys.exit(1)

    print("Done! All profiles updated successfully.")


if __name__ == "__main__":
    main()
