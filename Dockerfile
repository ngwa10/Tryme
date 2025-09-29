FROM ubuntu:latest

# Install dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    tightvncserver \
    xterm \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    sudo \
    python3 \
    python3-pip \
    wget \
    curl \
    net-tools \
    git \
    && apt-get clean

# Create non-root user
RUN useradd -m dockuser && \
    echo "dockuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Google Chrome (official .deb from Google)
RUN wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get update && \
    apt-get install -y /tmp/chrome.deb || apt-get -f install -y && \
    rm /tmp/chrome.deb

# Install noVNC
RUN git clone https://github.com/novnc/noVNC.git /opt/noVNC


# Copy start.sh script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Make sure dockuser owns everything
RUN chown -R dockuser:dockuser /home/dockuser /opt/noVNC /start.sh

# Expose VNC and noVNC ports
EXPOSE 5901 6080

# Switch to dockuser
USER dockuser

# Entry point
CMD ["/start.sh"]
