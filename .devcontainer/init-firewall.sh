#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Optional network firewall for agent containers.
# Implements a default-deny iptables policy, whitelisting only specific
# domains required for AI coding agents and package registries.
#
# Adapted from Anthropic's reference:
# https://github.com/anthropics/claude-code/tree/main/.devcontainer
#
# Usage: AGENT_FIREWALL=1 when starting a container, or run directly:
#   sudo /usr/local/bin/init-firewall.sh
#
set -euo pipefail

# --- Allowed domains ---
ALLOWED_DOMAINS=(
    # Claude Code / Anthropic
    api.anthropic.com
    sentry.io
    statsig.anthropic.com
    statsig.com

    # GitHub Copilot
    api.github.com
    api.githubcopilot.com
    copilot-proxy.githubusercontent.com

    # npm registry
    registry.npmjs.org

    # PyPI (uv/pip)
    pypi.org
    files.pythonhosted.org

    # Go modules
    proxy.golang.org
    sum.golang.org
    storage.googleapis.com

    # .NET / NuGet
    api.nuget.org
    dotnetcli.azureedge.net
    dotnet.microsoft.com

    # OpenTofu / Terraform registries
    registry.opentofu.org
    releases.hashicorp.com

    # AWS (for AWS CLI and services)
    sts.amazonaws.com
)

# Patterns for wildcard-style domain matching (resolved via iptables string match is
# not practical, so we resolve these to IPs where feasible or allow broad ranges)
AWS_DOMAIN_SUFFIX="amazonaws.com"

echo "=== Initializing agent container firewall ==="

# Flush existing rules (preserve Docker's DNS rules on the DOCKER chain if present)
iptables -F OUTPUT 2>/dev/null || true
iptables -F INPUT 2>/dev/null || true

# Create ipset for allowed IPs
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net

# Resolve GitHub IP ranges from their meta API
echo "Fetching GitHub IP ranges..."
GITHUB_META=$(curl -sf https://api.github.com/meta 2>/dev/null || echo '{}')
if [ "$GITHUB_META" != '{}' ]; then
    for key in web api git; do
        echo "$GITHUB_META" | jq -r ".${key}[]? // empty" 2>/dev/null | while read -r cidr; do
            ipset add allowed-domains "$cidr" 2>/dev/null || true
        done
    done
    echo "  Added GitHub IP ranges"
fi

# Resolve allowed domains to IPs
echo "Resolving allowed domains..."
for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
    for ip in $ips; do
        ipset add allowed-domains "${ip}/32" 2>/dev/null || true
    done
done
echo "  Resolved ${#ALLOWED_DOMAINS[@]} domains"

# Resolve AWS IP ranges (broad — allows all AWS service endpoints)
echo "Fetching AWS IP ranges..."
AWS_RANGES=$(curl -sf https://ip-ranges.amazonaws.com/ip-ranges.json 2>/dev/null || echo '{}')
if [ "$AWS_RANGES" != '{}' ]; then
    # Add a subset of common AWS service prefixes to avoid huge ipset
    echo "$AWS_RANGES" | jq -r '.prefixes[] | select(.service == "GLOBALACCELERATOR" or .service == "AMAZON" or .service == "S3") | .ip_prefix' 2>/dev/null \
        | head -500 | while read -r cidr; do
        ipset add allowed-domains "$cidr" 2>/dev/null || true
    done
    echo "  Added AWS IP ranges (subset)"
fi

# Detect host/Docker network
HOST_NET=$(ip route | grep default | awk '{print $3}' | head -1)
HOST_SUBNET=$(ip route | grep -v default | grep "$(ip route | grep default | awk '{print $5}')" | awk '{print $1}' | head -1)

echo "  Host network: ${HOST_SUBNET:-unknown}"

# --- Apply firewall rules ---

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Allow established/related connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (needed for domain resolution)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow SSH (port 22) — needed for git operations
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Allow traffic to host/Docker network (for Docker DNS, host services, etc.)
if [ -n "$HOST_SUBNET" ]; then
    iptables -A OUTPUT -d "$HOST_SUBNET" -j ACCEPT
    iptables -A INPUT -s "$HOST_SUBNET" -j ACCEPT
fi

# Allow traffic to IPs in the allowed-domains ipset
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default deny
iptables -P OUTPUT DROP
iptables -P INPUT DROP
# Don't touch FORWARD — Docker manages that

echo ""
echo "=== Firewall active ==="
echo "Verifying..."

# Quick validation
if curl -sf --max-time 5 https://example.com >/dev/null 2>&1; then
    echo "  WARNING: example.com is reachable (should be blocked)"
else
    echo "  OK: example.com is blocked"
fi

if curl -sf --max-time 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "  OK: api.github.com is reachable"
else
    echo "  WARNING: api.github.com is unreachable (should be allowed)"
fi

echo "=== Firewall setup complete ==="
