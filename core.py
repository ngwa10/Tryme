#!/usr/bin/env python3
"""
Integrated Pocket Option Telegram Trading Bot
Combines all functionality: Telegram listener, trade manager, health server, and GUI automation
"""

import os
import sys
import time
import threading
import logging
import signal
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional, Dict, Any
import re

# =========================
# ENVIRONMENT VARIABLES
# =========================
EMAIL = os.getenv("BOT_EMAIL", "mylivemyfuture@123gmail.com")
PASSWORD = os.getenv("BOT_PASSWORD", "AaCcWw3468,")
TELEGRAM_API_ID = int(os.getenv("TELEGRAM_API_ID", "29630724"))
TELEGRAM_API_HASH = os.getenv("TELEGRAM_API_HASH", "8e12421a95fd722246e0c0b194fd3e0c")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "8477806088:AAGEXpIAwN5tNQM0hsCGqP-otpLJjPJLmWA")
TELEGRAM_CHANNEL = os.getenv("TELEGRAM_CHANNEL", "-1003033183667")
WEB_PORT = int(os.getenv("WEB_PORT", "8080"))
NOVNC_PORT = int(os.getenv("NOVNC_PORT", "6080"))
HEALTH_PORT = int(os.getenv("HEALTH_PORT", "6081"))
BASE_TRADE_AMOUNT = float(os.getenv("BASE_TRADE_AMOUNT", "1.0"))
MAX_MARTINGALE = int(os.getenv("MAX_MARTINGALE", "2"))

# =========================
# Logging Setup
# =========================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/bot.log')
    ]
)
logger = logging.getLogger(__name__)

# =========================
# Display and GUI Setup
# =========================
os.environ.setdefault('DISPLAY', ':1')
os.environ['XAUTHORITY'] = '/root/.Xauthority'

# Try to import GUI automation libraries
try:
    import pyautogui
    pyautogui.FAILSAFE = True
    pyautogui.PAUSE = 0.1
    pyautogui.size()  # Test display access
    logger.info("[✅] pyautogui loaded and display accessible")
except Exception as e:
    pyautogui = None
    logger.warning(f"[⚠️] pyautogui not available: {e}")

# Try to import Telegram libraries
try:
    from telethon import TelegramClient, events
    telegram_available = True
    logger.info("[✅] Telegram libraries loaded")
except Exception as e:
    telegram_available = False
    logger.warning(f"[⚠️] Telegram libraries not available: {e}")

# Try to import Selenium
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.by import By
    selenium_available = True
    logger.info("[✅] Selenium libraries loaded")
except Exception as e:
    selenium_available = False
    logger.warning(f"[⚠️] Selenium not available: {e}")

# =========================
# POCKET OPTION LOGIN FEATURE (NEW)
# =========================
def launch_pocketoption_and_autofill():
    """Launch Chrome, navigate to Pocket Option login and autofill credentials."""
    if not selenium_available:
        logger.warning("[⚠️] Selenium not available, cannot auto-launch Pocket Option login.")
        return
    try:
        chrome_options = Options()
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--start-maximized")
        chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
        chrome_options.add_experimental_option('useAutomationExtension', False)
        chrome_options.add_argument("--user-data-dir=/home/dockuser/chrome-profile")
        # NOT headless so you can interact
        service = Service("/usr/local/bin/chromedriver")
        driver = webdriver.Chrome(service=service, options=chrome_options)
        logger.info("[🌐] Chrome launched for Pocket Option login.")

        # Go to the Pocket Option login page
        driver.get("https://pocketoption.com/login")
        logger.info("[🌐] Navigated to https://pocketoption.com/login")

        # Wait for email and password fields to load
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC

        wait = WebDriverWait(driver, 20)
        email_input = wait.until(EC.presence_of_element_located((By.NAME, "email")))
        password_input = wait.until(EC.presence_of_element_located((By.NAME, "password")))

        # Autofill email and password
        email_input.clear()
        email_input.send_keys(EMAIL)
        logger.info("[✍️] Email autofilled.")
        password_input.clear()
        password_input.send_keys(PASSWORD)
        logger.info("[✍️] Password autofilled.")

        logger.info("[⏸️] Please click the Login button manually in the opened Chrome window.")
        # Do not click login, leave for user interaction

    except Exception as e:
        logger.error(f"[❌] Could not launch or autofill Pocket Option login: {e}")

# =========================
# Health Check Server
# =========================
class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ['/health', '/', '/status']:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            status_data = {
                "status": "healthy",
                "bot": "running",
                "timestamp": time.time(),
                "services": {
                    "pyautogui": pyautogui is not None,
                    "telegram": telegram_available,
                    "selenium": selenium_available,
                    "trading_active": getattr(trade_manager, 'trading_active', False) if 'trade_manager' in globals() else False
                }
            }
            response = str(status_data).replace("'", '"')
            self.wfile.write(response.encode())
        elif self.path == '/vnc':
            self.send_response(302)
            self.send_header('Location', f'http://localhost:{NOVNC_PORT}/vnc.html')
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress HTTP logs

def start_health_server():
    """Start health check HTTP server"""
    try:
        logger.info(f"[🏥] Starting health server on port {HEALTH_PORT}")
        server = HTTPServer(('0.0.0.0', HEALTH_PORT), HealthHandler)
        server.serve_forever()
    except Exception as e:
        logger.error(f"[❌] Health server failed to start: {e}")

# =========================
# Signal Parser
# =========================
def parse_signal(message_text):
    """
    Parse trading signals from Telegram message text
    Returns dictionary with parsed signal data
    """
    result = {
        "currency_pair": None,
        "direction": None,
        "entry_time": None,
        "timeframe": None,
        "martingale_times": []
    }

    # Currency pair parsing
    pair_match = re.search(r'(?:Pair:|CURRENCY PAIR:|🇺🇸|📊)\s*([\w\/\-]+)', message_text)
    if pair_match:
        result['currency_pair'] = pair_match.group(1).strip()

    # Direction parsing
    direction_match = re.search(r'(BUY|SELL|CALL|PUT|🔼|🟥|🟩)', message_text, re.IGNORECASE)
    if direction_match:
        direction = direction_match.group(1).upper()
        if direction in ['CALL', 'BUY', '🟩', '🔼']:
            result['direction'] = 'BUY'
        else:
            result['direction'] = 'SELL'

    # Entry time parsing
    entry_time_match = re.search(r'(?:Entry Time:|Entry at|TIME \(UTC-03:00\):)\s*(\d{2}:\d{2}(?::\d{2})?)', message_text)
    if entry_time_match:
        result['entry_time'] = entry_time_match.group(1)

    # Timeframe parsing
    timeframe_match = re.search(r'Expiration:?\s*(M1|M5|1 Minute|5 Minute)', message_text)
    if timeframe_match:
        tf = timeframe_match.group(1)
        result['timeframe'] = 'M1' if tf in ['M1', '1 Minute'] else 'M5'

    # Martingale times parsing
    martingale_matches = re.findall(r'(?:Level \d+|level(?: at)?|PROTECTION).*?\s*(\d{2}:\d{2})', message_text)
    result['martingale_times'] = martingale_matches

    # Default Anna signals martingale logic
    if "anna signals" in message_text.lower() and not result['martingale_times'] and result['entry_time']:
        try:
            fmt = "%H:%M:%S" if len(result['entry_time'].split(':')) == 3 else "%H:%M"
            entry_dt = datetime.strptime(result['entry_time'], fmt)
            interval = 1 if result['timeframe'] == "M1" else 5
            result['martingale_times'] = [
                (entry_dt + timedelta(minutes=interval * i)).strftime(fmt)
                for i in range(1, 3)
            ]
            logger.info(f"[🔁] Default Anna martingale times applied: {result['martingale_times']}")
        except Exception as e:
            logger.warning(f"[⚠️] Error calculating martingale times: {e}")

    return result

# =========================
# Telegram Integration
# =========================
class TelegramManager:
    def __init__(self):
        self.client = None
        self.channel_entity = None
        
    async def setup(self):
        """Initialize Telegram client and resolve channel"""
        if not telegram_available:
            logger.warning("[⚠️] Telegram not available, skipping setup")
            return False
            
        try:
            self.client = TelegramClient('bot_session', TELEGRAM_API_ID, TELEGRAM_API_HASH)
            await self.client.start(bot_token=TELEGRAM_BOT_TOKEN)
            
            # Resolve channel
            if TELEGRAM_CHANNEL.startswith("-100") or TELEGRAM_CHANNEL.lstrip("-").isdigit():
                self.channel_entity = await self.client.get_entity(int(TELEGRAM_CHANNEL))
            else:
                self.channel_entity = await self.client.get_entity(TELEGRAM_CHANNEL)
                
            logger.info(f"[✅] Telegram connected. Channel: {getattr(self.channel_entity, 'title', TELEGRAM_CHANNEL)}")
            return True
        except Exception as e:
            logger.error(f"[❌] Telegram setup failed: {e}")
            return False

    def start_listener(self, signal_callback, command_callback):
        """Start Telegram message listener"""
        if not telegram_available or not self.client:
            logger.warning("[⚠️] Telegram listener not available")
            return

        @self.client.on(events.NewMessage())
        async def handler(event):
            # Only process messages from target channel
            target_id = getattr(self.channel_entity, 'id', None)
            if event.chat_id != target_id:
                return

            text = event.message.message
            logger.info(f"[📩] New message received: {text[:100]}...")

            if text.startswith("/start") or text.startswith("/stop"):
                logger.info(f"[💻] Command detected: {text}")
                await command_callback(text)
            else:
                signal = parse_signal(text)
                if signal['currency_pair'] and signal['entry_time']:
                    logger.info(f"[⚡] Parsed signal: {signal}")
                    await signal_callback(signal)

        try:
            logger.info("[✅] Telegram listener started")
            self.client.run_until_disconnected()
        except Exception as e:
            logger.error(f"[❌] Telegram listener failed: {e}")

# =========================
# Selenium Manager
# =========================
class SeleniumManager:
    def __init__(self):
        self.driver = None
        
    def setup_driver(self, headless=False):
        """Initialize Chrome WebDriver"""
        if not selenium_available:
            logger.warning("[⚠️] Selenium not available")
            return None
            
        try:
            chrome_options = Options()
            chrome_options.add_argument("--no-sandbox")
            chrome_options.add_argument("--disable-dev-shm-usage")
            chrome_options.add_argument("--disable-gpu")
            chrome_options.add_argument("--start-maximized")
            chrome_options.add_argument("--disable-blink-features=AutomationControlled")
            chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
            chrome_options.add_experimental_option('useAutomationExtension', False)
            chrome_options.add_argument("--user-data-dir=/home/dockuser/chrome-profile")
            
            if headless:
                chrome_options.add_argument("--headless=new")
            
            service = Service("/usr/local/bin/chromedriver")
            self.driver = webdriver.Chrome(service=service, options=chrome_options)
            logger.info("[✅] Selenium WebDriver initialized")
            return self.driver
        except Exception as e:
            logger.warning(f"[⚠️] Selenium setup failed: {e}")
            return None

    def detect_trade_result(self):
        """Monitor trade results"""
        if not self.driver:
            return None
            
        try:
            # This is a placeholder - adjust selectors based on actual Pocket Option UI
            result_elements = self.driver.find_elements(By.CSS_SELECTOR, ".trade-history .trade-result")
            for elem in result_elements:
                text = elem.text.strip()
                if text.startswith("+"):
                    return "WIN"
                elif text == "$0":
                    return "LOSS"
        except Exception as e:
            logger.warning(f"[⚠️] Error detecting trade result: {e}")
        return None

# =========================
# Trade Manager
# =========================
class TradeManager:
    def __init__(self, base_amount=BASE_TRADE_AMOUNT, max_martingale=MAX_MARTINGALE):
        self.trading_active = False
        self.base_amount = base_amount
        self.max_martingale = max_martingale
        self.current_trades = {}
        self.selenium_manager = SeleniumManager()
        
    async def handle_command(self, command: str):
        """Handle Telegram bot commands"""
        cmd = command.strip().lower()
        if cmd.startswith("/start"):
            self.trading_active = True
            logger.info("[▶️] Trading activated")
        elif cmd.startswith("/stop"):
            self.trading_active = False
            logger.info("[⏹️] Trading deactivated")

    async def handle_signal(self, signal: Dict[str, Any]):
        """Process incoming trading signals"""
        if not self.trading_active:
            logger.info("[⏸️] Trading inactive, ignoring signal")
            return

        logger.info(f"[📈] Processing signal: {signal}")
        
        # Adjust timezone if needed
        entry_time = signal.get("entry_time")
        if signal.get("timezone", "UTC-3") == "UTC-4":
            try:
                fmt = "%H:%M:%S" if len(entry_time.split(":")) == 3 else "%H:%M"
                dt = datetime.strptime(entry_time, fmt)
                dt += timedelta(hours=1)
                entry_time = dt.strftime(fmt)
                signal['entry_time'] = entry_time
            except Exception as e:
                logger.warning(f"[⚠️] Timezone adjustment failed: {e}")

        # Schedule primary trade
        if entry_time:
            self.schedule_trade(entry_time, signal.get("direction", "BUY"), self.base_amount, 0)

        # Schedule martingale trades
        for i, mg_time in enumerate(signal.get("martingale_times", []) or []):
            if i + 1 > self.max_martingale:
                break
            mg_amount = self.base_amount * (2 ** (i + 1))
            self.schedule_trade(mg_time, signal.get("direction", "BUY"), mg_amount, i + 1)

    def schedule_trade(self, entry_time: str, direction: str, amount: float, martingale_level: int):
        """Schedule a trade for specific time"""
        def execute_trade():
            try:
                self.wait_until_time(entry_time)
                self.place_trade(amount, direction, martingale_level)
            except Exception as e:
                logger.error(f"[❌] Trade execution failed: {e}")
                
        threading.Thread(target=execute_trade, daemon=True).start()
        logger.info(f"[⏰] Scheduled trade: {direction} ${amount} at {entry_time} (level {martingale_level})")

    def wait_until_time(self, time_str: str):
        """Wait until specified time"""
        try:
            # Parse time string
            fmt = "%H:%M:%S" if len(time_str.split(":")) == 3 else "%H:%M"
            target_time = datetime.strptime(time_str, fmt).time()
            
            # Get current time
            now = datetime.now().time()
            
            # Calculate seconds until target time
            now_seconds = now.hour * 3600 + now.minute * 60 + now.second
            target_seconds = target_time.hour * 3600 + target_time.minute * 60 + target_time.second
            
            # Handle next day case
            if target_seconds < now_seconds:
                target_seconds += 24 * 3600
                
            wait_seconds = target_seconds - now_seconds
            
            if wait_seconds > 0:
                logger.info(f"[⏳] Waiting {wait_seconds} seconds for trade execution...")
                time.sleep(wait_seconds)
                
        except Exception as e:
            logger.warning(f"[⚠️] Time parsing failed: {e}")

    def place_trade(self, amount: float, direction: str, martingale_level: int):
        """Execute trade using GUI automation"""
        if pyautogui is None:
            logger.warning("[⚠️] GUI automation not available")
            return

        try:
            logger.info(f"[💹] Placing trade: {direction} ${amount} (level {martingale_level})")
            
            # Use keyboard shortcuts for trading
            if direction.upper() == "BUY":
                pyautogui.keyDown('shift')
                pyautogui.press('w')
                pyautogui.keyUp('shift')
                logger.info("[🔼] BUY trade executed")
            elif direction.upper() == "SELL":
                pyautogui.keyDown('shift')
                pyautogui.press('s')
                pyautogui.keyUp('shift')
                logger.info("[🔽] SELL trade executed")
                
        except Exception as e:
            logger.error(f"[❌] Trade placement failed: {e}")

# =========================
# Signal Handlers
# =========================
def setup_signal_handlers():
    """Setup graceful shutdown handlers"""
    def signal_handler(signum, frame):
        logger.info("[✋] Received shutdown signal, exiting gracefully...")
        sys.exit(0)
        
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

# =========================
# Main Application
# =========================
async def start_telegram_service(trade_manager):
    """Start Telegram service"""
    telegram_manager = TelegramManager()
    if await telegram_manager.setup():
        telegram_manager.start_listener(
            trade_manager.handle_signal,
            trade_manager.handle_command
        )

def main():
    """Main application entry point"""
    logger.info("[🚀] Starting Pocket Option Trading Bot...")
    
    # Setup signal handlers
    setup_signal_handlers()
    
    # Start health server
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    logger.info("[✅] Health server started")
    
    # Initialize trade manager
    global trade_manager
    trade_manager = TradeManager()
    logger.info("[✅] Trade manager initialized")
    
    # Start Telegram service in separate thread
    if telegram_available:
        telegram_thread = threading.Thread(
            target=lambda: asyncio.run(start_telegram_service(trade_manager)),
            daemon=True
        )
        telegram_thread.start()
        logger.info("[✅] Telegram service thread started")
    
    # Keep main thread alive
    logger.info("[✅] Bot is running. Press Ctrl+C to stop.")
    try:
        while True:
            time.sleep(30)
            logger.debug("[💓] Bot heartbeat")
    except KeyboardInterrupt:
        logger.info("[✋] Bot stopped by user")
    except Exception as e:
        logger.error(f"[❌] Unexpected error: {e}")

if __name__ == "__main__":
    # Import asyncio here to handle potential import issues
    try:
        import asyncio
    except ImportError:
        logger.error("[❌] asyncio not available")
        sys.exit(1)

    # === CALL THE NEW FEATURE HERE ===
    launch_pocketoption_and_autofill()
    # ================================

    main()
