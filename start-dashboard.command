#!/bin/zsh

set -euo pipefail

PROJECT_DIR="/Users/puneet/Downloads/MBTA Widgets/MBTA"
URL="http://127.0.0.1:6000/dashboards/mbta-usage"
PORT="6000"
SERVER_CMD="cd \"$PROJECT_DIR\" && env PORT=$PORT python3 UsageDashboard/server.py"

if lsof -ti tcp:$PORT >/dev/null 2>&1; then
    open "$URL"
    exit 0
fi

osascript - "$PROJECT_DIR" "$PORT" <<'APPLESCRIPT'
on run argv
    set projectDir to item 1 of argv
    set portValue to item 2 of argv
    set shellCommand to "cd " & quoted form of projectDir & " && env PORT=" & portValue & " python3 UsageDashboard/server.py"

    tell application "Terminal"
        activate
        do script shellCommand
    end tell
end run
APPLESCRIPT

python3 - <<'PY'
import time
import urllib.request

url = "http://127.0.0.1:6000/dashboards/mbta-usage"

for _ in range(20):
    try:
        with urllib.request.urlopen(url, timeout=1) as response:
            if response.status == 200:
                break
    except Exception:
        time.sleep(0.5)
else:
    raise SystemExit("Dashboard server did not start on port 6000.")
PY

osascript - "$URL" <<'APPLESCRIPT'
on run argv
    set dashboardURL to item 1 of argv

    tell application "Safari"
        activate
        open location dashboardURL
    end tell
end run
APPLESCRIPT
