################################################################################
# QwenCode Dockerfile — Full Developer Environment (qwen serve)
# ubuntu:24.04 base with bash, git, gh CLI, gcloud, firebase, Node.js 24 LTS
################################################################################

ARG QWEN_VERSION

################################################################################
# Final stage — Full developer environment
################################################################################

FROM --platform=linux/arm64 ubuntu:24.04

ARG QWEN_VERSION

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

# Install Qwen Code CLI (qwen serve ships in this package)
RUN npm install -g @qwen-code/qwen-code@${QWEN_VERSION}

# Install optional CLIs: GitLab glab, Neon neonctl, Expo eas-cli (ARM64)
RUN curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v1.114.0/downloads/glab_1.114.0_linux_arm64.tar.gz" -o /tmp/glab.tar.gz \
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

# Create non-root user with home directory and bash shell
RUN useradd -m -s /bin/bash qwen && \
    mkdir -p /home/qwen/.qwen && \
    chown -R qwen:qwen /home/qwen

# Base settings: model providers via env keys (credentials are never baked
# into the image; the runtime reads process.env[envKey]). Seeded into the
# state volume by the qwen-config initContainer on first boot.
COPY scripts/qwen-settings.json /usr/local/share/qwen-settings.json

# Global agent context: browser automation + cost discipline.
RUN printf '%s\n' \
    '## Browser automation (headless Chromium)' \
    '' \
    'A cluster-hosted headless Chromium is available at http://localhost:9222' \
    '(CDP; env QWEN_BROWSER_CDP). Connect with a CDP client (playwright):' \
    '' \
    '```js' \
    'const { chromium } = require("playwright");' \
    'const browser = await chromium.connectOverCDP("http://localhost:9222");' \
    '```' \
    '' \
    'Never install chromium binaries or apt packages for browser work — they do' \
    'not persist and lack system libs in this container.' \
    '' \
    '## Cost discipline' \
    '' \
    'Keep runs terse, stop early when blocked, at most one retry on provider' \
    'errors; never change model configuration yourself.' \
    > /usr/local/share/qwen-QWEN.md

USER qwen
WORKDIR /home/qwen

EXPOSE 4170

ENTRYPOINT ["qwen"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "4170"]
