#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot Container..."

# Create necessary directories
mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp
chmod 700 /home/dockuser/.vnc

# Create xstartup for VNC
cat > /home/dockuser/.vnc/xstartup << 'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
export DISPLAY=:1
unset SESSION_MANAGER
exec startxfce4 &
EOF
chmod +x /home/dockuser/.vnc/xstartup

# Create Xauthority file
touch /home/dockuser/.Xauthority
export XAUTHORITY=/home/dockuser/.Xauthority

echo "🖥️  Starting VNC server..."
vncserver :1 -geometry 1280x800 -depth 24 -SecurityTypes None -localhost no

# Wait for VNC to start
sleep 3

echo "🌐 Starting noVNC web interface..."
cd /opt/noVNC
/opt/noVNC/utils/websockify/run 6080 localhost:5901 --web /opt/noVNC &
NOVNC_PID=$!

# Wait for noVNC to start
sleep 2

echo "🌍 Starting Chrome browser..."
export DISPLAY=:1
google-chrome-stable \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --user-data-dir=/home/dockuser/chrome-profile \
  --start-maximized \
  --disable-blink-features=AutomationControlled \
  --disable-web-security \
  --allow-running-insecure-content \
  "https://pocketoption.com/login" &
CHROME_PID=$!

# Wait for Chrome to start
sleep 5

echo "🤖 Starting Trading Bot..."
cd /home/dockuser
python3 core.py &
BOT_PID=$!

echo "✅ All services started successfully!"
echo "📊 Access VNC interface: http://localhost:6080"
echo "🏥 Health check: http://localhost:6081/health"
echo "📝 Bot logs: tail -f /tmp/bot.log"

# Function to cleanup on exit
cleanup() {
    echo "🛑 Shutting down services..."
    kill $BOT_PID 2>/dev/null || true
    kill $CHROME_PID 2>/dev/null || true
    kill $NOVNC_PID 2>/dev/null || true
    vncserver -kill :1 2>/dev/null || true
    echo "✅ Cleanup completed"
}

# Setup signal handlers
trap cleanup SIGTERM SIGINT

# Wait for any process to exit
wait $BOT_PID
