#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot Container..."

# Create required directories
mkdir -p /home/dockuser/.vnc 
mkdir -p /home/dockuser/chrome-profile
mkdir -p /tmp/logs
chmod 700 /home/dockuser/.vnc

# Setup VNC
echo "📺 Setting up VNC server..."
cat > /home/dockuser/.vnc/xstartup << 'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
export DISPLAY=:1
xsetroot -solid grey
exec startxfce4 > /tmp/logs/xfce4.log 2>&1 &
EOF
chmod +x /home/dockuser/.vnc/xstartup

# Create VNC password (optional, using no auth for simplicity)
echo "🔐 Configuring VNC..."
echo "password" | vncpasswd -f > /home/dockuser/.vnc/passwd || true
chmod 600 /home/dockuser/.vnc/passwd || true

# Start Xvfb first (virtual framebuffer)
echo "🖥️ Starting Xvfb..."
Xvfb :1 -screen 0 1280x800x24 -ac +extension GLX +extension RANDR +extension RENDER -noreset > /tmp/logs/xvfb.log 2>&1 &
XVFB_PID=$!
export DISPLAY=:1

# Wait for Xvfb to start
sleep 3

# Start window manager
echo "🪟 Starting window manager..."
export DISPLAY=:1
startxfce4 > /tmp/logs/xfce4.log 2>&1 &
sleep 5

# Start VNC server
echo "📺 Starting VNC server..."
vncserver :1 -geometry 1280x800 -depth 24 -SecurityTypes None > /tmp/logs/vnc.log 2>&1 &
sleep 3

# Start noVNC web client
echo "🌐 Starting noVNC web client..."
cd /opt/noVNC
/opt/noVNC/utils/websockify/run 6080 localhost:5901 --web /opt/noVNC > /tmp/logs/novnc.log 2>&1 &
sleep 3

# Verify display is working
echo "🔍 Verifying display setup..."
export DISPLAY=:1
xdpyinfo > /tmp/logs/display_test.log 2>&1 || echo "⚠️ Display test failed, continuing anyway..."

# Start Chrome in the background
echo "🌐 Starting Chrome browser..."
export DISPLAY=:1
google-chrome-stable \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --user-data-dir=/home/dockuser/chrome-profile \
    --start-maximized \
    --disable-blink-features=AutomationControlled \
    --disable-automation \
    --disable-web-security \
    --allow-running-insecure-content \
    "https://pocketoption.com/en/login/" > /tmp/logs/chrome.log 2>&1 &

# Wait for Chrome to start
sleep 10

# Test GUI automation
echo "🧪 Testing pyautogui setup..."
python3 -c "
try:
    import pyautogui
    import os
    os.environ['DISPLAY'] = ':1'
    size = pyautogui.size()
    print(f'✅ PyAutoGUI working - Screen size: {size}')
except Exception as e:
    print(f'⚠️ PyAutoGUI test failed: {e}')
" || echo "⚠️ PyAutoGUI test completed with warnings"

# Create a simple test to verify everything is working
echo "🧪 Running system tests..."
python3 -c "
import sys
sys.path.append('/app')

# Test imports
try:
    from telegram_integration import parse_signal
    print('✅ Telegram integration: OK')
except Exception as e:
    print(f'❌ Telegram integration: {e}')

try:
    from selenium_integration import setup_driver
    print('✅ Selenium integration: OK')  
except Exception as e:
    print(f'❌ Selenium integration: {e}')

try:
    import pyautogui
    print('✅ PyAutoGUI: OK')
except Exception as e:
    print(f'❌ PyAutoGUI: {e}')
    
print('🧪 System tests completed')
" || echo "⚠️ Some system tests failed, but continuing..."

# Show service status
echo "📊 Service Status:"
echo "   - Xvfb (Virtual Display): $(pgrep Xvfb > /dev/null && echo '✅ Running' || echo '❌ Not running')"
echo "   - XFCE Desktop: $(pgrep xfce4-session > /dev/null && echo '✅ Running' || echo '❌ Not running')"
echo "   - VNC Server: $(pgrep vnc > /dev/null && echo '✅ Running' || echo '❌ Not running')"
echo "   - noVNC Web: $(pgrep websockify > /dev/null && echo '✅ Running' || echo '❌ Not running')"
echo "   - Chrome Browser: $(pgrep chrome > /dev/null && echo '✅ Running' || echo '❌ Not running')"

# Show access information
echo ""
echo "🌐 Access URLs:"
echo "   - noVNC Web Client: http://localhost:6080/vnc.html"
echo "   - Trading Bot Health: http://localhost:6081/health"
echo "   - Pocket Option Login: https://pocketoption.com/en/login/"
echo ""

# Wait a bit more for everything to stabilize
echo "⏳ Allowing services to stabilize..."
sleep 15

# Start the main trading bot
echo "🤖 Starting Trading Bot Core..."
cd /app

# Set environment variables for the bot
export DISPLAY=:1
export PYTHONPATH=/app:$PYTHONPATH

# Run the core trading bot
python3 core.py

# If we get here, the bot exited - keep container alive for debugging
echo "🛑 Trading bot stopped. Keeping container alive for debugging..."
echo "📝 Check logs in /tmp/logs/ for troubleshooting"
echo "🌐 VNC still available at http://localhost:6080/vnc.html"

# Show recent logs for debugging
echo "📋 Recent logs:"
echo "--- Core bot log ---"
tail -20 /tmp/bot.log 2>/dev/null || echo "No bot log found"

echo "--- Chrome log ---"  
tail -10 /tmp/logs/chrome.log 2>/dev/null || echo "No Chrome log found"

# Keep container running
tail -f /dev/null
