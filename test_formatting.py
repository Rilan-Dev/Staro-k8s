from datetime import datetime, timedelta, timezone
import json
from dateutil import parser

# Mocking the format_group function from main.py for testing
def format_group(header: str, alerts: list) -> str:
    lines = [f"<b>{header} ({len(alerts)})</b>"]
    
    for alert in alerts:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        
        name = labels.get("alertname", "Unknown")
        severity = labels.get("severity", "unknown")
        namespace = labels.get("namespace", "unknown")
        summary = annotations.get("summary") or annotations.get("message") or annotations.get("description") or "No description"
        
        # Icon based on severity
        sev_icon = "🔴" if severity == "critical" else "⚠️"
        
        # Duration for resolved
        duration_str = ""
        if alert.get("status") == "resolved":
            starts = alert.get("startsAt")
            ends = alert.get("endsAt")
            if starts and ends:
                try:
                    s_dt = parser.isoparse(starts)
                    e_dt = parser.isoparse(ends)
                    diff = e_dt - s_dt
                    # simple format
                    hours, remainder = divmod(int(diff.total_seconds()), 3600)
                    minutes, _ = divmod(remainder, 60)
                    duration_str = f" (Duration: {hours}h {minutes}m)"
                except Exception as e:
                    print(e)
        
        lines.append(f"\n{sev_icon} <b>{name}</b> {duration_str}")
        lines.append(f"Namespace: <code>{namespace}</code>")
        lines.append(f"<i>{summary}</i>")

    return "\n".join(lines)

# Sample Data
now = datetime.now(timezone.utc)
past = now - timedelta(hours=2, minutes=30)

firing_alerts = [
    {
        "status": "firing",
        "labels": {"alertname": "HighCPU", "severity": "critical", "namespace": "prod"},
        "annotations": {"summary": "CPU usage is > 90%"}
    },
    {
        "status": "firing",
        "labels": {"alertname": "PodRestarting", "severity": "warning", "namespace": "prod"},
        "annotations": {"summary": "Pod restarted 5 times"}
    }
]

resolved_alerts = [
    {
        "status": "resolved",
        "startsAt": past.isoformat(),
        "endsAt": now.isoformat(),
        "labels": {"alertname": "MemoryLeak", "severity": "warning", "namespace": "dev"},
        "annotations": {"summary": "Memory usage high"}
    }
]

print("--- FIRING ---")
print(format_group("🔥 FIRING", firing_alerts))
print("\n--- RESOLVED ---")
print(format_group("✅ RESOLVED", resolved_alerts))
