[CmdletBinding()]
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path (Join-Path $Root 'installer') 'setup-bootstrap.ps1'
$tokens = $null
$parseErrors = $null
$bootstrapAst = [System.Management.Automation.Language.Parser]::ParseFile(
  $bootstrapPath,
  [ref]$tokens,
  [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
  throw 'Bootstrap failure test could not parse setup-bootstrap.ps1.'
}

foreach ($functionName in @(
  'Set-DreamSkinBootstrapPhase',
  'Invoke-DreamSkinBootstrapChild',
  'Get-DreamSkinBootstrapFailureCategory',
  'Get-DreamSkinBootstrapFailureOutcome',
  'Get-DreamSkinBootstrapExitCode',
  'Test-DreamSkinBootstrapManagedPath',
  'Write-DreamSkinBootstrapFallbackFile',
  'Write-DreamSkinBootstrapFailureRecord',
  'Get-DreamSkinBootstrapFailureMessage'
)) {
  $functionAst = $bootstrapAst.Find({
      param($node)
      $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $functionName
    }, $true)
  if ($null -eq $functionAst) { throw "Bootstrap helper is missing: $functionName" }
  . ([scriptblock]::Create($functionAst.Extent.Text))
}

$script:DreamSkinBootstrapFailurePhases = @(
  'startup',
  'validate-arguments',
  'load-payload',
  'uninstall-preflight',
  'uninstall-restore',
  'uninstall-runtime-cleanup',
  'install-preflight',
  'install-payload-validation',
  'install-runtime-and-config',
  'install-post-validation',
  'launch-tray'
)
$script:DreamSkinBootstrapFailureMaxBytes = 4096
$script:DreamSkinBootstrapFailureCategories = @(
  'invalid-arguments', 'payload-incomplete', 'tray-active',
  'uninstall-preflight-failed', 'restore-failed', 'runtime-removal-failed',
  'codex-running', 'node-runtime-invalid', 'downgrade-blocked',
  'payload-version-invalid', 'payload-invalid', 'config-initialization-failed',
  'theme-initialization-failed', 'install-initialization-failed',
  'runtime-validation-failed', 'tray-launch-failed', 'internal-error'
)

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ('dreamskin-bootstrap-failure-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
$script:CapturedRecord = $null

function Ensure-DreamSkinManagedDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Assert-DreamSkinNoReparseComponents {
  param([Parameter(Mandatory = $true)][string]$Path)
}

function Write-DreamSkinUtf8FileAtomically {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $script:CapturedRecord = $Content
  $directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Assert-Test {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) { throw $Message }
}

try {
  New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
  $env:LOCALAPPDATA = $temporaryRoot
  $stateRoot = Join-Path $temporaryRoot 'CodexDreamSkin'
  $script:DreamSkinBootstrapFailurePath = Join-Path $stateRoot 'setup-failure.json'

  $failingChild = Join-Path $temporaryRoot 'failing-child.ps1'
  [System.IO.File]::WriteAllText(
    $failingChild,
    "throw 'forced child failure C:\\Users\\private\\config.toml token=secret'`r`n",
    [System.Text.UTF8Encoding]::new($false)
  )

  $script:DreamSkinBootstrapAction = 'uninstall'
  $script:DreamSkinBootstrapPhase = 'startup'
  $childFailure = $null
  try {
    Invoke-DreamSkinBootstrapChild -ScriptPath $failingChild -Parameters @{} `
      -Phase 'uninstall-runtime-cleanup'
  } catch {
    $childFailure = $_
  }
  Assert-Test ($null -ne $childFailure) 'The failing child fixture did not throw.'
  $childMessage = "$($childFailure.Exception.Message)"
  $childCategory = Get-DreamSkinBootstrapFailureCategory -ErrorMessage $childMessage
  $childExitCode = Get-DreamSkinBootstrapExitCode
  $childOutcome = Get-DreamSkinBootstrapFailureOutcome
  Assert-Test ($childCategory -ceq 'runtime-removal-failed') `
    'A child failure did not map to the runtime-removal category.'
  Assert-Test ($childExitCode -eq 72) 'A partial uninstall did not receive exit code 72.'
  Assert-Test ($childOutcome -ceq 'uninstall-cleanup-unverified') `
    'A partial uninstall did not produce the cleanup-unverified outcome.'

  $recordWritten = Write-DreamSkinBootstrapFailureRecord -Category $childCategory `
    -ExitCode $childExitCode
  Assert-Test ([bool]$recordWritten) 'The bounded failure record was not written.'
  $recordPath = Join-Path $stateRoot 'setup-failure.json'
  Assert-Test (Test-Path -LiteralPath $recordPath -PathType Leaf) `
    'The failure record path was not created under the managed state root.'
  $recordText = [System.IO.File]::ReadAllText($recordPath)
  Assert-Test ($recordText.Length -lt 4096) 'The failure record exceeded its bounded size.'
  Assert-Test ($recordText -notmatch 'private|config\.toml|secret') `
    'The failure record leaked exception text or private values.'
  $record = $recordText | ConvertFrom-Json
  Assert-Test ("$($record.action)" -ceq 'uninstall') 'The record action is incorrect.'
  Assert-Test ("$($record.phase)" -ceq 'uninstall-runtime-cleanup') `
    'The record phase is incorrect.'
  Assert-Test ("$($record.category)" -ceq 'runtime-removal-failed') `
    'The record category is incorrect.'
  Assert-Test ([int]$record.exitCode -eq 72) 'The record exit code is incorrect.'
  $safeMessage = Get-DreamSkinBootstrapFailureMessage -Category $childCategory `
    -ExitCode $childExitCode -RecordWritten $true
  Assert-Test ($safeMessage -match 'runtime-removal-failed') `
    'The safe bootstrap message omitted the failure category.'
  Assert-Test ($safeMessage -match 'setup-failure\.json') `
    'The safe bootstrap message omitted the diagnostic record path.'
  Assert-Test ($safeMessage -notmatch 'private|config\.toml|secret') `
    'The safe bootstrap message leaked child exception text.'
  $unavailableMessage = Get-DreamSkinBootstrapFailureMessage -Category $childCategory `
    -ExitCode $childExitCode -RecordWritten $false
  Assert-Test ($unavailableMessage -match 'could not be written') `
    'A failed record write was reported as if a diagnostic record existed.'

  $silentRoot = Join-Path $temporaryRoot 'silent-child'
  $silentPayloadScripts = Join-Path $silentRoot 'payload\scripts'
  New-Item -ItemType Directory -Path $silentPayloadScripts -Force | Out-Null
  $silentBootstrap = Join-Path $silentRoot 'setup-bootstrap.ps1'
  [System.IO.File]::Copy($bootstrapPath, $silentBootstrap)
  $silentLocalAppData = Join-Path $silentRoot 'localappdata'
  New-Item -ItemType Directory -Path (Join-Path $silentLocalAppData 'CodexDreamSkin') `
    -Force | Out-Null
  $processPath = (Get-Process -Id $PID -ErrorAction Stop).Path
  if (-not $processPath) {
    $processPath = Join-Path $PSHOME (if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
  }
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $processPath
  $startInfo.Arguments = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "' +
    $silentBootstrap.Replace('"', '\"') + '" -Install -Silent'
  $startInfo.WorkingDirectory = $silentRoot
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.EnvironmentVariables['LOCALAPPDATA'] = $silentLocalAppData
  $childProcess = [System.Diagnostics.Process]::new()
  $childProcess.StartInfo = $startInfo
  if (-not $childProcess.Start()) { throw 'The silent bootstrap child could not start.' }
  $stderr = $childProcess.StandardError.ReadToEnd()
  $childProcess.WaitForExit()
  Assert-Test ($childProcess.ExitCode -eq 61) `
    "Silent bootstrap returned an unexpected exit code: $($childProcess.ExitCode)"
  Assert-Test ($stderr -match 'payload-incomplete') `
    'Silent bootstrap stderr omitted the sanitized failure category.'
  Assert-Test ($stderr -notmatch 'config\.toml|token=secret') `
    'Silent bootstrap stderr leaked raw exception details.'
  $silentRecordPath = Join-Path (Join-Path $silentLocalAppData 'CodexDreamSkin') `
    'setup-failure.json'
  Assert-Test (Test-Path -LiteralPath $silentRecordPath -PathType Leaf) `
    'Silent bootstrap did not leave a diagnostic record.'
  $silentRecordText = [System.IO.File]::ReadAllText($silentRecordPath)
  Assert-Test ($silentRecordText -match '"category":"payload-incomplete"') `
    'Silent bootstrap record has the wrong category.'
} finally {
  $env:LOCALAPPDATA = $oldLocalAppData
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Output 'PASS: bootstrap failure records are bounded, sanitized, categorized, and surfaced with actual exit codes.'
