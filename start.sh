#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot Container..."
echo "Current user: $(whoami)"

# Create necessary directories
mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp /run/dbus
chmod 700 /home/dockuser/.vnc
chown dockuser:dockuser /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp

# Create dummy DBus socket to suppress Chrome errors
touch /run/dbus/system_bus_socket
chmod 666 /run/dbus/system_bus_socket

# Minimal robust xstartup for XFCE
cat > /home/dockuser/.vnc/xstartup << 'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
exec xfce4-session
EOF
chmod +x /home/dockuser/.vnc/xstartup

# Set up X11 environment
touch /home/dockuser/.Xauthority
chown dockuser:dockuser /home/dockuser/.Xauthority
export XAUTHORITY=/home/dockuser/.Xauthority
export DISPLAY=:1

echo "🖥️  Starting VNC server..."
vncserver :1 -geometry 1280x800 -depth 24 -SecurityTypes None -localhost no --I-KNOW-THIS-IS-INSECURE
sleep 3

echo "🌐 Starting noVNC web interface..."
cd /opt/noVNC
/opt/noVNC/utils/websockify/run 6080 localhost:5901 --web /opt/noVNC &
NOVNC_PID=$!
sleep 2

# 🧹 Clean up any leftover Chrome lock files
rm -f /home/dockuser/chrome-profile/SingletonLock
rm -f /home/dockuser/chrome-profile/SingletonSocket

# 🌐 Launch Chrome as non-root to avoid permission issues
echo "🌐 Starting Chrome for GUI login..."
su dockuser -c "google-chrome-stable --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-software-rasterizer \
  --enable-logging --v=1 \
  --user-data-dir=/home/dockuser/chrome-profile --profile-directory='Profile 1' \
  --no-first-run --no-default-browser-check \
  --disable-features=OutOfBlinkOOMKill \
  --start-maximized 'https://pocketoption.com/login'" &
echo "✅ Chrome launched!"
echo "📊 Access VNC interface: http://localhost:6080"

# 🤖 Launch Trading Bot
echo "🤖 Starting Trading Bot..."
python3 /home/dockuser/bot/core.py &
BOT_PID=$!

echo "🏥 Health check: http://localhost:6081/health"
echo "📝 Bot logs: tail -f /tmp/bot.log"

# Graceful shutdown handler
cleanup() {
    echo "🛑 Shutting down services..."
    kill $BOT_PID 2>/dev/null || true
    kill $NOVNC_PID 2>/dev/null || true
    vncserver -kill :1 2>/dev/null || true
    echo "✅ Cleanup completed"
}

trap cleanup SIGTERM SIGINT

wait $BOT_PID
