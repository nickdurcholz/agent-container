#!/bin/bash
# Installs Claude Code to /opt/claude.
# Adapted from https://claude.ai/install.sh to use a fixed prefix instead of $HOME/.local.
set -e

TARGET="$1"

if [[ -n "$TARGET" ]] && [[ ! "$TARGET" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?)$ ]]; then
    echo "Usage: $0 [stable|latest|VERSION]" >&2
    exit 1
fi

GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
INSTALL_DIR="/opt/claude"
DOWNLOAD_DIR="$INSTALL_DIR/downloads"

download_file() {
    local url="$1" output="$2"
    if [ -n "$output" ]; then
        curl -fsSL -o "$output" "$url"
    else
        curl -fsSL "$url"
    fi
}

get_checksum_from_manifest() {
    local json="$1" platform="$2"
    json=$(echo "$json" | tr -d '\n\r\t' | sed 's/ \+/ /g')
    if [[ $json =~ \"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) echo "Unsupported OS" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$os" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
        platform="linux-${arch}-musl"
    else
        platform="linux-${arch}"
    fi
else
    platform="${os}-${arch}"
fi

mkdir -p "$DOWNLOAD_DIR"

version=$(download_file "$GCS_BUCKET/latest")
manifest_json=$(download_file "$GCS_BUCKET/$version/manifest.json")

if command -v jq >/dev/null 2>&1; then
    checksum=$(echo "$manifest_json" | jq -r ".platforms[\"$platform\"].checksum // empty")
else
    checksum=$(get_checksum_from_manifest "$manifest_json" "$platform")
fi

if [ -z "$checksum" ] || [[ ! "$checksum" =~ ^[a-f0-9]{64}$ ]]; then
    echo "Platform $platform not found in manifest" >&2
    exit 1
fi

binary_path="$DOWNLOAD_DIR/claude-$version-$platform"
if ! download_file "$GCS_BUCKET/$version/$platform/claude" "$binary_path"; then
    echo "Download failed" >&2
    rm -f "$binary_path"
    exit 1
fi

actual=$(sha256sum "$binary_path" | cut -d' ' -f1)
if [ "$actual" != "$checksum" ]; then
    echo "Checksum verification failed" >&2
    rm -f "$binary_path"
    exit 1
fi

chmod +x "$binary_path"

echo "Installing Claude Code to $INSTALL_DIR..."
HOME="$INSTALL_DIR" "$binary_path" install ${TARGET:+"$TARGET"}

# The installer puts the launcher in $INSTALL_DIR/.local/bin/claude — symlink it
# into /usr/local/bin so it's on the default PATH for all users.
ln -sf "$INSTALL_DIR/.local/bin/claude" /usr/local/bin/claude

rm -f "$binary_path"
echo "Claude Code installed to $INSTALL_DIR"
