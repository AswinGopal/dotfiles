#!/bin/bash

# modules/firewall.sh
#
# Fedora only. Harden the firewall by removing permissive port ranges and
# services from the permanent configuration, then reload to apply.
#
# Remove commands suppress stderr — firewall-cmd --remove-* exits non-zero if
# the target is not present ("Warning: NOT_ENABLED"). "Already not present" is
# the desired state and is not treated as a failure. Only the reload is checked.
#
# Public interface: run_firewall()

# ------------------------------------------------------------------------------
# run_firewall
# ------------------------------------------------------------------------------
run_firewall() {
    # Remove permissive port ranges and services from the permanent config.
    # Stderr suppressed: not-present is idempotent, not an error.
    sudo firewall-cmd --permanent --remove-port=1025-65535/tcp    2>/dev/null
    sudo firewall-cmd --permanent --remove-port=1025-65535/udp    2>/dev/null
    sudo firewall-cmd --permanent --remove-service=samba-client   2>/dev/null
    sudo firewall-cmd --permanent --remove-service=ssh            2>/dev/null

    # Apply permanent config to the runtime config. This is the only step
    # that can meaningfully fail.
    if ! sudo firewall-cmd --reload > /dev/null; then
        log_error "Failed to reload firewall."
        return 1
    fi

    success_message "Firewall configured."
    return 0
}
