#!/usr/bin/env bash
# rm-convert.sh — Download and convert reMarkable Quick Sheets pages to PNG
#
# Usage:
#   ./rm-convert.sh <rm_ip> <doc_id> <start_page> <out_dir> [rmc_path]
#
# Output:
#   Prints JSON to stdout:
#   { "pages": [ { "num": 749, "file": "/tmp/.../page_749.png", "size": 85299 }, ... ] }

set -euo pipefail

RM_IP="${1:?Missing reMarkable IP}"
DOC_ID="${2:?Missing document ID}"
START_PAGE="${3:?Missing start page}"
OUT_DIR="${4:?Missing output directory}"
RMC="${5:-rmc}"

RM_BASE="/home/root/.local/share/remarkable/xochitl"
CONTENT_FILE="${RM_BASE}/${DOC_ID}.content"

mkdir -p "$OUT_DIR"

# Download .content file
scp -q "root@${RM_IP}:${CONTENT_FILE}" "${OUT_DIR}/content.json" 2>/dev/null

# Parse active pages from start_page onwards
PAGES=$(python3 - <<PYEOF
import json, sys

with open('${OUT_DIR}/content.json') as f:
    content = json.load(f)

pages = content['cPages']['pages']
result = []
for i, page in enumerate(pages[${START_PAGE}-1:], start=${START_PAGE}):
    deleted = False
    d = page.get('deleted', {})
    if isinstance(d, dict) and d.get('value', 0) == 1:
        deleted = True
    result.append({'num': i, 'id': page['id'], 'deleted': deleted})

print(json.dumps(result))
PYEOF
)

# Download, convert, and collect results
OUTPUT_PAGES="[]"

while IFS= read -r entry; do
    NUM=$(echo "$entry" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['num'])")
    ID=$(echo "$entry"  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])")
    DELETED=$(echo "$entry" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['deleted'])")

    if [ "$DELETED" = "True" ]; then
        continue
    fi

    RM_FILE="${OUT_DIR}/page_${NUM}.rm"
    SVG_FILE="${OUT_DIR}/page_${NUM}.svg"
    PNG_FILE="${OUT_DIR}/page_${NUM}.svg.png"

    # Download .rm file
    scp -q "root@${RM_IP}:${RM_BASE}/${DOC_ID}/${ID}.rm" "$RM_FILE" 2>/dev/null || continue

    SIZE=$(stat -f%z "$RM_FILE" 2>/dev/null || stat -c%s "$RM_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -lt 3000 ]; then
        continue  # Skip empty pages
    fi

    # Convert rm -> svg
    "$RMC" -t svg "$RM_FILE" -o "$SVG_FILE" 2>/dev/null || continue

    # Convert svg -> png
    qlmanage -t -s 2000 -o "$OUT_DIR/" "$SVG_FILE" >/dev/null 2>&1 || continue

    if [ -f "$PNG_FILE" ]; then
        echo "PAGE:${NUM}:${PNG_FILE}:${SIZE}"
    fi
done < <(echo "$PAGES" | python3 -c "
import json, sys
pages = json.load(sys.stdin)
for p in pages:
    print(json.dumps(p))
")
