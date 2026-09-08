#define MyAppName "Clinic Smart Staff Connector"
#define MyAppPublisher "SMART MARKET & FARMING LIMITED"
#define MyAppExeName "ClinicSmartStaffConnectorService.exe"

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#ifndef BuildRoot
  #error BuildRoot must be provided
#endif

#ifndef OutputRoot
  #define OutputRoot ".\dist"
#endif

[Setup]
AppId={{C63EB705-7881-49E5-9657-CFD552D42752}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Clinic Smart Staff Connector
DefaultGroupName={#MyAppName}
OutputDir={#OutputRoot}
OutputBaseFilename=ClinicSmartStaffConnectorSetup-{#MyAppVersion}-x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes
UninstallDisplayName={#MyAppName}

[Dirs]
Name: "{app}\state"; Permissions: users-modify
Name: "{app}\logs"; Permissions: users-modify

[Files]
Source: "{#BuildRoot}\app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildRoot}\node\*"; DestDir: "{app}\node"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildRoot}\service\*"; DestDir: "{app}\service"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildRoot}\config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildRoot}\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\install-service.ps1"""; Flags: runhidden waituntilterminated; StatusMsg: "Installing Clinic Smart Staff Connector service..."

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\uninstall-service.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveConnectorService"
