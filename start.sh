#!/bin/bash
set -e

# Read environment variables
VNC_PASS=${VNC_PASSWORD:-password}
VNC_RESOLUTION=${VNC_RESOLUTION:-1280x800}
NO_VNC_HOME=/opt/noVNC
DISPLAY_NUM=${DISPLAY#:}   # if DISPLAY is ":1", this extracts "1"

# Prepare .vnc directory
mkdir -p /home/dockuser/.vnc
chmod 700 /home/dockuser/.vnc

# Write VNC password file (format for TigerVNC)
printf "%s\n" "$VNC_PASS" "$VNC_PASS" | vncpasswd -f > /home/dockuser/.vnc/passwd
chmod 600 /home/dockuser/.vnc/passwd

# Create xstartup file for XFCE session
cat > /home/dockuser/.vnc/xstartup << 'XSTART'
#!/bin/bash
xrdb $HOME/.Xresources >/dev/null 2>&1
startxfce4 &
XSTART

chmod +x /home/dockuser/.vnc/xstartup

# Kill any existing VNC server on :1
vncserver -kill :1 >/dev/null 2>&1 || true

# Start VNC server
vncserver :1 -geometry ${VNC_RESOLUTION} -depth 24

export DISPLAY=:1

# Wait a short moment for the display to initialize
sleep 2

# Launch Chrome to Pocket login page
CHROME_FLAGS="--no-sandbox --disable-dev-shm-usage --user-data-dir=/home/dockuser/chrome-profile --start-maximized"
google-chrome-stable ${CHROME_FLAGS} "https://getpocket.com/login" >/dev/null 2>&1 &

# Start noVNC (websockify) to expose VNC over HTTP
cd ${NO_VNC_HOME}
${NO_VNC_HOME}/utils/websockify/run 6080 localhost:5901 --web ${NO_VNC_HOME} --idle-timeout=0 &

# Keep container running by tailing logs
tail -f /home/dockuser/.vnc/*.log
