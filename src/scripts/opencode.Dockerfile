################################################################################
# OpenCode Dockerfile — Full Developer Environment
# python:3.12-slim base with bash, git, gh CLI, gcloud, firebase, Node.js 24 LTS
################################################################################

ARG OPENCODE_VERSION

################################################################################
# Builder stage — download opencode binary
################################################################################

FROM --platform=linux/arm64 python:3.12.13-slim AS builder

ARG OPENCODE_VERSION
ENV OPENCODE_VERSION="${OPENCODE_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-arm64.tar.gz" \
    -o /tmp/opencode.tar.gz \
    && mkdir -p /opt/opencode \
    && tar -xzf /tmp/opencode.tar.gz -C /opt/opencode \
    && chmod +x /opt/opencode/opencode

################################################################################
# Final stage — Full developer environment
################################################################################

FROM --platform=linux/arm64 ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    bash \
    openssh-client \
    wget \
    vim \
    nano \
    unzip \
    zip \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 24 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Upgrade npm and install pnpm latest
RUN npm install -g npm@latest pnpm@latest

# Install optional CLIs: GitLab glab, Neon neonctl, Expo eas-cli (ARM64)
RUN curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/latest/download/glab_linux_arm64.tar.gz" -o /tmp/glab.tar.gz \
    && tar -xzf /tmp/glab.tar.gz -C /tmp \
    && mv /tmp/bin/glab /usr/local/bin/glab \
    && rm -rf /tmp/bin /tmp/glab.tar.gz
RUN npm install -g neonctl eas-cli

# Install GitHub CLI (gh) for ARM64
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK (gcloud) for ARM64
RUN curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz \
    -o /tmp/google-cloud-sdk.tar.gz \
    && tar -xzf /tmp/google-cloud-sdk.tar.gz -C /opt \
    && /opt/google-cloud-sdk/install.sh --quiet --path-update=true --command-completion=false --usage-reporting=false \
    && rm -f /tmp/google-cloud-sdk.tar.gz

ENV PATH="/opt/google-cloud-sdk/bin:${PATH}"

# Install Firebase CLI via npm
RUN npm install -g firebase-tools

# Install global npm packages commonly used
RUN npm install -g typescript ts-node yarn @angular/cli @nestjs/cli

# Install Python packages commonly used
RUN pip3 install --break-system-packages --no-cache-dir \
    requests \
    urllib3 \
    boto3 \
    google-cloud-storage \
    firebase-admin \
    flask \
    fastapi \
    uvicorn \
    httpx \
    pydantic

# Copy opencode binary from builder
COPY --from=builder /opt/opencode/opencode /usr/local/bin/opencode

# Create non-root user with home directory and bash shell
RUN useradd -m -s /bin/bash opencode && \
    mkdir -p /home/opencode/.config && \
    chown -R opencode:opencode /home/opencode

USER opencode
WORKDIR /home/opencode

EXPOSE 4096

ENTRYPOINT ["opencode"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "4096"]
