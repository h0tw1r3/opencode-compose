FROM node:24.13.1-bookworm

FROM scratch AS node
COPY --from=0 / /

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,rw --mount=type=cache,target=/var/lib/apt,rw <<EOD
echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0"; Acquire::Retries "5"; Dpkg::Use-Pty "0"; Dpkg::Progress-Fancy="0";' > /etc/apt/apt.conf.d/99container
apt-get update -y
apt-get upgrade -qy
apt-get install -qy ca-certificates

# supporting software (for agents, and cli not required for opencode serve to run)
## general
apt-get install -qy \
  fd-find \
  jq \
  less \
  ripgrep \
  vim-tiny \
  tmux

ln -s "$(command -v fdfind)" /usr/local/bin/fd

## python
apt-get install -qy \
  pipx

cat >>/etc/profile.d/opencode.sh <<"EOF"
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
EOF
EOD

FROM node AS init-suid
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=bind,source=entrypoint.sh,target=/entrypoint.sh \
    apt-get update -qy ; \
    apt-get -qy install shc build-essential ; \
    shc -S -r -f /entrypoint.sh -o /init ; \
    chmod 755 /init && chmod ug+s /init

FROM node AS final
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

RUN --mount=type=cache,target=/root/.npm <<EOD
npm i -g opencode-ai
npm i -g firecrawl-cli
npm i -g btca
echo "Installed opencode version: $(opencode --version)"
echo "Installed firecrawl version: $(firecrawl --version)"
echo "Installed btca version: $(btca --version)"
EOD

USER node

RUN <<EOD
mkdir -p /home/node/.local/share/opencode
mkdir -p /home/node/.local/state/opencode
mkdir -p /home/node/.config/opencode

cat > /home/node/.config/opencode/config.json <<"EOL"
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "github:firecrawl/opencode-firecrawl#a5a7939005ad67b0a7a03f495aa224f6e9d2bb20@a5a7939005ad67b0a7a03f495aa224f6e9d2bb20",
    "micode"
  ],
  "permission": {
    "external_directory": {
      "${env:WORKDIR}/**": "allow",
      "/tmp/**": "allow",
      "/var/tmp/**": "allow"
    }
  },
  "server": {
    "hostname": "0.0.0.0"
  },
  "watcher": {
    "ignore": ["node_modules/**", "dist/**", ".git/**", ".venv/**"]
  }
}
EOL
EOD

USER root
COPY --from=init-suid /init /init

# healthcheck
COPY --from=ghcr.io/tarampampam/microcheck:1.3.0 /bin/httpcheck /bin/httpcheck
HEALTHCHECK --start-period=30s --start-interval=1s --interval=1m --timeout=10s \
  CMD ["/bin/httpcheck", "http://localhost:3000/global/health"]

USER node
WORKDIR /must-be-set-at-runtime

EXPOSE 4096

ENTRYPOINT ["/init"]
CMD ["serve", "--print-logs"]
