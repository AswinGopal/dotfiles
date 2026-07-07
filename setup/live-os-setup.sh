#!/bin/bash

set -e

# ─── Config ───────────────────────────────────────────────────────────────────

RUN_SIZE="8G"

# ─── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo "[+] $*"; }
die()     { echo "[✗] $*"; exit 1; }
section() { echo; echo "━━━ $* ━━━"; }

require_root() {
    [ "$EUID" -eq 0 ] || die "Run as root: sudo $0"
}

# ─── Tasks ────────────────────────────────────────────────────────────────────

task_resize_run_tmpfs() {
    section "Resize /run tmpfs"

    mountpoint -q /run || die "/run is not mounted."

    local fstype
    fstype=$(findmnt -n -o FSTYPE /run)
    [ "$fstype" = "tmpfs" ] || die "/run is not a tmpfs (found: $fstype)"

    mount -o remount,size="$RUN_SIZE" /run
    info "Remounted /run with size=$RUN_SIZE"
    df -h /run
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    require_root
    task_resize_run_tmpfs
}

main "$@"
