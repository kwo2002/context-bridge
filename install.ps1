# Context Bridge one-command install script (Windows PowerShell)
# Usage: irm https://raw.githubusercontent.com/kwo2002/context-bridge/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Write-Info  { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

# --- Check git installation ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Err "git is not installed. Please install Git for Windows first."
    exit 1
}

# --- Detect git root ---
$GitRoot = git rev-parse --show-toplevel 2>$null
if (-not $GitRoot) {
    Write-Err "Not a git repository. Please run from the project root."
    exit 1
}

Set-Location $GitRoot
Write-Host ""
Write-Host "Starting Context Bridge installation..."
Write-Host ""

# --- 1. Install Skill ---
$SkillDir = ".claude/skills/context-capture"
if (Test-Path $SkillDir) {
    Remove-Item $SkillDir -Recurse -Force
    Write-Warn "Removing existing context-capture Skill and replacing with latest version."
}

New-Item -ItemType Directory -Force -Path ".claude/skills" | Out-Null
$cloneResult = git clone --depth 1 https://github.com/kwo2002/context-bridge.git $SkillDir 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to clone Skill repository. Please check your network connection."
    if (Test-Path $SkillDir) { Remove-Item $SkillDir -Recurse -Force }
    exit 1
}
Remove-Item (Join-Path $SkillDir ".git") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $SkillDir "install.sh") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $SkillDir "install.ps1") -Force -ErrorAction SilentlyContinue

Write-Info "Skill installed -> $SkillDir"

# --- 2. Install settings.local.json (hooks) ---
$SettingsFile = ".claude/settings.local.json"

$HooksContent = @'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $SID=$J.session_id; if(-not $SID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'context-bridge.yml'; if(-not(Test-Path $CFG)){exit 0}; $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; if(-not $AK -or -not $EP){exit 0}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/work-sessions\\\" -Method Post -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body (@{claudeSessionId=$SID;agentType='CLAUDE_CODE'}|ConvertTo-Json -Compress) -TimeoutSec 5|Out-Null}catch{}; exit 0\"",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(*git commit*)",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $SID=$J.session_id; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'context-bridge.yml'; if(Test-Path $CFG){ $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; $PF=Join-Path $GR '.context-capture' \\\".claude-prompts-$SID\\\"; $OF=Join-Path $GR '.context-capture' \\\".claude-offset-$SID\\\"; if(Test-Path $PF){ $Content=Get-Content $PF -Raw; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/work-sessions/prompt\\\" -Method Put -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body (@{claudeSessionId=$SID;content=$Content}|ConvertTo-Json -Compress -Depth 5)}catch{}; $LastIndex=0; if(Test-Path $OF){$LastIndex=[int](Get-Content $OF -Raw)}; $Lines=(Get-Content $PF).Count; if($Lines -gt $LastIndex){ $Delta=(Get-Content $PF | Select-Object -Skip $LastIndex) -join \\\"`n\\\"; Set-Content -Path (Join-Path $GR '.context-capture' \\\".claude-conversation-delta-$SID\\\") -Value $Delta}; Set-Content -Path $OF -Value $Lines}}; $SkillCheck=Join-Path $GR '.claude/skills/context-capture'; if(Test-Path $SkillCheck){ Write-Output '{\\\"hookSpecificOutput\\\":{\\\"hookEventName\\\":\\\"PostToolUse\\\",\\\"additionalContext\\\":\\\"git commit completed. You must invoke the context-capture skill to capture the work context.\\\"}}' }\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $Prompt=$J.prompt; $SID=$J.session_id; if(-not $SID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; if(-not $GR){$GR=Get-Location}; $Dir=Join-Path $GR '.context-capture'; New-Item -ItemType Directory -Force -Path $Dir|Out-Null; $File=Join-Path $Dir \\\".claude-prompts-$SID\\\"; $Entry=@{role='user';content=$Prompt}|ConvertTo-Json -Compress; Add-Content -Path $File -Value $Entry\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $StopActive=$J.stop_hook_active; if($StopActive -eq 'true'){exit 0}; $SID=$J.session_id; $Msg=$J.last_assistant_message; if(-not $SID -or -not $Msg){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; if(-not $GR){$GR=Get-Location}; $Dir=Join-Path $GR '.context-capture'; New-Item -ItemType Directory -Force -Path $Dir|Out-Null; $File=Join-Path $Dir \\\".claude-prompts-$SID\\\"; $Entry=@{role='assistant';content=$Msg}|ConvertTo-Json -Compress; Add-Content -Path $File -Value $Entry\"",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $SID=$J.session_id; $GR=git rev-parse --show-toplevel 2>$null; if(-not $GR){$GR=Get-Location}; if($SID){ Remove-Item (Join-Path $GR '.context-capture' \\\".claude-prompts-$SID\\\") -Force -EA SilentlyContinue; Remove-Item (Join-Path $GR '.context-capture' \\\".claude-offset-$SID\\\") -Force -EA SilentlyContinue; Remove-Item (Join-Path $GR '.context-capture' \\\".claude-conversation-delta-$SID\\\") -Force -EA SilentlyContinue; $CFG=Join-Path $GR 'context-bridge.yml'; if(Test-Path $CFG){ $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/work-sessions/$SID\\\" -Method Delete -Headers @{'X-API-Key'=$AK}}catch{}}}\""
          }
        ]
      }
    ],
    "TaskCreated": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $TID=$J.task_id; $TTitle=$J.task_subject; $TDesc=$J.task_description; $SID=$J.session_id; if(-not $TID -or -not $SID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'context-bridge.yml'; if(-not(Test-Path $CFG)){exit 0}; $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/captures/tasks\\\" -Method Post -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body (@{externalTaskId=$TID;claudeSessionId=$SID;title=$TTitle;description=$TDesc}|ConvertTo-Json -Compress)}catch{}; exit 0\""
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $TID=$J.task_id; if(-not $TID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'context-bridge.yml'; if(-not(Test-Path $CFG)){exit 0}; $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/captures/tasks/$TID\\\" -Method Patch -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body '{\\\"status\\\":\\\"COMPLETED\\\"}'}catch{}; exit 0\""
          }
        ]
      }
    ]
  }
}
'@

if (-not (Test-Path $SettingsFile)) {
    Set-Content -Path $SettingsFile -Value $HooksContent -Encoding UTF8
    Write-Info "Hooks config created -> $SettingsFile"
} else {
    Write-Warn "Existing $SettingsFile found. Please add hooks manually."
    Write-Host ""
    Write-Host "  The hooks content to merge is shown above in the script source."
    Write-Host "  Or re-run this installer after removing the existing file."
}

# --- 2.5. Install MCP Server dependencies ---
$McpDir = Join-Path $SkillDir "mcp-server"
if ((Test-Path $McpDir) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Push-Location $McpDir
    try { npm install --production --silent 2>$null } catch {}
    Pop-Location
    Write-Info "MCP Server ready -> $McpDir"
}

# --- 2.6. Create .mcp.json ---
$McpJson = ".mcp.json"
if (-not (Test-Path $McpJson)) {
    $McpJsonContent = @'
{
  "mcpServers": {
    "context-bridge": {
      "command": "node",
      "args": [".claude/skills/context-capture/mcp-server/dist/index.js"]
    }
  }
}
'@
    Set-Content -Path $McpJson -Value $McpJsonContent -Encoding UTF8
    Write-Info "MCP config created -> $McpJson"
} else {
    if (-not (Select-String -Path $McpJson -Pattern "context-bridge" -Quiet)) {
        Write-Warn "Existing $McpJson found. Please add context-bridge MCP server manually."
    } else {
        Write-Info "context-bridge already configured in $McpJson"
    }
}

# --- 3. Update .gitignore ---
$GitIgnore = ".gitignore"
if (-not (Test-Path $GitIgnore)) { New-Item -ItemType File -Path $GitIgnore | Out-Null }

$GitIgnoreContent = Get-Content $GitIgnore -Raw -ErrorAction SilentlyContinue
if (-not $GitIgnoreContent) { $GitIgnoreContent = "" }

$entries = @("context-bridge.yml", ".context-capture/", ".claude/settings.local.json")
foreach ($entry in $entries) {
    if ($GitIgnoreContent -notmatch [regex]::Escape($entry)) {
        Add-Content -Path $GitIgnore -Value $entry
        Write-Info "Added $entry to .gitignore"
    } else {
        Write-Info "$entry already in .gitignore"
    }
}

# --- 4. Install Git hook ---
$SkillPrePush = Join-Path $SkillDir "scripts/pre-push.ps1"
$HooksTargetDir = ".git/hooks"

if (Test-Path $SkillPrePush) {
    $PrePushTarget = Join-Path $HooksTargetDir "pre-push"
    if (Test-Path $PrePushTarget) {
        Write-Warn "Existing $PrePushTarget found. Will not overwrite."
        Write-Host "  Please merge manually:"
        Write-Host "    type $SkillPrePush"
    } else {
        # Git for Windows는 Git Bash로 hook을 실행하므로 sh 래퍼 생성
        $WrapperContent = @"
#!/bin/sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "`$(git rev-parse --show-toplevel)/.claude/skills/context-capture/scripts/pre-push.ps1"
"@
        Set-Content -Path $PrePushTarget -Value $WrapperContent -Encoding UTF8
        Write-Info "pre-push hook installed -> $PrePushTarget"
    }
} else {
    Write-Warn "pre-push.ps1 script not found: $SkillPrePush"
}

# --- 5. Update CLAUDE.md ---
$ClaudeMd = "CLAUDE.md"
$Directive = "After git commit, you must always run the context-capture skill."

if (-not (Test-Path $ClaudeMd)) {
    Set-Content -Path $ClaudeMd -Value $Directive -Encoding UTF8
    Write-Info "CLAUDE.md created with directive"
} elseif (-not (Select-String -Path $ClaudeMd -Pattern "context-capture" -Quiet)) {
    Add-Content -Path $ClaudeMd -Value "`n$Directive"
    Write-Info "Directive added to CLAUDE.md"
} else {
    Write-Info "context-capture directive already exists in CLAUDE.md"
}

# --- Done ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Info "Installation complete!"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "  1. Go to Context Bridge project settings -> API Key Management and generate an API key"
Write-Host "  2. Place the downloaded context-bridge.yml in the project root"
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
