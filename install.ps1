# AIFlare one-command install script (Windows PowerShell)
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
Write-Host "Starting AIFlare installation..."
Write-Host ""

# --- 1. Clone repository to a temporary location ---
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aiflare-" + [guid]::NewGuid().ToString("N"))
$CloneDir = Join-Path $TempDir "repo"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

try {
    $cloneResult = git clone --depth 1 https://github.com/kwo2002/context-bridge.git $CloneDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to clone Skill repository. Please check your network connection."
        exit 1
    }
    Remove-Item (Join-Path $CloneDir ".git") -Recurse -Force -ErrorAction SilentlyContinue

    # --- 2. Install all skills ---
    $SkillsSource = Join-Path $CloneDir "skills"
    $SkillsTarget = ".claude/skills"

    if (-not (Test-Path $SkillsSource)) {
        Write-Err "skills/ directory not found in cloned repository."
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $SkillsTarget | Out-Null

    Get-ChildItem -Path $SkillsSource -Directory | ForEach-Object {
        $skillName = $_.Name
        $target = Join-Path $SkillsTarget $skillName
        if (Test-Path $target) {
            Remove-Item $target -Recurse -Force
            Write-Warn "Replaced existing skill: $skillName"
        }
        Copy-Item -Path $_.FullName -Destination $target -Recurse -Force
        Write-Info "Skill installed -> $target"
    }

    $ContextCaptureDir = Join-Path $SkillsTarget "context-capture"

    # --- 3. Install MCP Server (shared across all skills) ---
    $McpSource = Join-Path $CloneDir "mcp-server"
    $McpTarget = ".claude/mcp-server"

    if (Test-Path $McpSource) {
        if (Test-Path $McpTarget) { Remove-Item $McpTarget -Recurse -Force }
        Copy-Item -Path $McpSource -Destination $McpTarget -Recurse -Force
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Push-Location $McpTarget
            try { npm install --production --silent 2>$null } catch {}
            Pop-Location
        }
        Write-Info "MCP Server ready -> $McpTarget"
    }

    # --- 4. Install settings.local.json (hooks) ---
    $SettingsFile = ".claude/settings.local.json"
    New-Item -ItemType Directory -Force -Path ".claude" | Out-Null

    $HooksContent = @'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $SID=$J.session_id; if(-not $SID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'aiflare.yml'; if(-not(Test-Path $CFG)){exit 0}; $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; if(-not $EP){$EP='https://api.aiflare.dev'}; if(-not $AK){exit 0}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/work-sessions\\\" -Method Post -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body (@{claudeSessionId=$SID;agentType='CLAUDE_CODE'}|ConvertTo-Json -Compress) -TimeoutSec 5|Out-Null}catch{}; exit 0\"",
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
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $SID=$J.session_id; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'aiflare.yml'; if(Test-Path $CFG){ $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; if(-not $EP){$EP='https://api.aiflare.dev'}; $PF=Join-Path $GR '.context-capture' \\\".claude-prompts-$SID\\\"; $OF=Join-Path $GR '.context-capture' \\\".claude-offset-$SID\\\"; if(Test-Path $PF){ $Content=Get-Content $PF -Raw; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/work-sessions/prompt\\\" -Method Put -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body (@{claudeSessionId=$SID;content=$Content}|ConvertTo-Json -Compress -Depth 5)}catch{}; $LastIndex=0; if(Test-Path $OF){$LastIndex=[int](Get-Content $OF -Raw)}; $Lines=(Get-Content $PF).Count; if($Lines -gt $LastIndex){ $Delta=(Get-Content $PF | Select-Object -Skip $LastIndex) -join \\\"`n\\\"; Set-Content -Path (Join-Path $GR '.context-capture' \\\".claude-conversation-delta-$SID\\\") -Value $Delta}; Set-Content -Path $OF -Value $Lines}}; $SkillCheck=Join-Path $GR '.claude/skills/context-capture'; if(Test-Path $SkillCheck){ Write-Output '{\\\"hookSpecificOutput\\\":{\\\"hookEventName\\\":\\\"PostToolUse\\\",\\\"additionalContext\\\":\\\"git commit completed. You must invoke the context-capture skill to capture the work context.\\\"}}' }\""
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
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $SID=$J.session_id; $GR=git rev-parse --show-toplevel 2>$null; if(-not $GR){$GR=Get-Location}; if($SID){ Remove-Item (Join-Path $GR '.context-capture' \\\".claude-prompts-$SID\\\") -Force -EA SilentlyContinue; Remove-Item (Join-Path $GR '.context-capture' \\\".claude-offset-$SID\\\") -Force -EA SilentlyContinue; Remove-Item (Join-Path $GR '.context-capture' \\\".claude-conversation-delta-$SID\\\") -Force -EA SilentlyContinue; $CFG=Join-Path $GR 'aiflare.yml'; if(Test-Path $CFG){ $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; if(-not $EP){$EP='https://api.aiflare.dev'}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/work-sessions/$SID\\\" -Method Delete -Headers @{'X-API-Key'=$AK}}catch{}}}\""
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
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $TID=$J.task_id; $TTitle=$J.task_subject; $TDesc=$J.task_description; $SID=$J.session_id; if(-not $TID -or -not $SID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'aiflare.yml'; if(-not(Test-Path $CFG)){exit 0}; $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; if(-not $EP){$EP='https://api.aiflare.dev'}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/captures/tasks\\\" -Method Post -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body (@{externalTaskId=$TID;claudeSessionId=$SID;title=$TTitle;description=$TDesc}|ConvertTo-Json -Compress)}catch{}; exit 0\""
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
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='SilentlyContinue'; $J=$input|Out-String|ConvertFrom-Json; $TID=$J.task_id; if(-not $TID){exit 0}; $GR=git rev-parse --show-toplevel 2>$null; $CFG=Join-Path $GR 'aiflare.yml'; if(-not(Test-Path $CFG)){exit 0}; $AK=''; $EP=''; foreach($l in Get-Content $CFG){if($l-match'api_key:\\s*(.+)'){$AK=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")};if($l-match'endpoint:\\s*(.+)'){$EP=$Matches[1].Trim().Trim('\\\"').Trim(\\\"'\\\")}}; if(-not $EP){$EP='https://api.aiflare.dev'}; try{Invoke-RestMethod -Uri \\\"$EP/api/v1/captures/tasks/$TID\\\" -Method Patch -Headers @{'Content-Type'='application/json';'X-API-Key'=$AK} -Body '{\\\"status\\\":\\\"COMPLETED\\\"}'}catch{}; exit 0\""
          }
        ]
      }
    ]
  }
}
'@

    $ReferenceFile = ".claude/aiflare_settings.reference.json"
    $MergeScript = Join-Path $CloneDir "scripts/merge-hooks.js"

    if (-not (Test-Path $SettingsFile)) {
        Set-Content -Path $SettingsFile -Value $HooksContent -Encoding UTF8
        Write-Info "Hooks config created -> $SettingsFile"
    } elseif ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path $MergeScript)) {
        $HooksTempFile = Join-Path $TempDir "aiflare_settings.json"
        Set-Content -Path $HooksTempFile -Value $HooksContent -Encoding UTF8
        Copy-Item -Path $SettingsFile -Destination "$SettingsFile.bak" -Force
        try {
            node $MergeScript $SettingsFile $HooksTempFile
            if ($LASTEXITCODE -eq 0) {
                Write-Info "Hooks merged -> $SettingsFile (backup: $SettingsFile.bak)"
            } else {
                throw "merge-hooks.js exited with code $LASTEXITCODE"
            }
        } catch {
            Move-Item -Path "$SettingsFile.bak" -Destination $SettingsFile -Force
            Write-Warn "Hook merge failed. Original $SettingsFile restored."
            Set-Content -Path $ReferenceFile -Value $HooksContent -Encoding UTF8
            Write-Host "  Reference saved to $ReferenceFile for manual merge."
        }
    } else {
        Set-Content -Path $ReferenceFile -Value $HooksContent -Encoding UTF8
        Write-Warn "node not found. Cannot auto-merge hooks into existing $SettingsFile."
        Write-Host "  Reference saved to $ReferenceFile."
        Write-Host "  Please merge its `"hooks`" section into $SettingsFile manually."
    }

    # --- 5. Create .mcp.json ---
    $McpJson = ".mcp.json"
    if (-not (Test-Path $McpJson)) {
        $McpJsonContent = @'
{
  "mcpServers": {
    "aiflare": {
      "command": "node",
      "args": [".claude/mcp-server/dist/index.js"]
    }
  }
}
'@
        Set-Content -Path $McpJson -Value $McpJsonContent -Encoding UTF8
        Write-Info "MCP config created -> $McpJson"
    } else {
        if (-not (Select-String -Path $McpJson -Pattern "aiflare" -Quiet)) {
            Write-Warn "Existing $McpJson found. Please add aiflare MCP server manually."
        } else {
            Write-Info "aiflare already configured in $McpJson"
        }
    }

    # --- 6. Update .gitignore ---
    $GitIgnore = ".gitignore"
    if (-not (Test-Path $GitIgnore)) { New-Item -ItemType File -Path $GitIgnore | Out-Null }

    $GitIgnoreContent = Get-Content $GitIgnore -Raw -ErrorAction SilentlyContinue
    if (-not $GitIgnoreContent) { $GitIgnoreContent = "" }

    $entries = @("aiflare.yml", ".context-capture/", ".claude/settings.local.json")
    foreach ($entry in $entries) {
        if ($GitIgnoreContent -notmatch [regex]::Escape($entry)) {
            Add-Content -Path $GitIgnore -Value $entry
            Write-Info "Added $entry to .gitignore"
        } else {
            Write-Info "$entry already in .gitignore"
        }
    }

    # --- 7. Install Git pre-push hook ---
    $SkillPrePush = Join-Path $ContextCaptureDir "scripts/pre-push.ps1"
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

    # --- 8. Update CLAUDE.md ---
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
    Write-Host "  1. Go to AIFlare project settings -> API Key Management and generate an API key"
    Write-Host "  2. Place the downloaded aiflare.yml in the project root"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
} finally {
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
