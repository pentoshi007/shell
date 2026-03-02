# Shell C2 — Usage Guide

## Architecture

```
[Mac] server.py  ←—Cloudflare Tunnel—→  [Windows] pdf2.ps1
  operator types commands                 executes & streams output back
```

- `server.py` runs on your **Mac** and is your operator interface.
- `pdf2.ps1` runs on the **Windows** target, connects back via Cloudflare Tunnel, and executes commands.

---

## Starting Up

**Mac (server):**

```bash
python3 server.py
```

**Windows (client):** Run `pdf2.ps1` with PowerShell. It self-elevates to admin and installs a scheduled task for persistence.

---

## Operator Commands (typed in server.py terminal)

These are built-in commands — they are NOT sent to the remote shell.

| Command           | What it does                                                           |
| ----------------- | ---------------------------------------------------------------------- |
| `help`            | Show the list of built-in commands                                     |
| `status`          | Check if the client is online/offline and whether a command is running |
| `cancel`          | Abort the currently running remote command                             |
| `exit`            | Tell the client to shut itself down                                    |
| _(anything else)_ | Sent as a command to the remote Windows shell                          |

---

## Sending Remote Commands

Just type any shell command at the `shell>` prompt and press Enter. It will be sent to the Windows client, executed, and the output streamed back.

```
shell> whoami
shell> ipconfig /all
shell> dir C:\Users
```

The command header shows the full path and active timeout mode:

```
PS C:\Windows\system32> whoami [300s]
```

---

## Cancelling a Running Command

Type `cancel` at the `shell>` prompt while a command is executing:

```
shell> cancel
```

The server queues a cancel signal. The client picks it up on its next poll cycle (~200ms), stops the command, and sends back:

```
[!] Command cancelled by operator.
```

> **Note:** If no command is running, `cancel` will print `[*] No command is currently running.`

---

## Long-Running Commands (No Timeout)

By default commands time out after **300 seconds**. To run a command with no timeout, prefix it with `notimeout:`:

```
shell> notimeout:ping -t google.com
shell> notimeout:netstat -an
```

The header will confirm the mode:

```
PS C:\> ping -t google.com [no-timeout]
```

Use `cancel` to stop a no-timeout command when done.

---

## Checking Client Connectivity

```
shell> status
```

Output examples:

```
[*] Client ONLINE (IDLE) — last check-in 1.2s ago
[*] Client ONLINE (RUNNING command) — last check-in 0.4s ago
[!] Client may be OFFLINE — last check-in 45s ago
[*] No client check-in yet.
```

The server also automatically warns you if there has been no check-in for more than 20 seconds.

---

## Viewing Truncated Output (Full Result)

> ⚠️ **Not Available.** There is no built-in command to retrieve the full output of a truncated result.

Output chunks are capped at **32,000 bytes** per send. If a command produces more than that in a single streaming interval, the chunk is trimmed with `[...truncated]` appended.

**Workarounds:**

- Pipe output to a file on the target and retrieve it in parts:
  ```
  shell> some-command > C:\output.txt
  shell> Get-Content C:\output.txt -TotalCount 100
  shell> Get-Content C:\output.txt -Tail 100
  ```
- Use `Select-Object` or `head`/`tail` equivalents to limit output at the source.
- For directory listings, filter with `-Filter` or `Where-Object` instead of listing everything.

---

## Persistence & Crash Recovery

The client installs itself as a Windows Scheduled Task named `SystemManagementUpdate`:

- **Trigger:** At system startup
- **Restart on failure:** Up to 3 automatic restarts with a 10-second delay between each

If the process crashes mid-session, it will restart automatically (up to 3 times) without requiring a reboot.

---

## Log File

The client logs activity to `shell.txt` in the same directory as `pdf2.ps1`. Logs rotate automatically when the file exceeds 5 MB (old log saved as `shell.txt.old`).

Log entries include timestamps, levels (`INFO` / `WARN` / `ERROR`), and events like:

- Client start / PID
- Commands received
- Timeouts and cancellations
- Connection errors and retry counts
- Runspace (re)creation

---

## Output Streaming Behaviour

Output is streamed back **adaptively** — not on a fixed timer:

| Condition                    | Flush interval |
| ---------------------------- | -------------- |
| Output flowing actively      | ~200 ms        |
| No output for a few cycles   | ~500 ms        |
| Idle (no output for a while) | ~1000 ms       |

This means interactive commands feel snappy, while idle commands don't waste bandwidth.

---

## Tips

- Always check `status` before sending a command to confirm the client is online.
- Use `cancel` instead of closing the server — it cleanly stops the remote process.
- Prefer piping verbose commands to a file on the target and reading it in chunks to avoid output truncation.
- The `notimeout:` prefix is for commands you know will run long — always `cancel` them when done.
