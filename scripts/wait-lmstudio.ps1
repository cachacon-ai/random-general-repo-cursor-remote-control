Write-Host 'Waiting for LM Studio...'
for ($i = 1; $i -le 30; $i++) {
  Start-Sleep -Seconds 5
  try {
    $models = Invoke-RestMethod 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5
    if ($models.data.id -contains 'qwen/qwen3.8-27b') {
      $body = '{"model":"qwen/qwen3.8-27b","messages":[{"role":"user","content":"Say OK"}],"max_tokens":10,"stream":false}'
      $r = Invoke-RestMethod 'http://127.0.0.1:1234/v1/chat/completions' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 120
      Write-Host "LM STUDIO OK: $($r.choices[0].message.content)"
      exit 0
    }
    Write-Host "attempt $i - model not loaded yet"
  } catch {
    Write-Host "attempt $i - $($_.Exception.Message)"
  }
}
exit 1
