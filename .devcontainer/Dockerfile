# SPDX-License-Identifier: MIT
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG NODE_MAJOR=22
ARG CLAUDE_CODE_VERSION=latest
ARG COPILOT_VERSION=latest

# Firewall and utility dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset iproute2 dnsutils aggregate jq \
    zsh fzf man-db unzip gnupg2 \
    apt-transport-https ca-certificates \
    gosu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Node.js (needed at build time for claude-code and copilot npm packages)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# OpenTofu
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://get.opentofu.org/opentofu.gpg | tee /etc/apt/keyrings/opentofu.gpg >/dev/null \
    && curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null \
    && chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg \
    && echo \
        "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" \
        | tee /etc/apt/sources.list.d/opentofu.list >/dev/null \
    && apt-get update && apt-get install -y tofu \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# install GitHub Copilot CLI (global npm packages)
RUN npm install -g @github/copilot@${COPILOT_VERSION}
RUN HOME=/opt/claude curl -fsSL https://claude.ai/install.sh | bash \
    && chmod 777 -R /opt/claude

RUN echo "Updating dotnet..." \
    && curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel LTS --install-dir /usr/share/dotnet

# Copy scripts (build context is project root via devcontainer.json "context": "..")
COPY .devcontainer/init-firewall.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Allow any user to run firewall init and user management via sudo
RUN echo "ALL ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/firewall \
    && echo "ALL ALL=(root) NOPASSWD: /usr/sbin/usermod, /usr/sbin/groupmod, /usr/sbin/useradd, /usr/sbin/groupadd" > /etc/sudoers.d/usermgmt \
    && chmod 0440 /etc/sudoers.d/firewall /etc/sudoers.d/usermgmt

RUN echo 'DEVCONTAINER=true' > /.devcontainer
ENV DEVCONTAINER=true

COPY container-CLAUDE.md /etc/claude-code/CLAUDE.md

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
