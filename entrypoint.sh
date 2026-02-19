#!/bin/bash
# SPDX-License-Identifier: MIT
set -e

CONTAINER_USER="vscode"
HOST_UID="${HOST_UID:-}"
HOST_GID="${HOST_GID:-}"
HOST_HOME="${HOST_HOME:-}"

if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ] && [ -n "$HOST_HOME" ]; then
    # Remap the vscode user's GID/UID to match the host
    if [ "$(id -g "$CONTAINER_USER")" != "$HOST_GID" ]; then
        groupmod -g "$HOST_GID" "$CONTAINER_USER" 2>/dev/null || true
    fi
    if [ "$(id -u "$CONTAINER_USER")" != "$HOST_UID" ]; then
        usermod -u "$HOST_UID" -g "$HOST_GID" "$CONTAINER_USER"
    fi
    usermod -d "$HOST_HOME" "$CONTAINER_USER"

    echo "$CONTAINER_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent-user
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
        usermod -aG "$DOCKER_GROUP" "$CONTAINER_USER"
    fi

    # GPG agent forwarding: if the host socket is mounted at a path that differs
    # from where the container's gpg expects it, create a symlink.
    if [ -n "${HOST_GPG_AGENT_SOCK:-}" ] && [ -S "$HOST_GPG_AGENT_SOCK" ]; then
        CONTAINER_GPG_SOCK="$(gosu "$CONTAINER_USER" gpgconf --list-dirs agent-socket 2>/dev/null)" || true
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

    chown -R "$HOST_UID:$HOST_GID" /opt/claude

    # Drop privileges and exec the command as the vscode user
    exec gosu "$CONTAINER_USER" "$@"
else
    # No host user info — run as current user (devcontainer CLI path)
    if [ "${AGENT_FIREWALL:-0}" = "1" ]; then
        /usr/local/bin/init-firewall.sh
    fi
    export PATH="$HOME/.local/bin:/opt/claude/.local/bin:$PATH"
    exec "$@"
fi
