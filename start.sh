#!/bin/bash
set -e

# Read environment variables
VNC_PASS=${VNC_PASSWORD:-password}
VNC_RESOLUTION=${VNC_RESOLUTION:-1280x800}
NO_VNC_HOME=/opt/noVNC
DISPLAY_NUM=${DISPLAY#:}   # Extracts "1" from ":1"

# Prepare .vnc directory
mkdir -p /home/dockuser/.vnc
chmod 700 /home/dockuser/.vnc

# Set VNC password
echo "Configuring VNC password..."
printf "%s\n" "$VNC_PASS" "$VNC_PASS" | vncpasswd -f > /home/dockuser/.vnc/passwd
chmod 600 /home/dockuser/.vnc/passwd

# Create xstartup file for XFCE session
echo "Creating xstartup script..."
cat > /home/dockuser/.vnc/xstartup << 'XSTART'
#!/bin/bash
xrdb $HOME/.Xresources >/dev/null 2>&1
startxfce4 &
XSTART
chmod +x /home/dockuser/.vnc/xstartup

# Kill any existing VNC server
echo "Cleaning up old VNC sessions..."
vncserver -kill :${DISPLAY_NUM} >/dev/null 2>&1 || true

# Start VNC server
echo "Starting VNC server on display :${DISPLAY_NUM} with resolution ${VNC_RESOLUTION}..."
vncserver :${DISPLAY_NUM} -geometry ${VNC_RESOLUTION} -depth 24

export DISPLAY=:${DISPLAY_NUM}

# Wait for display to initialize
sleep 2

# Launch Chrome to Pocket Option login page
echo "Launching Chrome to Pocket Option login..."
CHROME_FLAGS="--no-sandbox --disable-dev-shm-usage --user-data-dir=/home/dockuser/chrome-profile --start-maximized"
google-chrome-stable ${CHROME_FLAGS} "https://pocketoption.com/login" >/dev/null 2>&1 &

# Start noVNC (websockify) to expose VNC over HTTP
echo "Starting noVNC on port 6080..."
cd ${NO_VNC_HOME}
${NO_VNC_HOME}/utils/websockify/run 6080 localhost:5901 --web ${NO_VNC_HOME} --idle-timeout=0 &

# Keep container running by tailing VNC logs
echo "Container is running. Tailing VNC logs..."
tail -F /home/dockuser/.vnc/*.log
