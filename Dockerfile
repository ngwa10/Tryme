# ==============================
# Pocket Option Telegram Trading Bot Dockerfile
# ==============================

FROM ubuntu:22.04

# Install base dependencies
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

# Install Google Chrome
RUN wget -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/google-chrome.deb || apt-get -f install -y && \
    rm /tmp/google-chrome.deb

# Install ChromeDriver (matching major version with Chrome)
RUN CHROME_VERSION=$(google-chrome --version | grep -oP '[0-9.]+' | head -1 | cut -d. -f1) && \
    DRIVER_VERSION=$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${CHROME_VERSION}") && \
    wget -O /tmp/chromedriver.zip "https://chromedriver.storage.googleapis.com/${DRIVER_VERSION}/chromedriver_linux64.zip" && \
    unzip /tmp/chromedriver.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/chromedriver && \
    rm /tmp/chromedriver.zip

# Install noVNC and websockify
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC && \
    git clone --depth 1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify

# Set up user
RUN useradd -m -s /bin/bash dockuser && \
    echo "dockuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set workdir and permissions
WORKDIR /home/dockuser
RUN mkdir -p /home/dockuser/bot /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp && \
    chown -R dockuser:dockuser /home/dockuser /tmp

# Copy bot code
COPY --chown=dockuser:dockuser core.py selenium_integration.py telegram_integration.py healthcheck.sh start.sh requirements.txt /home/dockuser/bot/
RUN chmod +x /home/dockuser/bot/healthcheck.sh /home/dockuser/bot/start.sh

# Install Python dependencies
RUN python3 -m pip install --upgrade pip
RUN pip3 install --no-cache-dir -r /home/dockuser/bot/requirements.txt

# Expose required ports
EXPOSE 6080 6081

# Set environment variables
ENV DISPLAY=:1
ENV XAUTHORITY=/home/dockuser/.Xauthority
ENV HOME=/home/dockuser
ENV LANG=en_US.UTF-8
ENV PYTHONUNBUFFERED=1

# Entrypoint ensures everything runs as correct user
USER dockuser

ENTRYPOINT ["/home/dockuser/bot/start.sh"]
