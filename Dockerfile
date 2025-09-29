FROM ubuntu:latest

# Install tightvncserver and basic desktop environment
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    tightvncserver \
    xterm \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    sudo \
    && apt-get clean

# Setup basic XFCE config so VNC launches a desktop
RUN echo '#!/bin/bash\nxrdb $HOME/.Xresources\nstartxfce4 &' > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

# Expose VNC port
EXPOSE 5901

# Start VNC server on container start, with no authentication (INSECURE!)
CMD ["vncserver", ":1", "--I-KNOW-THIS-IS-INSECURE", "-geometry", "1280x800", "-depth", "24"]
