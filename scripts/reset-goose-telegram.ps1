# Full Goose Telegram reset: fresh agent session, restart stack, verify tools.
$ErrorActionPreference = 'Stop'
$GooseExe = 'C:\Users\cjfit\Tools\goose\dist-windows\resources\bin\goose.exe'
$GooseDesktop = 'C:\Users\cjfit\Tools\goose\dist-windows\Goose.exe'
$ConfigPath = 'C:\Users\cjfit\AppData\Roaming\Block\goose\config\config.yaml'
$BotToken = '8941919067:AAFkkCnS0vZvlQppt9EgEtEF2qaD4HJo028'
$ChatId = '7993462191'
$WorkDir = 'C:\Users\cjfit'

function Fail($msg) { Write-Error $msg; exit 1 }

Write-Host '== 1/6 Stop gateway + hung goose runs =='
Get-CimInstance Win32_Process | Where-Object {
  ($_.Name -eq 'goose.exe' -and $_.CommandLine -match 'gateway start telegram|goose\.exe run')
} | ForEach-Object {
  Write-Host "  stop pid $($_.ProcessId)"
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

Write-Host '== 2/6 Apply agent config (direct developer tools, not code_execution) =='
& "$PSScriptRoot\configure-goose-agent.ps1" 2>$null
if (-not (Test-Path "$PSScriptRoot\configure-goose-agent.ps1")) {
  & '\\wsl.localhost\Ubuntu\home\chris\repos\random-general-repo-cursor-remote-control\scripts\configure-goose-agent.ps1'
}
# code_execution adds heavy execute_typescript layer; use developer shell directly
$config = Get-Content $ConfigPath -Raw
$config = $config -replace '(?ms)(  code_execution:\r?\n    enabled: )true', '${1}false'
$config = $config -replace '(?m)^GOOSE_MODE:.*$', 'GOOSE_MODE: auto'
Set-Content -Path $ConfigPath -Value $config -NoNewline

Write-Host '== 3/6 Restart goose serve (desktop backend) =='
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*goose.exe serve*' } | ForEach-Object {
  Write-Host "  stop serve pid $($_.ProcessId)"
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Get-Process Goose -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process $GooseDesktop | Out-Null
$deadline = (Get-Date).AddSeconds(45)
do {
  Start-Sleep -Seconds 2
  $serve = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*goose.exe serve*' } | Select-Object -First 1
} while (-not $serve -and (Get-Date) -lt $deadline)
if (-not $serve) { Fail 'goose serve did not restart' }
Write-Host "  serve pid $($serve.ProcessId)"

Write-Host '== 4/6 Create fresh Telegram agent session =='
Push-Location $WorkDir
try {
  $init = & $GooseExe run -t 'Reply with exactly: AGENT-READY' --no-session 2>&1 | ForEach-Object { "$_" }
  $initText = $init -join "`n"
  if ($initText -notmatch 'AGENT-READY') { Fail "Session init failed:`n$initText" }
  if ($initText -match '(\d{8}_\d+)') { $newSession = $Matches[1] } else { Fail "Could not parse new session id from:`n$initText" }
  Write-Host "  new session $newSession"

  $toolOut = & $GooseExe run -t 'Use the shell tool to run: echo TELEGRAM-AGENT-OK. Reply with output only.' --resume --session-id $newSession 2>&1 | ForEach-Object { "$_" }
  $toolText = $toolOut -join "`n"
  if ($toolText -notmatch 'TELEGRAM-AGENT-OK') { Fail "Tool test on new session failed:`n$toolText" }
  Write-Host '  tools OK on new session'
} finally {
  Pop-Location
}

Write-Host '== 5/6 Point Telegram pairing at new session =='
$config = Get-Content $ConfigPath -Raw
$config = $config -replace '(?ms)(gateway_pairings:\r?\n- platform: telegram\r?\n  user_id: ''7993462191''\r?\n  display_name: Chris Chacon\r?\n  state:\r?\n    state: paired\r?\n    session_id: )\d{8}_\d+', "`${1}$newSession"
if ($config -notmatch "session_id: $newSession") {
  Fail "Failed to update pairing session_id in config"
}
Set-Content -Path $ConfigPath -Value $config -NoNewline
Write-Host "  paired -> $newSession"

Write-Host '== 6/6 Start Telegram gateway =='
Start-Process -FilePath $GooseExe -ArgumentList @('gateway','start','telegram','--bot-token',$BotToken) -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 3
$gw = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'goose\.exe"?\s+gateway\s+start\s+telegram' } | Select-Object -First 1
if (-not $gw) { Fail 'Gateway failed to start' }
Write-Host "  gateway pid $($gw.ProcessId)"

$body = @{
  chat_id = $ChatId
  text = "Goose reset complete. Fresh agent session $newSession with shell/tools. Working dir: $WorkDir. Send: run shell command dir"
} | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" -Method Post -Body $body -ContentType 'application/json' | Out-Null

Write-Host "RESET OK - session $newSession, gateway $($gw.ProcessId)"
