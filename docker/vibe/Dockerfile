FROM mcr.microsoft.com/playwright:v1.58.0-noble

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    openssh-client \
    podman \
    slirp4netns \
    uidmap \
    fuse-overlayfs \
    python3 \
    tini \
    docker.io \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise bash

RUN npm install -g opencode-ai \
  && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/vibe-entrypoint
RUN chmod +x /usr/local/bin/vibe-entrypoint

ENV OPENCODE_PORT=3000

COPY opencode/ /opt/opencode-config/
RUN mkdir -p /root/.config/opencode /root/.local/share/opencode /workspace \
  && cp -R /opt/opencode-config/. /root/.config/opencode/

WORKDIR /workspace

EXPOSE 3000

ENTRYPOINT ["tini", "--", "/usr/local/bin/vibe-entrypoint"]
