# Optimized Dockerfile for Zeabur deployment
# Using python:3.11-slim-bullseye as it is a smaller, more focused base image for Python apps.
FROM python:3.11-slim-bullseye

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NO_VNC_HOME=/opt/noVNC \
    VNC_RESOLUTION=1280x800

# Install core dependencies for Chrome, Python, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates gnupg2 jq \
    git procps net-tools dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Install Chrome (re-using the reliable installation steps)
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install minimal XFCE for VNC, based on the working Dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    tigervnc-standalone-server \
    xfce4-session xfce4-panel \
    xfce4-terminal \
    dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

# Install ChromeDriver using the robust retry logic
RUN CHROME_MAJOR_VERSION=$(google-chrome --version | sed 's/Google Chrome [^0-9]*//g' | cut -d'.' -f1) \
    && for i in $(seq 1 5); do \
        JSON_RESPONSE=$(curl -s "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-json"); \
        if echo "${JSON_RESPONSE}" | jq . >/dev/null 2>&1; then \
            CHROMEDRIVER_VERSION=$(echo "${JSON_RESPONSE}" | jq -r '.channels.Stable.version'); \
            if [ -n "$CHROMEDRIVER_VERSION" ] && [ "$CHROMEDRIVER_VERSION" != "null" ]; then \
                echo "Found ChromeDriver version: $CHROMEDRIVER_VERSION. Attempting download."; \
                wget -q -O /tmp/chromedriver.zip "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/${CHROMEDRIVER_VERSION}/linux64/chromedriver-linux64.zip"; \
                if [ -f /tmp/chromedriver.zip ]; then \
                    echo "Download successful."; \
                    unzip -q /tmp/chromedriver.zip -d /tmp/; \
                    mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver; \
                    chmod +x /usr/local/bin/chromedriver; \
                    rm -rf /tmp/chromedriver.zip /tmp/chromedriver-linux64; \
                    break; \
                else \
                    echo "Download failed. Retrying..."; \
                fi; \
            else \
                echo "Failed to get ChromeDriver version from JSON. Retrying in 2 seconds..."; \
                sleep 2; \
            fi; \
        else \
            echo "curl did not return valid JSON. Retrying in 2 seconds..."; \
            sleep 2; \
        fi; \
    done \
    && if [ ! -f /usr/local/bin/chromedriver ]; then \
        echo "Failed to install ChromeDriver after multiple retries. Exiting."; \
        exit 1; \
    fi

# Install noVNC
RUN git clone --depth 1 --branch v1.4.0 https://github.com/novnc/noVNC.git ${NO_VNC_HOME} \
    && git clone --depth 1 https://github.com/novnc/websockify.git ${NO_VNC_HOME}/utils/websockify \
    && chmod +x ${NO_VNC_HOME}/utils/websockify/run

# Create user and directories
RUN useradd -m -s /bin/bash -u 1000 dockuser \
    && mkdir -p /home/dockuser/app /home/dockuser/chrome-profile /home/dockuser/.vnc /tmp/logs \
    && chown -R dockuser:dockuser /home/dockuser

# Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Copy application files
COPY --chown=dockuser:dockuser core.py /home/dockuser/app/
COPY --chown=dockuser:dockuser telegram_integration.py /home/dockuser/app/
COPY --chown=dockuser:dockuser selenium_integration.py /home/dockuser/app/
COPY --chown=dockuser:dockuser healthcheck.sh /home/dockuser/app/

# Create custom XFCE start script for VNC
RUN cat > /home/dockuser/startxfce4.sh << 'EOF'
#!/bin/bash
/bin/sh /etc/xdg/xfce4/xinitrc
EOF
RUN chmod +x /home/dockuser/startxfce4.sh

# Copy start script
COPY start.sh /usr/local/bin/start.sh
RUN dos2unix /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

# Create simple health check
RUN cat > /usr/local/bin/health.sh << 'EOF'
#!/bin/bash
if pgrep -f "python.*core.py" > /dev/null && \
   pgrep -f "chrome" > /dev/null && \
   pgrep -f "Xvnc" > /dev/null; then
    echo "Services running"
    exit 0
else
    echo "Services not running"
    exit 1
fi
EOF

RUN chmod +x /usr/local/bin/health.sh

EXPOSE 5901 6080

USER dockuser
WORKDIR /home/dockuser/app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/health.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
