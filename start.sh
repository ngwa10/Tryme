#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot Container..."

mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile /tmp
chmod 700 /home/dockuser/.vnc

# Minimal robust xstartup for XFCE
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

sleep 3

echo "🌐 Starting noVNC web interface..."
cd /opt/noVNC
/opt/noVNC/utils/websockify/run 6080 localhost:5901 --web /opt/noVNC &
NOVNC_PID=$!

sleep 2

# ---- Chrome automation for login ----
echo "🌐 Launching Chrome and automating login..."

# Use environment variables for credentials, or hardcoded if not set
EMAIL="${BOT_EMAIL:-mylivemyfuture@123gmail.com}"
PASSWORD="${BOT_PASSWORD:-AaCcWw3468,}"

python3 <<EOF
import os
import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

os.environ['DISPLAY'] = ':1'
os.environ['XAUTHORITY'] = '/home/dockuser/.Xauthority'

chrome_options = Options()
chrome_options.add_argument("--no-sandbox")
chrome_options.add_argument("--disable-dev-shm-usage")
chrome_options.add_argument("--disable-gpu")
chrome_options.add_argument("--start-maximized")
chrome_options.add_argument("--user-data-dir=/home/dockuser/chrome-profile")
service = Service("/usr/local/bin/chromedriver")
driver = webdriver.Chrome(service=service, options=chrome_options)
driver.get("https://pocketoption.com/login")
try:
    wait = WebDriverWait(driver, 20)
    email_input = wait.until(EC.presence_of_element_located((By.NAME, "email")))
    password_input = wait.until(EC.presence_of_element_located((By.NAME, "password")))
    email_input.clear()
    email_input.send_keys("$EMAIL")
    password_input.clear()
    password_input.send_keys("$PASSWORD")
    login_button = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "button[type='submit']")))
    login_button.click()
    time.sleep(5)
except Exception as e:
    print("[❌] Chrome login automation failed:", e)
# Keep Chrome open for VNC view
EOF

echo "✅ Chrome launched and login attempted!"
echo "📊 Access VNC interface: http://localhost:6080"

echo "🤖 Starting Trading Bot..."
python3 /home/dockuser/bot/core.py &
BOT_PID=$!

echo "🏥 Health check: http://localhost:6081/health"
echo "📝 Bot logs: tail -f /tmp/bot.log"

cleanup() {
    echo "🛑 Shutting down services..."
    kill $BOT_PID 2>/dev/null || true
    kill $NOVNC_PID 2>/dev/null || true
    vncserver -kill :1 2>/dev/null || true
    echo "✅ Cleanup completed"
}

trap cleanup SIGTERM SIGINT

wait $BOT_PID
