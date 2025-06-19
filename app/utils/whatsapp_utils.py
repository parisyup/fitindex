import logging
from flask import current_app, jsonify
import json
import requests
import re
from pathlib import Path
from datetime import datetime

from app.services.openai_service import generate_response

def log_http_response(response):
    logging.info(f"Status: {response.status_code}")
    logging.info(f"Content-type: {response.headers.get('content-type')}")
    logging.info(f"Body: {response.text}")

def get_text_message_input(recipient, text):
    return json.dumps(
        {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": recipient,
            "type": "text",
            "text": {"preview_url": False, "body": text},
        }
    )

def process_text_for_whatsapp(text):
    text = re.sub(r"\[.*?\]", "", text).strip()
    text = re.sub(r"\*\*(.*?)\*\*", r"*\\1*", text)
    return text

def process_whatsapp_message(body):
    wa_id = body["entry"][0]["changes"][0]["value"]["contacts"][0]["wa_id"]
    name = body["entry"][0]["changes"][0]["value"]["contacts"][0]["profile"]["name"]

    message = body["entry"][0]["changes"][0]["value"]["messages"][0]
    message_body = message["text"]["body"]

    # Step 1: Check alerts.txt
    alerts_path = Path("alerts.txt")
    alert_numbers = set()
    if alerts_path.exists():
        with open(alerts_path, "r") as f:
            alert_numbers = {line.strip() for line in f if line.strip()}
        if wa_id in alert_numbers:
            current_app.discord_notifier.alert(
                f"\U0001f6a8 **ALERT: Incoming message from flagged contact @everyone**\n"
                f"> 👤 `{name}` (`{wa_id}`)\n"
                f"> 💬 {message_body}"
            )

    # Load metadata before update
    metadata_file = Path("user_metadata.json")
    old_metadata = {
        "handoff": False,
        "status": "Cold",
        "tags": [],
        "notes": ""
    }
    if metadata_file.exists():
        with open(metadata_file, "r") as f:
            all_metadata = json.load(f)
            old_metadata = all_metadata.get(wa_id, old_metadata)

    previous_status = old_metadata.get("status", "Cold")

    # Generate response from OpenAI
    raw_response = generate_response(message_body, wa_id, name)
    print("HERE +++++ " + raw_response)

    # Load updated metadata after OpenAI response
    new_metadata = {
        "handoff": False,
        "status": "Cold",
        "tags": [],
        "notes": ""
    }
    if metadata_file.exists():
        with open(metadata_file, "r") as f:
            all_metadata = json.load(f)
            new_metadata = all_metadata.get(wa_id, new_metadata)

    # Step 2: Status change alert check
    status_levels = ["Cold", "New Lead", "Qualified", "Very Qualified"]
    try:
        old_index = status_levels.index(previous_status)
        new_index = status_levels.index(new_metadata.get("status", "Cold"))
        if new_index > old_index:
            current_app.discord_notifier.alert(
                f"🚨 **Status Upgrade Alert @everyone**\n"
                f"> 👤 `{name}` (`{wa_id}`)\n"
                f"> 📈 Status changed: `{previous_status}` → `{new_metadata['status']}`"
            )
    except ValueError:
        pass

    clean_response = re.sub(r"\[.*?\]", "", raw_response).strip()
    formatted_response = re.sub(r"\*\*(.*?)\*\*", r"*\\1*", clean_response)

    data = get_text_message_input(wa_id, formatted_response)

    # Step 3: Notify full message (standard)
    discord_msg = (
        f"**📥 WhatsApp Message Received**\n"
        f"> 👤 **From:** `{name}` (`{wa_id}`)\n"
        f"> 💬 **Message:** {message_body}\n\n"
        f"**🤖 Bot Response**\n"
        f"> 💬 **Reply:** {formatted_response}\n\n"
        f"**📌 Metadata**\n"
        f"> Handoff: `{new_metadata['handoff']}`\n"
        f"> Status: `{new_metadata['status']}`\n"
        f"> Tags: `{', '.join(new_metadata['tags'])}`\n"
        f"> Notes: `{new_metadata['notes']}`"
    )
    current_app.discord_notifier.notify(discord_msg)

    # Step 4: Alert with bot reply if flagged
    if wa_id in alert_numbers:
        current_app.discord_notifier.alert(
            f"🤖 **Bot Replied to `{name}` (`{wa_id}`):**\n"
            f"> 💬 {formatted_response}"
        )

    # Update contacts.json
    contact_file = Path("contacts.json")
    recipient_number = json.loads(data)["to"]
    if contact_file.exists():
        with open(contact_file, "r") as f:
            contacts = json.load(f)
    else:
        contacts = []

    if recipient_number not in contacts:
        contacts.append(recipient_number)
        with open(contact_file, "w") as f:
            json.dump(contacts, f, indent=2)

    # Block check
    if current_app.discord_notifier.is_blocked(wa_id):
        print("BLOCKED USER: " + wa_id)
        return

    # Save interaction history
    history_dir = Path("numbers_history")
    history_dir.mkdir(exist_ok=True)
    history_file = history_dir / f"{wa_id}.txt"
    timestamp = datetime.now().strftime("%A, %Y-%m-%d %H:%M:%S")

    with open(history_file, "a") as f:
        f.write(f"{name} ({wa_id}) {timestamp}:{message_body}\n\n")
        f.write(f"bot ({timestamp}):\n{formatted_response}\n\n")

    # Send WhatsApp message
    send_message(data)





def broadcast_template_to_file_numbers(template_name: str, discordName, language_code: str = "en_US"):
    numbers_file = Path("broadcast_numbers.txt")
    if not numbers_file.exists():
        raise FileNotFoundError("broadcast_numbers.txt not found")

    with open(numbers_file, "r") as f:
        numbers = [line.strip() for line in f if line.strip()]

    url = f"https://graph.facebook.com/{current_app.config['VERSION']}/{current_app.config['PHONE_NUMBER_ID']}/messages"
    headers = {
        "Authorization": "Bearer " + current_app.config["ACCESS_TOKEN"],
        "Content-Type": "application/json",
    }

    for number in numbers:
        payload = {
            "messaging_product": "whatsapp",
            "to": number,
            "type": "template",
            "template": {
                "name": template_name,
                "language": {"code": language_code}
            },
        }
        response = requests.post(url, headers=headers, json=payload)
        print(f"Sent to {number}: {response.status_code} {response.text}")
            
        alerts_path = Path("alerts.txt")
        alert_numbers = set()
        if alerts_path.exists():
            with open(alerts_path, "r") as f:
                alert_numbers = {line.strip() for line in f if line.strip()}
        if number in alert_numbers:
            current_app.discord_notifier.alert(
                f"🤖 **`{discordName}` Replied to (`{number}`):**\n"
                f"> 💬 {response.text}"
            )

        # Log history
        log_path = Path("numbers_history") / f"{number}.txt"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        with open(log_path, "a") as log_file:
            log_file.write(f"{discordName} ({timestamp}):\nTemplate sent: {template_name}\n\n")

        current_app.discord_notifier.notify(f"Sent to {number}")


def send_direct_whatsapp_message(number, message, discordName):
    headers = {
        "Content-type": "application/json",
        "Authorization": f"Bearer {current_app.config['ACCESS_TOKEN']}",
    }

    url = f"https://graph.facebook.com/{current_app.config['VERSION']}/{current_app.config['PHONE_NUMBER_ID']}/messages"

    payload = {
        "messaging_product": "whatsapp",
        "to": number,
        "type": "text",
        "text": {"preview_url": False, "body": message},
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        log_http_response(response)

        alerts_path = Path("alerts.txt")
        alert_numbers = set()
        if alerts_path.exists():
            with open(alerts_path, "r") as f:
                alert_numbers = {line.strip() for line in f if line.strip()}
        if number in alert_numbers:
            current_app.discord_notifier.alert(
                f"🤖 **`{discordName}` Replied to (`{number}`):**\n"
                f"> 💬 {message}"
            )

        # Log history
        log_path = Path("numbers_history") / f"{number}.txt"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        with open(log_path, "a") as log_file:
            log_file.write(f"{discordName} ({timestamp}):\n{message}\n\n")

        return True, None
    except requests.RequestException as e:
        logging.error(f"Failed to send message to {number}: {e}")
        return False, str(e)


def send_message(data):
    headers = {
        "Content-type": "application/json",
        "Authorization": f"Bearer {current_app.config['ACCESS_TOKEN']}",
    }

    url = f"https://graph.facebook.com/{current_app.config['VERSION']}/{current_app.config['PHONE_NUMBER_ID']}/messages"

    try:
        response = requests.post(
            url, data=data, headers=headers, timeout=10
        )
        response.raise_for_status()
    except requests.Timeout:
        logging.error("Timeout occurred while sending message")
        return jsonify({"status": "error", "message": "Request timed out"}), 408
    except requests.RequestException as e:
        logging.error(f"Request failed due to: {e}")
        return jsonify({"status": "error", "message": "Failed to send message"}), 500
    else:
        log_http_response(response)
        return response


def send_message_with_name(data, discordName):
    headers = {
        "Content-type": "application/json",
        "Authorization": f"Bearer {current_app.config['ACCESS_TOKEN']}",
    }

    url = f"https://graph.facebook.com/{current_app.config['VERSION']}/{current_app.config['PHONE_NUMBER_ID']}/messages"

    try:
        response = requests.post(url, data=data, headers=headers, timeout=10)
        response.raise_for_status()
        log_http_response(response)

        # Log history
        payload = json.loads(data)
        number = payload.get("to", "")
        text = payload.get("text", {}).get("body", "")


        alerts_path = Path("alerts.txt")
        alert_numbers = set()
        if alerts_path.exists():
            with open(alerts_path, "r") as f:
                alert_numbers = {line.strip() for line in f if line.strip()}
        if number in alert_numbers:
            current_app.discord_notifier.alert(
                f"🤖 **`{discordName}` Replied to (`{number}`):**\n"
                f"> 💬 {data}"
            )

        log_path = Path("numbers_history") / f"{number}.txt"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        with open(log_path, "a") as log_file:
            log_file.write(f"{discordName} ({timestamp}):\n{text}\n\n")

        return response
    except requests.Timeout:
        logging.error("Timeout occurred while sending message")
        return jsonify({"status": "error", "message": "Request timed out"}), 408
    except requests.RequestException as e:
        logging.error(f"Request failed due to: {e}")
        return jsonify({"status": "error", "message": "Failed to send message"}), 500

def is_valid_whatsapp_message(body):
    return (
        body.get("object")
        and body.get("entry")
        and body["entry"][0].get("changes")
        and body["entry"][0]["changes"][0].get("value")
        and body["entry"][0]["changes"][0]["value"].get("messages")
        and body["entry"][0]["changes"][0]["value"]["messages"][0]
    )
