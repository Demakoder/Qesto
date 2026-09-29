#define AppName "Qesto"
#ifndef AppVersion
#define AppVersion "1.0.23"
#endif
#define AppPublisher "Qesto"
#define AppExeName "qesto.exe"

[Setup]
AppId={{2F5B1FB0-83F5-4A36-B91E-7710A46121EF}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Qesto-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\qesto.dll
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
SignTool=qesto
SignedUninstaller=yes
SignToolRetryCount=3
SignToolRetryDelay=2000

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "qesto.exp,qesto.lib,debug.log"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\flutter_inappwebview_windows_plugin.dll"
Type: files; Name: "{app}\WebView2Loader.dll"
Type: files; Name: "{app}\native_assets.json"
Type: files; Name: "{app}\qesto.exp"
Type: files; Name: "{app}\qesto.lib"
Type: files; Name: "{app}\debug.log"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\qesto.dll"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\qesto.dll"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent
