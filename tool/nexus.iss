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
; Для себя — папка пользователя (без прав администратора). Для всех
; пользователей — Program Files: тогда режим TUN запускается при входе в
; систему без окна UAC и без риска подмены файлов программы.
DefaultDirName={autopf}\Nexus
DefaultGroupName=Nexus
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
UsePreviousAppDir=yes
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
; Снять блокировку kill switch (правила брандмауэра) — с окном UAC
Filename: "{app}\nexus.exe"; Parameters: "--killswitch-off"; Verb: "runas"; Flags: shellexec waituntilterminated; RunOnceId: "KillSwitchOff"; Check: KillSwitchActive
; Вернуть системный прокси пользователя, если Nexus удаляют подключённым
Filename: "{app}\nexus.exe"; Parameters: "--restore-proxy"; Flags: runhidden waituntilterminated; RunOnceId: "RestoreProxy"
Filename: "taskkill"; Parameters: "/F /IM nexus-core.exe"; Flags: runhidden; RunOnceId: "KillCore"

[Code]
function KillSwitchActive: Boolean;
begin
  Result := FileExists(ExpandConstant('{userappdata}\Nexus\killswitch.lock'));
end;
