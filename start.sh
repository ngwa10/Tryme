#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot Container..."

# Setup VNC and XFCE
mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile
chmod 700 /home/dockuser/.vnc

cat > /home/dockuser/.vnc/xstartup << 'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
exec xfce4-session
EOF
chmod +x /home/dockuser/.vnc/xstartup

touch /home/dockuser/.Xauthority
export XAUTHORITY=/home/dockuser/.Xauthority
export DISPLAY=:1

echo "🖥️  Starting VNC server..."
vncserver :1 -geometry 1280x800 -depth 24 -SecurityTypes None -localhost no --I-KNOW-THIS-IS-INSECURE

sleep 5

echo "🌐 Starting noVNC web interface..."
cd /opt/noVNC
/opt/noVNC/utils/websockify/run 6080 localhost:5901 --web /opt/noVNC &

sleep 2

echo "🌐 Starting Chrome for GUI login..."
google-chrome-stable --no-sandbox --disable-dev-shm-usage --disable-gpu \
  --user-data-dir=/home/dockuser/chrome-profile \
  --start-maximized "https://pocketoption.com/login" &

echo "✅ Chrome launched!"
