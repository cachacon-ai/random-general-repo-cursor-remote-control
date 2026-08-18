# Restore Goose as a coding agent (tools + reasonable token limits).
# Keeps thinking disabled so LM Studio API calls return visible text.
$ErrorActionPreference = 'Stop'
$ConfigPath = 'C:\Users\cjfit\AppData\Roaming\Block\goose\config\config.yaml'
$script:ConfigText = Get-Content $ConfigPath -Raw

function Set-ExtensionEnabled([string]$name, [string]$enabled) {
  $pattern = "(?ms)(  ${name}:\r?\n    enabled: )(?:true|false)"
  if ($script:ConfigText -notmatch $pattern) {
    Write-Warning "Extension block not found: $name"
    return
  }
  $script:ConfigText = [regex]::Replace($script:ConfigText, $pattern, "`${1}$enabled")
}

# Agent behavior — not chat-only
$script:ConfigText = $script:ConfigText -replace '(?m)^GOOSE_MODE:.*$', 'GOOSE_MODE: auto'
$script:ConfigText = $script:ConfigText -replace '(?m)^GOOSE_MAX_TOKENS:.*$', 'GOOSE_MAX_TOKENS: 8192'
if ($script:ConfigText -notmatch '(?m)^GOOSE_CONTEXT_LIMIT:') {
  $script:ConfigText = $script:ConfigText -replace '(?m)^GOOSE_MAX_TOKENS: 8192', "GOOSE_MAX_TOKENS: 8192`nGOOSE_CONTEXT_LIMIT: 65536"
} else {
  $script:ConfigText = $script:ConfigText -replace '(?m)^GOOSE_CONTEXT_LIMIT:.*$', 'GOOSE_CONTEXT_LIMIT: 65536'
}

foreach ($line in @(
  'GOOSE_DISABLE_SESSION_NAMING: true',
  'GOOSE_THINKING_EFFORT: off',
  'GOOSE_LOCAL_ENABLE_THINKING: false'
)) {
  $key = ($line -split ':')[0]
  if ($script:ConfigText -notmatch "(?m)^${key}:") {
    $script:ConfigText = "$script:ConfigText`n$line"
  } else {
    $script:ConfigText = $script:ConfigText -replace "(?m)^${key}:.*$", $line
  }
}

Set-ExtensionEnabled 'developer' 'true'
Set-ExtensionEnabled 'analyze' 'true'
Set-ExtensionEnabled 'skills' 'true'
Set-ExtensionEnabled 'todo' 'true'
Set-ExtensionEnabled 'code_execution' 'true'
Set-ExtensionEnabled 'summarize' 'true'
Set-ExtensionEnabled 'chatrecall' 'true'
Set-ExtensionEnabled 'memory' 'true'
Set-ExtensionEnabled 'apps' 'false'
Set-ExtensionEnabled 'orchestrator' 'false'
Set-ExtensionEnabled 'summon' 'false'
Set-ExtensionEnabled 'scheduler' 'false'
Set-ExtensionEnabled 'tom' 'false'
Set-ExtensionEnabled 'extensionmanager' 'false'
Set-ExtensionEnabled 'computercontroller' 'false'
Set-ExtensionEnabled 'autovisualiser' 'false'
Set-ExtensionEnabled 'tutorial' 'false'

Set-Content -Path $ConfigPath -Value $script:ConfigText -NoNewline
Write-Host 'Goose config updated:'
Write-Host '  GOOSE_MODE=auto (tools enabled)'
Write-Host '  GOOSE_MAX_TOKENS=8192 (output cap per reply, not context)'
Write-Host '  GOOSE_CONTEXT_LIMIT=65536 (matches LM Studio 64K load)'
Write-Host '  developer, analyze, skills, todo, code_execution, summarize, chatrecall, memory enabled'
