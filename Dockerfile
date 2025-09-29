FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x800 \
    NO_VNC_HOME=/opt/noVNC

# Install minimal packages first
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates gnupg2 \
    python3 python3-pip python3-setuptools python3-venv git locales unzip xauth \
    dbus-x11 supervisor net-tools lsof procps dos2unix \
    libnss3 libxss1 libasound2 libatk-bridge2.0-0 libgtk-3-0 \
    libgbm1 libu2f-udev fonts-liberation libappindicator3-1 \
    libxrandr2 libxdamage1 libxcomposite1 libxcursor1 libxinerama1 \
    libxext6 libxfixes3 libpango-1.0-0 libpangocairo-1.0-0 \
    libatspi2.0-0 libdrm2 libx11-xcb1 \
    python3-tk python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Locale setup
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install Chrome (official)
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install VNC and minimal XFCE desktop
RUN apt-get update && apt-get install -y --no-install-recommends \
    tigervnc-standalone-server \
    xfce4-session xfce4-panel xfce4-terminal \
    && rm -rf /var/lib/apt/lists/*

# Install noVNC
RUN git clone --depth 1 --branch v1.4.0 https://github.com/novnc/noVNC.git ${NO_VNC_HOME} \
    && git clone --depth 1 https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify \
    && chmod +x ${NO_VNC_HOME}/utils/websockify/run

# Create user and directories
RUN useradd -m -s /bin/bash -u 1000 dockuser \
    && mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile /home/dockuser/bot \
    && chown -R dockuser:dockuser /home/dockuser

WORKDIR /home/dockuser

# Copy your bot files
COPY --chown=dockuser:dockuser core.py selenium_integration.py telegram_integration.py healthcheck.sh start.sh requirements.txt /home/dockuser/bot/

# Copy start script
COPY start.sh /usr/local/bin/start.sh
RUN dos2unix /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

# Make bot scripts executable
RUN chmod +x /home/dockuser/bot/healthcheck.sh /home/dockuser/bot/start.sh

# Install Python dependencies
RUN python3 -m pip install --upgrade pip && pip3 install --no-cache-dir -r /home/dockuser/bot/requirements.txt

EXPOSE 5901 6080 6081

USER dockuser
WORKDIR /home/dockuser

ENTRYPOINT ["/usr/local/bin/start.sh"]
