"""
Telegram Integration Module
Handles Telegram client connection, message parsing, and signal processing
Designed to work seamlessly with the core trading bot
"""

import os
import re
import logging
from datetime import datetime
from typing import Dict, Any, Optional, Callable

# Setup logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

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
    def __init__(self):
        self.client = None
        self.channel_entity = None
        self.is_connected = False

    async def initialize(self) -> bool:
        if not TELEGRAM_AVAILABLE:
            logger.error("[❌] Telegram libraries not available")
            return False

        try:
            self.client = TelegramClient('bot_session', API_ID, API_HASH)
            await self.client.start(bot_token=BOT_TOKEN)
            logger.info("[✅] Telegram client connected")
            await self._resolve_channel()
            self.is_connected = True
            return True
        except Exception as e:
            logger.error(f"[❌] Failed to initialize Telegram: {e}")
            return False

    async def _resolve_channel(self):
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
        if not self.client:
            logger.error("[❌] Client not initialized")
            return

        @self.client.on(events.NewMessage())
        async def message_handler(event):
            try:
                logger.info(f"[📩] Message received: {event.message.message}")
                target_id = getattr(self.channel_entity, 'id', None)
                if event.chat_id != target_id:
                    return

                message_text = event.message.message

                if message_text.startswith("/"):
                    logger.info(f"[💻] Command detected: {message_text}")
                    try:
                        await command_callback(message_text)
                    except Exception as e:
                        logger.error(f"[❌] Error processing command '{message_text}': {e}")
                else:
                    signal = parse_trading_signal(message_text)
                    if signal and signal.get('currency_pair') and signal.get('entry_time'):
                        logger.info(
                            f"[⚡] Signal parsed: currency={signal['currency_pair']}, "
                            f"direction={signal.get('direction')}, entry_time={signal['entry_time']}"
                        )
                        await signal_callback(signal)
                    else:
                        logger.warning(f"[⚠️] Invalid or incomplete signal: {message_text}")
            except Exception as e:
                logger.exception(f"[❌] Error in message handler: {e}")

    async def run(self, signal_callback: Callable, command_callback: Callable):
        initialized = await self.initialize()
        if initialized:
            self.setup_handlers(signal_callback, command_callback)
            logger.info("[🚀] Telegram service is running...")
            await self.client.run_until_disconnected()

def parse_trading_signal(message: str) -> Optional[Dict[str, Any]]:
    """
    Parses a trading signal from a message string.

    Expected format example:
    "BUY BTC/USD at 41000 entry: 14:30"
    """
    try:
        # Example regex to match: BUY BTC/USD at 41000
        signal_pattern = r"(BUY|SELL)\s+([A-Z]{3,5}/[A-Z]{3,5})\s+(at|@)\s+([\d\.]+)"
        match = re.search(signal_pattern, message, re.IGNORECASE)
        if not match:
            logger.debug(f"[🔍] Signal regex match failed for message: {message}")
            return None

        direction, pair, _, price = match.groups()

        # Attempt to find entry time (e.g., 14:30 or 14h30)
        time_patterns = [
            r"\b(\d{1,2}:\d{2})\b",
            r"\b(\d{1,2}h\d{2})\b"
        ]
        entry_time = None
        for pattern in time_patterns:
            time_match = re.search(pattern, message)
            if time_match:
                time_str = time_match.group(1).replace("h", ":")
                try:
                    now = datetime.utcnow()
                    parsed_time = datetime.strptime(time_str, "%H:%M")
                    entry_time = now.replace(hour=parsed_time.hour, minute=parsed_time.minute, second=0, microsecond=0)
                    # Ensure it's not in the past
                    if entry_time < now:
                        entry_time = entry_time.replace(day=now.day + 1)
                    break
                except Exception as e:
                    logger.debug(f"[⚠️] Time parse failed for '{time_str}': {e}")

        return {
            "direction": direction.upper(),
            "currency_pair": pair.upper(),
            "entry_price": float(price),
            "entry_time": entry_time or datetime.utcnow()
        }

    except Exception as e:
        logger.error(f"[❌] Failed to parse trading signal: {e}")
        return None
