# agent-container

## What This Project Is

A containerized environment for running AI coding agents (Claude Code, GitHub Copilot CLI) with full autonomous permissions safely. The container provides process and network isolation while selectively mounting only the host directories the agent needs (credentials, source code), reducing the risk of sensitive data exfiltration compared to a full home directory mount.

The primary use case: `cd ~/src/repo && ./agent claude` runs Claude Code with `--dangerously-skip-permissions` inside an ephemeral Docker container instead of on the bare host.

## How It Works

The image is built using the **devcontainer CLI** (`@devcontainers/cli`), which processes `.devcontainer/devcontainer.json` and its referenced Dockerfile + features into a single Docker image. The features (Go, .NET, gh, AWS CLI, uv) are baked into the image at build time. The `agent` wrapper script then uses plain `docker run` to manage container instances.

**Ephemeral mode (default):**
1. `agent build` → `devcontainer build --image-name agent-container:latest` → Docker image
2. `agent claude` / `agent exec` / `agent copilot` → `docker run --rm` with a random-suffix container name, selective bind mounts, SSH/GPG sockets, host user env vars, and the requested command
3. `entrypoint.sh` runs as root: creates/remaps container user to match host UID/GID, creates home dir + `/work`, sets up GPG socket forwarding, optionally enables firewall, then `exec gosu <user> <command>`
4. Container is automatically removed when the command exits

**Persistent mode (with `-n <name>` or `AGENT_CONTAINER_NAME`):**
1. `agent -n foo start` → `docker run -d` long-running sidecar
2. `agent -n foo claude` → `docker exec` into the running container
3. `agent -n foo stop` → stops and removes the container

## Key Architecture Decisions

- **Node.js is installed in the Dockerfile**, not via a devcontainer feature, because `@anthropic-ai/claude-code` and `@github/copilot` are npm global packages that must be installed at image build time (features run after the Dockerfile but the npm install needs Node.js present in the Dockerfile layer).
- **Go, .NET, uv, gh, AWS CLI are installed via devcontainer features** in `devcontainer.json` because they have well-maintained official features and don't need to be available during earlier Dockerfile steps.
- **The build context is `..` (project root)**, not `.devcontainer/`. This is set in `devcontainer.json` `"build.context": ".."`. COPY paths in the Dockerfile are relative to the project root (e.g., `COPY entrypoint.sh`, `COPY .devcontainer/init-firewall.sh`).
- **Selective directory mounts at the same absolute paths** — only specific directories and files (`~/.claude`, `~/.claude.json`, `~/.gitconfig`, `~/.aws`, `~/.config/gh`, `~/.config/git`, `~/.config/NuGet`, `~/.ssh`, `~/src`) are mounted rather than the entire home directory. Each is mounted at the same absolute path so file paths work identically between host and container. The workdir is auto-mounted if not already covered. Mounts are configurable via `--mount`/`--mounts` flags and `AGENT_MOUNTS`/`AGENT_EXTRA_MOUNTS` env vars.
- **SSH and GPG agent sockets are auto-forwarded** when detected on the host. `$SSH_AUTH_SOCK` is bind-mounted and passed through. For GPG, the agent socket (from `gpgconf --list-dirs agent-socket`) is mounted along with `~/.gnupg` (for the public keyring), and the entrypoint handles socket path mapping if the container's gpg expects a different path.
- **The base image** (`mcr.microsoft.com/devcontainers/base:ubuntu-24.04`) ships with a `vscode` user at UID 1000. The entrypoint handles this by renaming that user to match the host user when UIDs collide.
- **Network firewall is opt-in** (`AGENT_FIREWALL=1`) because agents frequently need to install packages from arbitrary registries, and debugging firewall issues is painful.

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
| `entrypoint.sh` | Runs at container start as root. Creates a user matching the host (UID/GID/username/home), sets up sudoers, optionally runs firewall, then `gosu` drops to that user. |
| `.devcontainer/Dockerfile` | Image definition. Installs Node.js 20 (nodesource), Claude Code + Copilot CLI (npm), OpenTofu (apt), firewall deps (iptables/ipset/etc), and copies scripts. |
| `.devcontainer/devcontainer.json` | Declares features (Go, .NET, gh, AWS CLI, uv), build args, capabilities (NET_ADMIN/NET_RAW for firewall). |
| `.devcontainer/init-firewall.sh` | Opt-in iptables firewall. Default-deny with whitelisted domains (Anthropic API, GitHub, npm, PyPI, Go proxy, NuGet, AWS, OpenTofu). Adapted from Anthropic's reference devcontainer. |
| `plans/01-initial-project.md` | Design document from the initial planning session. |

## Installed Tools (in the built image)

Node.js 20, Go, .NET SDK, uv, git, gh (GitHub CLI), AWS CLI, OpenTofu, Claude Code (`claude`), GitHub Copilot CLI (`copilot`), zsh, fzf, jq, gosu

## Environment Variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `HOST_USER` | entrypoint.sh | Host username (set by `agent start`) |
| `HOST_UID` | entrypoint.sh | Host user ID (set by `agent start`) |
| `HOST_GID` | entrypoint.sh | Host group ID (set by `agent start`) |
| `HOST_HOME` | entrypoint.sh | Host home directory path (set by `agent start`) |
| `AGENT_CONTAINER_NAME` | agent script | Override container name (alternative to `-n`/`--name` flag) |
| `AGENT_FIREWALL` | entrypoint.sh, init-firewall.sh | Set to `1` to enable network firewall |
| `AGENT_MOUNTS` | agent script | Override default mount list (colon-separated absolute paths) |
| `AGENT_EXTRA_MOUNTS` | agent script | Append to default mounts (colon-separated absolute paths) |
| `HOST_GPG_AGENT_SOCK` | entrypoint.sh | Host GPG agent socket path (set automatically by `agent start`) |
| `ANTHROPIC_API_KEY` | claude | Passed through if set on host |

## Known Gotchas

- The **VS Code devcontainer shim** (`~/.local/bin/devcontainer`) can shadow the standalone `@devcontainers/cli`. The `agent build` command has a `find_devcontainer_cli()` function that prefers the npm-installed standalone version by checking `$(npm root -g)/../bin/devcontainer` first.
- **`~/.gitconfig` is mounted by default** so git identity and signing config are available in the container.
- **`docker exec` without `-u`** runs as root, not the host user. In persistent mode, the `agent exec/claude/copilot` commands always pass `-u $(id -u):$(id -g)`. In ephemeral mode, the entrypoint handles user creation and privilege dropping via `gosu`.
- **Multiple containers share the same mounted directories** read-write. Agents in different containers can potentially conflict if they modify the same files in mounted directories (e.g. `~/.claude`, `~/src`).
- The firewall resolves domains to IPs at startup time. If a service's IPs change while the container is running, new IPs won't be allowed until the firewall is re-initialized.
- **GPG agent forwarding** depends on the host's `gpgconf --list-dirs agent-socket` returning a valid socket. If the container's gpg resolves to a different socket path, the entrypoint creates a symlink, but unusual gpg configurations may require manual intervention.
