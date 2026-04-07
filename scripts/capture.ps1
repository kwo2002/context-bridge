# Context Bridge Capture Script (PowerShell)
# capture.sh PowerShell version
#
# Usage:
#   capture.ps1 -Title "title" -Intent "intent" -CommitHash "abc123" -AgentType "CLAUDE_CODE" `
#     -ClaudeSessionId "SESSION_ID" -ChangedFiles "file1.kt,file2.kt" -Tag "FEATURE" `
#     [-Alternatives "alternatives"] [-DiffSummary "diff summary"]

param(
    [string]$Title = $env:CB_TITLE,
    [string]$Intent = $env:CB_INTENT,
    [string]$CommitHash = $env:CB_COMMIT_HASH,
    [string]$AgentType = $(if ($env:CB_AGENT_TYPE) { $env:CB_AGENT_TYPE } else { "CLAUDE_CODE" }),
    [string]$ClaudeSessionId = $env:CB_CLAUDE_SESSION_ID,
    [string]$ChangedFiles = $env:CB_CHANGED_FILES,
    [string]$Tag = $env:CB_TAG,
    [string]$Alternatives = $env:CB_ALTERNATIVES,
    [string]$DiffSummary = $env:CB_DIFF_SUMMARY,
    [string]$ConversationSnippet = $env:CB_CONVERSATION_SNIPPET
)

$ErrorActionPreference = "Stop"

# --- Find config file (relative to git root) ---
$GitRoot = git rev-parse --show-toplevel 2>$null
if (-not $GitRoot) {
    Write-Host "Context Bridge capture skipped: not a git repository."
    exit 0
}

$ConfigFile = Join-Path $GitRoot "context-bridge.yml"
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Context Bridge capture skipped: context-bridge.yml not found."
    exit 0
}

# --- Extract config values ---
$ApiKey = ""
$Endpoint = ""
foreach ($line in (Get-Content $ConfigFile)) {
    if ($line -match '^\s*api_key\s*:\s*(.+)$') {
        $ApiKey = $Matches[1].Trim().Trim('"').Trim("'")
    }
    if ($line -match '^\s*endpoint\s*:\s*(.+)$') {
        $Endpoint = $Matches[1].Trim().Trim('"').Trim("'")
    }
}

if (-not $ApiKey -or -not $Endpoint) {
    Write-Host "Context Bridge capture skipped: api_key or endpoint missing in context-bridge.yml."
    exit 0
}

# --- claude-session-id fallback: extract from most recent prompt file ---
if (-not $ClaudeSessionId) {
    $CaptureDir = Join-Path $GitRoot ".context-capture"
    $LatestPrompt = Get-ChildItem -Path $CaptureDir -Filter ".claude-prompts-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($LatestPrompt) {
        $ClaudeSessionId = $LatestPrompt.Name -replace '^\.claude-prompts-', ''
    }
}

# --- conversation-snippet fallback: read from delta file ---
if (-not $ConversationSnippet -and $ClaudeSessionId) {
    $DeltaFile = Join-Path $GitRoot ".context-capture" ".claude-conversation-delta-$ClaudeSessionId"
    if (Test-Path $DeltaFile) {
        $ConversationSnippet = Get-Content $DeltaFile -Raw
        Remove-Item $DeltaFile -Force -ErrorAction SilentlyContinue
    }
}

# --- Required field validation ---
if (-not $Title -or -not $Intent -or -not $CommitHash -or -not $ClaudeSessionId -or -not $ChangedFiles -or -not $Tag) {
    Write-Error "Error: -Title, -Intent, -CommitHash, -ClaudeSessionId, -ChangedFiles, -Tag are required."
    exit 1
}

# --- Build payload ---
$ChangedFilesArray = ($ChangedFiles -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$Branch = git rev-parse --abbrev-ref HEAD 2>$null

$Payload = @{
    title           = $Title
    intent          = $Intent
    alternatives    = $Alternatives
    diffSummary     = $DiffSummary
    commitHash      = $CommitHash
    agentType       = $AgentType
    claudeSessionId = $ClaudeSessionId
    changedFiles    = @($ChangedFilesArray)
    tag             = $Tag
    branch          = $Branch
}

if ($ConversationSnippet) {
    $Payload["conversationSnippet"] = $ConversationSnippet
}

$JsonBody = $Payload | ConvertTo-Json -Depth 10 -Compress

# --- API call ---
$Headers = @{
    "Content-Type" = "application/json"
    "X-API-Key"    = $ApiKey
}

try {
    $Response = Invoke-RestMethod -Uri "$Endpoint/api/v1/captures" -Method Post -Headers $Headers -Body $JsonBody -ErrorAction Stop
    Write-Host "Context Bridge capture complete: $Title"
} catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__
    switch ($StatusCode) {
        400 { Write-Host "Context Bridge capture failed: invalid request data" }
        401 { Write-Host "Context Bridge capture failed: API Key is invalid." }
        404 { Write-Host "Context Bridge capture failed: no project found for this API Key." }
        429 { Write-Host "Context Bridge capture failed: rate limit exceeded. Please try again later." }
        default { Write-Host "Context Bridge capture failed: HTTP $StatusCode — server error. Please retry manually later." }
    }
}
