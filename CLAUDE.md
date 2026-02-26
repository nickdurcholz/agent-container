# agent-container

## What This Project Is

A containerized environment for running AI coding agents (Claude Code, GitHub Copilot CLI) with full autonomous permissions safely. The container provides process and network isolation while selectively mounting only the host directories the agent needs (credentials, source code), reducing the risk of sensitive data exfiltration compared to a full home directory mount.

The primary use case: `cd ~/src/repo && ./agent claude` runs Claude Code with `--dangerously-skip-permissions` inside an ephemeral Docker container instead of on the bare host.

## How It Works

The image is built using the **devcontainer CLI** (`@devcontainers/cli`), which processes `.devcontainer/devcontainer.json` and its referenced Dockerfile + features into a single Docker image. The features (Go, .NET, gh, AWS CLI, uv) are baked into the image at build time. The `agent` wrapper script then uses plain `docker run` to manage container instances.

**Ephemeral mode (default):**
1. `agent build` → `devcontainer build --image-name agent-container:latest` → Docker image
2. `agent claude` / `agent exec` / `agent copilot` → `docker run --rm` with a random-suffix container name, selective bind mounts, SSH/GPG sockets, host user env vars, and the requested command
3. `entrypoint.sh` runs as root: remaps the `vscode` user's UID/GID to match the host, creates home dir + `/work`, sets up GPG socket forwarding, then `exec gosu vscode <command>`
4. Container is automatically removed when the command exits

**Persistent mode (with `-n <name>` or `AGENT_CONTAINER_NAME`):**
1. `agent -n foo start` → `docker run -d` long-running sidecar
2. `agent -n foo claude` → `docker exec` into the running container
3. `agent -n foo stop` → stops and removes the container

## Key Architecture Decisions

- **Node.js is installed in the Dockerfile**, not via a devcontainer feature, because `@github/copilot` is an npm global package that must be installed at image build time (features run after the Dockerfile but the npm install needs Node.js present in the Dockerfile layer).
- **Claude Code is installed via a local copy of the bootstrap script** (`.devcontainer/install-claude.sh`, adapted from `https://claude.ai/install.sh`) that installs to `/opt/claude` instead of `$HOME/.local`. The launcher is symlinked into `/usr/local/bin/claude` so it's on PATH for all users without needing `~/.local/bin` mounts.
- **uv is installed via a local copy of the bootstrap script** (`.devcontainer/install-uv.sh`, adapted from `https://astral.sh/uv/install.sh`) that installs to `/opt/uv` instead of `$HOME/.local`. Symlinks for `uv` and `uvx` are created in `/usr/local/bin` so they're on PATH for all users. Python toolchains are installed to `/opt/uv/python`.
- **`$HOME/.local/bin` is added to PATH via `/etc/profile.d/agent-local-bin.sh` and `/etc/zsh/zshenv`** rather than via `export PATH` in the entrypoint, because `gosu` + shell rc files can reset inherited environment variables. The profile.d script handles bash login shells; the zshenv addition handles all zsh invocations.
- **Go, .NET, gh, AWS CLI are installed via devcontainer features** in `devcontainer.json` or Dockerfile scripts because they have well-maintained official features/installers and don't need to be available during earlier Dockerfile steps.
- **The build context is `..` (project root)**, not `.devcontainer/`. This is set in `devcontainer.json` `"build.context": ".."`. COPY paths in the Dockerfile are relative to the project root (e.g., `COPY entrypoint.sh`).
- **Selective directory mounts at the same absolute paths** — only specific directories and files (`~/.claude`, `~/.claude.json`, `~/.gitconfig`, `~/.aws`, `~/.config/gh`, `~/.config/git`, `~/.config/NuGet`, `~/.ssh`, `~/src`) are mounted rather than the entire home directory. Each is mounted at the same absolute path so file paths work identically between host and container. The workdir is auto-mounted if not already covered. Mounts are configurable via `--mount`/`--mounts` flags and `AGENT_MOUNTS`/`AGENT_EXTRA_MOUNTS` env vars.
- **SSH and GPG agent sockets are auto-forwarded** when detected on the host. `$SSH_AUTH_SOCK` is bind-mounted and passed through. For GPG, the agent socket (from `gpgconf --list-dirs agent-socket`) is mounted along with `~/.gnupg` (for the public keyring), and the entrypoint handles socket path mapping if the container's gpg expects a different path.
- **Docker socket is auto-forwarded** when `/var/run/docker.sock` exists on the host (Docker-outside-of-Docker). The Docker CLI is installed in the image via the `docker-outside-of-docker` devcontainer feature, and the entrypoint adds the container user to the group owning the socket. This gives agents the ability to build/run containers using the host's Docker daemon. Note: this means agents can interact with *all* containers on the host.
- **The base image** (`mcr.microsoft.com/devcontainers/base:ubuntu-24.04`) ships with a `vscode` user at UID 1000. The entrypoint remaps this user's UID/GID to match the host but keeps the `vscode` username so VS Code remote sessions continue to work.
## Commands

```bash
./agent build                        # Build image (requires: npm install -g @devcontainers/cli)
./agent claude [args...]             # Run claude in an ephemeral container
./agent exec [cmd...]                # Run command in an ephemeral container (default: bash)
./agent copilot [args...]            # Run GitHub Copilot CLI in an ephemeral container
./agent -n foo start [workdir]       # Start a persistent sidecar container
./agent -n foo claude [args...]      # Exec into a persistent container
./agent -n foo stop                  # Stop and remove a persistent container
./agent list                         # List containers (filtered by label agent-container=true)
```

Without `-n`/`--name`, `exec`/`claude`/`copilot` launch ephemeral containers named `agent-<dir>-<random>` that auto-remove on exit. With an explicit name, they `docker exec` into an existing persistent container. Containers are labeled `agent-container=true`.

## File Map

| File | What it does |
|------|-------------|
| `agent` | Wrapper script — the main user interface. Handles build/start/exec/stop/list/claude/copilot. |
| `entrypoint.sh` | Runs at container start as root. Remaps the `vscode` user's UID/GID to match the host, sets up sudoers, sets up GPG socket forwarding, then `gosu` drops to `vscode`. |
| `.devcontainer/Dockerfile` | Image definition. Installs Node.js (nodesource), Copilot CLI (npm), Claude Code (via install-claude.sh), OpenTofu (apt), and copies scripts. |
| `.devcontainer/install-claude.sh` | Installs Claude Code to `/opt/claude` with checksum verification. Adapted from the official `https://claude.ai/install.sh` bootstrap script. |
| `.devcontainer/install-uv.sh` | Installs uv to `/opt/uv` with symlinks in `/usr/local/bin`. Adapted from the official `https://astral.sh/uv/install.sh` bootstrap script. |
| `.devcontainer/devcontainer.json` | Declares features (Go, .NET, gh, AWS CLI, uv) and build args. |
| `plans/01-initial-project.md` | Design document from the initial planning session. |

## Installed Tools (in the built image)

Node.js 20, Go, .NET SDK, uv, git, gh (GitHub CLI), AWS CLI, OpenTofu, Docker CLI, Claude Code (`claude`), GitHub Copilot CLI (`copilot`), zsh, fzf, jq, gosu

## Environment Variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `HOST_UID` | entrypoint.sh | Host user ID (set by `agent start`) |
| `HOST_GID` | entrypoint.sh | Host group ID (set by `agent start`) |
| `HOST_HOME` | entrypoint.sh | Host home directory path (set by `agent start`) |
| `AGENT_CONTAINER_NAME` | agent script | Override container name (alternative to `-n`/`--name` flag) |
| `AGENT_MOUNTS` | agent script | Override default mount list (colon-separated absolute paths) |
| `AGENT_EXTRA_MOUNTS` | agent script | Append to default mounts (colon-separated absolute paths) |
| `HOST_GPG_AGENT_SOCK` | entrypoint.sh | Host GPG agent socket path (set automatically by `agent start`) |
| `ANTHROPIC_API_KEY` | claude | Passed through if set on host |

## Known Gotchas

- The **VS Code devcontainer shim** (`~/.local/bin/devcontainer`) can shadow the standalone `@devcontainers/cli`. The `agent build` command has a `find_devcontainer_cli()` function that prefers the npm-installed standalone version by checking `$(npm root -g)/../bin/devcontainer` first.
- **`~/.gitconfig` is mounted by default** so git identity and signing config are available in the container.
- **`docker exec` without `-u`** runs as root, not the container user. In persistent mode, the `agent exec/claude/copilot` commands always pass `-u $(id -u):$(id -g)`. In ephemeral mode, the entrypoint remaps the `vscode` user's UID/GID and drops privileges via `gosu`.
- **Multiple containers share the same mounted directories** read-write. Agents in different containers can potentially conflict if they modify the same files in mounted directories (e.g. `~/.claude`, `~/src`).
- **GPG agent forwarding** depends on the host's `gpgconf --list-dirs agent-socket` returning a valid socket. If the container's gpg resolves to a different socket path, the entrypoint creates a symlink, but unusual gpg configurations may require manual intervention.
