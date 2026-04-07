# AIFlare: push된 커밋의 타임라인 엔트리를 PUSHED 상태로 전환
# 실패해도 push를 차단하지 않음

$ErrorActionPreference = "SilentlyContinue"

$GitRoot = git rev-parse --show-toplevel 2>$null
$ConfigFile = Join-Path $GitRoot "aiflare.yml"

# aiflare.yml이 없으면 조용히 종료
if (-not (Test-Path $ConfigFile)) {
    exit 0
}

# 설정 읽기
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

# stdin에서 push 정보 파싱
$inputLines = @($input)
foreach ($line in $inputLines) {
    $parts = $line -split '\s+'
    if ($parts.Count -lt 4) { continue }

    $localRef = $parts[0]
    $localSha = $parts[1]
    $remoteSha = $parts[3]

    # 삭제 push인 경우 스킵
    if ($localSha -eq "0000000000000000000000000000000000000000") { continue }

    # 브랜치명 추출
    $branch = $localRef -replace '^refs/heads/', ''

    # push되는 커밋 해시 목록 추출
    if ($remoteSha -eq "0000000000000000000000000000000000000000") {
        $commitHashes = git log $localSha --format="%H" --not --remotes 2>$null
    } else {
        $commitHashes = git log "${remoteSha}..${localSha}" --format="%H" 2>$null
    }

    if (-not $commitHashes) { continue }

    # 배열로 변환
    $hashArray = @($commitHashes) | Where-Object { $_ }

    # JSON payload 생성
    $payload = @{
        commitHashes = $hashArray
        branch       = $branch
    } | ConvertTo-Json -Depth 5 -Compress

    # API 호출 (실패해도 무시)
    $headers = @{
        "Content-Type" = "application/json"
        "X-API-Key"    = $ApiKey
    }

    try {
        Invoke-RestMethod -Uri "$Endpoint/api/v1/captures/publish" -Method Post -Headers $headers -Body $payload | Out-Null
    } catch {
        # 실패해도 push를 차단하지 않음
    }
}

exit 0
