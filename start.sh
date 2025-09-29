#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot Container..."
echo "Current user: $(whoami)"

export DISPLAY=:1
export XAUTHORITY=/home/dockuser/.Xauthority

# Create necessary directories
mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp /run/dbus /tmp/crashpad
chmod 700 /home/dockuser/.vnc

# Minimal robust xstartup for XFCE
cat > /home/dockuser/.vnc/xstartup << 'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
exec startxfce4
EOF
chmod +x /home/dockuser/.vnc/xstartup

# Set up X11 environment
touch /home/dockuser/.Xauthority

echo "🖥️  Starting VNC server..."
vncserver :1 -geometry 1280x800 -depth 24 -SecurityTypes None -localhost no

sleep 3

# Wait for X to be ready
for i in {1..10}; do
  if xdpyinfo -display $DISPLAY >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "🌐 Starting noVNC web interface..."
cd /opt/noVNC
/opt/noVNC/utils/websockify/run 6080 localhost:5901 --web /opt/noVNC &
NOVNC_PID=$!
sleep 2

# Launch Chrome (official, as non-root, with your flags)
google-chrome-stable --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-software-rasterizer \
  --user-data-dir=/home/dockuser/chrome-profile \
  --no-first-run --no-default-browser-check \
  --kiosk 'https://pocketoption.com/login' &
echo "✅ Chrome launched!"

# Launch Trading Bot
python3 /home/dockuser/bot/core.py &
BOT_PID=$!

# Graceful shutdown
cleanup() {
    kill $BOT_PID 2>/dev/null || true
    kill $NOVNC_PID 2>/dev/null || true
    vncserver -kill :1 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

wait $BOT_PID
