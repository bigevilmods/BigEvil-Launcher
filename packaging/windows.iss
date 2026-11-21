#ifndef AppVersion
  #define AppVersion "1.3.0"
#endif

[Setup]
AppId=BigEvil.Launcher
AppName=BigEvil Launcher
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\BigEvil Launcher
DefaultGroupName=BigEvil Launcher
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
CloseApplications=yes
SetupIconFile=assets\bigevil.ico
OutputDir=..\dist
OutputBaseFilename=BigEvil-Launcher-windows-x64
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BigEvil Launcher"; Filename: "{app}\bigevil_launcher.exe"

[Run]
Filename: "{app}\bigevil_launcher.exe"; Description: "{cm:LaunchProgram,BigEvil Launcher}"; Flags: nowait postinstall skipifsilent
