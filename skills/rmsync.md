---
name: rmsync
description: Sync reMarkable Quick Sheets notebook to Obsidian via Claude Code
---

# Skill: /rmsync — reMarkable Quick Sheets → Obsidian

> **Scope:** This skill syncs the built-in **Quick Sheets** notebook only — the one accessible with a swipe from any reMarkable screen. Not for arbitrary notebooks.

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

## Step 0 — Read config from sync log

Read `SYNC_LOG` (default: `_rmsync_log.md` in the vault root). All config and state lives here — never in this skill file.

Extract:
- `VAULT_PATH`, `INBOX_PATH`, `DOC_ID`, `RM_IP_WIFI`, `RM_IP_USB`, `RM_MAC` (optional), `RMC_PATH`
- `next_page` — the next page number to import

If the sync log doesn't exist yet: run **First time setup** below.

---

## First time setup

Run this when the sync log is missing or SSH has never been configured.

### 1 — Check SSH

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes root@10.11.99.1 "echo ok" 2>/dev/null || echo "UNREACHABLE"
```

If `UNREACHABLE`:
- Tell the user: *"Connect your reMarkable via USB cable. The IP over USB is always `10.11.99.1`."*
- Tell the user: *"Go to Settings → Help → Copyrights and licenses on your reMarkable and scroll to the bottom — you'll find the root password there."*
- Ask the user to run:
  ```
  ! ssh-copy-id -i ~/.ssh/id_ed25519.pub -o PubkeyAuthentication=no root@10.11.99.1
  ```
- Test again. If successful: *"SSH is set up — you can unplug the cable, it also works over WiFi."*

### 2 — Auto-discover Quick Sheets DOC_ID

```bash
ssh root@10.11.99.1 \
  "grep -rl 'Quick sheets' /home/root/.local/share/remarkable/xochitl/*.metadata 2>/dev/null \
  | xargs -I{} basename {} .metadata"
```

Use the returned UUID as `DOC_ID`. Tell the user what was found.

### 3 — Check and patch rmc

```bash
python3 -c "
import rmc.exporters.writing_tools as wt
print('PATCH_NEEDED' if 'RM_PALETTE[base_color_id]' in open(wt.__file__).read() else 'OK')
"
```

If `PATCH_NEEDED`, apply automatically:
```bash
SITE=$(python3 -c "import rmc, os; print(os.path.dirname(rmc.__file__))")
sed -i '' \
  's/RM_PALETTE\[base_color_id\]/RM_PALETTE.get(base_color_id, (251, 247, 25))/' \
  "$SITE/exporters/writing_tools.py"
```
Tell the user: *"Applied a one-time compatibility fix for your reMarkable firmware."*

### 4 — Create sync log

Ask the user for:
- Path to their vault (`VAULT_PATH`)
- Where imported notes should land (`INBOX_PATH`, default: `00_Inbox/reMarkable`)
- Path to `rmc` if not in PATH (`RMC_PATH`, default: `rmc`)

Then get the current WiFi IP:
```bash
ssh root@10.11.99.1 "ip addr show wlan0 | grep 'inet '" 2>/dev/null
```

Create `_rmsync_log.md` in the vault with the discovered values (see sync log format below).
Also create `INBOX_PATH` folder if it doesn't exist.

---

## Process

### Step 1 — Connect to reMarkable

Try IPs in order, fall back to MAC discovery if `RM_MAC` is set:

```bash
# Try stored WiFi IP
ssh -o ConnectTimeout=5 -o BatchMode=yes root@<RM_IP_WIFI> "echo ok" 2>/dev/null

# Try USB fallback
ssh -o ConnectTimeout=5 -o BatchMode=yes root@<RM_IP_USB> "echo ok" 2>/dev/null

# Auto-discover via MAC (if RM_MAC is set and above failed)
SUBNET=$(ipconfig getifaddr en0 | sed 's/\.[0-9]*$//')
for i in $(seq 1 254); do ping -c1 -W1 $SUBNET.$i > /dev/null 2>&1 & done; wait
arp -a | grep -i "<RM_MAC>"
```

- Use the first IP that responds.
- If MAC discovery finds a new IP: update `RM_IP_WIFI` in the sync log and tell the user.
- If nothing responds: tell the user the reMarkable is not reachable and stop.

### Step 2 — Run conversion script

```bash
bash <SCRIPT_PATH> <ip> <DOC_ID> <next_page> /tmp/rm_sync <RMC_PATH>
```

Output lines: `PAGE:42:/tmp/rm_sync/page_42.svg.png:85299`

If none: *"No new pages found."* and stop.

### Step 3 — OCR all pages

Read all PNG files (batch 3–4 at a time).

For each page, note:
- Meeting title and date
- Key bullet points
- Action points (tasks, follow-ups, things to send)

Skip blank pages or scribbles.

### Step 4 — Show transcriptions for verification

```
## Transcriptions — please verify

**Page 42 – Team meeting 25 May**
- Point 1
- Point 2

Uncertain readings marked with [?].
Does this look right? (Reply "yes" to save, or correct specific pages.)
```

Wait for confirmation before writing any files.

### Step 5 — Write markdown files

Filename: `YYYY-MM-DD Description.md` in `INBOX_PATH`.

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
```

### Step 6 — Update sync log

Update in `_rmsync_log.md`:
- `Last synced` → today's date
- `Next page` → last imported page + 1
- Append table row for each imported/skipped page

### Step 7 — Report

```
Imported X pages (A–B):
- 2026-05-25 Team meeting.md

Action points:
- [ ] AP 1 (page 42)

Skipped: [list with reason]
```

---

## Sync log format

`_rmsync_log.md` stores both config and state:

```markdown
# reMarkable Sync Log

## Config
- VAULT_PATH: ~/path/to/vault
- INBOX_PATH: 00_Inbox/reMarkable
- DOC_ID: (auto-discovered)
- RM_IP_WIFI: 192.168.1.x
- RM_IP_USB: 10.11.99.1
- RM_MAC: (optional)
- RMC_PATH: rmc

## State
- Last synced: never
- Next page: 1

## Import history

| Page | Date | File | Status |
|------|------|------|--------|
```
