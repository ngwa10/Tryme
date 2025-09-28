"""
Selenium Integration Module
Handles browser automation for Pocket Option platform
Includes trade result detection and browser management
"""

import os
import time
import threading
import logging
from typing import Optional, Callable, Dict, Any

# Setup logging
logger = logging.getLogger(__name__)

# Configuration
CHECK_INTERVAL = 0.5  # Check trade results every 0.5 seconds
DRIVER_PATH = "/usr/local/bin/chromedriver"
CHROME_PROFILE_PATH = "/home/dockuser/chrome-profile"

# Try to import Selenium
try:
    from selenium import webdriver
    from selenium.webdriver.common.by import By
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.common.exceptions import TimeoutException, NoSuchElementException
    SELENIUM_AVAILABLE = True
    logger.info("[✅] Selenium imported successfully")
except ImportError as e:
    SELENIUM_AVAILABLE = False
    logger.warning(f"[⚠️] Selenium not available: {e}")


class BrowserManager:
    """
    Manages Chrome browser instance for Pocket Option automation
    """
    
    def __init__(self, headless: bool = False):
        self.driver = None
        self.headless = headless
        self.is_initialized = False
        self.monitoring_active = False
        
    def setup_driver(self) -> Optional[webdriver.Chrome]:
        """Initialize Chrome WebDriver with optimized settings"""
        if not SELENIUM_AVAILABLE:
            logger.error("[❌] Selenium not available")
            return None
            
        try:
            chrome_options = Options()
            
            # Basic Chrome options
            chrome_options.add_argument("--no-sandbox")
            chrome_options.add_argument("--disable-dev-shm-usage")
            chrome_options.add_argument("--disable-gpu")
            chrome_options.add_argument("--start-maximized")
            chrome_options.add_argument("--disable-web-security")
            chrome_options.add_argument("--allow-running-insecure-content")
            
            # Anti-detection options
            chrome_options.add_argument("--disable-blink-features=AutomationControlled")
            chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
            chrome_options.add_experimental_option('useAutomationExtension', False)
            
            # Profile and user data
            chrome_options.add_argument(f"--user-data-dir={CHROME_PROFILE_PATH}")
            
            # Headless mode if requested
            if self.headless:
                chrome_options.add_argument("--headless=new")
                
            # Display settings
            if os.getenv('DISPLAY'):
                chrome_options.add_argument(f"--display={os.getenv('DISPLAY')}")
            
            # Create service
            service = Service(DRIVER_PATH)
            
            # Initialize driver
            self.driver = webdriver.Chrome(service=service, options=chrome_options)
            
            # Set implicit wait
            self.driver.implicitly_wait(10)
            
            # Navigate to Pocket Option
            logger.info("[🌐] Navigating to Pocket Option...")
            self.driver.get("https://pocketoption.com/login")
            
            # Wait for page load
            WebDriverWait(self.driver, 30).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )
            
            logger.info("[✅] Chrome WebDriver initialized successfully")
            self.is_initialized = True
            return self.driver
            
        except Exception as e:
            logger.error(f"[❌] Failed to setup Chrome driver: {e}")
            if self.driver:
                self.driver.quit()
                self.driver = None
            return None
    
    def wait_for_login(self, timeout: int = 300) -> bool:
        """Wait for user to complete login process"""
        if not self.driver:
            return False
            
        try:
            logger.info("[⏳] Waiting for user login...")
            
            # Wait for login elements to disappear or trading interface to appear
            login_selectors = [
                "input[type='email']",
                "input[type='password']",
                ".login-form",
                "#login-form"
            ]
            
            trading_selectors = [
                ".trading-interface",
                ".chart-container",
                ".asset-select",
                "[data-testid='trading-panel']"
            ]
            
            start_time = time.time()
            while time.time() - start_time < timeout:
                # Check if still on login page
                login_elements = []
                for selector in login_selectors:
                    try:
                        elements = self.driver.find_elements(By.CSS_SELECTOR, selector)
                        login_elements.extend(elements)
                    except:
                        pass
                
                # Check if trading interface is visible
                trading_elements = []
                for selector in trading_selectors:
                    try:
                        elements = self.driver.find_elements(By.CSS_SELECTOR, selector)
                        trading_elements.extend([e for e in elements if e.is_displayed()])
                    except:
                        pass
                
                # If no login elements and trading elements present, login successful
                if not login_elements and trading_elements:
                    logger.info("[✅] Login completed successfully")
                    return True
                
                # Check URL for trading page
                current_url = self.driver.current_url.lower()
                if "trade" in current_url or "trading" in current_url:
                    logger.info("[✅] Login completed (URL check)")
                    return True
                
                time.sleep(2)
            
            logger.warning(f"[⚠️] Login timeout after {timeout} seconds")
            return False
            
        except Exception as e:
            logger.error(f"[❌] Error waiting for login: {e}")
            return False
    
    def detect_trade_result(self) -> Optional[str]:
        """
        Detect the result of the last trade
        Returns: 'WIN', 'LOSS', or None
        """
        if not self.driver:
            return None
            
        try:
            # Common selectors for trade results (adjust based on actual UI)
            result_selectors = [
                ".trade-result",
                ".trade-history-item:first-child",
                "[data-testid='trade-result']",
                ".history-item:first-child .profit",
                ".trades-history .trade:first-child .result"
            ]
            
            for selector in result_selectors:
                try:
                    elements = self.driver.find_elements(By.CSS_SELECTOR, selector)
                    for element in elements:
                        if not element.is_displayed():
                            continue
                            
                        text = element.text.strip()
                        
                        # Win indicators
                        if (text.startswith('+') or 
                            'win' in text.lower() or 
                            'profit' in text.lower()):
                            return "WIN"
                        
                        # Loss indicators  
                        if (text.startswith('-') or 
                            text == '$0' or 
                            'loss' in text.lower() or 
                            'lose' in text.lower()):
                            return "LOSS"
                            
                        # Color-based detection
                        color = element.value_of_css_property('color')
                        if 'rgb(0, 128, 0)' in color or 'green' in color.lower():
                            return "WIN"
                        elif 'rgb(255, 0, 0)' in color or 'red' in color.lower():
                            return "LOSS"
                            
                except Exception as e:
                    continue
            
            return None
            
        except Exception as e:
            logger.error(f"[❌] Error detecting trade result: {e}")
            return None
    
    def start_result_monitor(self, callback: Callable[[str], None]):
        """
        Start monitoring trade results in background thread
        Calls callback function when WIN or LOSS detected
        """
        if not self.driver:
            logger.error("[❌] Driver not initialized")
            return
            
        def monitor():
            self.monitoring_active = True
            logger.info("[👁️] Starting trade result monitoring...")
            
            last_result = None
            while self.monitoring_active:
                try:
                    result = self.detect_trade_result()
                    if result and result != last_result:
                        logger.info(f"[📊] Trade result detected: {result}")
                        callback(result)
                        last_result = result
                        
                    time.sleep(CHECK_INTERVAL)
                    
                except Exception as e:
                    logger.error(f"[❌] Monitor error: {e}")
                    time.sleep(CHECK_INTERVAL)
                    
            logger.info("[👁️] Trade result monitoring stopped")
        
        monitor_thread = threading.Thread(target=monitor, daemon=True)
        monitor_thread.start()
    
    def stop_monitoring(self):
        """Stop trade result monitoring"""
        self.monitoring_active = False
    
    def get_current_asset(self) -> Optional[str]:
        """Get currently selected trading asset"""
        if not self.driver:
            return None
            
        try:
            asset_selectors = [
                ".asset-select .current-asset",
                ".selected-asset",
                "[data-testid='current-asset']",
                ".asset-name"
            ]
            
            for selector in asset_selectors:
                try:
                    element = self.driver.find_element(By.CSS_SELECTOR, selector)
                    if element.is_displayed():
                        return element.text.strip()
                except:
                    continue
                    
            return None
            
        except Exception as e:
            logger.error(f"[❌] Error getting current asset: {e}")
            return None
    
    def set_trade_amount(self, amount: float) -> bool:
        """Set trade amount in the interface"""
        if not self.driver:
            return False
            
        try:
            amount_selectors = [
                "input[data-testid='amount-input']",
                ".amount-input input",
                "input.trade-amount",
                "#trade-amount"
            ]
            
            for selector in amount_selectors:
                try:
                    element = self.driver.find_element(By.CSS_SELECTOR, selector)
                    if element.is_displayed():
                        element.clear()
                        element.send_keys(str(amount))
                        logger.info(f"[💰] Trade amount set to ${amount}")
                        return True
                except:
                    continue
                    
            logger.warning("[⚠️] Could not find amount input field")
            return False
            
        except Exception as e:
            logger.error(f"[❌] Error setting trade amount: {e}")
            return False
    
    def take_screenshot(self, filename: str = None) -> str:
        """Take screenshot for debugging"""
        if not self.driver:
            return ""
            
        try:
            if not filename:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"/tmp/screenshot_{timestamp}.png"
                
            self.driver.save_screenshot(filename)
            logger.info(f"[📸] Screenshot saved: {filename}")
            return filename
            
        except Exception as e:
            logger.error(f"[❌] Error taking screenshot: {e}")
            return ""
    
    def cleanup(self):
        """Cleanup browser resources"""
        self.monitoring_active = False
        if self.driver:
            try:
                self.driver.quit()
                logger.info("[✅] Browser cleaned up")
            except:
                pass
            finally:
                self.driver = None
                self.is_initialized = False


# Legacy compatibility functions
def setup_driver(headless: bool = False) -> Optional[webdriver.Chrome]:
    """Legacy function for backward compatibility"""
    manager = BrowserManager(headless=headless)
    return manager.setup_driver()


def detect_trade_result(driver: webdriver.Chrome) -> Optional[str]:
    """Legacy function for backward compatibility"""
    if not driver:
        return None
        
    manager = BrowserManager()
    manager.driver = driver
    return manager.detect_trade_result()


def start_result_monitor(driver: webdriver.Chrome, callback: Callable[[str], None]):
    """Legacy function for backward compatibility"""
    if not driver:
        return
        
    manager = BrowserManager()
    manager.driver = driver
    manager.start_result_monitor(callback)


# Utility functions
def wait_for_element(driver: webdriver.Chrome, selector: str, timeout: int = 10):
    """Wait for element to be present and visible"""
    try:
        element = WebDriverWait(driver, timeout).until(
            EC.visibility_of_element_located((By.CSS_SELECTOR, selector))
        )
        return element
    except TimeoutException:
        return None


def click_element_safely(driver: webdriver.Chrome, selector: str) -> bool:
    """Safely click element with error handling"""
    try:
        element = wait_for_element(driver, selector)
        if element:
            element.click()
            return True
        return False
    except Exception as e:
        logger.error(f"[❌] Error clicking element {selector}: {e}")
        return False
