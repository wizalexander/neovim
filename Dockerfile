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
    fzf \
    lua5.4 \
    luarocks \
    python3 \
    python3-pip \
    python3-venv \
    clang \
    && rm -rf /var/lib/apt/lists/*

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

# Recreate 'dev' with UID/GID 1000
RUN groupadd -f -g 1000 dev && \
    useradd -m -u 1000 -g 1000 -s /bin/bash dev

USER dev
WORKDIR /home/dev

# npm global path for dev user
ENV PATH=/home/dev/.npm-global/bin:$PATH
RUN mkdir -p /home/dev/.npm-global \
    && npm config set prefix /home/dev/.npm-global

# ------------------------------
# Node-based LSPs & Neovim provider
# ------------------------------
RUN npm install -g \
    bash-language-server@5.4.3 \
    vscode-langservers-extracted@4.8.0 \
    yaml-language-server@1.14.0 \
    typescript@5.3.3 typescript-language-server@4.3.3 \
    neovim@5.4.0 \
    tree-sitter-cli@${TREE_SITTER_CLI_VERSION}

# ------------------------------
# Python provider & Pyright
# ------------------------------
USER root

RUN python3 -m pip install --no-cache-dir --break-system-packages \
    pyright==1.1.348 \
    pynvim==0.6.0

USER dev

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

# ------------------------------
# Start NeoVim by default
# ------------------------------
CMD ["nvim"]
