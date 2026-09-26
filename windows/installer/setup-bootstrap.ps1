[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$LaunchTray,
  [switch]$Uninstall,
  [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$payloadRoot = Join-Path $PSScriptRoot 'payload'
$payloadScripts = Join-Path $payloadRoot 'scripts'
$commonPath = Join-Path $payloadScripts 'common-windows.ps1'
$themePath = Join-Path $payloadScripts 'theme-windows.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Dream Skin.lnk'
$script:DreamSkinBootstrapAction = if ($Uninstall) {
  'uninstall'
} elseif ($Install) {
  'install'
} elseif ($LaunchTray) {
  'launch-tray'
} else {
  'install'
}
$script:DreamSkinBootstrapPhase = 'startup'
$script:DreamSkinBootstrapFailurePath = Join-Path $stateRoot 'setup-failure.json'
$script:DreamSkinBootstrapFailureMaxBytes = 4096
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
$script:DreamSkinBootstrapFailureCategories = @(
  'invalid-arguments',
  'payload-incomplete',
  'tray-active',
  'uninstall-preflight-failed',
  'restore-failed',
  'runtime-removal-failed',
  'codex-running',
  'node-runtime-invalid',
  'downgrade-blocked',
  'payload-version-invalid',
  'payload-invalid',
  'config-initialization-failed',
  'theme-initialization-failed',
  'install-initialization-failed',
  'runtime-validation-failed',
  'tray-launch-failed',
  'internal-error'
)

function Set-DreamSkinBootstrapPhase {
  param([Parameter(Mandatory = $true)][string]$Phase)
  if ($script:DreamSkinBootstrapFailurePhases -cnotcontains $Phase) {
    throw 'Invalid Dream Skin bootstrap phase.'
  }
  $script:DreamSkinBootstrapPhase = $Phase
}

function Invoke-DreamSkinBootstrapChild {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][hashtable]$Parameters,
    [Parameter(Mandatory = $true)][string]$Phase
  )
  Set-DreamSkinBootstrapPhase -Phase $Phase
  & $ScriptPath @Parameters
}

function Get-DreamSkinBootstrapFailureCategory {
  param([AllowEmptyString()][string]$ErrorMessage = '')
  switch ($script:DreamSkinBootstrapPhase) {
    'validate-arguments' { return 'invalid-arguments' }
    'load-payload' { return 'payload-incomplete' }
    'uninstall-preflight' {
      if ($ErrorMessage -match '(?i)tray') { return 'tray-active' }
      return 'uninstall-preflight-failed'
    }
    'uninstall-restore' { return 'restore-failed' }
    'uninstall-runtime-cleanup' { return 'runtime-removal-failed' }
    'install-preflight' {
      if ($ErrorMessage -match '(?i)tray') { return 'tray-active' }
      return 'codex-running'
    }
    'install-payload-validation' {
      if ($ErrorMessage -match '(?i)Node\.js|bundled Node') { return 'node-runtime-invalid' }
      if ($ErrorMessage -match '(?i)newer') { return 'downgrade-blocked' }
      if ($ErrorMessage -match '(?i)version') { return 'payload-version-invalid' }
      return 'payload-invalid'
    }
    'install-runtime-and-config' {
      if ($ErrorMessage -match '(?i)config|appearance') { return 'config-initialization-failed' }
      if ($ErrorMessage -match '(?i)theme') { return 'theme-initialization-failed' }
      if ($ErrorMessage -match '(?i)Node\.js|bundled Node') { return 'node-runtime-invalid' }
      return 'install-initialization-failed'
    }
    'install-post-validation' { return 'runtime-validation-failed' }
    'launch-tray' { return 'tray-launch-failed' }
    default { return 'internal-error' }
  }
}

function Get-DreamSkinBootstrapFailureOutcome {
  if ($script:DreamSkinBootstrapAction -ceq 'uninstall') {
    if ($script:DreamSkinBootstrapPhase -ceq 'uninstall-runtime-cleanup') {
      return 'uninstall-cleanup-unverified'
    }
    return 'uninstall-incomplete'
  }
  if ($script:DreamSkinBootstrapAction -ceq 'launch-tray') {
    return 'tray-launch-incomplete'
  }
  return 'install-incomplete'
}

function Get-DreamSkinBootstrapExitCode {
  if ($script:DreamSkinBootstrapAction -ceq 'uninstall') {
    if ($script:DreamSkinBootstrapPhase -ceq 'uninstall-runtime-cleanup') { return 72 }
    if ($script:DreamSkinBootstrapPhase -ceq 'uninstall-restore') { return 71 }
    return 70
  }
  if ($script:DreamSkinBootstrapAction -ceq 'launch-tray') { return 80 }
  if ($script:DreamSkinBootstrapPhase -ceq 'install-runtime-and-config') { return 62 }
  if ($script:DreamSkinBootstrapPhase -ceq 'install-post-validation') { return 63 }
  if ($script:DreamSkinBootstrapPhase -in @('load-payload', 'install-payload-validation')) { return 61 }
  return 60
}

function Test-DreamSkinBootstrapManagedPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    if (-not $env:LOCALAPPDATA) { return $false }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $localRoot = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    $expectedRoot = Join-Path $localRoot 'CodexDreamSkin'
    if (-not $fullPath.Equals($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
      -not $fullPath.StartsWith($expectedRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $fullPath
    while ($true) {
      if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
      }
      $currentNormalized = $current.TrimEnd('\')
      if ($currentNormalized.Equals($root.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) { break }
      $parent = [System.IO.Path]::GetDirectoryName($current)
      if (-not $parent -or $parent.Equals($current, [System.StringComparison]::OrdinalIgnoreCase)) { break }
      $current = $parent
    }
    return $true
  } catch {
    return $false
  }
}

function Write-DreamSkinBootstrapFallbackFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
  $temporary = Join-Path $directory ('.setup-failure-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
    if ([System.IO.File]::Exists($Path)) {
      [System.IO.File]::Replace($temporary, $Path, $null, $true)
    } else {
      [System.IO.File]::Move($temporary, $Path)
    }
  } finally {
    if ([System.IO.File]::Exists($temporary)) {
      try { [System.IO.File]::Delete($temporary) } catch {}
    }
  }
}

function Write-DreamSkinBootstrapFailureRecord {
  param(
    [Parameter(Mandatory = $true)][string]$Category,
    [Parameter(Mandatory = $true)][int]$ExitCode
  )
  try {
    if ($script:DreamSkinBootstrapFailureCategories -cnotcontains $Category -or
      $script:DreamSkinBootstrapFailurePhases -cnotcontains $script:DreamSkinBootstrapPhase) {
      return $false
    }
    $fullStateRoot = [System.IO.Path]::GetFullPath($stateRoot)
    if (-not (Test-DreamSkinBootstrapManagedPath -Path $fullStateRoot)) { return $false }
    $hasManagedDirectoryHelper = $null -ne (Get-Command Ensure-DreamSkinManagedDirectory `
      -CommandType Function -ErrorAction SilentlyContinue)
    if ($hasManagedDirectoryHelper) {
      Ensure-DreamSkinManagedDirectory -Path $fullStateRoot -Root $fullStateRoot
    } elseif (-not (Test-Path -LiteralPath $fullStateRoot -PathType Container)) {
      return $false
    }
    $path = [System.IO.Path]::GetFullPath($script:DreamSkinBootstrapFailurePath)
    if ($null -ne (Get-Command Assert-DreamSkinNoReparseComponents `
        -CommandType Function -ErrorAction SilentlyContinue)) {
      Assert-DreamSkinNoReparseComponents -Path $path
    } elseif (-not (Test-DreamSkinBootstrapManagedPath -Path $path)) {
      return $false
    }
    $record = [ordered]@{
      schemaVersion = 1
      action = $script:DreamSkinBootstrapAction
      phase = $script:DreamSkinBootstrapPhase
      category = $Category
      outcome = Get-DreamSkinBootstrapFailureOutcome
      exitCode = $ExitCode
      timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
      diagnosticFile = 'setup-failure.json'
    }
    $content = (($record | ConvertTo-Json -Compress) + "`r`n")
    $encoding = [System.Text.UTF8Encoding]::new($false)
    if ($encoding.GetByteCount($content) -gt $script:DreamSkinBootstrapFailureMaxBytes) {
      return $false
    }
    if ($null -ne (Get-Command Write-DreamSkinUtf8FileAtomically `
        -CommandType Function -ErrorAction SilentlyContinue)) {
      Write-DreamSkinUtf8FileAtomically -Path $path -Content $content
    } else {
      Write-DreamSkinBootstrapFallbackFile -Path $path -Content $content
    }
    return $true
  } catch {
    return $false
  }
}

function Remove-DreamSkinBootstrapFailureRecord {
  try {
    if (-not (Test-DreamSkinBootstrapManagedPath -Path $stateRoot)) { return }
    $path = [System.IO.Path]::GetFullPath($script:DreamSkinBootstrapFailurePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    if ($null -ne (Get-Command Assert-DreamSkinNoReparseComponents `
        -CommandType Function -ErrorAction SilentlyContinue)) {
      Assert-DreamSkinNoReparseComponents -Path $path
    } elseif (-not (Test-DreamSkinBootstrapManagedPath -Path $path)) {
      return
    }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  } catch {}
}

function Get-DreamSkinBootstrapFailureMessage {
  param(
    [Parameter(Mandatory = $true)][string]$Category,
    [Parameter(Mandatory = $true)][int]$ExitCode,
    [Parameter(Mandatory = $true)][bool]$RecordWritten
  )
  $recordText = if ($RecordWritten) {
    'Diagnostic record: %LOCALAPPDATA%\CodexDreamSkin\setup-failure.json'
  } else {
    'Diagnostic record could not be written; expected path: %LOCALAPPDATA%\CodexDreamSkin\setup-failure.json'
  }
  return ('Codex Dream Skin bootstrap failed during {0} (category: {1}, exit code: {2}). {3}' -f
    $script:DreamSkinBootstrapPhase, $Category, $ExitCode, $recordText)
}

function Show-DreamSkinBootstrapMessage {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet('Info', 'Error')][string]$Kind = 'Info'
  )
  if ($Silent) { return }
  Add-Type -AssemblyName System.Windows.Forms
  $icon = if ($Kind -eq 'Error') {
    [System.Windows.Forms.MessageBoxIcon]::Error
  } else {
    [System.Windows.Forms.MessageBoxIcon]::Information
  }
  [void][System.Windows.Forms.MessageBox]::Show(
    $Message,
    'Codex Dream Skin',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    $icon
  )
}

function Wait-DreamSkinCodexClosedForSetup {
  while ($true) {
    $registered = @(Get-DreamSkinRegisteredCodexInstalls)
    $running = @($registered | Where-Object { (Get-DreamSkinCodexProcesses -Codex $_).Count -gt 0 })
    if ($running.Count -eq 0) { return }
    if ($Silent) { throw 'Close Codex before installing or updating Codex Dream Skin.' }
    Add-Type -AssemblyName System.Windows.Forms
    $choice = [System.Windows.Forms.MessageBox]::Show(
      'Codex is currently running. Close it, then click Retry to continue setup.',
      'Codex Dream Skin Setup',
      [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
      [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($choice -ne [System.Windows.Forms.DialogResult]::Retry) {
      throw 'Setup was cancelled because Codex is still running.'
    }
  }
}

try {
  Set-DreamSkinBootstrapPhase -Phase 'validate-arguments'
  if ($Install -and ($LaunchTray -or $Uninstall)) {
    throw 'Choose exactly one installer bootstrap action.'
  }
  Set-DreamSkinBootstrapPhase -Phase 'load-payload'
  if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    throw 'The installer payload is incomplete.'
  }
  . $commonPath
  . $themePath
  Remove-DreamSkinBootstrapFailureRecord

  $engine = Get-DreamSkinRuntimeEnginePaths -StateRoot $stateRoot
  if ($Uninstall) {
    Set-DreamSkinBootstrapPhase -Phase 'uninstall-preflight'
    Stop-DreamSkinTrayProcess -ScriptPaths @($engine.Tray) -RequireStopped
    $restoreRequired = (Test-Path -LiteralPath $engine.Root -PathType Container) -or
      (Test-Path -LiteralPath (Join-Path $stateRoot 'config.before-dream-skin.toml') -PathType Leaf)
    if ($restoreRequired -and -not (Test-Path -LiteralPath $engine.Restore -PathType Leaf)) {
      throw 'The installed restore engine is missing. Reinstall Codex Dream Skin, then uninstall again so Codex can be restored safely.'
    }
    if ($restoreRequired) {
      $restoreParameters = @{
        Uninstall = $true
        ForceRestart = $true
        NoRelaunch = $true
      }
      if (Test-Path -LiteralPath (Join-Path $stateRoot 'config.before-dream-skin.toml') -PathType Leaf) {
        $restoreParameters.RestoreBaseTheme = $true
      }
      Invoke-DreamSkinBootstrapChild -ScriptPath $engine.Restore `
        -Parameters $restoreParameters -Phase 'uninstall-restore'
    }
    Set-DreamSkinBootstrapPhase -Phase 'uninstall-runtime-cleanup'
    if (Test-Path -LiteralPath $engine.Root -PathType Container) {
      Remove-DreamSkinRuntimeTree -Path $engine.Root -StateRoot $stateRoot
    }
    Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction SilentlyContinue
    exit 0
  }

  Set-DreamSkinBootstrapPhase -Phase 'install-payload-validation'
  $payloadNode = Join-Path $payloadRoot 'runtime\node\node.exe'
  $payloadNodeLicense = Join-Path $payloadRoot 'runtime\node\LICENSE'
  if (-not (Test-Path -LiteralPath $payloadNode -PathType Leaf) -or
    -not (Test-Path -LiteralPath $payloadNodeLicense -PathType Leaf)) {
    throw 'The installer payload is missing its bundled Node.js runtime. Re-download Setup.exe.'
  }
  $payloadVersion = ([System.IO.File]::ReadAllText((Join-Path $payloadRoot 'VERSION'))).Trim()
  if ($payloadVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw "The installer payload version is invalid: $payloadVersion"
  }
  $installedVersion = if (Test-Path -LiteralPath $engine.Version -PathType Leaf) {
    ([System.IO.File]::ReadAllText($engine.Version)).Trim()
  } else { '' }
  if ($installedVersion -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -and
    ([version]$installedVersion) -gt ([version]$payloadVersion)) {
    throw "A newer Codex Dream Skin v$installedVersion is already installed. Download that version or newer instead of downgrading to v$payloadVersion."
  }
  $backupExists = Test-Path -LiteralPath (Join-Path $stateRoot 'config.before-dream-skin.toml') -PathType Leaf
  $requiredEngineFiles = @(
    'VERSION',
    'assets\codex-dream-skin.ico',
    'assets\dream-reference.jpg',
    'assets\dream-skin.css',
    'assets\renderer-inject.js',
    'assets\safe-css-policy.json',
    'assets\safe-css-validator.mjs',
    'assets\selectors.json',
    'assets\theme-package-validator.mjs',
    'assets\theme.json',
    'presets\preset-gothic-void-crusade\background.jpg',
    'presets\preset-gothic-void-crusade\theme.json',
    'scripts\apply-community-theme.ps1',
    'scripts\check-update.ps1',
    'scripts\common-windows.ps1',
    'scripts\config-utf8.ps1',
    'scripts\image-metadata.mjs',
    'scripts\injector.mjs',
    'scripts\install-dream-skin.ps1',
    'scripts\localization-windows.ps1',
    'scripts\restore-dream-skin.ps1',
    'scripts\start-dream-skin.ps1',
    'scripts\theme-windows.ps1',
    'scripts\tray-dream-skin.ps1',
    'scripts\validate-safe-css-file.mjs',
    'scripts\verify-dream-skin.ps1',
    'runtime\node\node.exe',
    'runtime\node\LICENSE'
  )
  $missingEngineFiles = @($requiredEngineFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $engine.Root $_) -PathType Leaf)
  })
  $engineComplete = $missingEngineFiles.Count -eq 0
  $needsInstall = $Install -or $payloadVersion -cne $installedVersion -or
    -not $backupExists -or -not $engineComplete

  if ($needsInstall) {
    Set-DreamSkinBootstrapPhase -Phase 'install-preflight'
    Wait-DreamSkinCodexClosedForSetup
    Stop-DreamSkinTrayProcess -ScriptPaths @($engine.Tray) -RequireStopped
    Invoke-DreamSkinBootstrapChild -ScriptPath (Join-Path $payloadScripts 'install-dream-skin.ps1') `
      -Parameters @{ NoShortcuts = $true } -Phase 'install-runtime-and-config'
    $engine = Get-DreamSkinRuntimeEnginePaths -StateRoot $stateRoot
    Set-DreamSkinBootstrapPhase -Phase 'install-post-validation'
    $committedVersion = if (Test-Path -LiteralPath $engine.Version -PathType Leaf) {
      ([System.IO.File]::ReadAllText($engine.Version)).Trim()
    } else { '' }
    $missingEngineFiles = @($requiredEngineFiles | Where-Object {
      -not (Test-Path -LiteralPath (Join-Path $engine.Root $_) -PathType Leaf)
    })
    if ($committedVersion -cne $payloadVersion -or $missingEngineFiles.Count -gt 0 -or
      -not (Test-Path -LiteralPath (Join-Path $stateRoot 'config.before-dream-skin.toml') -PathType Leaf)) {
      throw 'Runtime installation did not commit a complete managed engine.'
    }
  }

  if ($LaunchTray -and -not (Test-DreamSkinTrayActive)) {
    Set-DreamSkinBootstrapPhase -Phase 'launch-tray'
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $argumentLine = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ' +
      (ConvertTo-DreamSkinProcessArgument -Value $engine.Tray)
    Start-Process -FilePath $powershell -ArgumentList $argumentLine -WindowStyle Hidden | Out-Null
  }
} catch {
  $category = Get-DreamSkinBootstrapFailureCategory -ErrorMessage "$($_.Exception.Message)"
  $exitCode = Get-DreamSkinBootstrapExitCode
  $recordWritten = Write-DreamSkinBootstrapFailureRecord -Category $category -ExitCode $exitCode
  $safeMessage = Get-DreamSkinBootstrapFailureMessage -Category $category -ExitCode $exitCode `
    -RecordWritten ([bool]$recordWritten)
  Show-DreamSkinBootstrapMessage -Message $safeMessage -Kind Error
  [Console]::Error.WriteLine($safeMessage)
  exit $exitCode
}
