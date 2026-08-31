# Pipeline Automation — Control Guide

You have **two modes**: manual (run whenever you want) and automatic (every 15 min).
Both use the same `run_pipeline.bat` under the hood.

---

## Mode 1 — Manual (always available)

Just **double-click `run_pipeline.bat`** in the project root.

That's it. No setup needed. The pipeline runs once, updates everything (DB, star schema, predictions), and exits.

```
run_pipeline.bat        ← double-click to run now
run_pipeline.bat --mock ← run with fake data (no API keys needed, for testing)
```

---

## Mode 2 — Automatic (every 15 minutes, optional)

Use the scripts in this folder to turn the scheduler ON or OFF whenever you want.

| What you want to do | Script to run | Needs Admin? |
|---|---|---|
| **First-time setup** (register the task) | `install_schedule.bat` | ✅ Yes |
| **Turn ON** auto-run | `start_schedule.bat` | ✅ Yes |
| **Turn OFF** auto-run | `stop_schedule.bat` | ✅ Yes |
| **Check status** (is it running or stopped?) | `schedule_status.bat` | ❌ No |

> **How to run as Administrator:**
> Right-click the `.bat` file → **Run as administrator**

---

## Typical Workflow

```
Day 1 — Setup
  1. install_schedule.bat (as Admin) — registers the task once
  2. start_schedule.bat   (as Admin) — turns it on → pipeline runs every 15 min

Anytime — Manual run
  → double-click run_pipeline.bat
  → data fetched, DB updated, predictions refreshed immediately

When you want to pause collection (e.g. going offline)
  → stop_schedule.bat (as Admin) — pauses auto-run, data is safe

When you want to resume
  → start_schedule.bat (as Admin) — turns it back on
```

---

## What each script does internally

| Script | Internal action |
|---|---|
| `install_schedule.bat` | `schtasks /create /xml schedule_pipeline.xml` |
| `start_schedule.bat` | `schtasks /change /enable` (also registers if missing) |
| `stop_schedule.bat` | `schtasks /change /disable` (task stays registered, just paused) |
| `schedule_status.bat` | `schtasks /query /fo LIST` (read-only, no changes) |

> [!NOTE]
> `stop_schedule.bat` **never deletes** the task — it only pauses it.
> Your database, model, and all data are completely untouched when you stop the scheduler.
