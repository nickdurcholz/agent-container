echo "Installing golang..."
GO_PKG=$(curl -s 'https://go.dev/dl/?mode=json' \
    | jq -r '[.[] | select(.stable)][0].files[] | select(.os=="linux" and .arch=="amd64").filename' \
    | head -n1 \
    | sed -E 's/.linux-amd64.tar.gz$//')

curl -L -o /tmp/$GO_PKG.linux-amd64.tar.gz https://go.dev/dl/${GO_PKG}.linux-amd64.tar.gz
mkdir -p /opt/go/$GO_PKG
cd /opt/go/$GO_PKG
tar -xzf /tmp/$GO_PKG.linux-amd64.tar.gz --strip-components=1
ls ./bin | xargs -I{} ln -fs /opt/go/$GO_PKG/bin/{} /usr/local/bin/{}
    