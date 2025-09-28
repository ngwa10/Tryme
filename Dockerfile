FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x800 \
    NO_VNC_HOME=/opt/noVNC \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    PATH="/usr/bin:$PATH"

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 xfce4-terminal \
    dbus-x11 x11-xserver-utils \
    wget curl ca-certificates gnupg2 \
    tigervnc-standalone-server tigervnc-common tigervnc-tools \
    python3 python3-pip python3-setuptools \
    git net-tools socat supervisor \
    xterm dos2unix \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y --no-install-recommends google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

# Install noVNC with specific version for stability
RUN git clone --depth 1 --branch v1.4.0 https://github.com/novnc/noVNC.git ${NO_VNC_HOME} && \
    git clone --depth 1 https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify && \
    chmod +x ${NO_VNC_HOME}/utils/websockify/run

# Create user with proper permissions
RUN useradd -m -s /bin/bash -u 1000 dockuser && \
    mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile && \
    chown -R dockuser:dockuser /home/dockuser && \
    chmod 755 /home/dockuser

# Create supervisor configuration directory
RUN mkdir -p /etc/supervisor/conf.d

# Copy supervisor configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy and setup start script
COPY start.sh /usr/local/bin/start.sh
RUN dos2unix /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

EXPOSE 5901 6080

USER dockuser
WORKDIR /home/dockuser

# Use supervisor to manage processes properly
ENTRYPOINT ["/usr/local/bin/start.sh"]
