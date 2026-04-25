$ErrorActionPreference = 'Stop'
$script:HOOK_NAME = 'session-end'
. "$PSScriptRoot\_common.ps1"

if (-not (Read-HookInput)) { return }
$gitRoot = Get-GitRoot
if ([string]::IsNullOrEmpty($gitRoot)) { $gitRoot = (Get-Location).Path }

# 세션 종료 시 .context-capture/ 의 4 종 파일 cleanup. 없어도 무해.
Remove-Item -Force -ErrorAction SilentlyContinue (Get-PromptFilePath        -SessionId $script:SESSION_ID -GitRoot $gitRoot)
Remove-Item -Force -ErrorAction SilentlyContinue (Get-OffsetFilePath        -SessionId $script:SESSION_ID -GitRoot $gitRoot)
Remove-Item -Force -ErrorAction SilentlyContinue (Get-DeltaFilePath         -SessionId $script:SESSION_ID -GitRoot $gitRoot)
Remove-Item -Force -ErrorAction SilentlyContinue (Get-PendingQuestionPath   -SessionId $script:SESSION_ID -GitRoot $gitRoot)
