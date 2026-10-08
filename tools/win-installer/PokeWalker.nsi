; PokeWalker's Windows installer (3.9.1): a per-user install (no admin) — %LOCALAPPDATA%\Programs\PokeWalker by default, the Start menu, an entry in
; 설정 → 앱 to remove it, a desktop shortcut and starting at sign-in as choices. The save and this PC's ID stay in %APPDATA%\PokeWalker (a zip's
; and the installer's alike: nothing moves). Built on the Mac by ./build.sh (makensis) from the windows workflow's PokeWalker folder:
;   makensis -DVERSION=3.9.1 -DSRC=<the PokeWalker folder> -DOUT=<setup.exe> tools/win-installer/PokeWalker.nsi
; The app's own auto-update (Core/Update.swift) runs it quietly: /S /UPDATE [/RELAUNCH], with PW_TARGET = its folder (installed over in place:
; a zip's folder becomes an installed one), PW_PID = its process (waited for) and PW_LOG = the update folder's install.log.
Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!ifndef VERSION
  !error "-DVERSION=x.y[.z] is needed"
!endif
!ifndef SRC
  !error "-DSRC=<the PokeWalker folder> is needed"
!endif
!ifndef OUT
  !define OUT "PokeWalker-windows-setup.exe"
!endif
!ifndef VERSION4
  !define VERSION4 "${VERSION}.0.0"
!endif

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "Sections.nsh"

!define APP "PokeWalker"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\PokeWalker"
!define RUNKEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define MUTEX "Local\dev.khmin.pokewalker"

Name "${APP}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\PokeWalker"
InstallDirRegKey HKCU "Software\PokeWalker" "InstallDir"
BrandingText "PokeWalker ${VERSION}"
VIProductVersion "${VERSION4}"
VIAddVersionKey /LANG=1042 "ProductName" "PokeWalker"
VIAddVersionKey /LANG=1042 "FileDescription" "PokeWalker 설치"
VIAddVersionKey /LANG=1042 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1042 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1042 "LegalCopyright" "PokeWalker"

Var Update      ; /UPDATE: the app's own update (quiet, in place)
Var Relaunch    ; /RELAUNCH: start it again after
Var Log         ; PW_LOG: where the app reads how it went

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "PokeWalker ${VERSION} 설치"
!define MUI_WELCOMEPAGE_TEXT "키보드를 누르고 클릭할 때마다 한 걸음 — 데스크톱 포켓워커를 설치해요.$\r$\n$\r$\n관리자 권한 없이 이 사용자에게만 설치돼요. 세이브와 트레이너 ID는 그대로 이어져요(%APPDATA%\PokeWalker).$\r$\n$\r$\n예전에 zip으로 쓰던 PokeWalker 폴더는 설치가 끝나면 지워도 돼요."
!define MUI_COMPONENTSPAGE_NODESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\PokeWalker.exe"
!define MUI_FINISHPAGE_RUN_TEXT "PokeWalker 실행"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"

; The app's line in the update folder's install.log (the app reads it; nothing in a manual install).
!macro Note text
  ${If} $Log != ""
    FileOpen $9 $Log a
    ${If} $9 != ""
      FileSeek $9 0 END
      FileWriteUTF16LE $9 "${text}$\r$\n"
      FileClose $9
    ${EndIf}
  ${EndIf}
!macroend

; PokeWalker running here (its one-a-login mutex): asked to close (WM_CLOSE saves), waited for — up to 20 s. $0 = 1 if it's gone.
!macro CloseApp
  StrCpy $0 1
  System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "${MUTEX}") p .r1'
  ${If} $1 P<> 0
    System::Call 'kernel32::CloseHandle(p r1)'
    FindWindow $2 "PokeWalker" "PokeWalker"
    ${If} $2 <> 0
      SendMessage $2 ${WM_CLOSE} 0 0 /TIMEOUT=5000
    ${EndIf}
    StrCpy $0 0
    ${For} $3 1 40
      Sleep 500
      System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "${MUTEX}") p .r1'
      ${If} $1 P= 0
        StrCpy $0 1
        ${Break}
      ${EndIf}
      System::Call 'kernel32::CloseHandle(p r1)'
    ${Next}
  ${EndIf}
!macroend

Function .onInit
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/UPDATE" $R1
  ${IfNot} ${Errors}
    StrCpy $Update 1
  ${EndIf}
  ClearErrors
  ${GetOptions} $R0 "/RELAUNCH" $R1
  ${IfNot} ${Errors}
    StrCpy $Relaunch 1
  ${EndIf}
  ReadEnvStr $Log PW_LOG
  ${If} $Update == 1
    ReadEnvStr $R2 PW_TARGET                                   ; the app's own folder: installed over in place
    ${If} $R2 != ""
      StrCpy $INSTDIR $R2
    ${EndIf}
    ReadEnvStr $R3 PW_PID                                      ; the app quitting for this: waited for (up to 30 s)
    ${If} $R3 != ""
      System::Call 'kernel32::OpenProcess(i 0x00100000, i 0, i R3) p .r4'
      ${If} $4 P<> 0
        System::Call 'kernel32::WaitForSingleObject(p r4, i 30000) i .r5'
        System::Call 'kernel32::CloseHandle(p r4)'
      ${EndIf}
    ${EndIf}
    ; an update keeps the choices as they were: a desktop shortcut and the sign-in start only where they already are
    ${IfNot} ${FileExists} "$DESKTOP\PokeWalker.lnk"
      !insertmacro UnselectSection 1
    ${EndIf}
    ReadRegStr $R4 HKCU "${RUNKEY}" "PokeWalker"
    ${If} $R4 == ""
      !insertmacro UnselectSection 2
    ${EndIf}
  ${EndIf}
FunctionEnd

Section "PokeWalker" SecApp
  SectionIn RO
  !insertmacro CloseApp
  ${If} $0 != 1
    !insertmacro Note "failed ${VERSION}: PokeWalker is still running"
    ${IfNot} ${Silent}
      MessageBox MB_ICONEXCLAMATION|MB_OK "PokeWalker가 아직 켜져 있어요. 트레이 아이콘에서 종료한 뒤 다시 설치해 주세요."
    ${EndIf}
    Abort
  ${EndIf}
  SetOutPath "$INSTDIR"
  ClearErrors
  File /r "${SRC}\*"
  ${If} ${Errors}
    !insertmacro Note "failed ${VERSION}: files couldn't be written to $INSTDIR"
    Abort
  ${EndIf}
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\PokeWalker" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "PokeWalker"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "Publisher" "PokeWalker"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\PokeWalker.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $1 $2 $3
  WriteRegDWORD HKCU "${UNINSTKEY}" "EstimatedSize" $1
  CreateShortCut "$SMPROGRAMS\PokeWalker.lnk" "$INSTDIR\PokeWalker.exe" "" "$INSTDIR\PokeWalker.exe" 0 SW_SHOWNORMAL "" "포켓워커"
  !insertmacro Note "installed ${VERSION}"
SectionEnd

Section "바탕 화면 바로가기" SecDesktop
  CreateShortCut "$DESKTOP\PokeWalker.lnk" "$INSTDIR\PokeWalker.exe" "" "$INSTDIR\PokeWalker.exe" 0 SW_SHOWNORMAL "" "포켓워커"
SectionEnd

Section "로그인할 때 자동 실행 (걸음을 놓치지 않아요)" SecRun
  WriteRegStr HKCU "${RUNKEY}" "PokeWalker" '"$INSTDIR\PokeWalker.exe"'
SectionEnd

Section "-sign-in off"                                         ; (hidden) unchecked on an interactive install: not started at sign-in
  ${IfNot} ${SectionIsSelected} ${SecRun}
  ${AndIf} $Update != 1
    DeleteRegValue HKCU "${RUNKEY}" "PokeWalker"
  ${EndIf}
SectionEnd

Function .onInstSuccess
  ${If} $Relaunch == 1
    Exec '"$INSTDIR\PokeWalker.exe"'
  ${EndIf}
FunctionEnd

Function .onInstFailed                                          ; the update didn't go in: the app as it was starts again (it won't try this version again)
  ${If} $Relaunch == 1
  ${AndIf} ${FileExists} "$INSTDIR\PokeWalker.exe"
    Exec '"$INSTDIR\PokeWalker.exe"'
  ${EndIf}
FunctionEnd

Section "Uninstall"
  !insertmacro CloseApp
  Delete "$SMPROGRAMS\PokeWalker.lnk"
  Delete "$DESKTOP\PokeWalker.lnk"
  DeleteRegValue HKCU "${RUNKEY}" "PokeWalker"
  DeleteRegKey HKCU "${UNINSTKEY}"
  DeleteRegKey HKCU "Software\PokeWalker"
  RMDir /r "$INSTDIR\Resources"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\PokeWalker.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"                                              ; (only if nothing else is in it; the save in %APPDATA%\PokeWalker stays)
SectionEnd
