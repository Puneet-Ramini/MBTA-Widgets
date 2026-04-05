from __future__ import annotations

import json
import os
import plistlib
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
SIMULATOR_GLOB = (
    Path.home()
    / "Library/Developer/CoreSimulator/Devices"
)
APP_GROUP_PLIST_PATTERN = "*/data/Containers/Shared/AppGroup/*/Library/Preferences/group.Widgets.MBTA.plist"
REQUEST_LIMIT = 2000


def find_latest_plist() -> Path | None:
    candidates = list(SIMULATOR_GLOB.glob(APP_GROUP_PLIST_PATTERN))
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


def empty_snapshot(message: str) -> dict:
    return {
        "totalRequests": 0,
        "successRequests": 0,
        "failedRequests": 0,
        "endpointCounts": {},
        "sourceCounts": {},
        "dailyCounts": {},
        "hourlyCounts": {},
        "recentRequests": [],
        "lastUpdated": None,
        "limit": REQUEST_LIMIT,
        "remaining": REQUEST_LIMIT,
        "percentUsed": 0,
        "dataSource": message,
    }


def load_snapshot() -> dict:
    plist_path = find_latest_plist()
    if plist_path is None:
        return empty_snapshot("No simulator usage data found yet.")

    with plist_path.open("rb") as handle:
        plist_data = plistlib.load(handle)

    raw_snapshot = plist_data.get("apiUsageSnapshot")
    if raw_snapshot is None:
        return empty_snapshot(f"Found {plist_path}, but no API usage has been recorded yet.")

    if isinstance(raw_snapshot, bytes):
        snapshot = json.loads(raw_snapshot.decode("utf-8"))
    elif isinstance(raw_snapshot, str):
        snapshot = json.loads(raw_snapshot)
    else:
        return empty_snapshot(f"Could not decode usage data from {plist_path}.")

    total_requests = int(snapshot.get("totalRequests", 0))
    limit = int(plist_data.get("apiUsageLimit", REQUEST_LIMIT))
    remaining = max(limit - total_requests, 0)
    percent_used = min((total_requests / limit) * 100 if limit else 0, 100)

    return {
        **snapshot,
        "limit": limit,
        "remaining": remaining,
        "percentUsed": percent_used,
        "dataSource": str(plist_path),
    }


class DashboardHandler(SimpleHTTPRequestHandler):
    dashboard_path = "/dashboards/mbta-usage"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/stats":
            payload = load_snapshot()
            data = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        if parsed.path in {"/", "/index.html", self.dashboard_path}:
            return super().do_GET()

        self.send_error(404, "Not found")

    def translate_path(self, path: str) -> str:
        parsed = urlparse(path)
        if parsed.path == self.dashboard_path:
            relative = "index.html"
        else:
            relative = parsed.path.lstrip("/") or "index.html"
        return str(ROOT / relative)

    def log_message(self, format: str, *args) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {format % args}")


def main() -> None:
    port = int(os.environ.get("PORT", "3001"))
    server = ThreadingHTTPServer(("127.0.0.1", port), DashboardHandler)
    print(f"MBTA usage dashboard running at http://localhost:{port}{DashboardHandler.dashboard_path}")
    server.serve_forever()


if __name__ == "__main__":
    main()
