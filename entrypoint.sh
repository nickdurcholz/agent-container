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
        usermod -l "$HOST_USER" -d "$HOST_HOME" -g "$HOST_GID" -s /bin/bash "$EXISTING_USER"
        # Rename the user's primary group if it matches the old username
        OLD_GROUP=$(getent group "$HOST_GID" 2>/dev/null | cut -d: -f1 || true)
        if [ "$OLD_GROUP" = "$EXISTING_USER" ]; then
            groupmod -n "$HOST_USER" "$OLD_GROUP" 2>/dev/null || true
        fi
    elif [ -z "$EXISTING_USER" ]; then
        useradd -u "$HOST_UID" -g "$HOST_GID" -d "$HOST_HOME" -s /bin/bash -M "$HOST_USER"
    fi
    # If EXISTING_USER == HOST_USER, nothing to do

    # Give the user passwordless sudo
    echo "$HOST_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent-user
    chmod 0440 /etc/sudoers.d/agent-user

    # Ensure home directory exists (selective mounts don't create it)
    mkdir -p "$HOST_HOME"
    chown "$HOST_UID:$HOST_GID" "$HOST_HOME"

    # Create /work scratch space owned by the container user
    mkdir -p /work
    chown "$HOST_UID:$HOST_GID" /work

    # Create XDG_RUNTIME_DIR for agent sockets (normally done by systemd-logind)
    RUNTIME_DIR="/run/user/$HOST_UID"
    mkdir -p "$RUNTIME_DIR"
    chown "$HOST_UID:$HOST_GID" "$RUNTIME_DIR"
    chmod 700 "$RUNTIME_DIR"

    # Docker socket access: match the container's docker group GID to the
    # mounted socket's group so the user can talk to the host daemon.
    if [ -S /var/run/docker.sock ]; then
        SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
        if getent group "$SOCK_GID" >/dev/null 2>&1; then
            DOCKER_GROUP=$(getent group "$SOCK_GID" | cut -d: -f1)
        else
            groupadd -g "$SOCK_GID" docker
            DOCKER_GROUP="docker"
        fi
        usermod -aG "$DOCKER_GROUP" "$HOST_USER"
    fi

    # GPG agent forwarding: if the host socket is mounted at a path that differs
    # from where the container's gpg expects it, create a symlink.
    if [ -n "${HOST_GPG_AGENT_SOCK:-}" ] && [ -S "$HOST_GPG_AGENT_SOCK" ]; then
        CONTAINER_GPG_SOCK="$(gosu "$HOST_USER" gpgconf --list-dirs agent-socket 2>/dev/null)" || true
        if [ -n "$CONTAINER_GPG_SOCK" ] && [ "$CONTAINER_GPG_SOCK" != "$HOST_GPG_AGENT_SOCK" ]; then
            mkdir -p "$(dirname "$CONTAINER_GPG_SOCK")"
            ln -sf "$HOST_GPG_AGENT_SOCK" "$CONTAINER_GPG_SOCK"
        fi
    fi

    # Run firewall if requested
    if [ "${AGENT_FIREWALL:-0}" = "1" ]; then
        /usr/local/bin/init-firewall.sh
    fi

    # Ensure claude's install location and the user's own .local/bin are in PATH
    export PATH="$HOST_HOME/.local/bin:/opt/claude/.local/bin:$PATH"

    # Drop privileges and exec the command as the host user
    exec gosu "$HOST_USER" "$@"
else
    # No host user info — run as current user (devcontainer CLI path)
    if [ "${AGENT_FIREWALL:-0}" = "1" ]; then
        /usr/local/bin/init-firewall.sh
    fi
    export PATH="$HOME/.local/bin:/opt/claude/.local/bin:$PATH"
    exec "$@"
fi
