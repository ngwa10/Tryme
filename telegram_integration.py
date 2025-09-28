"""
Telegram Integration Module
Handles Telegram client connection, message parsing, and signal processing
Designed to work seamlessly with the core trading bot
"""

import os
import re
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, Callable

# Setup logging
logger = logging.getLogger(__name__)

# Environment variables
API_ID = int(os.getenv("TELEGRAM_API_ID", "29630724"))
API_HASH = os.getenv("TELEGRAM_API_HASH", "8e12421a95fd722246e0c0b194fd3e0c")
BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "8477806088:AAGEXpIAwN5tNQM0hsCGqP-otpLJjPJLmWA")
CHANNEL_ID = os.getenv("TELEGRAM_CHANNEL", "-1003033183667")

# Try to import Telegram libraries
try:
    from telethon import TelegramClient, events
    TELEGRAM_AVAILABLE = True
    logger.info("[✅] Telethon imported successfully")
except ImportError as e:
    TELEGRAM_AVAILABLE = False
    logger.warning(f"[⚠️] Telethon not available: {e}")

class TelegramService:
    """
    Telegram service for handling bot connections and message processing
    """
    
    def __init__(self):
        self.client = None
        self.channel_entity = None
        self.is_connected = False
        
    async def initialize(self) -> bool:
        """Initialize Telegram client and connect"""
        if not TELEGRAM_AVAILABLE:
            logger.error("[❌] Telegram libraries not available")
            return False
            
        try:
            # Create Telegram client
            self.client = TelegramClient('bot_session', API_ID, API_HASH)
            
            # Start client with bot token
            await self.client.start(bot_token=BOT_TOKEN)
            logger.info("[✅] Telegram client connected")
            
            # Resolve target channel
            await self._resolve_channel()
            
            self.is_connected = True
            return True
            
        except Exception as e:
            logger.error(f"[❌] Failed to initialize Telegram: {e}")
            return False
    
    async def _resolve_channel(self):
        """Resolve the target Telegram channel"""
        try:
            if CHANNEL_ID.startswith("-100") or CHANNEL_ID.lstrip("-").isdigit():
                self.channel_entity = await self.client.get_entity(int(CHANNEL_ID))
            else:
                self.channel_entity = await self.client.get_entity(CHANNEL_ID)
                
            channel_name = getattr(self.channel_entity, 'title', CHANNEL_ID)
            logger.info(f"[✅] Resolved channel: {channel_name}")
            
        except Exception as e:
            logger.error(f"[❌] Failed to resolve channel '{CHANNEL_ID}': {e}")
            raise
    
    def setup_handlers(self, signal_callback: Callable, command_callback: Callable):
        """Setup message event handlers"""
        if not self.client:
            logger.error("[❌] Client not initialized")
            return
            
        @self.client.on(events.NewMessage())
        async def message_handler(event):
            try:
                # Only process messages from target channel
                target_id = getattr(self.channel_entity, 'id', None)
                if event.chat_id != target_id:
                    return
                
                message_text = event.message.message
                logger.info(f"[📩] New message: {message_text[:100]}...")
                
                # Check if it's a command
                if message_text.startswith("/"):
                    logger.info(f"[💻] Command detected: {message_text}")
                    await command_callback(message_text)
                else:
                    # Parse as trading signal
                    signal = parse_trading_signal(message_text)
                    if signal and signal.get('currency_pair') and signal.get('entry_time'):
                        logger.info(f"[⚡] Valid signal parsed: {signal}")
                        await signal_callback(signal)
                    else:
                        logger.debug(f"[📝] Message not recognized as signal")
                        
            except Exception as e:
                logger.error(f"[❌] Error handling message: {e}")
    
    async def run(self):
        """Run the Telegram client"""
        if not self.is_connected:
            logger.error("[❌] Client not connected")
            return
            
        try:
            logger.info("[🔄] Starting Telegram listener...")
            await self.client.run_until_disconnected()
        except Exception as e:
            logger.error(f"[❌] Telegram client error: {e}")


def parse_trading_signal(message_text: str) -> Optional[Dict[str, Any]]:
    """
    Parse trading signal from message text
    Returns None if no valid signal found
    """
    signal = {
        "currency_pair": None,
        "direction": None,
        "entry_time": None,
        "timeframe": None,
        "martingale_times": [],
        "raw_message": message_text
    }
    
    try:
        # Extract currency pair
        pair_patterns = [
            r'(?:Pair:|CURRENCY PAIR:|🇺🇸|📊)\s*([\w\/\-]+)',
            r'(EUR\/USD|GBP\/USD|USD\/JPY|AUD\/USD|USD\/CAD|USD\/CHF)',
            r'([A-Z]{3}\/[A-Z]{3})',
        ]
        
        for pattern in pair_patterns:
            match = re.search(pattern, message_text, re.IGNORECASE)
            if match:
                signal['currency_pair'] = match.group(1).strip().upper()
                break
        
        # Extract direction
        direction_patterns = [
            (r'(BUY|CALL|🔼|🟩)', 'BUY'),
            (r'(SELL|PUT|🔽|🟥)', 'SELL'),
        ]
        
        for pattern, direction in direction_patterns:
            if re.search(pattern, message_text, re.IGNORECASE):
                signal['direction'] = direction
                break
        
        # Extract entry time
        time_patterns = [
            r'(?:Entry Time:|Entry at|TIME \(UTC-03:00\):)\s*(\d{1,2}:\d{2}(?::\d{2})?)',
            r'(?:Time:|At:)\s*(\d{1,2}:\d{2}(?::\d{2})?)',
            r'(\d{1,2}:\d{2}(?::\d{2})?)\s*(?:UTC|GMT)',
        ]
        
        for pattern in time_patterns:
            match = re.search(pattern, message_text)
            if match:
                signal['entry_time'] = match.group(1)
                break
        
        # Extract timeframe/expiration
        tf_patterns = [
            r'(?:Expiration:|Timeframe:|TF:)\s*(M1|M5|1\s*Min|5\s*Min)',
            r'(1|5)\s*(?:minute|min)',
        ]
        
        for pattern in tf_patterns:
            match = re.search(pattern, message_text, re.IGNORECASE)
            if match:
                tf = match.group(1).upper()
                if tf in ['M1', '1', '1MIN']:
                    signal['timeframe'] = 'M1'
                elif tf in ['M5', '5', '5MIN']:
                    signal['timeframe'] = 'M5'
                break
        
        # Extract martingale times
        mg_patterns = [
            r'(?:Level\s*\d+|Martingale|Protection).*?(\d{1,2}:\d{2}(?::\d{2})?)',
            r'(?:MG\s*\d+|Level\s*\d+).*?(\d{1,2}:\d{2}(?::\d{2})?)',
        ]
        
        martingale_times = []
        for pattern in mg_patterns:
            matches = re.findall(pattern, message_text, re.IGNORECASE)
            martingale_times.extend(matches)
        
        signal['martingale_times'] = list(dict.fromkeys(martingale_times))  # Remove duplicates
        
        # Generate default martingale times for Anna signals
        if ("anna" in message_text.lower() and 
            signal['entry_time'] and 
            not signal['martingale_times']):
            
            signal['martingale_times'] = generate_default_martingale_times(
                signal['entry_time'], 
                signal.get('timeframe', 'M5')
            )
            logger.info(f"[🔁] Generated default martingale times: {signal['martingale_times']}")
        
        # Validate signal
        if signal['currency_pair'] and signal['direction'] and signal['entry_time']:
            logger.info(f"[✅] Valid signal parsed for {signal['currency_pair']}")
            return signal
        else:
            logger.debug("[📝] Incomplete signal data")
            return None
            
    except Exception as e:
        logger.error(f"[❌] Error parsing signal: {e}")
        return None


def generate_default_martingale_times(entry_time: str, timeframe: str = 'M5') -> list:
    """Generate default martingale times based on entry time and timeframe"""
    try:
        # Parse entry time
        time_format = "%H:%M:%S" if len(entry_time.split(':')) == 3 else "%H:%M"
        entry_dt = datetime.strptime(entry_time, time_format)
        
        # Determine interval
        interval_minutes = 1 if timeframe == 'M1' else 5
        
        # Generate 2 martingale levels
        martingale_times = []
        for level in range(1, 3):  # Levels 1 and 2
            mg_time = entry_dt + timedelta(minutes=interval_minutes * level)
            martingale_times.append(mg_time.strftime(time_format))
        
        return martingale_times
        
    except Exception as e:
        logger.error(f"[❌] Error generating martingale times: {e}")
        return []


def format_signal_summary(signal: Dict[str, Any]) -> str:
    """Format signal data for logging/display"""
    if not signal:
        return "Invalid signal"
        
    summary = f"Signal: {signal.get('currency_pair', 'Unknown')} "
    summary += f"{signal.get('direction', 'Unknown')} "
    summary += f"at {signal.get('entry_time', 'Unknown')}"
    
    if signal.get('timeframe'):
        summary += f" ({signal['timeframe']})"
        
    if signal.get('martingale_times'):
        summary += f" | MG: {', '.join(signal['martingale_times'])}"
        
    return summary


# Legacy compatibility functions for backward compatibility with existing code
def start_telegram_listener(signal_callback: Callable, command_callback: Callable):
    """
    Legacy function for backward compatibility
    Starts Telegram listener with provided callbacks
    """
    import asyncio
    
    async def run_service():
        service = TelegramService()
        if await service.initialize():
            service.setup_handlers(signal_callback, command_callback)
            await service.run()
    
    try:
        asyncio.run(run_service())
    except Exception as e:
        logger.error(f"[❌] Telegram listener failed: {e}")


def parse_signal(message_text: str) -> Dict[str, Any]:
    """Legacy function for backward compatibility"""
    result = parse_trading_signal(message_text)
    if result is None:
        return {
            "currency_pair": None,
            "direction": None,
            "entry_time": None,
            "timeframe": None,
            "martingale_times": []
        }
    return result


# Additional utility functions for signal processing
def validate_signal_timing(signal: Dict[str, Any]) -> bool:
    """Validate if signal timing is reasonable (not too old)"""
    if not signal.get('entry_time'):
        return False
        
    try:
        time_format = "%H:%M:%S" if len(signal['entry_time'].split(':')) == 3 else "%H:%M"
        entry_dt = datetime.strptime(signal['entry_time'], time_format)
        current_time = datetime.now().time()
        
        # Convert to minutes for comparison
        entry_minutes = entry_dt.hour * 60 + entry_dt.minute
        current_minutes = current_time.hour * 60 + current_time.minute
        
        # Allow up to 2 minutes in the past or 10 minutes in the future
        time_diff = entry_minutes - current_minutes
        
        return -2 <= time_diff <= 10
        
    except Exception as e:
        logger.warning(f"[⚠️] Error validating signal timing: {e}")
        return True  # If we can't validate, assume it's okay


def extract_signal_confidence(message_text: str) -> Optional[str]:
    """Extract confidence level from signal message"""
    confidence_patterns = [
        r'(?:Confidence:|Accuracy:|Success Rate:)\s*(\d+%)',
        r'(\d+%)\s*(?:accuracy|confidence|success)',
        r'(?:HIGH|MEDIUM|LOW)\s*(?:CONFIDENCE|ACCURACY)',
    ]
    
    for pattern in confidence_patterns:
        match = re.search(pattern, message_text, re.IGNORECASE)
        if match:
            return match.group(1) if match.lastindex else match.group(0)
    
    return None


def is_signal_from_trusted_source(message_text: str) -> bool:
    """Check if signal is from a trusted/verified source"""
    trusted_indicators = [
        "anna signals",
        "verified",
        "premium",
        "vip",
        "official"
    ]
    
    message_lower = message_text.lower()
    return any(indicator in message_lower for indicator in trusted_indicators)
