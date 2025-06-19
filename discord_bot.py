import discord
import asyncio
import threading
from datetime import datetime, timezone, timedelta
from discord.ext import commands
import os
import sys
import json
from pathlib import Path
from datetime import datetime
import subprocess
from time import time
from app.utils.whatsapp_utils import get_text_message_input, send_message_with_name, send_direct_whatsapp_message, broadcast_template_to_file_numbers
import re

BROADCAST_REGEX = r"^\+9715\d{8}$"

def is_valid_uae_number(number):
    return re.match(BROADCAST_REGEX, number.strip()) is not None



# === Static Config ===
DISCORD_TOKEN = ""
CHANNEL_ID = 1
ALERT_CHANNEL_ID = 1
AUTHORIZED_USER_IDS = []


class DiscordNotifier:
    def __init__(self, flask_app):
        intents = discord.Intents.default()
        intents.voice_states = True
        intents.guilds = True
        intents.members = True
        intents.message_content = True

        self.flask_app = flask_app

        self.bot = commands.Bot(command_prefix="!", intents=intents)
        self.blocklist_file = Path("blocked_contacts.json")
        self.blocked_contacts = self.load_blocked_contacts()

        self.setup_events()
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self._run_bot, daemon=True)
        self.thread.start()

        # Resume countdown for active temp blocks
        now = int(time())
        for number, expires_at in self.blocked_contacts["temporary"].items():
            if expires_at > now:
                self.loop.create_task(self._resume_temp_block(number, expires_at))

    # === Blocklist methods ===
    def load_blocked_contacts(self):
        if self.blocklist_file.exists():
            with open(self.blocklist_file, "r") as f:
                data = json.load(f)
                return {
                    "permanent": set(data.get("permanent", [])),
                    "temporary": {k: int(v) for k, v in data.get("temporary", {}).items()}
                }
        return {"permanent": set(), "temporary": {}}

    def save_blocked_contacts(self):
        data = {
            "permanent": list(self.blocked_contacts["permanent"]),
            "temporary": self.blocked_contacts["temporary"]
        }
        with open(self.blocklist_file, "w") as f:
            json.dump(data, f)

    def block_contact(self, number):
        self.blocked_contacts["permanent"].add(number)
        self.save_blocked_contacts()

    def unblock_contact(self, number):
        self.blocked_contacts["permanent"].discard(number)
        self.blocked_contacts["temporary"].pop(number, None)
        self.save_blocked_contacts()

    def is_blocked(self, number):
        now = int(time())
        if number in self.blocked_contacts["permanent"]:
            return True
        if number in self.blocked_contacts["temporary"]:
            if now < self.blocked_contacts["temporary"][number]:
                return True
            else:
                self.unblock_contact(number)
        return False

    async def _resume_temp_block(self, number, expires_at):
        reminder_sent = False
        while int(time()) < expires_at:
            await asyncio.sleep(1)
            if not reminder_sent and int(expires_at - time()) == 60:
                channel = self.bot.get_channel(CHANNEL_ID)
                if channel:
                    try:
                        await channel.send(f"⏰ @everyone Reminder: {number} will be unblocked in 60 seconds!")
                    except discord.HTTPException:
                        await channel.send("⚠️ Could not send @everyone reminder.")
                reminder_sent = True

        self.unblock_contact(number)
        channel = self.bot.get_channel(CHANNEL_ID)
        if channel:
            await channel.send(f"🟢 {number} has been automatically unblocked (restored from restart)")

    # === Discord Bot Setup ===
    def setup_events(self):
        @self.bot.event
        async def on_ready():
            print(f"✅ Discord bot ready: {self.bot.user}")

        @self.bot.command(name="block")
        async def block(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return

            if self.is_blocked(number):
                await ctx.send(f"{number} is already blocked 🚫")
            else:
                self.block_contact(number)
                await ctx.send(f"🚫 Blocked {number}")

        @self.bot.command(name="tempblock")
        async def tempblock(ctx, number: str, seconds: int):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return
            if seconds < 90:
                seconds = 90
                await ctx.send(f"⚠️ Minimum block time is 90 seconds. {number} has been blocked for 90 seconds instead.")

            unblock_at = int(time()) + seconds

            if number in self.blocked_contacts["temporary"]:
                self.blocked_contacts["temporary"][number] += seconds
                self.save_blocked_contacts()
                await ctx.send(f"⏳ Extended block for {number} by {seconds}s. New unblock at <t:{self.blocked_contacts['temporary'][number]}:R>")
                return

            self.blocked_contacts["temporary"][number] = unblock_at
            self.save_blocked_contacts()
            await ctx.send(f"🚫 Temporarily blocked {number} until <t:{unblock_at}:R>.")

            reminder_sent = False
            while int(time()) < unblock_at:
                await asyncio.sleep(1)
                if not reminder_sent and int(unblock_at - time()) == 60:
                    try:
                        await ctx.send(f"⏰ @everyone Reminder: {number} will be unblocked in 60 seconds!")
                    except discord.HTTPException:
                        await ctx.send("⚠️ Could not send @everyone reminder.")
                    reminder_sent = True

            self.unblock_contact(number)
            await ctx.send(f"🟢 {number} has been automatically unblocked.")

        @self.bot.command(name="blocktime")
        async def blocktime(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return

            now = int(time())
            if number in self.blocked_contacts["temporary"]:
                seconds_left = self.blocked_contacts["temporary"][number] - now
                await ctx.send(f"⏳ {number} is temporarily blocked. Time remaining: {seconds_left} seconds.")
            elif number in self.blocked_contacts["permanent"]:
                await ctx.send(f"🚫 {number} is permanently blocked.")
            else:
                await ctx.send(f"✅ {number} is not currently blocked.")

        @self.bot.command(name="unblock")
        async def unblock(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return

            if not self.is_blocked(number):
                await ctx.send(f"{number} is not blocked 🟢")
            else:
                self.unblock_contact(number)
                await ctx.send(f"🟢 Unblocked {number}")

        @self.bot.command(name="restartflask")
        async def restartflask(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            await ctx.send("♻️ Restarting Flask + Discord...")
            subprocess.Popen(["bash", "restart.sh"])
            os._exit(0)

        @self.bot.command(name="broadcast")
        async def broadcast(ctx, *, message: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return

            contact_file = Path("contacts.json")
            if not contact_file.exists():
                await ctx.send("❌ contacts.json not found.")
                return

            with open(contact_file, "r") as f:
                contacts = json.load(f)

            if not contacts:
                await ctx.send("📭 No contacts to broadcast to.")
                return

            await ctx.send(f"📢 Broadcasting message to {len(contacts)} contacts...")

            # ✅ Use Flask app context here
            with self.flask_app.app_context():
                for number in contacts:
                    try:
                        data = get_text_message_input(number, message)
                        send_message_with_name(data, ctx.author.name)
                    except Exception as e:
                        print(f"❌ Failed to send to {number}: {e}")

            await ctx.send("✅ Broadcast complete.")

        @self.bot.command(name="broadcast_images")
        async def broadcast_images(ctx, image_urls: str, *, caption: str = ""):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return

            urls = [url.strip() for url in image_urls.split(",")]
            if not urls:
                await ctx.send("❌ You must provide at least one image URL.")
                return

            contact_file = Path("contacts.json")
            if not contact_file.exists():
                await ctx.send("❌ contacts.json not found.")
                return

            with open(contact_file, "r") as f:
                contacts = json.load(f)

            if not contacts:
                await ctx.send("📭 No contacts to broadcast to.")
                return

            await ctx.send(f"🖼️ Broadcasting {len(urls)} images to {len(contacts)} contacts...")

            with self.flask_app.app_context():
                for number in contacts:
                    for i, url in enumerate(urls):
                        try:
                            data = {
                                "messaging_product": "whatsapp",
                                "to": number,
                                "type": "image",
                                "image": {
                                    "link": url,
                                    "caption": caption if i == 0 else ""
                                }
                            }
                            send_message_with_name(json.dumps(data), ctx.author.name)
                        except Exception as e:
                            print(f"❌ Failed to send to {number}: {e}")

            await ctx.send("✅ Multi-image broadcast complete.")


        @self.bot.command(name="broadcast_videos")
        async def broadcast_videos(ctx, video_urls: str, *, caption: str = ""):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized to broadcast.")
                return

            # Split and clean all video URLs
            urls = [url.strip() for url in video_urls.split(",") if url.strip()]
            if not urls:
                await ctx.send("❌ You must provide at least one video URL.")
                return

            # Load contacts
            contact_file = Path("contacts.json")
            if not contact_file.exists():
                await ctx.send("❌ contacts.json not found.")
                return

            with open(contact_file, "r") as f:
                contacts = json.load(f)

            if not contacts:
                await ctx.send("📭 No contacts to broadcast to.")
                return

            await ctx.send(f"🎬 Broadcasting {len(urls)} videos to {len(contacts)} contacts...")

            with self.flask_app.app_context():
                for number in contacts:
                    for i, url in enumerate(urls):
                        try:
                            data = {
                                "messaging_product": "whatsapp",
                                "to": number,
                                "type": "video",
                                "video": {
                                    "link": url,
                                    "caption": caption if i == 0 else ""  # Optional: caption only on 1st video
                                }
                            }
                            send_message_with_name(json.dumps(data), ctx.author.name)
                        except Exception as e:
                            print(f"❌ Failed to send to {number}: {e}")

            await ctx.send("✅ Multi-video broadcast complete.")


        @self.bot.command(name="add_contact")
        async def add_contact(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            contact_file = Path("contacts.json")
            contacts = []

            if contact_file.exists():
                with open(contact_file, "r") as f:
                    contacts = json.load(f)

            if number in contacts:
                await ctx.send(f"ℹ️ {number} is already in the contact list.")
                return

            contacts.append(number)
            with open(contact_file, "w") as f:
                json.dump(contacts, f, indent=2)

            await ctx.send(f"✅ Added {number} to the broadcast contact list.")

        @self.bot.command(name="list_contacts")
        async def list_contacts(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            contact_file = Path("contacts.json")
            if not contact_file.exists():
                await ctx.send("❌ contacts.json not found.")
                return

            with open(contact_file, "r") as f:
                contacts = json.load(f)

            if not contacts:
                await ctx.send("📭 No contacts saved.")
                return

            formatted = "\n".join(f"- `{c}`" for c in contacts)
            await ctx.send(f"**📒 Broadcast Contacts ({len(contacts)})**:\n{formatted}")

        @self.bot.command(name="broadcast_template")
        async def broadcast_template(ctx, template_name: str, lang: str = "en_US"):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return
            discordName = ctx.author.name
            await ctx.send(f"📢 Broadcasting template '{template_name}' to numbers in `broadcast_numbers.txt`...")

            try:
                with self.flask_app.app_context():
                    broadcast_template_to_file_numbers(template_name, discordName, lang)
                await ctx.send("✅ Broadcast complete.")
            except Exception as e:
                await ctx.send(f"❌ Error: {str(e)}")

        @self.bot.command(name="remove_contact")
        async def remove_contact(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            contact_file = Path("contacts.json")
            if not contact_file.exists():
                await ctx.send("❌ contacts.json not found.")
                return

            with open(contact_file, "r") as f:
                contacts = json.load(f)

            if number not in contacts:
                await ctx.send(f"ℹ️ {number} is not in the contact list.")
                return

            contacts.remove(number)
            with open(contact_file, "w") as f:
                json.dump(contacts, f, indent=2)

            await ctx.send(f"🗑️ Removed {number} from the contact list.")

        @self.bot.command(name="set_broadcast_numbers")
        async def set_broadcast_numbers(ctx, *numbers):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            valid_numbers = [n for n in numbers if is_valid_uae_number(n)]
            invalid_numbers = [n for n in numbers if not is_valid_uae_number(n)]

            with open("broadcast_numbers.txt", "w") as f:
                for number in valid_numbers:
                    f.write(number.strip() + "\n")

            response = f"✅ Set {len(valid_numbers)} broadcast number(s)."
            if invalid_numbers:
                response += f"\n⚠️ Skipped {len(invalid_numbers)} invalid numbers:\n" + "\n".join(invalid_numbers)

            await ctx.send(response)


        @self.bot.command(name="add_broadcast_numbers")
        async def add_broadcast_numbers(ctx, *numbers):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            valid = [n for n in numbers if is_valid_uae_number(n)]
            invalid = [n for n in numbers if not is_valid_uae_number(n)]

            current_numbers = set()
            if Path("broadcast_numbers.txt").exists():
                with open("broadcast_numbers.txt", "r") as f:
                    current_numbers = set(line.strip() for line in f)

            current_numbers.update(valid)

            with open("broadcast_numbers.txt", "w") as f:
                for n in sorted(current_numbers):
                    f.write(n + "\n")

            msg = f"✅ Added {len(valid)} valid number(s)."
            if invalid:
                msg += f"\n⚠️ Skipped invalid format(s):\n" + "\n".join(invalid)
            await ctx.send(msg)


        @self.bot.command(name="remove_broadcast_numbers")
        async def remove_broadcast_numbers(ctx, *numbers):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            if not Path("broadcast_numbers.txt").exists():
                await ctx.send("📭 No broadcast file found.")
                return

            with open("broadcast_numbers.txt", "r") as f:
                current_numbers = set(line.strip() for line in f)

            removed = [n for n in numbers if n in current_numbers]
            not_found = [n for n in numbers if n not in current_numbers]

            current_numbers.difference_update(removed)

            with open("broadcast_numbers.txt", "w") as f:
                for n in sorted(current_numbers):
                    f.write(n + "\n")

            msg = f"🗑️ Removed {len(removed)} number(s)."
            if not_found:
                msg += f"\n⚠️ Not found:\n" + "\n".join(not_found)
            await ctx.send(msg)

        @self.bot.command(name="list_broadcast_numbers")
        async def list_broadcast_numbers(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            if not Path("broadcast_numbers.txt").exists():
                await ctx.send("📭 No broadcast numbers found.")
                return

            with open("broadcast_numbers.txt", "r") as f:
                numbers = [line.strip() for line in f if line.strip()]

            if not numbers:
                await ctx.send("📭 Broadcast list is empty.")
            else:
                formatted = "\n".join(numbers)
                await ctx.send(f"📋 Broadcast List:\n```\n{formatted}\n```")


        @self.bot.command(name="send_dm")
        async def send_dm(ctx, number: str, *, message: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return
            discordName = ctx.author.name

            # 👇 Add app context
            with self.flask_app.app_context():
                success, error = send_direct_whatsapp_message(number, message, discordName)

            if success:
                await ctx.send(f"✅ Message sent to {number}")
            else:
                await ctx.send(f"❌ Failed to send message to {number}: {error}")

        @self.bot.command(name="send_dm_multi")
        async def send_dm_multi(ctx, *args):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            try:
                # Split numbers and message
                parts = " ".join(args).split("|", 1)
                if len(parts) != 2:
                    await ctx.send("❌ Use the format:\n`!send_dm_multi <number1> <number2> ... | <message>`")
                    return

                raw_numbers, message = parts
                numbers = [n.strip() for n in raw_numbers.strip().split() if n.strip()]
                message = message.strip()

                if not message or not numbers:
                    await ctx.send("❌ Provide both numbers and a message.")
                    return

                successes = []
                failures = []

                with self.flask_app.app_context():
                    for number in numbers:
                        discordName = ctx.author.name
                        success, error = send_direct_whatsapp_message(number, message, discordName)
                        if success:
                            successes.append(number)
                        else:
                            failures.append(f"{number} ({error})")

                report = f"✅ Sent to {len(successes)} number(s).\n"
                if failures:
                    report += f"⚠️ Failed to send to {len(failures)}:\n" + "\n".join(failures)

                await ctx.send(report)

            except Exception as e:
                await ctx.send(f"❌ Unexpected error: {e}")

        @self.bot.command(name="list_leads")
        async def list_leads(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            path = Path("user_metadata.json")
            if not path.exists():
                await ctx.send("❌ user_metadata.json not found.")
                return

            with open(path, "r") as f:
                data = json.load(f)

            new_contacts = {
                "Cold": [],
                "New Lead": [],
                "Qualified": [],
                "Very Qualified": [],
            }
            old_contacts = {
                "Cold": [],
                "New Lead": [],
                "Qualified": [],
                "Very Qualified": [],
            }

            now = datetime.now(timezone.utc)
            cutoff = now - timedelta(hours=72)

            def get_name(meta):
                notes = meta.get("notes", "")
                match = re.search(r"name:\s*([^\s,]+)", notes, re.IGNORECASE)
                return match.group(1) if match else "Unknown"

            for wa_id, meta in data.items():
                status = meta.get("status", "Cold").title()
                if status not in new_contacts:
                    status = "Cold"

                name = get_name(meta)
                entry = f"{wa_id} – {name}"

                last_contacted = meta.get("last_contacted")
                if not last_contacted:
                    old_contacts[status].append(entry)
                    continue

                try:
                    contact_time = datetime.fromisoformat(last_contacted)
                except:
                    contact_time = now

                if contact_time >= cutoff:
                    new_contacts[status].append(entry)
                else:
                    old_contacts[status].append(entry)

            def format_section(title, section_data):
                lines = [f"**📁 {title}**"]
                for status, numbers in section_data.items():
                    if numbers:
                        formatted_numbers = "\n".join([f"- `{n}`" for n in numbers])
                        lines.append(f"\n🔸 **{status}** ({len(numbers)}):\n{formatted_numbers}")
                return "\n".join(lines)

            message = format_section("NEW CONTACTS (last 72h)", new_contacts)
            message += "\n\n" + format_section("OLD CONTACTS", old_contacts)

            if len(message) > 1900:
                parts = [message[i:i+1900] for i in range(0, len(message), 1900)]
                for part in parts:
                    await ctx.send(part)
            else:
                await ctx.send(message)


        @self.bot.command(name="view_lead")
        async def view_lead(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            path = Path("user_metadata.json")
            if not path.exists():
                await ctx.send("❌ user_metadata.json not found.")
                return

            with open(path, "r") as f:
                data = json.load(f)

            number = number.replace("+", "").strip()
            lead = data.get(number)

            if not lead:
                await ctx.send(f"❌ No lead data found for `{number}`.")
                return

            def safe_get(key, default="—"):
                return lead.get(key, default) or default

            # Format last_contacted to UAE timezone
            try:
                utc_time = datetime.fromisoformat(lead.get("last_contacted"))
                uae_time = utc_time + timedelta(hours=4)
                last_contacted_str = uae_time.strftime("%d/%m/%Y %H:%M:%S")
            except:
                last_contacted_str = "Unknown"

            response = (
                f"📋 **Lead Details for `{number}`**\n"
                f"• **Status**: `{safe_get('status')}`\n"
                f"• **Handoff**: `{safe_get('handoff')}`\n"
                f"• **Tags**: `{', '.join(safe_get('tags', []))}`\n"
                f"• **Notes**: `{safe_get('notes')}`\n"
                f"• **Last Contacted (UAE)**: `{last_contacted_str}`\n"
                f"• **AI last responded with:**\n```{safe_get('my_previous_response')}```"
            )

            await ctx.send(response)

        @self.bot.command(name="set_alert")
        async def set_alert(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            alerts_file = Path("alerts.txt")
            existing = set()

            if alerts_file.exists():
                with open(alerts_file, "r") as f:
                    existing = set(line.strip() for line in f if line.strip())

            if number in existing:
                await ctx.send(f"⚠️ {number} is already in the alerts list.")
                return

            existing.add(number)
            with open(alerts_file, "w") as f:
                for num in sorted(existing):
                    f.write(num + "\n")

            await ctx.send(f"✅ Added {number} to alerts.")


        @self.bot.command(name="remove_alert")
        async def remove_alert(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            alerts_file = Path("alerts.txt")

            if not alerts_file.exists():
                await ctx.send("📭 No alerts file found.")
                return

            with open(alerts_file, "r") as f:
                numbers = [line.strip() for line in f if line.strip()]

            if number not in numbers:
                await ctx.send(f"⚠️ {number} not found in alerts.")
                return

            numbers.remove(number)
            with open(alerts_file, "w") as f:
                for n in numbers:
                    f.write(n + "\n")

            await ctx.send(f"🗑️ Removed {number} from alerts.")

        @self.bot.command(name="show_alerts")
        async def show_alerts(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            path = Path("alerts.txt")
            if not path.exists():
                await ctx.send("📭 No alerts file found.")
                return

            with open(path, "r") as f:
                numbers = [f"{line.strip()}" for line in f if line.strip()]

            if not numbers:
                await ctx.send("📭 No numbers on alert.")
                return

            message = "**🔔 Numbers with Alert Enabled:**\n" + "\n".join(f"- `{n}`" for n in numbers)

            if len(message) > 1900:
                parts = [message[i:i + 1900] for i in range(0, len(message), 1900)]
                for part in parts:
                    await ctx.send(part)
            else:
                await ctx.send(message)

        @self.bot.command(name="history")
        async def history(ctx, number: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            log_path = Path("numbers_history") / f"{number}.txt"
            if not log_path.exists():
                await ctx.send(f"📭 No history found for `{number}`.")
                return

            with open(log_path, "r") as f:
                content = f.read()

            if len(content) <= 1900:
                await ctx.send(f"**📜 History for `{number}`:**\n```{content}```")
            else:
                # Send in chunks if over Discord message limit
                chunks = [content[i:i+1900] for i in range(0, len(content), 1900)]
                await ctx.send(f"**📜 History for `{number}`:**")
                for chunk in chunks:
                    await ctx.send(f"```{chunk}```")

        @self.bot.command(name="clear_history")
        async def clear_history(ctx, wa_id: str):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            file_path = Path(f"numbers_history/{wa_id}.txt")
            if file_path.exists():
                file_path.unlink()
                await ctx.send(f"🗑️ History for `{wa_id}` has been deleted.")
            else:
                await ctx.send(f"⚠️ No history found for `{wa_id}`.")
        
        @self.bot.command(name="clear_all_history")
        async def clear_all_history(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            history_folder = Path("numbers_history")
            if not history_folder.exists():
                await ctx.send("📭 No history folder found.")
                return

            deleted = 0
            for file in history_folder.glob("*.txt"):
                file.unlink()
                deleted += 1

            await ctx.send(f"🧹 Cleared {deleted} history file(s).")



        @self.bot.command(name="aboutme")
        async def aboutme(ctx):
            if ctx.author.id not in AUTHORIZED_USER_IDS:
                await ctx.send("⛔ Not authorized.")
                return

            help_text = (
                "**🤖 WhatsApp CRM Bot – User Guide**\n\n"
                "Here’s what I can help you with:\n\n"
                "🔒 **Blocking Contacts from using AI**\n"
                "`!block <number>` – Permanently block a WhatsApp contact from using the AI\n"
                "`!tempblock <number> <seconds>` – Temporarily block a number (minimum 90s)\n"
                "`!unblock <number>` – Unblock a contact\n"
                "`!blocktime <number>` – Check how long a temp block has left\n\n"
                "📢 **Broadcasting Messages**\n"
                "`!broadcast <message>` – Send a text message to all saved contacts\n"
                "`!broadcast_images <url1,url2,...> <caption>` – Send one or more images to all contacts\n"
                "`!broadcast_videos <url1,url2,...> <caption>` – Send a video to all contacts\n\n"
                "📬 **Didn’t Contact Us Broadcast Template List (ONLY USE '+' HERE)**\n"
                "`!set_broadcast_numbers <+9715xxxxxxxx>...` – Overwrite the broadcast file with new numbers\n"
                "`!add_broadcast_numbers <+9715xxxxxxxx>...` – Add one or more numbers\n"
                "`!remove_broadcast_numbers <+9715xxxxxxxx>...` – Remove one or more numbers\n"
                "`!list_broadcast_numbers` – Show all current broadcast numbers\n"
                "`!broadcast_template <template_name>` – Send a predefined WhatsApp template to broadcast numbers\n\n"
                "📨 **Direct Messaging**\n"
                "`!send_dm <9715xxxxxxxx> <message>` – Send a direct WhatsApp message to one number\n"
                "`!send_dm_multi <9715xxxxxxxx> <9715xxxxxxxx> ... | <message>` – Send a direct message to multiple numbers\n\n"
                "📋 **Lead Viewing**\n"
                "`!list_leads` – View recent and older contacted leads by status\n"
                "`!view_lead <number>` – View all saved metadata about a specific lead\n\n"
                "🚨 **Alerts**\n"
                "`!set_alert <9715xxxxxxxx>` – Mark a number to trigger a Discord alert when they message\n"
                "`!remove_alert <9715xxxxxxxx>` – Remove a number from alert watchlist\n"
                "`!show_alerts` – View all numbers currently on alert\n\n"
                "🧾 **Message History**\n"
                "`!history <number>` – Show the full message history of a lead\n"
                "`!clear_history <number>` – Delete the message history for a specific number\n"
                "`!clear_all_history` – Delete all message history records\n\n"
                "👥 **Manage Contact List**\n"
                "`!add_contact <number>` – Add a number to the broadcast contact list\n"
                "`!remove_contact <number>` – Remove a number from the list\n"
                "`!list_contacts` – View saved broadcast contacts\n\n"
                "🛠️ **Admin Tools**\n"
                "`!restartflask` – Restart the entire Flask + Discord system\n"
                "`!aboutme` – Show this help message\n\n"
                "⚠️ *Only authorized admins can use most of these commands.*"
            )


            # Discord character limit handling
            if len(help_text) > 1901:
                chunks = [help_text[i:i + 1901] for i in range(0, len(help_text), 1901)]
                for chunk in chunks:
                    await ctx.send(chunk)
            else:
                await ctx.send(help_text)




        @self.bot.event
        async def on_message(message):
            if message.author != self.bot.user:
                await self.bot.process_commands(message)

    def _run_bot(self):
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self.bot.start(DISCORD_TOKEN))

    def notify(self, message):
        async def send():
            await self.bot.wait_until_ready()
            channel = self.bot.get_channel(CHANNEL_ID)
            if channel:
                await channel.send(message)
            else:
                print("❌ Could not find the channel")
        asyncio.run_coroutine_threadsafe(send(), self.loop)

    def alert(self, message):
        async def send():
            await self.bot.wait_until_ready()
            channel = self.bot.get_channel(ALERT_CHANNEL_ID)
            if channel:
                await channel.send(message)
            else:
                print("❌ Could not find the channel")
        asyncio.run_coroutine_threadsafe(send(), self.loop)
