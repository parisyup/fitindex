from openai import OpenAI
import shelve
from dotenv import load_dotenv
import os
import logging
import re
import json
from pathlib import Path
from datetime import datetime, timezone, timedelta

load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client = OpenAI(api_key=OPENAI_API_KEY)

LEAD_DB = "lead_data"
JSON_DB = Path("user_metadata.json")

# UAE timezone offset
UTC_OFFSET = timedelta(hours=4)

# Track the last message sent by the assistant
PREVIOUS_RESPONSES = {}


def store_lead_metadata(wa_id, metadata):
    now = datetime.now(timezone.utc)
    metadata["last_contacted"] = now.isoformat()
    metadata["my_previous_response"] = PREVIOUS_RESPONSES.get(wa_id, "")

    with shelve.open(LEAD_DB, writeback=True) as db:
        db[wa_id] = metadata

    if JSON_DB.exists():
        with open(JSON_DB, "r") as f:
            json_data = json.load(f)
    else:
        json_data = {}

    json_data[wa_id] = metadata

    with open(JSON_DB, "w") as f:
        json.dump(json_data, f, indent=2)


def get_lead_metadata(wa_id):
    with shelve.open(LEAD_DB) as db:
        return db.get(wa_id, {})


def extract_metadata_and_reply(response: str):
    metadata = {
        "handoff": False,
        "status": "New Lead",
        "tags": [],
        "notes": ""
    }

    lines = response.strip().splitlines()
    metadata_lines = []
    clean_start_index = 0

    for i, line in enumerate(lines):
        if line.strip().startswith("[") and ":" in line and line.strip().endswith("]"):
            metadata_lines.append(line.strip())
        else:
            clean_start_index = i
            break

    for line in metadata_lines:
        try:
            key, value = line[1:-1].split(":", 1)
            key = key.strip().lower()
            value = value.strip()

            if key == "handoff":
                metadata["handoff"] = value.lower() == "true"
            elif key == "status":
                metadata["status"] = value
            elif key == "tags":
                metadata["tags"] = [t.strip() for t in value.split(",") if t.strip()]
            elif key == "notes":
                metadata["notes"] = value
        except Exception as e:
            logging.warning(f"Metadata parse error: {e} in line {line}")

    clean_reply = "\n".join(lines[clean_start_index:]).strip()
    return metadata, clean_reply


def format_last_contacted(last_contacted_str):
    try:
        last_time_utc = datetime.fromisoformat(last_contacted_str)
        last_time_local = last_time_utc.astimezone(timezone(UTC_OFFSET))
        now = datetime.now(timezone.utc).astimezone(timezone(UTC_OFFSET))
        diff = now - last_time_local
        seconds = int(diff.total_seconds())
        minutes = seconds // 60
        hours = minutes // 60

        if hours > 0:
            ago = f"{hours} hour{'s' if hours != 1 else ''} ago"
        elif minutes > 0:
            ago = f"{minutes} minute{'s' if minutes != 1 else ''} ago"
        else:
            ago = f"{seconds} second{'s' if seconds != 1 else ''} ago"

        formatted_time = last_time_local.strftime("%d%m%y %H:%M:%S")
        return f"{formatted_time} ({ago})"
    except Exception as e:
        logging.warning(f"Error formatting last contacted: {e}")
        return "Unknown"


def generate_response(message_body, wa_id, name):
    prior_metadata = get_lead_metadata(wa_id)

    memory_prompt = ""
    if prior_metadata:
        last_contacted_display = format_last_contacted(prior_metadata.get("last_contacted", ""))
        memory_prompt = (
            f"[status: {prior_metadata.get('status', 'New Lead')}]\n"
            f"[tags: {', '.join(prior_metadata.get('tags', []))}]\n"
            f"[notes: {prior_metadata.get('notes', '')}]\n"
            f"[last contacted: {last_contacted_display}]\n"
            f"[my previous response: {prior_metadata.get('my_previous_response', '')}]\n"
        )

    prompt = memory_prompt + f"\n{name}: {message_body}"

    response = client.chat.completions.create(
        model="gpt-4-1106-preview",
        messages=[
            {
                "role": "system",
                "content": (
                    "You are a smart, friendly assistant working for Faris Alblooki Real Estate (FAREA) in Abu Dhabi. Your main goal is to qualify leads and hand them off to a human agent when ready.\n\n"
                    "**Start EVERY response with this exact metadata block:**\n"
                    "[handoff: true/false]\n"
                    "[status: New Lead | Qualified | very qualified | Cold | Unreachable]\n"
                    "[tags: 3–5 keywords like Saadiyat, 2BR, rent]\n"
                    "[notes: short facts like name: Faris, sea view, urgent]\n"
                    "[last contacted: DO NOT MODIFY THIS WHATSOEVER]\n"
                    "[my previous response: DO NOT MODIFY THIS EITHER]\n\n"
                    "**Rules:**\n"
                    "• Use 'my previous response' to understand context. Check if the user's reply answers your last message.\n"
                    "• If the user gives 2+ useful details or shows strong interest, set handoff: true.\n"
                    "• Once handoff is true, do NOT mention agents or offers to follow up again.\n"
                    "• NEVER mention inventory or make appointments.\n"
                    "• ONLY discuss real estate in Abu Dhabi.\n"
                    "• NEVER message in Arabic always in english unless they message in arabic. If they switch to English, follow their lead.\n\n"
                    "**Flow:**\n"
                    "NOTE dont be too focused on the flow. if they are inquiring about something make sure they are answered then come back to the flow"
                    "1. Find out if they want to rent, buy, or sell.\n"
                    "2. Ask for area and budget. Then ask for size too. \n"
                    "3. As info builds: status = Cold (0), New Lead (1), Qualified (2–3), Very Qualified (3+).\n"
                    "4. When status reaches Qualified — ALWAYS set handoff: true and ask if they'd like us to reach out.\n"
                    "5. Keep replies short, focused, and helpful. Do not repeat yourself. Always end with a follow-up question."
                    "6. if you reach very qualified or gathered (BUDGET and AREA and SIZE) then just say someone will contact you and stop asking questions. and thank them as (FAREA)"
                )
            },
            {"role": "user", "content": prompt}
        ]
    ) 

    ai_text = response.choices[0].message.content.strip()
    metadata, clean_reply = extract_metadata_and_reply(ai_text)

    PREVIOUS_RESPONSES[wa_id] = clean_reply
    store_lead_metadata(wa_id, metadata)

    return clean_reply
