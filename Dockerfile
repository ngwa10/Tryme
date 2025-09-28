# Dockerfile for VNC + Chrome for Pocket login# Dockerfile for VNC + Chrome for Pocket login

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x800 \
    NO_VNC_HOME=/opt/noVNC

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 xfce4-terminal \
    dbus-x11 x11-xserver-utils \
    wget curl ca-certificates gnupg2 \
    tigervnc-standalone-server tigervnc-common \
    python3 python3-pip python3-setuptools \
    git net-tools socat supervisor \
    xterm \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y --no-install-recommends google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

# Install noVNC for web-based VNC access
RUN git clone https://github.com/novnc/noVNC.git ${NO_VNC_HOME} && \
    git clone https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify

# Create user
RUN useradd -m -s /bin/bash dockuser && \
    mkdir -p /home/dockuser/.vnc && chown -R dockuser:dockuser /home/dockuser

WORKDIR /home/dockuser

# Copy start script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && chown dockuser:dockuser /usr/local/bin/start.sh

# Expose ports
EXPOSE 5901 6080

# Use user
USER dockuser

ENTRYPOINT [ "/usr/local/bin/start.sh" ]


FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x800 \
    NO_VNC_HOME=/opt/noVNC

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 xfce4-terminal \
    dbus-x11 x11-xserver-utils \
    wget curl ca-certificates gnupg2 \
    tigervnc-standalone-server tigervnc-common \
    python3 python3-pip python3-setuptools \
    git net-tools socat supervisor \
    xterm \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y --no-install-recommends google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

# Install noVNC for web-based VNC access
RUN git clone https://github.com/novnc/noVNC.git ${NO_VNC_HOME} && \
    git clone https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify

# Create user
RUN useradd -m -s /bin/bash dockuser && \
    mkdir -p /home/dockuser/.vnc && chown -R dockuser:dockuser /home/dockuser

WORKDIR /home/dockuser

# Copy start script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && chown dockuser:dockuser /usr/local/bin/start.sh

# Expose ports
EXPOSE 5901 6080

# Use user
USER dockuser

ENTRYPOINT [ "/usr/local/bin/start.sh" ]
