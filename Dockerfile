# Optimized Dockerfile for Zeabur deployment
FROM python:3.11-slim-bullseye

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NO_VNC_HOME=/opt/noVNC

# Install system dependencies in stages to reduce build time
# Combine apt-get commands to reduce image layers
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    gnupg2 \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add Chrome repository and install Chrome
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

# Install Chrome and jq (for parsing JSON)
RUN apt-get update && apt-get install -y --no-install-recommends \
    google-chrome-stable \
    jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install minimal dependencies for VNC and automation
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    fluxbox \
    git \
    procps \
    net-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install ChromeDriver using the new "Chrome for Testing" API
RUN CHROME_MAJOR_VERSION=$(google-chrome --version | sed 's/Google Chrome [^0-9]*//g' | cut -d'.' -f1) \
    && CHROMEDRIVER_VERSION=$(curl -s "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-json" | jq -r '.channels.Stable.version') \
    && wget -q -O /tmp/chromedriver.zip "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/${CHROMEDRIVER_VERSION}/linux64/chromedriver-linux64.zip" \
    && unzip -q /tmp/chromedriver.zip -d /tmp/ \
    && mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver \
    && chmod +x /usr/local/bin/chromedriver \
    && rm -rf /tmp/chromedriver.zip /tmp/chromedriver-linux64

# Install noVNC
RUN git clone --depth 1 --branch v1.4.0 https://github.com/novnc/noVNC.git ${NO_VNC_HOME} \
    && git clone --depth 1 https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify \
    && chmod +x ${NO_VNC_HOME}/utils/websockify/run

# Create user and directories
RUN useradd -m -s /bin/bash -u 1000 botuser \
    && mkdir -p /home/botuser/app /home/botuser/.chrome /tmp/logs \
    && chown -R botuser:botuser /home/botuser /tmp/logs

# Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Copy application files
COPY --chown=botuser:botuser core.py /home/botuser/app/
COPY --chown=botuser:botuser telegram_integration.py /home/botuser/app/
COPY --chown=botuser:botuser selenium_integration.py /home/botuser/app/
COPY --chown=botuser:botuser healthcheck.sh /home/botuser/app/

# Create optimized startup script
RUN cat > /home/botuser/app/start.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting Pocket Option Bot..."

# Set up display
export DISPLAY=:1
export CHROME_USER_DATA_DIR=/home/botuser/.chrome

# Start Xvfb (virtual display)
echo "🖥️  Starting virtual display..."
Xvfb :1 -screen 0 1280x800x24 -ac +extension GLX +render -noreset &
sleep 2

# Start VNC server
echo "📡 Starting VNC server..."
x11vnc -display :1 -nopw -listen localhost -xkb -ncache 10 -ncache_cr -forever &
sleep 1

# Start noVNC
echo "🌐 Starting web interface..."
cd ${NO_VNC_HOME}
${NO_VNC_HOME}/utils/websockify/run 6080 localhost:5900 --web ${NO_VNC_HOME} &
sleep 2

# Start window manager
echo "🪟 Starting window manager..."
DISPLAY=:1 fluxbox &
sleep 1

# Start Chrome browser
echo "🌍 Starting Chrome..."
DISPLAY=:1 google-chrome-stable \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --user-data-dir=/home/botuser/.chrome \
    --remote-debugging-port=9222 \
    --start-maximized \
    --disable-web-security \
    --disable-features=VizDisplayCompositor \
    "https://pocketoption.com/login" &

# Wait for Chrome to start
sleep 5

# Start the trading bot
echo "🤖 Starting trading bot..."
cd /home/botuser/app
exec python3 core.py
EOF

RUN chmod +x /home/botuser/app/start.sh \
    && chmod +x /home/botuser/app/healthcheck.sh

# Create simple health check
RUN cat > /usr/local/bin/health.sh << 'EOF'
#!/bin/bash
if pgrep -f "python.*core.py" > /dev/null && \
   pgrep -f "chrome" > /dev/null && \
   pgrep -f "Xvfb" > /dev/null; then
    echo "Services running"
    exit 0
else
    echo "Services not running"
    exit 1
fi
EOF

RUN chmod +x /usr/local/bin/health.sh

# Switch to user
USER botuser
WORKDIR /home/botuser/app

# Expose ports
EXPOSE 6080 6081 5900

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/health.sh

# Start the application
CMD ["./start.sh"]
