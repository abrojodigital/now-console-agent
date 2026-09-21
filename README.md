# NOW console agent

A small Windows program for ski-race timekeepers. It watches the folder where the
timing software (SKI PRO) writes its race files, and sends a **copy** of the race in
progress to [NOW](https://now-ski.com) — together with this PC's clock — so race videos can
be matched to racers by start time.

It is one PowerShell script with a WinForms window (pick the console, pick the folder,
press *Iniciar envío*), runs on Windows PowerShell 5.1 (which ships with Windows) and
installs nothing: to remove it, delete the folder.

> The server side is **not** in this repository, and the agent is useless without a
> per-console token issued by NOW.

## What it does — and refuses to do

- Looks in **one** folder for `Event*.scdb`, takes the pair written most recently, copies
  it to a temp folder, and uploads the copies. Nothing else is ever sent.
- **Never opens SKI PRO's live database** (a reader holding it is how a program causes
  "database is locked" mid-race). It waits while a `-journal` file is present.
- Uploads only when the bytes changed; sends a heartbeat every minute so the server can tell
  "idle" from "not running", and raises a connection alarm when the link drops.
- Measures the PC clock against the server (NTP-style, lowest round trip of three) — a
  timing box's own clock can be minutes off, and that is what this project exists to catch.
- No auto-update, by design: it stops and asks for a person.

## Use

1. Copy `settings.example.txt` to `settings.txt` and put the real console token(s) in it
   (`settings.txt` is git-ignored — it holds live tokens).
2. Double-click `start-agent.bat`. Choose the console and the folder, press **Iniciar envío**.
   Minimising sends it to the notification area, still sending.

End-user manual (Spanish): [`instructions-es.md`](instructions-es.md).

Headless (the old console output), useful for checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File now-console-agent.ps1 -NoGui -Token <token> -Folder "D:\skipro\events"
```

`-NoGui -Once` sends once and exits. **Without `-Url` that is a real upload** — point `-Url` at a
closed local port (`http://127.0.0.1:9/api/console/file`) when testing.

## Tests

No framework, no network (fake tokens, local closed port):

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File tests\Test-Agent.ps1
```

The exit code is the number of failures.

## Notes

- `now-console-agent.ps1` is saved as **UTF-8 with BOM**, on purpose: Windows PowerShell 5.1
  reads a BOM-less script as ANSI and the Spanish window would show mojibake. If an editor
  drops the BOM, the tests fail.
- Architecture, invariants and gotchas: [`CLAUDE.md`](CLAUDE.md). Version history:
  [`VERSION-ps-0.8.0.txt`](VERSION-ps-0.8.0.txt).
- No license file yet: until one is added, all rights are reserved.
