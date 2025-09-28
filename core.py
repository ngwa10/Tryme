#!/usr/bin/env python3
"""
Unified Core Logic for Pocket Option Telegram Trading Bot.
Combines bot orchestrator, trade manager, Telegram listener, health server, and
integrates with Selenium for trade result detection.
"""

import os
import sys
import time
import threading
import logging
import signal
import asyncio
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional, Dict, Any

# =========================
# HARD-CODED CREDENTIALS
# =========================
EMAIL = "mylivemyfuture@123gmail.com"
PASSWORD = "AaCcWw3468,"
TELEGRAM_API_ID = 29630724
TELEGRAM_API_HASH = "8e12421a95fd722246e0c0b194fd3e0c"
TELEGRAM_BOT_TOKEN = "8477806088:AAGEXpIAwN5tNQM0hsCGqP-otpLJjPJLmWA"
TELEGRAM_CHANNEL = "-1003033183667"
WEB_PORT = 8080
NOVNC_PORT = 6080
HEALTH_PORT = 6081
POST_LOGIN_WAIT = 180

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
# Health Check Server
# =========================
class HealthHandler(BaseHTTPRequestHandler):
    def __init__(self, trade_manager, *args, **kwargs):
        self.trade_manager = trade_manager
        super().__init__(*args, **kwargs)
        
    def do_GET(self):
        if self.path in ['/health', '/', '/status']:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            status = {
                "status": "healthy", 
                "bot": "running", 
                "trading_active": getattr(self.trade_manager, 'trading_active', False),
                "gui_available": getattr(self.trade_manager, 'gui_available', False),
                "selenium_available": getattr(self.trade_manager, 'selenium_available', False),
                "telegram_connected": getattr(self.trade_manager, 'telegram_connected', False),
                "timestamp": time.time()
            }
            
            response = str(status).replace("'", '"').replace("True", "true").replace("False", "false")
            self.wfile.write(response.encode())
        elif self.path == '/vnc.html':
            self.send_response(302)
            self.send_header('Location', f'http://localhost:{NOVNC_PORT}/vnc.html')
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()
            
    def log_message(self, format, *args):
        pass  # suppress logs

def create_health_handler(trade_manager):
    """Create health handler with trade manager reference"""
    class Handler(HealthHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(trade_manager, *args, **kwargs)
    return Handler

def start_health_server(trade_manager):
    try:
        logger.info(f"[🌐] Starting health server on port {HEALTH_PORT}")
        handler_class = create_health_handler(trade_manager)
        server = HTTPServer(('0.0.0.0', HEALTH_PORT), handler_class)
        server.serve_forever()
    except Exception as e:
        logger.error(f"[❌] Health server failed to start: {e}")

# =========================
# Environment Setup
# =========================
def setup_environment():
    """Setup X11, display and pyautogui environment"""
    os.environ.setdefault('DISPLAY', ':1')
    xauth_path = '/root/.Xauthority'
    
    if not os.path.exists(xauth_path):
        try:
            open(xauth_path, 'a').close()
            logger.info(f"[✅] Created {xauth_path} file")
        except Exception as e:
            logger.warning(f"[⚠️] Could not create {xauth_path}: {e}")
    
    os.environ['XAUTHORITY'] = xauth_path
    time.sleep(1)

# =========================
# Unified Trade Manager
# =========================
class UnifiedTradeManager:
    def __init__(self, base_amount: float = 1.0, max_martingale: int = 2):
        self.trading_active = False
        self.base_amount = base_amount
        self.max_martingale = max_martingale
        self.current_martingale_count = 0
        self.current_pair = None
        self.active_trades = {}
        
        # Component availability flags
        self.gui_available = False
        self.selenium_available = False
        self.telegram_connected = False
        
        # Initialize components
        self._init_gui()
        self._init_selenium()
        
    def _init_gui(self):
        """Initialize GUI automation"""
        try:
            import pyautogui
            pyautogui.FAILSAFE = True
            pyautogui.PAUSE = 0.1
            pyautogui.size()  # test display access
            self.pyautogui = pyautogui
            self.gui_available = True
            logger.info("[✅] pyautogui loaded and display accessible")
        except Exception as e:
            self.pyautogui = None
            self.gui_available = False
            logger.warning(f"[⚠️] pyautogui not available: {e}")
    
    def _init_selenium(self):
        """Initialize Selenium driver if available"""
        try:
            from selenium_integration import setup_driver, start_result_monitor
            self.selenium_driver = None  # Will be set up when needed
            self.setup_driver = setup_driver
            self.start_result_monitor = start_result_monitor
            self.selenium_available = True
            logger.info("[✅] Selenium integration available")
        except Exception as e:
            self.selenium_available = False
            logger.warning(f"[⚠️] Selenium integration not available: {e}")
    
    def setup_selenium_monitoring(self):
        """Setup Selenium for trade result monitoring"""
        if not self.selenium_available:
            return
            
        try:
            if not self.selenium_driver:
                self.selenium_driver = self.setup_driver(headless=False)
                logger.info("[🌐] Selenium driver initialized")
            
            # Start monitoring trade results
            self.start_result_monitor(self.selenium_driver, self.handle_trade_result)
            logger.info("[👁️] Started Selenium trade result monitoring")
            
        except Exception as e:
            logger.error(f"[❌] Failed to setup Selenium monitoring: {e}")
    
    def handle_trade_result(self, result):
        """Handle trade result from Selenium monitoring"""
        logger.info(f"[📊] Trade result detected: {result}")
        
        if result == "WIN":
            # Stop any pending martingale trades
            self.current_martingale_count = 0
            logger.info("[✅] Trade won - stopping martingale sequence")
            
        elif result == "LOSS":
            # Continue with martingale if within limits
            if self.current_martingale_count < self.max_martingale:
                logger.info(f"[🔄] Trade lost - martingale level {self.current_martingale_count + 1}")
            else:
                logger.info("[❌] Max martingale reached - sequence complete")
                self.current_martingale_count = 0

    def wait_until_entry_time(self, entry_time_str: str):
        """Wait until the specified entry time"""
        try:
            # Handle timezone conversion if needed
            if hasattr(self, 'signal_timezone') and self.signal_timezone == "OTC-4":
                fmt = "%H:%M:%S" if len(entry_time_str.split(":")) == 3 else "%H:%M"
                dt = datetime.strptime(entry_time_str, fmt)
                dt += timedelta(hours=1)  # Convert OTC-4 to OTC-3
                entry_time_str = dt.strftime(fmt)
            
            # Parse time and wait
            now = datetime.now()
            time_parts = entry_time_str.split(':')
            hour, minute = int(time_parts[0]), int(time_parts[1])
            second = int(time_parts[2]) if len(time_parts) == 3 else 0
            
            target_time = now.replace(hour=hour, minute=minute, second=second, microsecond=0)
            
            # If time has passed today, assume tomorrow
            if target_time <= now:
                target_time += timedelta(days=1)
            
            wait_seconds = (target_time - now).total_seconds()
            
            if wait_seconds > 0:
                logger.info(f"[⏰] Waiting {wait_seconds:.1f}s until {entry_time_str}")
                time.sleep(wait_seconds)
                
        except Exception as e:
            logger.error(f"[❌] Error waiting for entry time: {e}")

    def handle_signal(self, signal: Dict[str, Any]):
        """Handle incoming trading signal from Telegram"""
        if not self.trading_active:
            logger.info("[🚫] Trading inactive, ignoring signal")
            return

        logger.info(f"[📈] Processing signal: {signal}")
        
        # Store signal info for timezone handling
        self.signal_timezone = signal.get("timezone", "OTC-3")
        
        # Handle main entry
        entry_time = signal.get("entry_time")
        if entry_time:
            self.schedule_trade(
                entry_time, 
                signal.get("direction", "BUY"), 
                self.base_amount, 
                0
            )

        # Handle martingale entries
        martingale_times = signal.get("martingale_times", [])
        for i, mg_time in enumerate(martingale_times[:self.max_martingale]):
            mg_amount = self.base_amount * (2 ** (i + 1))
            self.schedule_trade(mg_time, signal.get("direction", "BUY"), mg_amount, i + 1)

    def schedule_trade(self, entry_time: str, direction: str, amount: float, martingale_level: int):
        """Schedule a trade for execution"""
        def execute_trade():
            try:
                # Wait for entry time
                self.wait_until_entry_time(entry_time)
                
                # Check if we should still execute (martingale logic)
                if martingale_level > 0 and self.current_martingale_count == 0:
                    logger.info(f"[⏭️] Skipping martingale level {martingale_level} - previous trade won")
                    return
                
                # Place the trade
                success = self.place_trade(amount, direction)
                
                if success:
                    trade_id = f"{int(time.time())}_{martingale_level}"
                    self.active_trades[trade_id] = {
                        "time": entry_time,
                        "direction": direction,
                        "amount": amount,
                        "level": martingale_level
                    }
                    
                    if martingale_level > 0:
                        self.current_martingale_count = martingale_level
                        
                    logger.info(f"[💹] Trade executed: {direction} ${amount} (Level: {martingale_level})")
                else:
                    logger.error(f"[❌] Failed to execute trade")
                    
            except Exception as e:
                logger.error(f"[❌] Trade execution error: {e}")
        
        threading.Thread(target=execute_trade, daemon=True).start()

    def place_trade(self, amount: float, direction: str = "BUY") -> bool:
        """Place trade using GUI automation"""
        if not self.gui_available:
            logger.warning("[⚠️] GUI not available, simulating trade")
            return True
            
        try:
            # Use keyboard shortcuts based on your original logic
            if direction.upper() == "BUY":
                self.pyautogui.keyDown('shift')
                self.pyautogui.press('w')
                self.pyautogui.keyUp('shift')
            elif direction.upper() == "SELL":
                self.pyautogui.keyDown('shift')
                self.pyautogui.press('s')
                self.pyautogui.keyUp('shift')
            
            return True
            
        except Exception as e:
            logger.error(f"[❌] GUI automation failed: {e}")
            return False

    def handle_command(self, command: str):
        """Handle Telegram commands"""
        cmd = command.strip().lower()
        
        if cmd.startswith("/start"):
            self.trading_active = True
            logger.info("[🟢] Trading activated")
            
            # Setup Selenium monitoring when trading starts
            if self.selenium_available and not self.selenium_driver:
                threading.Thread(target=self.setup_selenium_monitoring, daemon=True).start()
                
        elif cmd.startswith("/stop"):
            self.trading_active = False
            logger.info("[🔴] Trading deactivated")
            
        elif cmd.startswith("/status"):
            status = "ACTIVE" if self.trading_active else "INACTIVE"
            active_count = len(self.active_trades)
            logger.info(f"[🤖] Bot Status: {status}, Active Trades: {active_count}")
            
        else:
            logger.info(f"[💻] Command received: {command}")

    def set_telegram_status(self, connected: bool):
        """Update Telegram connection status"""
        self.telegram_connected = connected

# =========================
# Signal Handlers for graceful shutdown
# =========================
def setup_signal_handlers():
    def signal_handler(signum, frame):
        logger.info("[✋] Shutting down gracefully...")
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

# =========================
# Main Application
# =========================
def main():
    logger.info("[🚀] Starting Unified Trading Bot Core")
    
    # Setup environment and signal handlers
    setup_environment()
    setup_signal_handlers()
    
    # Initialize trade manager
    trade_manager = UnifiedTradeManager(base_amount=1.0, max_martingale=2)
    
    # Start health server
    threading.Thread(
        target=start_health_server, 
        args=(trade_manager,), 
        daemon=True
    ).start()
    logger.info(f"[🌐] Health server started on port {HEALTH_PORT}")
    
    # Wait a bit for services to initialize
    time.sleep(5)
    
    # Start Telegram listener if available
    try:
        from telegram_integration import start_telegram_listener
        
        def telegram_wrapper():
            try:
                trade_manager.set_telegram_status(True)
                start_telegram_listener(
                    trade_manager.handle_signal, 
                    trade_manager.handle_command
                )
            except Exception as e:
                logger.error(f"[❌] Telegram listener failed: {e}")
                trade_manager.set_telegram_status(False)
        
        threading.Thread(target=telegram_wrapper, daemon=True).start()
        logger.info("[📱] Telegram listener thread started")
        
    except ImportError as e:
        logger.warning(f"[⚠️] Telegram integration not available: {e}")
    
    # Main loop
    logger.info("[✅] All systems operational!")
    logger.info(f"[📊] GUI Available: {trade_manager.gui_available}")
    logger.info(f"[📊] Selenium Available: {trade_manager.selenium_available}")
    logger.info(f"[📊] Health endpoint: http://localhost:{HEALTH_PORT}/health")
    
    try:
        while True:
            time.sleep(30)
            # Periodic status log
            active_trades = len(trade_manager.active_trades)
            if active_trades > 0:
                logger.debug(f"[📊] Active trades: {active_trades}")
                
    except KeyboardInterrupt:
        logger.info("[👋] Received shutdown signal")
    except Exception as e:
        logger.error(f"[❌] Unexpected error in main loop: {e}")

if __name__ == "__main__":
    main()
