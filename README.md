# agent-container

A Docker container image for running AI coding agents (Claude Code, GitHub Copilot CLI) safely in isolation, with a thin wrapper script for easy instance management.

The container mounts your home directory so it feels like your host workstation — all credentials, SSH keys, git config, and tools in `~/.local/bin` are automatically available.

## Prerequisites

- Docker
- [devcontainer CLI](https://github.com/devcontainers/cli) (for building the image):
  ```bash
  npm install -g @devcontainers/cli
  ```

## Quick Start

```bash
# Build the image (one-time)
./agent build

# Start a container for a project
./agent start myproject ~/src/my-repo

# Run Claude Code with full permissions
./agent claude myproject

# Or open a shell
./agent exec myproject

# Stop when done
./agent stop myproject
```

## Commands

| Command | Description |
|---------|-------------|
| `agent build` | Build the container image using devcontainer CLI |
| `agent start <name> [workdir]` | Start a named container (workdir defaults to `$PWD`) |
| `agent exec <name> [cmd...]` | Run a command in the container (default: `bash`) |
| `agent stop <name>` | Stop and remove a container |
| `agent list` | List running agent containers |
| `agent claude <name> [args...]` | Run `claude --dangerously-skip-permissions` |
| `agent copilot <name> [args...]` | Run GitHub Copilot CLI |

## Included Tools

- **AI Agents:** Claude Code, GitHub Copilot CLI
- **Languages:** Node.js 20, Go, .NET SDK, Python (via uv)
- **Infrastructure:** AWS CLI, OpenTofu
- **Dev Tools:** git, gh (GitHub CLI), zsh, fzf

## Environment Variables

| Variable | Description |
|----------|-------------|
| `AGENT_CONTAINER_NAME` | Default container name (alternative to `-n`/`--name` flag or positional arg) |
| `ANTHROPIC_API_KEY` | Passed to the container if set |
| `AGENT_FIREWALL=1` | Enable opt-in network firewall (restricts outbound to whitelisted domains only) |

## `.env` File Loading

The `agent` script automatically loads `.env` files from the current directory and all ancestor directories up to `/`. When multiple files are found, they are applied root-first so that values in nearer directories override those further up.

All variables defined in `.env` files are passed through to the container via `docker run`/`docker exec`.

```bash
# ~/src/my-repo/.env
AGENT_CONTAINER_NAME=myrepo
ANTHROPIC_API_KEY=sk-ant-...
MY_CUSTOM_VAR=hello
```

```bash
cd ~/src/my-repo
./agent start        # no name arg needed — picks up AGENT_CONTAINER_NAME from .env
./agent claude       # MY_CUSTOM_VAR is available inside the container
```

## Network Firewall

By default, containers have unrestricted network access. Set `AGENT_FIREWALL=1` to enable a default-deny iptables firewall that only allows traffic to:

- Anthropic API, GitHub, npm registry, PyPI, Go module proxy, NuGet, AWS endpoints, OpenTofu registry

```bash
AGENT_FIREWALL=1 ./agent start secure-task ~/src/my-repo
```

## Multi-Instance

Each `agent start` creates an independent container. All containers share the same home directory mount but have isolated process and network namespaces:

```bash
./agent start frontend ~/src/frontend
./agent start backend ~/src/backend

# In separate terminals:
./agent claude frontend
./agent copilot backend

./agent list
./agent stop frontend
./agent stop backend
```
