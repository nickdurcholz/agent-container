#!/bin/bash
# SPDX-License-Identifier: MIT
set -e

HOST_USER="${HOST_USER:-}"
HOST_UID="${HOST_UID:-}"
HOST_GID="${HOST_GID:-}"
HOST_HOME="${HOST_HOME:-}"

if [ -n "$HOST_USER" ] && [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ] && [ -n "$HOST_HOME" ]; then
    # Handle group: reuse existing GID or create new
    EXISTING_GROUP=$(getent group "$HOST_GID" 2>/dev/null | cut -d: -f1 || true)
    if [ -z "$EXISTING_GROUP" ]; then
        groupadd -g "$HOST_GID" "$HOST_USER"
    fi

    # Handle user: if a user with our target UID already exists, modify it;
    # otherwise create a new one. The devcontainer base image ships with a
    # 'vscode' user at UID 1000, which commonly conflicts.
    EXISTING_USER=$(getent passwd "$HOST_UID" 2>/dev/null | cut -d: -f1 || true)
    if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "$HOST_USER" ]; then
        # Rename existing user to match host
        usermod -l "$HOST_USER" -d "$HOST_HOME" -s /bin/zsh "$EXISTING_USER"
        # Rename the user's primary group if it matches the old username
        OLD_GROUP=$(getent group "$HOST_GID" 2>/dev/null | cut -d: -f1 || true)
        if [ "$OLD_GROUP" = "$EXISTING_USER" ]; then
            groupmod -n "$HOST_USER" "$OLD_GROUP" 2>/dev/null || true
        fi
    elif [ -z "$EXISTING_USER" ]; then
        useradd -u "$HOST_UID" -g "$HOST_GID" -d "$HOST_HOME" -s /bin/zsh -M "$HOST_USER"
    fi
    # If EXISTING_USER == HOST_USER, nothing to do

    # Give the user passwordless sudo
    echo "$HOST_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent-user
    chmod 0440 /etc/sudoers.d/agent-user

    # Run firewall if requested
    if [ "${AGENT_FIREWALL:-0}" = "1" ]; then
        /usr/local/bin/init-firewall.sh
    fi

    # Drop privileges and exec the command as the host user
    exec gosu "$HOST_USER" "$@"
else
    # No host user info — run as current user (devcontainer CLI path)
    if [ "${AGENT_FIREWALL:-0}" = "1" ]; then
        /usr/local/bin/init-firewall.sh
    fi
    exec "$@"
fi
