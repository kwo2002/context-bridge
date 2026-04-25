# AIFlare one-command install script (Windows PowerShell)
# Usage: irm https://raw.githubusercontent.com/kwo2002/context-bridge/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

# Disable colors when stdout is redirected (piped to file, iex, etc.)
$UseColor = -not [Console]::IsOutputRedirected

function Write-Info    { param([string]$Msg)
    if ($UseColor) { Write-Host "[OK] $Msg" -ForegroundColor Green } else { Write-Host "[OK] $Msg" }
}
function Write-Success { param([string]$Msg)
    if ($UseColor) { Write-Host "[OK] $Msg" -ForegroundColor Green -BackgroundColor Black } else { Write-Host "[OK] $Msg" }
}
function Write-Warn    { param([string]$Msg)
    if ($UseColor) { Write-Host "[!] $Msg" -ForegroundColor Yellow } else { Write-Host "[!] $Msg" }
}
function Write-Err     { param([string]$Msg)
    if ($UseColor) { Write-Host "[X] $Msg" -ForegroundColor Red } else { Write-Host "[X] $Msg" }
}

# --- Check required dependencies ---
foreach ($cmd in @("git", "node")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Err "$cmd is required but not installed. Please install $cmd and try again."
        exit 1
    }
}

# --- Detect git root ---
$GitRoot = git rev-parse --show-toplevel 2>$null
if (-not $GitRoot) {
    Write-Err "Not a git repository. Please run from the project root."
    exit 1
}

Set-Location $GitRoot

# --- 0. Enforce aiflare.yml presence (must be downloaded before install) ---
$YmlPath = Join-Path $GitRoot "aiflare.yml"
if (-not (Test-Path $YmlPath)) {
    Write-Err "aiflare.yml not found in project root."
    Write-Host ""
    Write-Host "  Setup steps:"
    Write-Host "    1) Sign up & generate an API key at https://aiflare.dev"
    Write-Host "    2) Place the downloaded aiflare.yml in $GitRoot"
    Write-Host "    3) Re-run this installer"
    Write-Host ""
    exit 1
}

# --- 0.5. Parse aiflare.yml: api_key (required) + endpoint (default fallback) ---
$YmlApiKey = ""
$YmlEndpoint = ""
foreach ($l in Get-Content $YmlPath) {
    if ($l -match '^api_key:\s*(.+)') { $YmlApiKey = $Matches[1].Trim().Trim('"').Trim("'") }
    if ($l -match '^endpoint:\s*(.+)') { $YmlEndpoint = $Matches[1].Trim().Trim('"').Trim("'") }
}

if (-not $YmlApiKey) {
    Write-Err "aiflare.yml is missing 'api_key:' value."
    Write-Host "  Re-download aiflare.yml from https://aiflare.dev project settings."
    exit 1
}

if (-not $YmlEndpoint) {
    $YmlEndpoint = "https://api.aiflare.dev"
    Write-Info "endpoint not set in aiflare.yml; using default: $YmlEndpoint"
}

Write-Info "Credentials loaded from aiflare.yml (endpoint: $YmlEndpoint)"

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
    $HooksSource = Join-Path $CloneDir "aiflare_settings.json"
    $MergeScript = Join-Path $CloneDir "scripts/merge-hooks.js"
    $ReferenceFile = ".claude/aiflare_settings.reference.json"

    New-Item -ItemType Directory -Force -Path ".claude" | Out-Null

    # --- 4.0. Render placeholders in hook template (HTTP hooks need url baked in) ---
    $RenderedHooksSource = Join-Path $TempDir "aiflare_settings.rendered.json"
    if (Test-Path $HooksSource) {
        $TemplateContent = Get-Content $HooksSource -Raw
        $TemplateContent = $TemplateContent.Replace('__AIFLARE_ENDPOINT__', $YmlEndpoint).Replace('__AIFLARE_API_KEY__', $YmlApiKey)
        Set-Content -Path $RenderedHooksSource -Value $TemplateContent -Encoding UTF8
        $HooksSource = $RenderedHooksSource
    }

    if (-not (Test-Path $HooksSource)) {
        Write-Warn "Hooks source file not found in repository: aiflare_settings.json"
    } elseif (-not (Test-Path $SettingsFile)) {
        Copy-Item -Path $HooksSource -Destination $SettingsFile -Force
        Write-Info "Hooks config created -> $SettingsFile"
    } elseif ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path $MergeScript)) {
        Copy-Item -Path $SettingsFile -Destination "$SettingsFile.bak" -Force
        try {
            node $MergeScript $SettingsFile $HooksSource
            if ($LASTEXITCODE -eq 0) {
                Write-Info "Hooks merged -> $SettingsFile (backup: $SettingsFile.bak)"
            } else {
                throw "merge-hooks.js exited with code $LASTEXITCODE"
            }
        } catch {
            Move-Item -Path "$SettingsFile.bak" -Destination $SettingsFile -Force
            Write-Warn "Hook merge failed. Original $SettingsFile restored."
            Copy-Item -Path $HooksSource -Destination $ReferenceFile -Force
            Write-Host "  Reference saved to $ReferenceFile for manual merge."
        }
    } else {
        Copy-Item -Path $HooksSource -Destination $ReferenceFile -Force
        Write-Warn "node not found. Cannot auto-merge hooks into existing $SettingsFile."
        Write-Host "  Reference saved to $ReferenceFile."
        Write-Host "  Please merge its `"hooks`" section into $SettingsFile manually."
    }

    # --- 4.5. Inject credentials into settings.local.json "env" (single source: aiflare.yml) ---
    if ((Test-Path $SettingsFile) -and (Get-Command node -ErrorAction SilentlyContinue)) {
        Copy-Item -Path $SettingsFile -Destination "$SettingsFile.bak.env" -Force -ErrorAction SilentlyContinue
        $env:AIFLARE_API_KEY_IN = $YmlApiKey
        $env:AIFLARE_ENDPOINT_IN = $YmlEndpoint
        $NodeScript = @"
const fs = require('fs');
const [, , p] = process.argv;
const s = JSON.parse(fs.readFileSync(p, 'utf8'));
s.env = s.env || {};
s.env.AIFLARE_API_KEY  = process.env.AIFLARE_API_KEY_IN;
s.env.AIFLARE_ENDPOINT = process.env.AIFLARE_ENDPOINT_IN;
fs.writeFileSync(p, JSON.stringify(s, null, 2) + '\n');
"@
        $envInjectFailed = $false
        try {
            $NodeScript | node - $SettingsFile
            if ($LASTEXITCODE -ne 0) {
                throw "node env injection exited with code $LASTEXITCODE"
            }
            Remove-Item "$SettingsFile.bak.env" -Force -ErrorAction SilentlyContinue
            Write-Info "Credentials injected into $SettingsFile"
        } catch {
            if (Test-Path "$SettingsFile.bak.env") {
                Move-Item -Path "$SettingsFile.bak.env" -Destination $SettingsFile -Force
            }
            Write-Err "Credential injection failed. Original $SettingsFile restored."
            $envInjectFailed = $true
        } finally {
            Remove-Item Env:AIFLARE_API_KEY_IN -ErrorAction SilentlyContinue
            Remove-Item Env:AIFLARE_ENDPOINT_IN -ErrorAction SilentlyContinue
        }
        if ($envInjectFailed) { exit 1 }
    }

    # --- 5. Install/merge .mcp.json ---
    $McpJson = ".mcp.json"
    $MergeMcpScript = Join-Path $CloneDir "scripts/merge-mcp.js"
    $McpReferenceFile = ".claude/mcp.reference.json"
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

    if (-not (Test-Path $McpJson)) {
        Set-Content -Path $McpJson -Value $McpJsonContent -Encoding UTF8
        Write-Info "MCP config created -> $McpJson"
    } elseif (Test-Path $MergeMcpScript) {
        $McpSrcTmp = Join-Path $TempDir "mcp-aiflare.json"
        Set-Content -Path $McpSrcTmp -Value $McpJsonContent -Encoding UTF8
        Copy-Item -Path $McpJson -Destination "$McpJson.bak" -Force
        try {
            node $MergeMcpScript $McpJson $McpSrcTmp
            if ($LASTEXITCODE -eq 0) {
                Write-Info "MCP config merged -> $McpJson (backup: $McpJson.bak)"
            } else {
                throw "merge-mcp.js exited with code $LASTEXITCODE"
            }
        } catch {
            Move-Item -Path "$McpJson.bak" -Destination $McpJson -Force
            Write-Warn "MCP config merge failed. Original $McpJson restored."
            Set-Content -Path $McpReferenceFile -Value $McpJsonContent -Encoding UTF8
            Write-Host "  Reference saved to $McpReferenceFile for manual merge."
        }
    } else {
        Set-Content -Path $McpReferenceFile -Value $McpJsonContent -Encoding UTF8
        Write-Warn "Merge script unavailable. Cannot update existing $McpJson."
        Write-Host "  Reference saved to $McpReferenceFile."
        Write-Host "  Please add the `"aiflare`" entry to $McpJson manually."
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

    # --- 9. Post-install verification ---
    Write-Host ""
    Write-Info "Verifying installation..."

    $verifyFailed = $false

    Get-ChildItem -Path $SkillsTarget -Directory | ForEach-Object {
        $skillMdPath = Join-Path $_.FullName "SKILL.md"
        if (-not (Test-Path $skillMdPath)) {
            Write-Warn "Skill missing SKILL.md: $($_.Name)"
            $verifyFailed = $true
        }
    }

    if (Test-Path $McpTarget) {
        $McpEntry = Join-Path $McpTarget "dist/index.js"
        if (-not (Test-Path $McpEntry)) {
            Write-Warn "MCP server entry point missing: $McpEntry"
            $verifyFailed = $true
        } else {
            try {
                node --check $McpEntry 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "MCP server entry point failed syntax check: $McpEntry"
                    $verifyFailed = $true
                }
            } catch {
                Write-Warn "MCP server entry point failed syntax check: $McpEntry"
                $verifyFailed = $true
            }
        }
    }

    if (Test-Path $McpJson) {
        try {
            Get-Content $McpJson -Raw | ConvertFrom-Json | Out-Null
        } catch {
            Write-Warn "$McpJson is not valid JSON"
            $verifyFailed = $true
        }
    }

    if (-not $verifyFailed) {
        Write-Info "All components verified"
    }

    # --- Done ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Success "Installation complete!"
    Write-Host ""
    Write-Host "  AIFlare is ready to use:"
    Write-Host "  - Hooks installed and credentials injected into $SettingsFile"
    Write-Host "  - Try starting Claude Code in this project to verify hook calls"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
} finally {
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
