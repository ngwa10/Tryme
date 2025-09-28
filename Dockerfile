FROM ubuntu:22.04

# Install system dependencies, XFCE, and gnupg for Chrome key
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    python3 python3-pip python3-setuptools python3-venv \
    xvfb xfce4 xfce4-session xterm dbus-x11 x11-xkb-utils x11-utils \
    tigervnc-standalone-server tigervnc-common \
    wget curl ca-certificates git locales unzip xauth \
    gnupg \
    libnss3 libxss1 libasound2 libatk-bridge2.0-0 libgtk-3-0 \
    libgbm1 libu2f-udev fonts-liberation libappindicator3-1 \
    libxrandr2 libxdamage1 libxcomposite1 libxcursor1 libxinerama1 \
    libxext6 libxfixes3 libpango-1.0-0 libpangocairo-1.0-0 \
    libatspi2.0-0 libdrm2 libx11-xcb1 \
    supervisor net-tools lsof procps xfonts-base xfonts-scalable xfonts-100dpi xfonts-75dpi \
    python3-tk python3-dev \
    && apt-get clean

# Locale fix
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install Google Chrome via official repo (robust, works on all Ubuntu versions)
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
 && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
 && apt-get update \
 && apt-get install -y google-chrome-stable

# Find Chrome version and install matching ChromeDriver
RUN CHROME_VERSION=$(google-chrome-stable --version | awk '{print $3}') && \
    CHROME_MAJOR_VERSION=$(echo $CHROME_VERSION | cut -d '.' -f 1) && \
    echo "Detected Chrome version: $CHROME_VERSION (Major: $CHROME_MAJOR_VERSION)" && \
    DRIVER_URL="https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chromedriver-linux64.zip" && \
    wget -O /tmp/chromedriver.zip "$DRIVER_URL" || \
    (echo "Falling back to latest for major version"; \
     DRIVER_URL="https://storage.googleapis.com/chrome-for-testing-public/$CHROME_MAJOR_VERSION.0.0.0/linux64/chromedriver-linux64.zip"; \
     wget -O /tmp/chromedriver.zip "$DRIVER_URL") && \
    unzip /tmp/chromedriver.zip -d /usr/local/bin/ && \
    mv /usr/local/bin/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver && \
    chmod +x /usr/local/bin/chromedriver && \
    rm -rf /tmp/chromedriver.zip /usr/local/bin/chromedriver-linux64

# Check Chrome install
RUN which google-chrome-stable && google-chrome-stable --version && /usr/local/bin/chromedriver --version

# noVNC
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC && \
    git clone --depth 1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify

# Create dockuser (must happen before USER dockuser!)
RUN useradd -m -s /bin/bash dockuser && \
    echo "dockuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/dockuser
RUN mkdir -p /home/dockuser/bot /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp && \
    chown -R dockuser:dockuser /home/dockuser /tmp

COPY --chown=dockuser:dockuser core.py selenium_integration.py telegram_integration.py healthcheck.sh start.sh requirements.txt /home/dockuser/bot/
RUN chmod +x /home/dockuser/bot/healthcheck.sh /home/dockuser/bot/start.sh

RUN python3 -m pip install --upgrade pip
RUN pip3 install --no-cache-dir -r /home/dockuser/bot/requirements.txt

EXPOSE 6080 6081
ENV DISPLAY=:1
ENV XAUTHORITY=/home/dockuser/.Xauthority
ENV HOME=/home/dockuser
ENV PYTHONUNBUFFERED=1

USER dockuser
ENTRYPOINT ["/home/dockuser/bot/start.sh"]
