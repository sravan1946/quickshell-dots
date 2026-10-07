# /// script
# requires-python = ">=3.11"
# dependencies = ["icalendar>=6", "recurring-ical-events>=3"]
# ///
"""Google Calendar events for the bar's calendar, from the calendar's secret iCal
address (read-only, no OAuth). Prints one JSON object:
  {"events": [{title, start, end, allDay, location, link}], "fetched": epoch_ms, "stale": bool,
   "owner": calendar email, "tz": IANA zone (for new-event links)}
with recurring events expanded over [today - 60d, today + 180d], times in local time.

The URL lives in ~/.local/share/quickshell-bar/gcal-ics.url (mode 600). The last good
feed is cached, so a failed fetch still prints events (stale: true).
"""
import base64
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import icalendar
import recurring_ical_events

URL_FILE = Path.home() / ".local/share/quickshell-bar/gcal-ics.url"
CACHE = Path.home() / ".cache/quickshell-bar/gcal.ics"


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            data = r.read()
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_bytes(data)
        CACHE.chmod(0o600)   # it's the whole calendar
        return data, False
    except Exception as e:
        if CACHE.exists():
            print(f"gcal: fetch failed ({e}); using cache", file=sys.stderr)
            return CACHE.read_bytes(), True
        raise


def local(v):
    """iCal value -> (local naive datetime, all_day)."""
    if isinstance(v, datetime):
        return (v.astimezone() if v.tzinfo else v).replace(tzinfo=None), False
    return datetime(v.year, v.month, v.day), True


def link(uid, start, recurring, all_day, owner):
    # Google's event page takes eid = base64("<event id> <calendar email>"); a recurring
    # instance's id is "<series id>_<UTC start>" (date only for all-day events)
    eid = uid.removesuffix("@google.com")
    if recurring:
        eid += "_" + (start.strftime("%Y%m%d") if all_day else start.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    token = base64.urlsafe_b64encode(f"{eid} {owner}".encode()).decode().rstrip("=")
    # the event's view page (Google's own share-link form), not the editor.
    # authuser=<email>: open it in that signed-in account, not the browser's default one.
    # (An email in the path, /u/<email>/, 404s on Calendar.)
    return f"https://calendar.google.com/calendar/event?eid={token}&authuser={urllib.parse.quote(owner)}"


def main():
    url = URL_FILE.read_text().strip()
    owner = urllib.parse.unquote(url.split("/ical/")[1].split("/")[0])
    data, stale = fetch(url)
    cal = icalendar.Calendar.from_ical(data)
    today = date.today()
    out = []
    for ev in recurring_ical_events.of(cal).between(today - timedelta(days=60), today + timedelta(days=180)):
        if str(ev.get("STATUS", "")).upper() == "CANCELLED":
            continue
        s_raw = ev["DTSTART"].dt
        start, all_day = local(s_raw)
        end = local(ev["DTEND"].dt)[0] if ev.get("DTEND") else start + timedelta(days=1 if all_day else 0)
        out.append({
            "title": str(ev.get("SUMMARY", "(no title)")),
            "start": start.isoformat(),
            "end": end.isoformat(),
            "allDay": all_day,
            "location": str(ev.get("LOCATION", "")),
            "link": link(str(ev.get("UID", "")), s_raw, bool(ev.get("RRULE") or ev.get("RECURRENCE-ID")), all_day, owner),
        })
    out.sort(key=lambda e: (e["start"], not e["allDay"]))
    tz = str(Path("/etc/localtime").resolve()).split("zoneinfo/")[-1]
    print(json.dumps({"events": out, "fetched": int(time.time() * 1000), "stale": stale, "owner": owner, "tz": tz}))


if __name__ == "__main__":
    main()
