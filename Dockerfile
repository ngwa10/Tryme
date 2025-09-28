# ===========================================
# Pocket Option Telegram Trading Bot Dockerfile
# Zeabur/Cloud-optimized, Chrome+ChromeDriver pinned for reliability
# ===========================================

FROM ubuntu:22.04

# 1. Install system and X11/VNC dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    python3 python3-pip python3-setuptools python3-venv \
    xvfb xfce4 xfce4-terminal dbus-x11 x11-xkb-utils x11-utils \
    xfonts-base xfonts-scalable xfonts-100dpi xfonts-75dpi \
    wget curl ca-certificates \
    net-tools lsof procps \
    supervisor \
    git \
    libnss3 libxss1 libasound2 libatk-bridge2.0-0 libgtk-3-0 \
    libgbm1 libu2f-udev fonts-liberation libappindicator3-1 \
    libxrandr2 libxdamage1 libxcomposite1 libxcursor1 libxinerama1 \
    libxext6 libxfixes3 libpango-1.0-0 libpangocairo-1.0-0 \
    libatspi2.0-0 libdrm2 libx11-xcb1 \
    unzip \
    xauth \
    && apt-get clean

# 2. Install Google Chrome (pinned version for driver compatibility)
RUN wget -O /tmp/google-chrome.deb https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_120.0.6099.71-1_amd64.deb && \
    apt-get install -y /tmp/google-chrome.deb || apt-get -f install -y && \
    rm /tmp/google-chrome.deb

# 3. Install ChromeDriver (version 120 to match Chrome 120)
RUN wget -O /tmp/chromedriver.zip "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/120.0.6099.71/linux64/chromedriver-linux64.zip" && \
    unzip /tmp/chromedriver.zip -d /usr/local/bin/ && \
    mv /usr/local/bin/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver && \
    chmod +x /usr/local/bin/chromedriver && \
    rm -rf /tmp/chromedriver.zip /usr/local/bin/chromedriver-linux64

# 4. Install noVNC and websockify
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC && \
    git clone --depth 1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify

# 5. Add the non-root user
RUN useradd -m -s /bin/bash dockuser && \
    echo "dockuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 6. Set up directories, permissions
WORKDIR /home/dockuser
RUN mkdir -p /home/dockuser/bot /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp && \
    chown -R dockuser:dockuser /home/dockuser /tmp

# 7. Copy bot code into image
COPY --chown=dockuser:dockuser core.py selenium_integration.py telegram_integration.py healthcheck.sh start.sh requirements.txt /home/dockuser/bot/
RUN chmod +x /home/dockuser/bot/healthcheck.sh /home/dockuser/bot/start.sh

# 8. Install Python dependencies
RUN python3 -m pip install --upgrade pip
RUN pip3 install --no-cache-dir -r /home/dockuser/bot/requirements.txt

# 9. Expose required ports (for Zeabur to map)
EXPOSE 6080 6081

# 10. Set environment variables
ENV DISPLAY=:1
ENV XAUTHORITY=/home/dockuser/.Xauthority
ENV HOME=/home/dockuser
ENV LANG=en_US.UTF-8
ENV PYTHONUNBUFFERED=1

# 11. Run as non-root user
USER dockuser

# 12. Entrypoint (starts VNC, noVNC, Chrome, your bot)
ENTRYPOINT ["/home/dockuser/bot/start.sh"]
