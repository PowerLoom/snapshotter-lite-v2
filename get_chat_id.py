import requests
import time
import uuid

def get_my_chat_id():
    # Get bot token from user
    bot_token = input("Enter your bot token (from @BotFather): ").strip()
    
    if not bot_token:
        print("Bot token is required!")
        return None
    
    # Validate bot token format (basic check)
    if not bot_token.count(':') == 1 or len(bot_token.split(':')[0]) < 8:
        print("Invalid bot token format. It should look like: 123456789:ABCDEF...")
        return None
    
    # Generate a unique identifier
    unique_code = str(uuid.uuid4())[:8]
    
    print(f"\nStep 1: Send this EXACT message to your bot: /mychatid_{unique_code}")
    print("Step 2: After sending the message, press Enter to continue...")
    input()
    
    # Wait a moment for the message to be processed
    time.sleep(2)
    
    url = f"https://api.telegram.org/bot{bot_token}/getUpdates"
    
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to Telegram API: {e}")
        return None
    except ValueError as e:
        print(f"Error parsing response: {e}")
        return None
    
    if not data.get('ok', False):
        print(f"Telegram API error: {data.get('description', 'Unknown error')}")
        print("Please check your bot token and try again.")
        return None
    
    if not data['result']:
        print("No messages found. Make sure you sent the message to the bot!")
        return None
    
    # Search for the message with our unique code
    for update in reversed(data['result']):  # Check recent messages first
        if 'message' in update and 'text' in update['message']:
            message_text = update['message']['text']
            if f'/mychatid_{unique_code}' in message_text:
                chat_id = update['message']['chat']['id']
                username = update['message']['chat'].get('username', 'No username')
                first_name = update['message']['chat'].get('first_name', 'No name')
                
                print(f"\n✅ Found your message!")
                print(f"Your chat ID is: {chat_id}")
                print(f"Name: {first_name}")
                print(f"Username: @{username}" if username != 'No username' else "Username: Not set")
                print(f"\nUse this in your webhook payload as: \"chatId\": \"{chat_id}\"")
                return chat_id
    
    print(f"Could not find message with code '{unique_code}'. Make sure you sent the exact message!")
    return None

if __name__ == "__main__":
    get_my_chat_id()