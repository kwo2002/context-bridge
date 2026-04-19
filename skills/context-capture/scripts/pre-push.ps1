# AIFlare: mark pushed commits' timeline entries as PUSHED
# Failures never block the push

$ErrorActionPreference = "SilentlyContinue"

$GitRoot = git rev-parse --show-toplevel 2>$null
$ConfigFile = Join-Path $GitRoot "aiflare.yml"

# Exit silently when aiflare.yml is missing
if (-not (Test-Path $ConfigFile)) {
    exit 0
}

# Read configuration
$Endpoint = ""
$ApiKey = ""
foreach ($line in (Get-Content $ConfigFile)) {
    if ($line -match '^\s*endpoint\s*:\s*(.+)$') {
        $Endpoint = $Matches[1].Trim().Trim('"').Trim("'")
    }
    if ($line -match '^\s*api_key\s*:\s*(.+)$') {
        $ApiKey = $Matches[1].Trim().Trim('"').Trim("'")
    }
}

if (-not $Endpoint) { $Endpoint = "https://api.aiflare.dev" }

if (-not $ApiKey) {
    exit 0
}

# Parse push info from stdin
$inputLines = @($input)
foreach ($line in $inputLines) {
    $parts = $line -split '\s+'
    if ($parts.Count -lt 4) { continue }

    $localRef = $parts[0]
    $localSha = $parts[1]
    $remoteSha = $parts[3]

    # Skip delete pushes
    if ($localSha -eq "0000000000000000000000000000000000000000") { continue }

    # Extract branch name
    $branch = $localRef -replace '^refs/heads/', ''

    # Collect the commit hashes being pushed
    if ($remoteSha -eq "0000000000000000000000000000000000000000") {
        $commitHashes = git log $localSha --format="%H" --not --remotes 2>$null
    } else {
        $commitHashes = git log "${remoteSha}..${localSha}" --format="%H" 2>$null
    }

    if (-not $commitHashes) { continue }

    # Convert to array
    $hashArray = @($commitHashes) | Where-Object { $_ }

    # Build JSON payload
    $payload = @{
        commitHashes = $hashArray
        branch       = $branch
    } | ConvertTo-Json -Depth 5 -Compress

    # Call the API (ignore failures)
    $headers = @{
        "Content-Type" = "application/json"
        "X-API-Key"    = $ApiKey
    }

    try {
        Invoke-RestMethod -Uri "$Endpoint/api/v1/captures/publish" -Method Post -Headers $headers -Body $payload | Out-Null
    } catch {
        # Failures never block the push
    }
}

exit 0
