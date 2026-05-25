---
name: rmsync
description: Sync reMarkable Quick Sheets notebook to Obsidian via Claude Code
---

# Skill: /rmsync — reMarkable Quick Sheets → Obsidian

> **Scope:** This skill syncs the built-in **Quick Sheets** notebook only — the one accessible with a swipe from any reMarkable screen. Not for arbitrary notebooks.

## First time setup

Before running the sync, check if SSH works:
```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes root@10.11.99.1 "echo ok" 2>/dev/null \
  || echo "UNREACHABLE"
```

If `UNREACHABLE`, guide the user through setup step by step:

**Step 1 — Find the root password**
Tell the user: *"On your reMarkable, go to Settings → Help → Copyrights and licenses and scroll to the bottom. You'll see the root password there."*

**Step 2 — Connect via USB**
Tell the user: *"Connect your reMarkable to your Mac with the USB cable. The IP over USB is always `10.11.99.1`."*

**Step 3 — Copy SSH key**
Ask the user to run in their terminal:
```
! ssh-copy-id -i ~/.ssh/id_ed25519.pub -o PubkeyAuthentication=no root@10.11.99.1
```
Tell them to enter the password from step 1 when prompted.

**Step 4 — Test**
```bash
ssh -o ConnectTimeout=5 root@10.11.99.1 "echo connected"
```
If successful: *"SSH is set up. You can unplug the cable — the connection also works over WiFi."*
Then continue with the regular sync process.

---

## Triggers

Run this skill when the user types any of:
- `/rmsync`
- "sync my reMarkable"
- "sync my notes"
- "import from reMarkable"
- "import quick sheets"
- "sync the tablet"

---

## ⚙️ USER CONFIGURATION
<!-- Edit these values once to match your setup -->

```
VAULT_PATH   = ~/path/to/your/ObsidianVault
INBOX_PATH   = 00_Inbox/reMarkable          (relative to vault, where notes land)
SYNC_LOG     = _sync_log.md                 (relative to vault, tracks sync state)
SCRIPT_PATH  = .claude/skills/scripts/rm-convert.sh

DOC_ID       = f4e87156-14ee-4872-bc6f-feb4e3a77cad   (your Quick Sheets UUID)
RM_IP_WIFI   = 192.168.1.x                 (find in reMarkable Settings → Help)
RM_IP_USB    = 10.11.99.1                  (constant when connected via USB)
RM_MAC       = xx:xx:xx:xx:xx:xx           (find in reMarkable Settings → Help, used for auto-discovery)
RMC_PATH     = rmc                         (or full path, e.g. ~/bin/rmc)
```

---

## Process

### Step 1 — Read sync state

Read `SYNC_LOG`. Extract:
- `next_page` (integer) — the next page number to import
- Any known IP addresses for the reMarkable

### Step 2 — Connect to reMarkable

Try known IPs first, then fall back to MAC-based discovery:

```bash
# 1. Try stored WiFi IP
ssh -o ConnectTimeout=5 -o BatchMode=yes root@<RM_IP_WIFI> "echo ok" 2>/dev/null && echo "OK:<RM_IP_WIFI>"

# 2. Try USB
ssh -o ConnectTimeout=5 -o BatchMode=yes root@<RM_IP_USB> "echo ok" 2>/dev/null && echo "OK:<RM_IP_USB>"

# 3. Auto-discover via MAC address (when IP has changed)
for i in $(seq 1 254); do ping -c1 -W1 <subnet>.$i > /dev/null 2>&1 & done; wait
arp -a | grep -i "<RM_MAC>"
```

- Use the first IP that responds.
- If MAC discovery finds a new IP: update `RM_IP_WIFI` in the config and tell the user.
- If nothing responds: tell the user the reMarkable is not reachable and stop.
- Note which IP worked — use it for all subsequent commands.

### Step 3 — Run conversion script

One single bash call:
```bash
bash <SCRIPT_PATH> <ip> <DOC_ID> <next_page> /tmp/rm_sync <RMC_PATH>
```

The script outputs lines like:
```
PAGE:42:/tmp/rm_sync/page_42.svg.png:85299
```

Collect all `PAGE:` lines. If none: tell the user "No new pages found" and stop.

### Step 4 — OCR all pages

Read all PNG files (batch 3–4 at a time if needed).

For each page, note:
- Page number
- Meeting title and date (from handwriting)
- Key bullet points
- Identifiable action points (tasks, follow-ups, things to send)

Skip pages that appear blank or contain only scribbles.

### Step 5 — Show transcriptions for verification

Present a compact summary before saving anything:

```
## Transcriptions — please verify

**Page 42 – Team meeting 25 May**
- Point 1
- Point 2

**Page 43 – 1:1 with Alice**
- ...

Uncertain readings marked with [?].
Does this look right? (Reply "yes" to save, or correct specific pages.)
```

Wait for user confirmation before writing any files.

### Step 6 — Write markdown files

For each confirmed page, create a file in `INBOX_PATH`:

Filename: `YYYY-MM-DD Description.md`

Template:
```markdown
# [Meeting name] [Date]

*Imported from reMarkable Quick Sheets page [N]*
*Client: [[Client name]]* (if applicable)

---

[Transcribed content with headings]

---

## Action Points
- [ ] [Task 1]
- [ ] [Task 2]
```

### Step 7 — Update sync log

In `SYNC_LOG`, update:
- `Last synced` → today's date
- `Next page to import` → last imported page + 1
- Append a table row for each imported or skipped page

### Step 8 — Report

```
Imported X pages (pages A–B):
- 2026-05-25 Team meeting.md
- 2026-05-25 1-1 Alice.md

Action points to follow up:
- [ ] AP 1 (source: page 42)
- [ ] AP 2 (source: page 43)

Skipped: [page numbers and reason]
```

---

## Notes

### Finding your Quick Sheets document ID
```bash
ssh root@10.11.99.1 \
  "ls /home/root/.local/share/remarkable/xochitl/*.content" \
  | xargs -I{} basename {} .content
```
Match UUIDs against notebook names in the reMarkable app.

### rmc compatibility patch (firmware 3.x)
If `rmc` fails with `KeyError` on color IDs, apply this one-time fix:
```bash
SITE=$(python3 -c "import rmc, os; print(os.path.dirname(rmc.__file__))")
sed -i '' \
  's/RM_PALETTE\[base_color_id\]/RM_PALETTE.get(base_color_id, (251, 247, 25))/' \
  "$SITE/exporters/writing_tools.py"
```

### SSH key setup (first time only)
```bash
# Connect reMarkable via USB, then:
ssh-copy-id -i ~/.ssh/id_ed25519.pub -o PubkeyAuthentication=no root@10.11.99.1
# Root password: reMarkable → Settings → Help → Copyrights and licenses (scroll to bottom)
```
