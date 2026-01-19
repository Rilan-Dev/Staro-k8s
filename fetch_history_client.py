import json
import asyncio
from datetime import datetime, timedelta, timezone
from telethon import TelegramClient

# --- CONFIGURATION ---
# YOU MUST FILL THESE IN
# Get them from https://my.telegram.org
API_ID = '30539712'
API_HASH = '1750a8e33946280e0e13c7eecd49de3e'

# The bot token you provided
BOT_TOKEN = '7955458864:AAEBsf7aZMwZRKsPGIb9v0wXp3lAZV8Kl44'

# Output file
OUTPUT_FILE = 'bot_history_2days.json'

async def main():
    # Initialize the client with the bot token
    # We use a session file 'bot_session' to store auth state
    async with TelegramClient('bot_session', API_ID, API_HASH) as client:
        await client.start(bot_token=BOT_TOKEN)
        
        me = await client.get_me()
        print(f"Connected as: {me.username} ({me.id})")
        
        cutoff_date = datetime.now(timezone.utc) - timedelta(days=2)
        print(f"Fetching history since: {cutoff_date}")

        all_data = {}

        # Specific Chat ID found in secret.yaml
        target_chat_id = 1269861867
        print(f"Fetching history for chat ID: {target_chat_id}")
        
        chat_history = []
        try:
            # Fetch messages from the last 2 days
            async for message in client.iter_messages(target_chat_id, offset_date=cutoff_date, reverse=True):
                 # Double check date just in case
                if message.date < cutoff_date:
                    continue
                    
                msg_data = {
                    'id': message.id,
                    'date': message.date.isoformat(),
                    'sender_id': message.sender_id,
                    'text': message.text,
                    'media': str(message.media) if message.media else None
                }
                chat_history.append(msg_data)
                
            print(f"  - Retrieved {len(chat_history)} messages.")
            all_data[str(target_chat_id)] = {
                'chat_id': target_chat_id,
                'messages': chat_history
            }
        except Exception as e:
            print(f"Error fetching history for {target_chat_id}: {e}")

        # Save to JSON

        # Save to JSON
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            json.dump(all_data, f, indent=2, ensure_ascii=False)
        
        print(f"\nDone! History saved to {OUTPUT_FILE}")

if __name__ == '__main__':
    # Check if API credentials are filled
    if API_ID == 'YOUR_API_ID':
        print("ERROR: You must set API_ID and API_HASH in the script first!")
        print("Get them from https://my.telegram.org")
    else:
        asyncio.run(main())
