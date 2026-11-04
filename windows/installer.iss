; Inno Setup definition (UTF-8 with BOM: Inno needs it for the Khmer name) for Typer-windows-setup.exe (a normal Next / Install / Finish wizard).
; Build (CI does this): iscc /DVersion=0.1.0 windows\installer.iss
; Expects both DLLs built (x64 + x86, so 32-bit apps get Typer too) and data\out from data\build.py.

#ifndef Version
  #define Version "0.0.0"
#endif
; CLSID and profile GUID from windows/src/lib.rs
#define Tip "0453:{BFD22721-7C69-45BB-B43C-57DEC56E4E58}{F7873286-5E67-4BEF-8A3E-41CEFD0FFC7F}"

[Setup]
AppId={{BFD22721-7C69-45BB-B43C-57DEC56E4E58}
AppName=Typer / សរសេរ
AppVersion={#Version}
AppPublisher=Typer
AppPublisherURL=https://nel-sokchhunly.github.io/typer/
DefaultDirName={autopf}\Typer
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=no
UninstallDisplayIcon={app}\typer.ico
UninstallDisplayName=Typer / សរសេរ (Khmer keyboard)
OutputDir=..\build
OutputBaseFilename=Typer-windows-setup

[Files]
Source: "typer.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\data\out\lexicon.tsv"; DestDir: "{app}\data"; Flags: ignoreversion
Source: "..\data\out\ngrams.tsv"; DestDir: "{app}\data"; Flags: ignoreversion
Source: "..\data\out\english.tsv"; DestDir: "{app}\data"; Flags: ignoreversion
; Apps that already loaded Typer keep the old DLL until they restart; restartreplace swaps it then.
Source: "target\x86_64-pc-windows-msvc\release\typer_tsf.dll"; DestDir: "{app}"; DestName: "typer64.dll"; Flags: ignoreversion regserver restartreplace uninsrestartdelete 64bit
Source: "target\i686-pc-windows-msvc\release\typer_tsf.dll"; DestDir: "{app}"; DestName: "typer32.dll"; Flags: ignoreversion regserver restartreplace uninsrestartdelete 32bit

[Messages]
FinishedLabelNoIcons=Typer / សរសេរ is installed.%n%nPress Windows + Space and choose Typer / សរសេរ to start typing. Type Khmer in Latin letters with spaces between words, then press Enter or a number to pick.
FinishedLabel=Typer / សរសេរ is installed.%n%nPress Windows + Space and choose Typer / សរសេរ to start typing. Type Khmer in Latin letters with spaces between words, then press Enter or a number to pick.

[Code]
// Adds / removes Typer in the user's keyboard list, so there is nothing to set up in Settings.
function InstallLayoutOrTip(psz: String; dwFlags: DWORD): BOOL;
  external 'InstallLayoutOrTip@input.dll stdcall delayload';
function UninstallLayoutOrTip(psz: String; dwFlags: DWORD): BOOL;
  external 'InstallLayoutOrTip@input.dll stdcall delayload uninstallonly';

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    InstallLayoutOrTip('{#Tip}', 0);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    UninstallLayoutOrTip('{#Tip}', 1); // ILOT_UNINSTALL
end;
