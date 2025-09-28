#!/bin/bash
set -e

# Enhanced healthcheck script for Pocket Option Trading Bot
# Checks all critical services and provides detailed status

echo "🏥 Pocket Option Trading Bot Health Check"
echo "========================================="

HEALTH_STATUS=0
SERVICES_STATUS=""

# Function to check service and log status
check_service() {
    local service_name="$1"
    local process_pattern="$2"
    local description="$3"
    
    if pgrep -f "$process_pattern" > /dev/null 2>&1; then
        echo "✅ $service_name: Running"
        SERVICES_STATUS="$SERVICES_STATUS$service_name:OK "
    else
        echo "❌ $service_name: Not Running"
        SERVICES_STATUS="$SERVICES_STATUS$service_name:FAILED "
        HEALTH_STATUS=1
    fi
}

# Function to check port accessibility
check_port() {
    local port="$1"
    local service_name="$2"
    
    if netstat -tuln 2>/dev/null | grep ":$port " > /dev/null 2>&1 || \
       ss -tuln 2>/dev/null | grep ":$port " > /dev/null 2>&1 || \
       lsof -i ":$port" > /dev/null 2>&1; then
        echo "✅ Port $port ($service_name): Open"
        SERVICES_STATUS="$SERVICES_STATUS$service_name-port:OK "
    else
        echo "⚠️  Port $port ($service_name): Not accessible"
        SERVICES_STATUS="$SERVICES_STATUS$service_name-port:WARNING "
    fi
}

# Function to check HTTP endpoint
check_endpoint() {
    local url="$1"
    local service_name="$2"
    
    if curl -sf "$url" > /dev/null 2>&1; then
        echo "✅ $service_name endpoint: Responding"
        SERVICES_STATUS="$SERVICES_STATUS$service_name-http:OK "
    else
        echo "⚠️  $service_name endpoint: Not responding"
        SERVICES_STATUS="$SERVICES_STATUS$service_name-http:WARNING "
    fi
}

# Function to check file existence and permissions
check_file() {
    local file_path="$1"
    local description="$2"
    
    if [ -f "$file_path" ]; then
        echo "✅ $description: Found"
        SERVICES_STATUS="$SERVICES_STATUS$description:OK "
    else
        echo "⚠️  $description: Missing"
        SERVICES_STATUS="$SERVICES_STATUS$description:WARNING "
    fi
}

echo ""
echo "🔍 Checking Core Services..."
echo "----------------------------"

# Check VNC Server
check_service "VNC Server" "Xvnc|vncserver" "X11 VNC server for remote desktop access"

# Check noVNC/websockify
check_service "noVNC/Websockify" "websockify|novnc" "Web-based VNC client"

# Check Chrome Browser
check_service "Chrome Browser" "chrome|google-chrome" "Web browser for Pocket Option"

# Check Trading Bot
check_service "Trading Bot" "python.*core\.py|core\.py" "Main trading bot application"

echo ""
echo "🌐 Checking Network Services..."
echo "-------------------------------"

# Check critical ports
check_port "5901" "VNC Direct"
check_port "6080" "noVNC Web"
check_port "6081" "Health API"

echo ""
echo "🔗 Checking HTTP Endpoints..."
echo "-----------------------------"

# Check health API endpoint
check_endpoint "http://localhost:6081/health" "Health API"

# Check if noVNC web interface is accessible
check_endpoint "http://localhost:6080/vnc.html" "noVNC Interface"

echo ""
echo "📁 Checking Critical Files..."
echo "-----------------------------"

# Check important files and directories
check_file "/home/dockuser/bot/core.py" "Bot Core"
check_file "/home/dockuser/bot/telegram_integration.py" "Telegram Module"
check_file "/home/dockuser/bot/selenium_integration.py" "Selenium Module"
check_file "/home/dockuser/.vnc/xstartup" "VNC Startup"
check_file "/tmp/bot.log" "Bot Logs"

echo ""
echo "💾 System Resources..."
echo "---------------------"

# Memory usage
if command -v free >/dev/null 2>&1; then
    MEM_USAGE=$(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')
    echo "📊 Memory Usage: $MEM_USAGE"
    SERVICES_STATUS="$SERVICES_STATUS memory:$MEM_USAGE "
fi

# Disk usage
if command -v df >/dev/null 2>&1; then
    DISK_USAGE=$(df -h / | awk 'NR==2{printf("%s", $5)}')
    echo "💽 Disk Usage: $DISK_USAGE"
    SERVICES_STATUS="$SERVICES_STATUS disk:$DISK_USAGE "
fi

# Load average
if [ -f /proc/loadavg ]; then
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1}')
    echo "⚡ Load Average: $LOAD_AVG"
    SERVICES_STATUS="$SERVICES_STATUS load:$LOAD_AVG "
fi

echo ""
echo "🔧 Environment Check..."
echo "----------------------"

# Check DISPLAY variable
if [ -n "$DISPLAY" ]; then
    echo "✅ DISPLAY: $DISPLAY"
    SERVICES_STATUS="$SERVICES_STATUS display:OK "
else
    echo "❌ DISPLAY: Not set"
    SERVICES_STATUS="$SERVICES_STATUS display:FAILED "
    HEALTH_STATUS=1
fi

# Check if X11 is accessible
if command -v xdpyinfo >/dev/null 2>&1; then
    if xdpyinfo > /dev/null 2>&1; then
        echo "✅ X11 Display: Accessible"
        SERVICES_STATUS="$SERVICES_STATUS x11:OK "
    else
        echo "❌ X11 Display: Not accessible"
        SERVICES_STATUS="$SERVICES_STATUS x11:FAILED "
        HEALTH_STATUS=1
    fi
fi

# Check Python modules
echo ""
echo "🐍 Python Dependencies..."
echo "-------------------------"

python3 -c "import telethon; print('✅ Telethon: Available')" 2>/dev/null || {
    echo "❌ Telethon: Missing"
    SERVICES_STATUS="$SERVICES_STATUS telethon:FAILED "
    HEALTH_STATUS=1
}

python3 -c "import selenium; print('✅ Selenium: Available')" 2>/dev/null || {
    echo "❌ Selenium: Missing"
    SERVICES_STATUS="$SERVICES_STATUS selenium:FAILED "
    HEALTH_STATUS=1
}

python3 -c "import pyautogui; print('✅ PyAutoGUI: Available')" 2>/dev/null || {
    echo "⚠️  PyAutoGUI: Missing (GUI automation disabled)"
    SERVICES_STATUS="$SERVICES_STATUS pyautogui:WARNING "
}

echo ""
echo "📊 Overall Status..."
echo "-------------------"

# Final status summary
if [ $HEALTH_STATUS -eq 0 ]; then
    echo "🎉 Overall Status: HEALTHY"
    echo "📝 Services: $SERVICES_STATUS"
    echo ""
    echo "🌐 Access URLs:"
    echo "   • VNC Web Interface: http://localhost:6080"
    echo "   • Health API: http://localhost:6081/health"
    echo "   • Bot Logs: tail -f /tmp/bot.log"
else
    echo "💥 Overall Status: UNHEALTHY"
    echo "📝 Services: $SERVICES_STATUS"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   • Check logs: tail -f /tmp/bot.log"
    echo "   • Restart services: docker restart <container>"
    echo "   • Check environment variables"
fi

echo ""
echo "⏰ Health Check Completed: $(date)"
echo "========================================="

# Return appropriate exit code
exit $HEALTH_STATUS
