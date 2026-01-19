from fastapi import FastAPI, Request, Header, HTTPException
import os
import httpx
import asyncio
import logging
from datetime import datetime


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
    
    if not alerts:
        return {"status": "ok", "processed": 0}

    # Group alerts by status
    firing = []
    resolved = []

    for alert in alerts:
        status = alert.get("status", "firing")
        if status == "firing":
            firing.append(alert)
        elif status == "resolved":
            resolved.append(alert)

    # Construct messages
    messages_to_send = []

    if firing:
        messages_to_send.append(format_group("🔥 FIRING", firing))
    
    if resolved:
        messages_to_send.append(format_group("✅ RESOLVED", resolved))

    # Send messages
    failures = 0
    for msg in messages_to_send:
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


def format_group(header: str, alerts: list) -> str:
    lines = [f"<b>{header} ({len(alerts)})</b>"]
    
    for alert in alerts:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        
        name = labels.get("alertname", "Unknown")
        severity = labels.get("severity", "unknown")
        namespace = labels.get("namespace", "unknown")
        summary = annotations.get("summary") or annotations.get("message") or annotations.get("description") or "No description"
        
        # Icon based on severity
        sev_icon = "🔴" if severity == "critical" else "⚠️"
        
        # Duration for resolved
        duration_str = ""
        if alert.get("status") == "resolved":
            starts = alert.get("startsAt")
            ends = alert.get("endsAt")
            if starts and ends:
                try:
                    s_dt = datetime.fromisoformat(starts.replace("Z", "+00:00"))
                    e_dt = datetime.fromisoformat(ends.replace("Z", "+00:00"))
                    diff = e_dt - s_dt
                    # simple format
                    hours, remainder = divmod(int(diff.total_seconds()), 3600)
                    minutes, _ = divmod(remainder, 60)
                    duration_str = f" (Duration: {hours}h {minutes}m)"
                except:
                    pass
        
        lines.append(f"\n{sev_icon} <b>{name}</b> {duration_str}")
        lines.append(f"Namespace: <code>{namespace}</code>")
        lines.append(f"<i>{summary}</i>")

    return "\n".join(lines)


async def send_telegram_with_retry(message: str) -> bool:
    url = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"

    for attempt in range(1, RETRIES + 1):
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                response = await client.post(url, json={
                    "chat_id": TG_CHAT,
                    "text": message,
                    "parse_mode": "HTML"
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
