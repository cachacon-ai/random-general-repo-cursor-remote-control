# Self-test for Goose + LM Studio + Telegram gateway harness.
$ErrorActionPreference = 'Stop'
$GooseExe = 'C:\Users\cjfit\Tools\goose\dist-windows\resources\bin\goose.exe'
$BotToken = '8941919067:AAFkkCnS0vZvlQppt9EgEtEF2qaD4HJo028'
$ChatId = '7993462191'
$Prompt = 'Reply with exactly: HARNESS-OK'
$Expected = 'HARNESS-OK'
function Fail($msg) { Write-Error $msg; exit 1 }
Write-Host '== 1/5 LM Studio =='
try {
  $models = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 10
  if (-not ($models.data.id -contains 'qwen/qwen3.8-27b')) { Fail 'qwen/qwen3.8-27b not loaded' }
} catch { Fail "LM Studio unreachable: $($_.Exception.Message)" }
Write-Host 'OK'
Write-Host '== 2/5 Goose agent path (3 runs) =='
1..3 | ForEach-Object {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & $GooseExe run -t $Prompt --no-session 2>&1 | Out-String
  $sw.Stop()
  if ($out -notmatch [regex]::Escape($Expected)) { Fail "Run $_ missing '$Expected'. Output:`n$out" }
  if ($sw.Elapsed.TotalSeconds -gt 30) { Fail "Run $_ too slow: $($sw.Elapsed.TotalSeconds)s" }
  Write-Host "  run $_ OK in $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
}
Write-Host '== 3/5 Gateway pairing (config) =='
$config = Get-Content 'C:\Users\cjfit\AppData\Roaming\Block\goose\config\config.yaml' -Raw
if ($config -notmatch '7993462191') { Fail 'Telegram user not paired in config.yaml' }
if ($config -notmatch 'session_id:\s*(\d{8}_\d+)') { Fail 'Gateway session_id missing from config.yaml' }
$SessionId = $Matches[1]
Write-Host "OK (session $SessionId)"
Write-Host '== 4/5 Telegram outbound =='
$body = @{ chat_id = $ChatId; text = "Goose harness self-test passed at $(Get-Date -Format 'HH:mm:ss'). Agent replied: $Expected" } | ConvertTo-Json
try {
  $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
  if (-not $resp.ok) { Fail "sendMessage failed: $($resp | ConvertTo-Json -Compress)" }
} catch { Fail "Telegram outbound failed: $($_.Exception.Message)" }
Write-Host 'OK'
Write-Host '== 5/7 Goose serve =='
$serve = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'goose.exe' -and $_.CommandLine -like '*goose.exe serve*' }
if (-not $serve) { Fail 'goose serve not running (start Goose desktop app)' }
Write-Host "OK (pid $($serve.ProcessId))"
Write-Host '== 6/7 Gateway process =='
$gw = @(Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq 'goose.exe' -and $_.CommandLine -match 'goose\.exe"?\s+gateway\s+start\s+telegram'
})
if ($gw.Count -eq 0) { Fail 'Telegram gateway process not running' }
if ($gw.Count -gt 1) { Fail "Multiple gateway processes ($($gw.Count)); kill duplicates" }
Write-Host "OK (pid $($gw[0].ProcessId))"
Write-Host '== 7/7 Gateway session agent path =='
$sw = [Diagnostics.Stopwatch]::StartNew()
Push-Location 'C:\Users\cjfit'
try {
  $out = cmd /c "`"$GooseExe`" run -t `"Reply with exactly: SESSION-OK`" --resume --session-id $SessionId 2>&1"
} finally {
  Pop-Location
}
$sw.Stop()
if ($out -notmatch 'SESSION-OK') { Fail "Gateway session relay failed:`n$out" }
if ($sw.Elapsed.TotalSeconds -gt 30) { Fail "Gateway session too slow: $($sw.Elapsed.TotalSeconds)s" }
Write-Host "OK in $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
Write-Host 'ALL CHECKS PASSED'
