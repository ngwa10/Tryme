FROM ubuntu:22.04

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x800 \
    NO_VNC_HOME=/opt/noVNC \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Basic utilities
    curl \
    wget \
    ca-certificates \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    # Python and pip
    python3 \
    python3-pip \
    python3-dev \
    # Git for cloning repositories
    git \
    # Build essentials for Python packages
    build-essential \
    # Text processing utilities
    dos2unix \
    # Process management
    procps \
    # X11 and display
    xauth \
    x11-utils \
    # Networking
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install Chrome browser
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install ChromeDriver
RUN CHROME_VERSION=$(google-chrome --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+") \
    && DRIVER_VERSION=$(curl -s "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${CHROME_VERSION%%.*}") \
    && wget -O /tmp/chromedriver.zip "https://chromedriver.storage.googleapis.com/${DRIVER_VERSION}/chromedriver_linux64.zip" \
    && unzip /tmp/chromedriver.zip -d /tmp/ \
    && mv /tmp/chromedriver /usr/local/bin/chromedriver \
    && chmod +x /usr/local/bin/chromedriver \
    && rm /tmp/chromedriver.zip

# Install VNC and desktop environment
RUN apt-get update && apt-get install -y --no-install-recommends \
    # VNC server
    tigervnc-standalone-server \
    tigervnc-common \
    # Minimal XFCE desktop
    xfce4-session \
    xfce4-panel \
    xfce4-terminal \
    xfce4-settings \
    # D-Bus for desktop services
    dbus-x11 \
    # Fonts
    fonts-dejavu-core \
    fonts-liberation \
    # Additional X11 tools
    xfonts-base \
    xfonts-75dpi \
    xfonts-100dpi \
    && rm -rf /var/lib/apt/lists/*

# Install noVNC for web-based VNC access
RUN git clone --depth 1 --branch v1.4.0 https://github.com/novnc/noVNC.git ${NO_VNC_HOME} \
    && git clone --depth 1 https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify \
    && chmod +x ${NO_VNC_HOME}/utils/websockify/run

# Install Python packages
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel

# Install core Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Alternative: Install packages directly if no requirements.txt
RUN pip3 install --no-cache-dir \
    # Telegram client
    telethon \
    # Web automation
    selenium \
    # GUI automation
    pyautogui \
    # HTTP requests
    requests \
    urllib3 \
    # Image processing for pyautogui
    Pillow \
    # Additional utilities
    python-dateutil \
    # Async support
    asyncio \
    aiohttp

# Create non-root user
RUN useradd -m -s /bin/bash -u 1000 dockuser \
    && mkdir -p /home/dockuser/.vnc /home/dockuser/chrome-profile /home/dockuser/bot \
    && chown -R dockuser:dockuser /home/dockuser

# Create X authority file
RUN touch /home/dockuser/.Xauthority \
    && chown dockuser:dockuser /home/dockuser/.Xauthority

# Copy application files
COPY --chown=dockuser:dockuser core.py /home/dockuser/bot/
COPY --chown=dockuser:dockuser telegram_integration.py /home/dockuser/bot/
COPY --chown=dockuser:dockuser selenium_integration.py /home/dockuser/bot/
COPY --chown=dockuser:dockuser start.sh /usr/local/bin/start.sh

# Make scripts executable and fix line endings
RUN dos2unix /usr/local/bin/start.sh \
    && chmod +x /usr/local/bin/start.sh \
    && dos2unix /home/dockuser/bot/*.py

# Create log directory
RUN mkdir -p /tmp/bot-logs \
    && chown -R dockuser:dockuser /tmp/bot-logs

# Set up VNC configuration
RUN mkdir -p /home/dockuser/.vnc \
    && echo "#!/bin/bash\nexport XKL_XMODMAP_DISABLE=1\nexport DISPLAY=:1\nunset SESSION_MANAGER\nexec startxfce4 &" > /home/dockuser/.vnc/xstartup \
    && chmod +x /home/dockuser/.vnc/xstartup \
    && chown -R dockuser:dockuser /home/dockuser/.vnc

# Create requirements.txt content for reference
RUN cat > /home/dockuser/bot/requirements.txt << 'EOF'
telethon>=1.28.5
selenium>=4.15.0
pyautogui>=0.9.54
Pillow>=10.0.0
requests>=2.31.0
urllib3>=2.0.0
python-dateutil>=2.8.2
aiohttp>=3.8.0
asyncio
EOF

# Create environment template
RUN cat > /home/dockuser/bot/.env.template << 'EOF'
# Telegram Configuration
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHANNEL=your_channel_id

# Trading Configuration
BASE_TRADE_AMOUNT=1.0
MAX_MARTINGALE=2

# Pocket Option Credentials
BOT_EMAIL=your_email@gmail.com
BOT_PASSWORD=your_password

# Server Ports
HEALTH_PORT=6081
NOVNC_PORT=6080
WEB_PORT=8080
EOF

# Create docker-compose.yml template
RUN cat > /home/dockuser/bot/docker-compose.yml << 'EOF'
version: '3.8'

services:
  trading-bot:
    build: .
    container_name: pocket-option-bot
    ports:
      - "6080:6080"   # noVNC web interface
      - "6081:6081"   # Health check endpoint
      - "5901:5901"   # VNC direct connection
    environment:
      - DISPLAY=:1
      - TELEGRAM_API_ID=${TELEGRAM_API_ID}
      - TELEGRAM_API_HASH=${TELEGRAM_API_HASH}
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_CHANNEL=${TELEGRAM_CHANNEL}
      - BASE_TRADE_AMOUNT=${BASE_TRADE_AMOUNT:-1.0}
      - MAX_MARTINGALE=${MAX_MARTINGALE:-2}
      - BOT_EMAIL=${BOT_EMAIL}
      - BOT_PASSWORD=${BOT_PASSWORD}
    volumes:
      - bot-data:/home/dockuser/chrome-profile
      - bot-logs:/tmp/bot-logs
      - bot-vnc:/home/dockuser/.vnc
    restart: unless-stopped
    shm_size: 2gb
    security_opt:
      - seccomp:unconfined
    cap_add:
      - SYS_ADMIN
    networks:
      - bot-network

volumes:
  bot-data:
  bot-logs:
  bot-vnc:

networks:
  bot-network:
    driver: bridge
EOF

# Create startup script with better error handling
RUN cat > /home/dockuser/bot/run.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Trading Bot..."

# Check if running in container
if [ -f /.dockerenv ]; then
    echo "📦 Running in Docker container"
    exec /usr/local/bin/start.sh
else
    echo "💻 Running locally"
    
    # Check Python dependencies
    python3 -c "import telethon, selenium, pyautogui" 2>/dev/null || {
        echo "❌ Missing Python dependencies. Installing..."
        pip3 install telethon selenium pyautogui Pillow requests
    }
    
    # Set display if not set
    export DISPLAY=${DISPLAY:-:0}
    
    # Start the bot
    cd "$(dirname "$0")"
    python3 core.py
fi
EOF

# Make run script executable
RUN chmod +x /home/dockuser/bot/run.sh

# Create monitoring script
RUN cat > /home/dockuser/bot/monitor.sh << 'EOF'
#!/bin/bash

echo "📊 Pocket Option Bot Monitoring Dashboard"
echo "========================================"

while true; do
    clear
    echo "📊 Bot Status - $(date)"
    echo "========================================"
    
    # Health check
    echo "🏥 Health Check:"
    curl -s http://localhost:6081/health 2>/dev/null | python3 -m json.tool || echo "❌ Health check failed"
    echo ""
    
    # Process status
    echo "🔍 Process Status:"
    pgrep -f "core.py" >/dev/null && echo "✅ Bot process running" || echo "❌ Bot process not found"
    pgrep -f "chrome" >/dev/null && echo "✅ Chrome running" || echo "❌ Chrome not running"
    pgrep -f "Xvnc" >/dev/null && echo "✅ VNC server running" || echo "❌ VNC server not running"
    echo ""
    
    # Recent logs
    echo "📝 Recent Logs:"
    tail -n 5 /tmp/bot.log 2>/dev/null || echo "No logs found"
    echo ""
    
    # Resource usage
    echo "💾 Resource Usage:"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
    echo "Memory: $(free | grep Mem | awk '{printf("%.1f%%\n", $3/$2 * 100.0)}')"
    echo ""
    
    echo "Press Ctrl+C to exit monitoring..."
    sleep 10
done
EOF

RUN chmod +x /home/dockuser/bot/monitor.sh

# Create README with usage instructions
RUN cat > /home/dockuser/bot/README.md << 'EOF'
# Pocket Option Telegram Trading Bot

## Quick Start

### Using Docker (Recommended)

1. **Build and run:**
   ```bash
   docker-compose up -d
   ```

2. **Access interfaces:**
   - VNC Web Interface: http://localhost:6080
   - Health Check: http://localhost:6081/health

3. **View logs:**
   ```bash
   docker logs -f pocket-option-bot
   ```

### Local Installation

1. **Install dependencies:**
   ```bash
   pip3 install -r requirements.txt
   ```

2. **Configure environment:**
   ```bash
   cp .env.template .env
   # Edit .env with your credentials
   ```

3. **Run bot:**
   ```bash
   ./run.sh
   ```

## Configuration

Edit `.env` file with your credentials:
- Telegram API credentials
- Bot token and channel ID
- Trading parameters
- Pocket Option login details

## Monitoring

Use the monitoring dashboard:
```bash
./monitor.sh
```

## Manual Trading

Access the browser via VNC and complete the initial login:
1. Go to http://localhost:6080
2. Login to Pocket Option
3. The bot will handle subsequent trades

## Troubleshooting

- Check logs: `tail -f /tmp/bot.log`
- Health status: `curl http://localhost:6081/health`
- Restart services: `docker-compose restart`

## Features

- ✅ Telegram signal parsing
- ✅ Automated trade execution
- ✅ Martingale support
- ✅ Browser automation
- ✅ Health monitoring
- ✅ VNC remote access
- ✅ Docker deployment
EOF

# Expose ports
EXPOSE 5901 6080 6081

# Switch to non-root user
USER dockuser
WORKDIR /home/dockuser/bot

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:6081/health || exit 1

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/start.sh"]
