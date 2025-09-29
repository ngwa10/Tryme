FROM ubuntu:latest

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

# Copy your start.sh script into the image
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 5901

# Start your custom script on container start
CMD ["/start.sh"]
