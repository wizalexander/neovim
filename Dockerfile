# ------------------------------
# Base image
# ------------------------------
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------
# Versions (pin everything)
# ------------------------------
ENV NEOVIM_VERSION=0.11.5
ENV NODE_VERSION=18.19.0
ENV LUA_LS_VERSION=3.7.4
ENV TREE_SITTER_CLI_VERSION=0.25.0
ENV OXKER_VERSION=0.12.0

# ------------------------------
# Core system dependencies
# ------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    unzip \
    xz-utils \
    locales \
    pkg-config \
    ripgrep \
    fd-find \
    fontconfig \
    fzf \
    iputils-ping \
    lua5.4 \
    luarocks \
    openssh-client \
    xclip \
    python3 \
    python3-pip \
    python3-venv \
    tmux \
    tree \
    vifm \
    clang \
    apt-transport-https ca-certificates gnupg lsb-release sudo \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------
# Install Docker CLI
# ------------------------------
RUN curl -fsSL https://get.docker.com | sh -s -- --version 28.0.0

# fd is installed as fdfind on Ubuntu
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

# ------------------------------
# Generate UTF-8 locale
# ------------------------------
RUN locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ------------------------------
# Node.js (pinned)
# ------------------------------
RUN curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    | tar -xJ -C /usr/local --strip-components=1

# ------------------------------
# NeoVim (official, pinned)
# ------------------------------
RUN curl -LO https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz \
    && tar -xzf nvim-linux-x86_64.tar.gz -C /opt \
    && ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim \
    && rm nvim-linux-x86_64.tar.gz

# ------------------------------
# oxker (user-local installation per documentation)
# ------------------------------
RUN curl -LO https://github.com/mrjackwills/oxker/releases/download/v${OXKER_VERSION}/oxker_linux_x86_64.tar.gz \
    && mkdir -p /home/dev/.local/bin \
    && tar xzvf oxker_linux_x86_64.tar.gz oxker \
    && install -Dm 755 oxker -t /home/dev/.local/bin \
    && rm oxker_linux_x86_64.tar.gz oxker

# ------------------------------
# Lua Language Server (binary)
# ------------------------------
RUN curl -LO https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-linux-x64.tar.gz \
    && mkdir -p /opt/lua-language-server \
    && tar -xzf lua-language-server-${LUA_LS_VERSION}-linux-x64.tar.gz -C /opt/lua-language-server \
    && ln -s /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server \
    && rm lua-language-server-${LUA_LS_VERSION}-linux-x64.tar.gz

# ------------------------------
# Non-root user
# ------------------------------
# Delete if it exists (optional, careful)
RUN userdel -r ubuntu || true

# Recreate 'dev' with UID/GID 1000 and add to docker group
RUN groupadd -f -g 1000 dev && \
    useradd -m -u 1000 -g 1000 -s /bin/bash dev && \
    groupadd docker 2>/dev/null || true && \
    usermod -aG docker dev

USER dev
WORKDIR /home/dev

# Configure sudoers for dev user (as root)
USER root
RUN echo 'dev ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/dev
USER dev

# Create Docker helper script (as root)
USER root
RUN echo '#!/bin/bash\n/usr/bin/docker "$@"' > /usr/local/bin/docker && \
    chmod +x /usr/local/bin/docker

# Add local bin and npm global paths for dev user
ENV PATH=/home/dev/.local/bin:/home/dev/.npm-global/bin:$PATH
RUN mkdir -p /home/dev/.npm-global && \
    chown -R dev:dev /home/dev/.npm-global && \
    (mkdir -p /home/dev/.npm && chown -R dev:dev /home/dev/.npm || true)

# ------------------------------
# Node-based LSPs & Neovim provider
# ------------------------------
USER root
RUN rm -rf /home/dev/.npm && \
    mkdir -p /home/dev/.npm && \
    chown -R dev:dev /home/dev/.npm && \
    npm config set prefix /home/dev/.npm-global && \
    npm install -g \
    bash-language-server@5.4.3 \
    vscode-langservers-extracted@4.8.0 \
    yaml-language-server@1.14.0 \
    typescript@5.3.3 typescript-language-server@4.3.3 \
    neovim@5.4.0 \
    tree-sitter-cli@${TREE_SITTER_CLI_VERSION} && \
    chown -R dev:dev /home/dev/.npm-global

USER root

# ------------------------------
# Python provider & Pyright
# ------------------------------

RUN python3 -m pip install --no-cache-dir --break-system-packages \
    pyright==1.1.348 \
    pynvim==0.6.0

RUN mkdir -p /usr/share/fonts/truetype/nerd-fonts && \
    curl -Lo /tmp/FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/FiraCode.zip && \
    unzip /tmp/FiraCode.zip -d /usr/share/fonts/truetype/nerd-fonts && \
    fc-cache -fv && \
    rm /tmp/FiraCode.zip

# ------------------------------
# Dotfiles (optional)
# ------------------------------
ARG DOTFILES_GIT_URL
ENV DOTFILES_GIT_URL=${DOTFILES_GIT_URL}

RUN if [ -n "$DOTFILES_GIT_URL" ]; then \
      git clone "$DOTFILES_GIT_URL" /home/dev/dotfiles && \
      cp -r /home/dev/dotfiles/.[!.]* /home/dev/ || true && \
      cp -r /home/dev/dotfiles/* /home/dev/ || true && \
      chown -R dev:dev /home/dev ; \
    fi

RUN git clone https://github.com/asdf-vm/asdf.git /home/dev/.asdf --branch v0.15.0 && \
    chown -R dev:dev /home/dev/.asdf

# ------------------------------
# Docker socket permission fix
# ------------------------------
RUN chmod 666 /var/run/docker.sock 2>/dev/null || true

# ------------------------------
# Entrypoint script for Docker socket permissions
# ------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER dev

# ------------------------------
# Install AWS CLI V2
# ------------------------------
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
  && unzip awscliv2.zip \
  && sudo ./aws/install \
  && rm -rf aws awscliv2.zip

# ------------------------------
# Install OpenCode CLI
# ------------------------------
RUN curl -fsSL https://opencode.ai/install | bash

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# ------------------------------
# Start NeoVim by default
# ------------------------------
CMD ["nvim"]
