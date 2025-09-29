FROM python:3.12-slim

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
  xvfb xfce4 xfce4-session xterm dbus-x11 x11-xkb-utils x11-utils \
  tigervnc-standalone-server tigervnc-common \
  wget curl ca-certificates git locales unzip xauth gnupg \
  libnss3 libxss1 libasound2 libatk-bridge2.0-0 libgtk-3-0 \
  libgbm1 libu2f-udev fonts-liberation libappindicator3-1 \
  libxrandr2 libxdamage1 libxcomposite1 libxcursor1 libxinerama1 \
  libxext6 libxfixes3 libpango-1.0-0 libpangocairo-1.0-0 \
  libatspi2.0-0 libdrm2 libx11-xcb1 \
  supervisor net-tools lsof procps \
  xfonts-base xfonts-scalable xfonts-100dpi xfonts-75dpi \
  python3-tk python3-dev dbus \
  chromium && \
  apt-get install -y --no-install-recommends locales && \
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
  locale-gen && \
  apt-get clean

# Locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN useradd -m -s /bin/bash dockuser && \
  echo "dockuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Generate machine-id for DBus
RUN dbus-uuidgen > /etc/machine-id

# Install noVNC
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC && \
  git clone --depth 1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify

WORKDIR /home/dockuser

# Create directories and set permissions
RUN mkdir -p /home/dockuser/bot /home/dockuser/.vnc /home/dockuser/chrome-profile /home/dockuser/.config/tigervnc /tmp && \
    chown -R dockuser:dockuser /home/dockuser /tmp

# Copy your bot files
COPY --chown=dockuser:dockuser core.py selenium_integration.py telegram_integration.py healthcheck.sh start.sh requirements.txt /home/dockuser/bot/

# Make startup scripts executable
RUN chmod +x /home/dockuser/bot/healthcheck.sh /home/dockuser/bot/start.sh

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /home/dockuser/bot/requirements.txt

EXPOSE 6080 6081

ENV DISPLAY=:1
ENV XAUTHORITY=/home/dockuser/.Xauthority
ENV HOME=/home/dockuser
ENV PYTHONUNBUFFERED=1

USER dockuser

ENTRYPOINT ["/home/dockuser/bot/start.sh"]
