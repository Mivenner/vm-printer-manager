; VM Printer Manager - Inno Setup 6
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "dist"
#endif
#define MyAppName "VM Printer Manager"
#define MyAppExeName "VMPrinterManager.exe"

[Setup]
AppId={{C8E3A4F5-33CC-4D4E-9B2A-7F8A9B0C1D23}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=vm technology
DefaultDirName={autopf}\VM Printer Manager
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputBaseFilename=VMPrinterManager_Setup_{#MyAppVersion}
SetupIconFile={#SourceDir}\app.ico
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
MinVersion=10.0
DisableProgramGroupPage=yes

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\VMPrinterManager.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\VMPrinter.Engine.psm1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\VMPrinter.CLI.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\GUI.xaml"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\app.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Avvia-CLI.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
