; Установщик Nexus для Windows (Inno Setup 6).
; Собирается в GitHub Actions: iscc /DAppVersion=1.0.0 /DSourceDir=... tool\nexus.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7B1E6C0E-4C1B-4C9F-9E58-2A7F2C0E5A11}
AppName=Nexus
AppVersion={#AppVersion}
AppPublisher=NEXUS_VPN
DefaultDirName={localappdata}\Programs\Nexus
DefaultGroupName=Nexus
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Nexus-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nexus.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
; Обновить кэш значков — иначе Windows показывает старую иконку
ChangesAssociations=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Nexus"; Filename: "{app}\nexus.exe"
Name: "{autodesktop}\Nexus"; Filename: "{app}\nexus.exe"; Tasks: desktopicon

[Run]
Filename: "{sys}\ie4uinit.exe"; Parameters: "-show"; Flags: runhidden skipifdoesntexist
Filename: "{app}\nexus.exe"; Description: "Запустить Nexus"; Flags: nowait postinstall skipifsilent
; После тихого автообновления — запустить снова
Filename: "{app}\nexus.exe"; Flags: nowait; Check: WizardSilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM nexus-core.exe"; Flags: runhidden; RunOnceId: "KillCore"
