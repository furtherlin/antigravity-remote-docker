# =============================================================================
# Antigravity Remote Docker
# A GPU-accelerated container for running Google Antigravity remotely via noVNC
# =============================================================================

# =============================================================================
# Using vittico's tool to build the deb file
# Reference: https://github.com/vittico/packaged-gravity
# =============================================================================

FROM ubuntu:jammy-20260627 as builder

ARG ANTIGRAVITY_VERSION=2.3.1-5358163105546240
ARG ANTIGRAVITY_IDE_VERSION=2.1.1-6123990880747520
RUN apt-get update && apt-get install -y --no-install-recommends file tar python3 git wget ca-certificates imagemagick

RUN git clone https://github.com/vittico/packaged-gravity.git && \
    cd packaged-gravity && \
#    wget https://storage.googleapis.com/antigravity-public/antigravity-hub/${ANTIGRAVITY_VERSION}/linux-x64/Antigravity.tar.gz && \
    wget https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${ANTIGRAVITY_IDE_VERSION}/linux-x64/Antigravity%20IDE.tar.gz && \
#    sed -s 's/detect_arch\ \"$optdir\/$AG_EXEC\"/AG_ARCH_RPM=x86_64;AG_ARCH_DEB=amd64;AG_ARCH_APPIMAGE=x86_64;/g' -i lib/stage.sh && \
    ./build.sh "Antigravity IDE.tar.gz" --format deb
     #./build.sh "Antigravity.tar.gz"  --format deb


FROM nvidia/cuda:12.3.1-runtime-ubuntu22.04

LABEL maintainer="raphl"
LABEL description="Google Antigravity with noVNC remote access and GPU support"

# =============================================================================
# Environment Configuration
# =============================================================================
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    # Display settings
    DISPLAY=:1 \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    DISPLAY_DEPTH=24 \
    # VNC settings
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    VNC_PASSWORD=antigravity \
    # User settings
    USER=antigravity \
    UID=1000 \
    GID=1000 \
    HOME=/home/antigravity \
    # Antigravity settings
    ANTIGRAVITY_AUTO_UPDATE=true

# =============================================================================
# System Dependencies
# =============================================================================
ARG NOVNC_VERSION=1.7.0
ARG WEBSOCKIFY=0.13.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    ca-certificates \
    curl \
    wget \
    gnupg \
    sudo \
    locales \
    tzdata \
    dbus-x11 \
    # X11 and desktop
    xvfb \
    x11vnc \
    tigervnc-standalone-server \
    tigervnc-common \
    tigervnc-tools \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    # Fonts and theming
    fonts-dejavu \
    fonts-liberation \
    fonts-noto \
    gtk2-engines-pixbuf \
    adwaita-icon-theme \
    # noVNC dependencies
    python3 \
    python3-pip \
    python3-numpy \
    # Audio (optional, for future use)
    pulseaudio \
    # Clipboard support
    xclip \
    xsel \
    # Process management
    supervisor \
    # Auto-updates
    unattended-upgrades \
    apt-transport-https \
    # Utilities
    nano \
    vim \
    git \
    htop \
    procps \
    net-tools \
    # Window management (for auto-maximize)
    wmctrl \
    xdotool \
    libsecret-1-0 \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    fcitx5 \
    fcitx5-chinese-addons \
    fcitx5-chewing \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Install Google Chrome
# =============================================================================
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Locale Configuration
# =============================================================================
RUN locale-gen en_US.UTF-8
RUN locale-gen zh_TW.UTF-8

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# =============================================================================
# Install noVNC and websockify
# =============================================================================
RUN mkdir -p /opt/novnc \
    && curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz | tar -xz -C /opt/novnc --strip-components=1 \
    && mkdir -p /opt/websockify \
    && curl -fsSL https://github.com/novnc/websockify/archive/refs/tags/v${WEBSOCKIFY}.tar.gz | tar -xz -C /opt/websockify --strip-components=1 \
    && ln -sf /opt/websockify /opt/novnc/utils/websockify

# Create custom index.html that forces English language and auto-connects
RUN echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=vnc.html?autoconnect=true&resize=remote&lang=en"></head><body>Redirecting...</body></html>' > /opt/novnc/index.html

# =============================================================================
# Install Antigravity
# =============================================================================
COPY --from=builder /packaged-gravity/dist/antigravity*.deb /opt/antigravity.deb

RUN dpkg -i /opt/antigravity.deb && \
    apt-get update && \
    apt-get install -f && \
    rm /opt/antigravity.deb && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Create Non-Root User
# =============================================================================
RUN groupadd -g ${GID} ${USER} \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER}

# =============================================================================
# Configure VNC and Desktop
# =============================================================================
RUN mkdir -p /home/${USER}/.vnc /home/${USER}/.config \
    && chown -R ${USER}:${USER} /home/${USER}

# =============================================================================
# Copy Configuration Files
# =============================================================================
COPY --chown=${USER}:${USER} config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY --chown=${USER}:${USER} scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# =============================================================================
# Exposed Ports
# =============================================================================
# VNC: 5901, noVNC: 6080
EXPOSE ${VNC_PORT} ${NOVNC_PORT}

# =============================================================================
# Copy Configuration Defaults
# =============================================================================
RUN mkdir -p /opt/defaults
COPY config/xfce4-panel.xml /opt/defaults/xfce4-panel.xml

# =============================================================================
# Volumes
# =============================================================================
VOLUME ["/home/${USER}/workspace", "/home/${USER}/.config"]

# =============================================================================
# Health Check
# =============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${NOVNC_PORT}/ || exit 1

# =============================================================================
# Entrypoint
# =============================================================================
USER ${USER}
WORKDIR /home/${USER}

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["supervisord"]
