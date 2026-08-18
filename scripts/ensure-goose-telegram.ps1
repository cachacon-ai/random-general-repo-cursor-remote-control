# Ensure Goose Telegram gateway is running and send a fresh pairing code if needed.
$ErrorActionPreference = 'Stop'
$GooseDesktop = 'C:\Users\cjfit\Tools\goose\dist-windows\Goose.exe'
$GooseExe = 'C:\Users\cjfit\Tools\goose\dist-windows\resources\bin\goose.exe'
$ConfigPath = 'C:\Users\cjfit\AppData\Roaming\Block\goose\config\config.yaml'
$BotToken = '8941919067:AAFkkCnS0vZvlQppt9EgEtEF2qaD4HJo028'
$ChatId = '7993462191'

function Fail($msg) { Write-Error $msg; exit 1 }

function Get-GooseServe {
  Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'goose.exe' -and $_.CommandLine -like '*goose.exe serve*'
  } | Select-Object -First 1
}

function Get-TelegramGateways {
  @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'goose.exe' -and $_.CommandLine -match 'goose\.exe"?\s+gateway\s+start\s+telegram'
  })
}

function Get-ValidPairingCode {
  $config = Get-Content $ConfigPath -Raw
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $codes = [regex]::Matches($config, 'code: (\w+)\r?\n\s+gateway_type: telegram\r?\n\s+expires_at: (\d+)')
  $valid = $codes | ForEach-Object {
    [pscustomobject]@{ Code = $_.Groups[1].Value; Expires = [int64]$_.Groups[2].Value }
  } | Where-Object { $_.Expires -gt $now } | Sort-Object Expires -Descending | Select-Object -First 1
  if ($valid) { return $valid.Code }
  return $null
}

Write-Host '== Ensure Goose desktop + serve =='
$serve = Get-GooseServe
if (-not $serve) {
  if (-not (Test-Path $GooseDesktop)) { Fail "Goose desktop not found: $GooseDesktop" }
  Write-Host 'Starting Goose desktop...'
  Start-Process $GooseDesktop | Out-Null
  $deadline = (Get-Date).AddSeconds(30)
  do {
    Start-Sleep -Seconds 2
    $serve = Get-GooseServe
  } while (-not $serve -and (Get-Date) -lt $deadline)
  if (-not $serve) { Fail 'goose serve did not start (open Goose desktop manually)' }
}
Write-Host "OK (serve pid $($serve.ProcessId))"

Write-Host '== Ensure single Telegram gateway =='
$gateways = Get-TelegramGateways
if ($gateways.Count -gt 1) {
  $keep = $gateways | Sort-Object ProcessId | Select-Object -First 1
  $gateways | Where-Object { $_.ProcessId -ne $keep.ProcessId } | ForEach-Object {
    Write-Host "Killing duplicate gateway pid $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force
  }
  Start-Sleep -Seconds 2
  $gateways = Get-TelegramGateways
}
if ($gateways.Count -eq 0) {
  Write-Host 'Starting Telegram gateway...'
  Start-Process -FilePath $GooseExe -ArgumentList @(
    'gateway', 'start', 'telegram', '--bot-token', $BotToken
  ) -WindowStyle Hidden | Out-Null
  Start-Sleep -Seconds 3
  $gateways = Get-TelegramGateways
  if ($gateways.Count -eq 0) { Fail 'Failed to start Telegram gateway' }
}
if ($gateways.Count -gt 1) { Fail "Still have $($gateways.Count) gateway processes; kill extras manually" }
Write-Host "OK (gateway pid $($gateways[0].ProcessId))"

Write-Host '== Pairing code =='
$code = Get-ValidPairingCode
if (-not $code) {
  $pairOut = & $GooseExe gateway pair telegram 2>&1 | Out-String
  if ($pairOut -match 'Pairing code:\s*(\w+)') { $code = $Matches[1] }
  else { Fail "Could not generate pairing code:`n$pairOut" }
  Write-Host "Generated $code"
} else {
  Write-Host "Using existing valid code $code"
}

Write-Host '== Send code to Telegram =='
$text = @"
Goose pairing code: $code

Reply to @Goooooooose_duck_bot with just that code (one message). Codes expire in ~5 minutes.
"@
$body = @{ chat_id = $ChatId; text = $text.Trim() } | ConvertTo-Json
$resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
if (-not $resp.ok) { Fail "Telegram send failed: $($resp | ConvertTo-Json -Compress)" }
Write-Host 'OK (code sent to your Telegram)'
Write-Host "PAIRING_CODE=$code"
