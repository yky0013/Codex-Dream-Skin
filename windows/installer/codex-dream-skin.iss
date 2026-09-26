#ifndef AppVersion
  #error AppVersion must be supplied by build-release.ps1
#endif
#ifndef StageRoot
  #error StageRoot must be supplied by build-release.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build-release.ps1
#endif

#define AppName "Codex Dream Skin"
#define AppPublisher "Codex Dream Skin contributors"
#define AppUrl "https://dreamskin.cc"
#define PowerShellPath "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"
#define PersistentPowerShellPath "{win}\System32\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId={{DCCDAF1A-9ACD-4AAB-B55B-DF17EB2CDA2E}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL=https://github.com/Fei-Away/Codex-Dream-Skin/releases
DefaultDirName={localappdata}\Programs\CodexDreamSkin
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=CodexDreamSkin-Setup-v{#AppVersion}
SetupIconFile={#StageRoot}\payload\assets\codex-dream-skin.ico
UninstallDisplayIcon={app}\payload\assets\codex-dream-skin.ico
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
CloseApplications=no
RestartApplications=no
RestartIfNeededByRun=no
ChangesAssociations=yes
ChangesEnvironment=no
UsePreviousTasks=yes
SetupLogging=yes
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "{#StageRoot}\languages\ChineseSimplified.isl"

[Messages]
english.ConfirmUninstall=Uninstall will close Codex, restore its original appearance, remove the Dream Skin runtime, and keep saved themes and images.%n%nContinue?
chinesesimplified.ConfirmUninstall=卸载将关闭 Codex、恢复官方外观并移除 Dream Skin 运行时；已保存主题和图片会保留。%n%n是否继续？

[Tasks]
Name: "startup"; Description: "Start Codex Dream Skin when I sign in"; GroupDescription: "Additional options:"; Flags: unchecked

[Files]
; Keep a second, temporary copy so initialization runs before Inno starts
; copying/registering the installed application files. Exceptions from
; CurStepChanged(ssInstall) are fatal and therefore stop Setup cleanly.
Source: "{#StageRoot}\setup-bootstrap.ps1"; DestDir: "{tmp}"; Flags: dontcopy noencryption
Source: "{#StageRoot}\payload\*"; DestDir: "{tmp}\payload"; Flags: dontcopy noencryption recursesubdirs createallsubdirs
Source: "{#StageRoot}\setup-bootstrap.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\payload\*"; DestDir: "{app}\payload"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Codex Dream Skin"; Filename: "{#PersistentPowerShellPath}"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{app}\setup-bootstrap.ps1"" -LaunchTray"; WorkingDir: "{app}"; IconFilename: "{app}\payload\assets\codex-dream-skin.ico"
Name: "{userstartup}\Codex Dream Skin"; Filename: "{#PersistentPowerShellPath}"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{app}\setup-bootstrap.ps1"" -LaunchTray"; WorkingDir: "{app}"; IconFilename: "{app}\payload\assets\codex-dream-skin.ico"; Tasks: startup

[Registry]
Root: HKCU; Subkey: "Software\Classes\dreamskin"; ValueType: string; ValueName: ""; ValueData: "URL:DreamSkin Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\dreamskin"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\dreamskin\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\payload\assets\codex-dream-skin.ico"
Root: HKCU; Subkey: "Software\Classes\dreamskin\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{#PersistentPowerShellPath}"" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{localappdata}\CodexDreamSkin\engine\scripts\apply-community-theme.ps1"" ""%1"""

[Run]
Filename: "{#PowerShellPath}"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{app}\setup-bootstrap.ps1"" -LaunchTray"; WorkingDir: "{app}"; Description: "Launch Codex Dream Skin"; Flags: nowait postinstall skipifsilent

[Code]
const
  BootstrapInstallPayloadExitCode = 61;
  BootstrapInstallRuntimeExitCode = 62;
  BootstrapInstallValidationExitCode = 63;
  BootstrapUninstallRestoreExitCode = 71;
  BootstrapUninstallCleanupExitCode = 72;
  BootstrapTrayExitCode = 80;

function BootstrapDiagnosticPath(): String;
begin
  Result := ExpandConstant('{localappdata}\CodexDreamSkin\setup-failure.json');
end;

function BootstrapFailurePhaseDescription(const ExitCode: Integer): String;
begin
  case ExitCode of
    BootstrapInstallPayloadExitCode:
      Result := 'installer preflight or payload validation';
    BootstrapInstallRuntimeExitCode:
      Result := 'runtime, theme, or Codex configuration initialization';
    BootstrapInstallValidationExitCode:
      Result := 'post-install runtime validation';
    BootstrapUninstallRestoreExitCode:
      Result := 'uninstall preflight or Codex appearance restore';
    BootstrapUninstallCleanupExitCode:
      Result := 'uninstall runtime cleanup after the restore step';
    BootstrapTrayExitCode:
      Result := 'tray launch';
  else
    Result := 'installer bootstrap';
  end;
end;

function PowerShellArguments(
  const ScriptPath: String;
  const ActionArguments: String;
  const Silent: Boolean
): String;
begin
  Result := '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ' +
    AddQuotes(ScriptPath) + ' ' + ActionArguments;
  if Silent then
    Result := Result + ' -Silent';
end;

function RunBootstrap(
  const ScriptPath: String;
  const ActionArguments: String;
  const Silent: Boolean;
  var ExitCode: Integer
): Boolean;
begin
  Result := Exec(
    ExpandConstant('{#PowerShellPath}'),
    PowerShellArguments(ScriptPath, ActionArguments, Silent),
    ExtractFileDir(ScriptPath),
    SW_HIDE,
    ewWaitUntilTerminated,
    ExitCode
  );
end;

function InstallInitializationFailureMessage(const ExitCode: Integer): String;
begin
  Result := 'Codex Dream Skin installation did not complete during ' +
    BootstrapFailurePhaseDescription(ExitCode) + ' (exit code ' +
    IntToStr(ExitCode) + '). Setup did not commit its application files, but '
    + 'managed state may have changed. Diagnostic record (if available): ' +
    BootstrapDiagnosticPath();
end;

function UninstallFailureMessage(const ExitCode: Integer): String;
begin
  if ExitCode = BootstrapUninstallCleanupExitCode then
    Result := 'Codex Dream Skin uninstall did not complete during runtime cleanup '
      + 'after the restore step (exit code ' + IntToStr(ExitCode) + '). Runtime '
      + 'cleanup was not verified; installed files may remain and configuration '
      + 'or shortcuts may already have changed. Diagnostic record (if available): '
      + BootstrapDiagnosticPath()
  else
    Result := 'Codex Dream Skin uninstall did not complete during ' +
      BootstrapFailurePhaseDescription(ExitCode) + ' (exit code ' +
      IntToStr(ExitCode) + '). Installed files were retained, but configuration '
      + 'or shortcuts may already have changed. Diagnostic record (if available): '
      + BootstrapDiagnosticPath();
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ExitCode: Integer;
  TemporaryBootstrap: String;
begin
  if CurStep <> ssInstall then
    exit;

  ExtractTemporaryFiles('{tmp}\setup-bootstrap.ps1');
  ExtractTemporaryFiles('{tmp}\payload\*');
  TemporaryBootstrap := ExpandConstant('{tmp}\setup-bootstrap.ps1');
  if not RunBootstrap(TemporaryBootstrap, '-Install', WizardSilent, ExitCode) then
    RaiseException('Codex Dream Skin initialization could not be started.');
  if ExitCode <> 0 then
    RaiseException(InstallInitializationFailureMessage(ExitCode));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExitCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    exit;

  { The standard Inno confirmation has completed before usUninstall. }
  if not RunBootstrap(ExpandConstant('{app}\setup-bootstrap.ps1'), '-Uninstall', True, ExitCode) then
    RaiseException(
      'Codex Dream Skin uninstall could not be started. Installed files were retained; '
      + 'check the installer log and retry. Diagnostic record (if available): ' +
      BootstrapDiagnosticPath()
    );
  if ExitCode <> 0 then
    RaiseException(UninstallFailureMessage(ExitCode));
end;
