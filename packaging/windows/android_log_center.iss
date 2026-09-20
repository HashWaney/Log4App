#ifndef MyAppVersion
  #define MyAppVersion "2.1.0"
#endif

#define MyAppName "Android Log Center"
#define MyAppExeName "android_log_center.exe"

[Setup]
AppId={{E6102FE2-377B-49BB-AF4A-405A56A499EA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppName}
DefaultDirName={autopf}\Android Log Center
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=AndroidLogCenter-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} Installer

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Android Log Center (TCP 9090)"""; Flags: runhidden; StatusMsg: "正在更新防火墙规则..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Android Log Center (TCP 9090)"" dir=in action=allow protocol=TCP localport=9090 program=""{app}\{#MyAppExeName}"" enable=yes profile=private"; Flags: runhidden; StatusMsg: "正在允许局域网设备连接..."
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Android Log Center (TCP 9090)"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"
