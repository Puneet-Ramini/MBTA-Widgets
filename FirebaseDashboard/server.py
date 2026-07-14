from __future__ import annotations

import json
import os
from collections import Counter
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import firebase_admin
from firebase_admin import credentials, firestore

ROOT = Path(__file__).resolve().parent

# --- Firebase init ---
SERVICE_ACCOUNT_PATH = ROOT / "serviceAccountKey.json"

if not firebase_admin._apps:
    if SERVICE_ACCOUNT_PATH.exists():
        cred = credentials.Certificate(str(SERVICE_ACCOUNT_PATH))
        firebase_admin.initialize_app(cred)
    else:
        firebase_admin.initialize_app()

db = firestore.client()

# Cache to avoid hammering Firestore on every poll
_cache: dict = {}
_cache_time: float = 0
CACHE_TTL = 10  # seconds


def _normalize_timestamp(ts) -> str | None:
    """Convert Firestore Timestamp or ISO string to a consistent ISO format."""
    if hasattr(ts, "isoformat"):
        return ts.isoformat()
    elif isinstance(ts, str):
        return ts.replace("Z", "+00:00") if ts.endswith("Z") else ts
    return None


def fetch_logs() -> list[dict]:
    """Fetch api_logs documents from Firestore (cached)."""
    global _cache, _cache_time

    now = datetime.now(timezone.utc).timestamp()
    if _cache and (now - _cache_time) < CACHE_TTL:
        return _cache["logs"]

    docs = db.collection("api_logs").limit(5000).stream()

    logs = []
    for doc in docs:
        data = doc.to_dict()
        data["timestamp"] = _normalize_timestamp(data.get("timestamp"))
        logs.append(data)

    # Sort in Python because Firestore can't sort mixed Timestamp/string types
    logs.sort(key=lambda l: l.get("timestamp") or "", reverse=True)

    _cache = {"logs": logs}
    _cache_time = now
    return logs


def build_stats() -> dict:
    logs = fetch_logs()
    total = len(logs)
    success = sum(1 for l in logs if l.get("status_code") is not None and 200 <= l["status_code"] <= 299)
    failed = sum(1 for l in logs if l.get("status_code") is not None and not (200 <= l["status_code"] <= 299))

    endpoint_counts = dict(Counter(l.get("endpoint", "unknown") for l in logs))
    source_counts = dict(Counter(l.get("source", "unknown") for l in logs))
    unique_devices = len({l.get("device_id") for l in logs if l.get("device_id")} - {"firebase-cloud-function"})

    daily_counts: dict[str, int] = {}
    hourly_counts: dict[str, int] = {}
    minute_counts: dict[str, int] = {}

    for l in logs:
        ts_str = l.get("timestamp")
        if not ts_str:
            continue
        try:
            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            continue
        day_key = ts.strftime("%Y-%m-%d")
        hour_key = ts.strftime("%Y-%m-%d %H")
        minute_key = ts.strftime("%Y-%m-%d %H:%M")
        daily_counts[day_key] = daily_counts.get(day_key, 0) + 1
        hourly_counts[hour_key] = hourly_counts.get(hour_key, 0) + 1
        minute_counts[minute_key] = minute_counts.get(minute_key, 0) + 1

    recent = []
    for l in logs[:100]:
        recent.append({
            "timestamp": l.get("timestamp"),
            "endpoint": l.get("endpoint", "unknown"),
            "source": l.get("source", "unknown"),
            "statusCode": l.get("status_code"),
            "routeName": l.get("route_name"),
            "directionName": l.get("direction_name"),
            "stopName": l.get("stop_name"),
            "deviceId": l.get("device_id"),
            "responseTimeMs": l.get("response_time_ms"),
        })

    last_updated = logs[0].get("timestamp") if logs else None

    return {
        "totalRequests": total,
        "successRequests": success,
        "failedRequests": failed,
        "uniqueDevices": unique_devices,
        "endpointCounts": endpoint_counts,
        "sourceCounts": source_counts,
        "dailyCounts": daily_counts,
        "hourlyCounts": hourly_counts,
        "minuteCounts": minute_counts,
        "recentRequests": recent,
        "lastUpdated": last_updated,
        "dataSource": "Firebase Firestore — api_logs collection",
    }


class DashboardHandler(SimpleHTTPRequestHandler):
    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/stats":
            payload = build_stats()
            data = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        if parsed.path in {"/", "/index.html"}:
            return super().do_GET()

        self.send_error(404, "Not found")

    def translate_path(self, path: str) -> str:
        parsed = urlparse(path)
        relative = parsed.path.lstrip("/") or "index.html"
        return str(ROOT / relative)

    def log_message(self, format: str, *args) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {format % args}")


def main() -> None:
    port = int(os.environ.get("PORT", "3002"))
    server = ThreadingHTTPServer(("127.0.0.1", port), DashboardHandler)
    print(f"Firebase Usage Dashboard running at http://localhost:{port}")
    print("Press Ctrl+C to stop.")
    server.serve_forever()


if __name__ == "__main__":
    main()
