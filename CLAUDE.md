# agent-container

## What This Project Is

A containerized environment for running AI coding agents (Claude Code, GitHub Copilot CLI) with full autonomous permissions safely. The container provides process and network isolation while mounting the host home directory so it feels like the host workstation — all credentials, SSH keys, git config, and user-installed tools are available without enumeration.

The primary use case: `./agent start foo ~/src/repo && ./agent claude foo` runs Claude Code with `--dangerously-skip-permissions` inside a Docker container instead of on the bare host.

## How It Works

The image is built using the **devcontainer CLI** (`@devcontainers/cli`), which processes `.devcontainer/devcontainer.json` and its referenced Dockerfile + features into a single Docker image. The features (Go, .NET, gh, AWS CLI, uv) are baked into the image at build time. The `agent` wrapper script then uses plain `docker run` to manage container instances.

**Container lifecycle:**
1. `agent build` → `devcontainer build --image-name agent-container:latest` → Docker image
2. `agent start <name>` → `docker run -d` with home dir bind mount + host user env vars
3. `entrypoint.sh` runs as root: creates/remaps container user to match host UID/GID, optionally enables firewall, then `exec gosu <user> sleep infinity`
4. `agent exec/claude/copilot <name>` → `docker exec -u <uid>:<gid>` into the running container

## Key Architecture Decisions

- **Node.js is installed in the Dockerfile**, not via a devcontainer feature, because `@anthropic-ai/claude-code` and `@github/copilot` are npm global packages that must be installed at image build time (features run after the Dockerfile but the npm install needs Node.js present in the Dockerfile layer).
- **Go, .NET, uv, gh, AWS CLI are installed via devcontainer features** in `devcontainer.json` because they have well-maintained official features and don't need to be available during earlier Dockerfile steps.
- **The build context is `..` (project root)**, not `.devcontainer/`. This is set in `devcontainer.json` `"build.context": ".."`. COPY paths in the Dockerfile are relative to the project root (e.g., `COPY entrypoint.sh`, `COPY .devcontainer/init-firewall.sh`).
- **Home dir is mounted at the same absolute path** (`$HOME:$HOME`), so all file paths work identically between host and container.
- **The base image** (`mcr.microsoft.com/devcontainers/base:ubuntu-24.04`) ships with a `vscode` user at UID 1000. The entrypoint handles this by renaming that user to match the host user when UIDs collide.
- **Network firewall is opt-in** (`AGENT_FIREWALL=1`) because agents frequently need to install packages from arbitrary registries, and debugging firewall issues is painful.

## Commands

```bash
./agent build                        # Build image (requires: npm install -g @devcontainers/cli)
./agent start [name] [workdir]       # Start container (workdir defaults to $PWD)
./agent exec [name] [cmd...]         # Run command (default: bash)
./agent claude [name] [args...]      # Run claude --dangerously-skip-permissions
./agent copilot [name] [args...]     # Run GitHub Copilot CLI
./agent stop [name]                  # Stop and remove container
./agent list                         # List containers (filtered by label agent-container=true)
```

Container name can be provided via `-n`/`--name` flag, `AGENT_CONTAINER_NAME` env var, or as the first positional argument to subcommands. Containers are named `agent-<name>` and labeled `agent-container=true`.

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
| `AGENT_CONTAINER_NAME` | agent script | Default container name (alternative to `-n`/`--name` flag) |
| `AGENT_FIREWALL` | entrypoint.sh, init-firewall.sh | Set to `1` to enable network firewall |
| `ANTHROPIC_API_KEY` | claude | Passed through if set on host |

## Known Gotchas

- The **VS Code devcontainer shim** (`~/.local/bin/devcontainer`) can shadow the standalone `@devcontainers/cli`. The `agent build` command has a `find_devcontainer_cli()` function that prefers the npm-installed standalone version by checking `$(npm root -g)/../bin/devcontainer` first.
- **GPG commit signing won't work** inside containers — the host's GPG agent socket isn't forwarded. If the host `.gitconfig` has `commit.gpgsign = true`, commits inside the container will fail unless overridden with `git config --global commit.gpgsign false`.
- **`docker exec` without `-u`** runs as root, not the host user. The `agent exec/claude/copilot` commands always pass `-u $(id -u):$(id -g)`.
- **Multiple containers share the same home dir** read-write. Agents in different containers can potentially conflict if they modify the same files. This is by design (feels like the host) but worth being aware of.
- The firewall resolves domains to IPs at startup time. If a service's IPs change while the container is running, new IPs won't be allowed until the firewall is re-initialized.
