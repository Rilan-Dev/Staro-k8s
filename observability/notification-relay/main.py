from fastapi import FastAPI, Request, Header, HTTPException
import os
import httpx
import asyncio
import logging

app = FastAPI()

# Environment variables
ALERT_TOKEN = os.getenv("ALERT_RELAY_TOKEN")
TG_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TG_CHAT = os.getenv("TELEGRAM_CHAT_ID")

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("notification-relay")

# HTTP client config
TIMEOUT = httpx.Timeout(10.0)
RETRIES = 3


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/alerts")
async def receive_alert(req: Request, authorization: str = Header(None)):
    if authorization != f"Bearer {ALERT_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")

    payload = await req.json()
    alerts = payload.get("alerts", [])

    failures = 0

    for alert in alerts:
        msg = format_alert(alert)
        success = await send_telegram_with_retry(msg)
        if not success:
            failures += 1

    if failures > 0:
        logger.error("Some alerts failed to send")
        return {"status": "partial", "failed": failures}

    return {"status": "ok"}


from pydantic import BaseModel

class Message(BaseModel):
    text: str

@app.post("/message")
async def send_message(msg: Message, authorization: str = Header(None)):
    """Generic endpoint to send any text message to Telegram"""
    if authorization != f"Bearer {ALERT_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")

    success = await send_telegram_with_retry(msg.text)
    
    if not success:
        logger.error("Failed to send message")
        raise HTTPException(status_code=500, detail="Failed to send Telegram message")

    return {"status": "ok"}


def format_alert(alert: dict) -> str:
    return (
        f"🚨 ALERT: {alert['labels'].get('alertname', 'Unknown')}\n"
        f"Severity: {alert['labels'].get('severity', 'unknown')}\n"
        f"Namespace: {alert['labels'].get('namespace', 'unknown')}\n\n"
        f"{alert['annotations'].get('summary', '')}\n"
        f"{alert['annotations'].get('description', '')}"
    )


async def send_telegram_with_retry(message: str) -> bool:
    url = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"

    for attempt in range(1, RETRIES + 1):
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                response = await client.post(url, json={
                    "chat_id": TG_CHAT,
                    "text": message
                })

            if response.status_code == 200:
                logger.info("Telegram message sent")
                return True

            logger.warning(
                f"Telegram API error {response.status_code}: {response.text}"
            )

        except Exception as e:
            logger.error(f"Attempt {attempt} failed: {e}")

        await asyncio.sleep(2)

    return False
