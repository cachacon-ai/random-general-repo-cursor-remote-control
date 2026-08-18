$ErrorActionPreference = 'Stop'
$GooseExe = 'C:\Users\cjfit\Tools\goose\dist-windows\resources\bin\goose.exe'
Push-Location 'C:\Users\cjfit'
try {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & $GooseExe run -t 'Use the shell tool to run: echo TOOLS-OK. Reply with the command output only.' --no-session 2>&1 | ForEach-Object { "$_" }
  $sw.Stop()
  $text = $out -join "`n"
  Write-Host "Elapsed: $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
  Write-Host $text
  if ($text -notmatch 'TOOLS-OK') { exit 1 }
  Write-Host 'TOOLS TEST PASSED'
} finally {
  Pop-Location
}
