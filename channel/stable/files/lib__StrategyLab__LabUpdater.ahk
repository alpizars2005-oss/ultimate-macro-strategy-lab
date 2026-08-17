#Requires AutoHotkey v2.0

; Private Strategy Lab updater.
; Uses a local Git cache + Git Credential Manager for private GitHub access.
; No GitHub token, PAT, Discord credential, or arbitrary download URL is stored here.

LabUpdaterRepoUrl() => "https://github.com/alpizars2005-oss/ultimate-macro-strategy-lab.git"
LabUpdaterCacheRoot() {
    localAppData := EnvGet("LOCALAPPDATA")
    if (localAppData = "")
        localAppData := A_AppData
    return localAppData "\Ultimate_Macro\StrategyLabUpdater"
}
LabUpdaterCacheRepo() => LabUpdaterCacheRoot() "\repo"
LabUpdaterChannelRoot() => LabUpdaterCacheRepo() "\channel\stable"
LabUpdaterVersionFile() => LabUpdaterChannelRoot() "\version.ini"
LabUpdaterLogPath() => LabUpdaterCacheRoot() "\updater.log"

LabUpdaterInstalledVersion(fallbackVersion := "0.0.0") {
    versionFile := A_ScriptDir "\lab_version.ini"
    try return IniRead(versionFile, "Lab", "Version", fallbackVersion)
    catch
        return fallbackVersion
}

LabUpdaterLog(message) {
    try {
        root := LabUpdaterCacheRoot()
        if !DirExist(root)
            DirCreate(root)
        clean := StrReplace(String(message), "`r", "")
        clean := StrReplace(clean, "`n", " | ")
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " clean "`r`n", LabUpdaterLogPath(), "UTF-8")
    }
}

LabUpdaterGitAvailable() {
    try return RunWait(A_ComSpec ' /d /c git --version >nul 2>&1', , "Hide") = 0
    catch
        return false
}

LabUpdaterRunGit(args, visible := false) {
    cmd := A_ComSpec ' /d /c git ' args
    try return RunWait(cmd, , visible ? "" : "Hide")
    catch Error as err {
        LabUpdaterLog("git launch failed: " err.Message)
        return -1
    }
}

LabUpdaterRefreshCache(allowEnrollmentPrompt := true) {
    root := LabUpdaterCacheRoot()
    repo := LabUpdaterCacheRepo()
    if !DirExist(root)
        DirCreate(root)

    if !DirExist(repo "\.git") {
        if !allowEnrollmentPrompt
            return false
        answer := MsgBox(
            "Enable private automatic updates for Strategy Lab?`n`n"
            . "GitHub may open a browser once so Git Credential Manager can authorize this private repo. "
            . "No token is stored inside the macro.`n`n"
            . "After that, new Lab builds can update themselves without downloading ZIP files.",
            "Strategy Lab Updates", "YesNo Iconi")
        if (answer != "Yes")
            return false

        try {
            if DirExist(repo)
                DirDelete(repo, true)
        }
        cloneArgs := 'clone --depth 1 --branch main "' LabUpdaterRepoUrl() '" "' repo '"'
        code := LabUpdaterRunGit(cloneArgs, true)
        if (code != 0 || !DirExist(repo "\.git")) {
            LabUpdaterLog("initial clone failed with exit code " code)
            MsgBox(
                "I couldn't connect the private Lab update channel.`n`n"
                . "The macro will keep working normally. You can try again next launch."
                . "`n`nGit/GitHub may currently be unavailable or Git Credential Manager may still need authorization.",
                "Strategy Lab Updates", "Icon!")
            return false
        }
        return true
    }

    code := LabUpdaterRunGit('-C "' repo '" fetch --quiet --depth 1 origin main', false)
    if (code != 0) {
        LabUpdaterLog("fetch failed with exit code " code)
        return false
    }
    code := LabUpdaterRunGit('-C "' repo '" reset --quiet --hard FETCH_HEAD', false)
    if (code != 0) {
        LabUpdaterLog("reset failed with exit code " code)
        return false
    }
    return true
}

LabUpdaterVersionParts(versionText) {
    parts := []
    for token in StrSplit(Trim(String(versionText)), ".") {
        if RegExMatch(token, "^(\d+)", &m)
            parts.Push(Integer(m[1]))
        else
            parts.Push(0)
    }
    return parts
}

LabUpdaterIsNewer(remoteVersion, localVersion) {
    remote := LabUpdaterVersionParts(remoteVersion)
    localParts := LabUpdaterVersionParts(localVersion)
    count := Max(remote.Length, localParts.Length)
    Loop count {
        r := A_Index <= remote.Length ? remote[A_Index] : 0
        l := A_Index <= localParts.Length ? localParts[A_Index] : 0
        if (r > l)
            return true
        if (r < l)
            return false
    }
    return false
}

LabUpdaterStartupCheck(currentVersion, *) {
    currentVersion := LabUpdaterInstalledVersion(currentVersion)
    if !LabUpdaterGitAvailable() {
        LabUpdaterLog("Git not available; private auto-update skipped")
        return
    }

    cacheExists := DirExist(LabUpdaterCacheRepo() "\.git")
    if !LabUpdaterRefreshCache(!cacheExists)
        return

    versionFile := LabUpdaterVersionFile()
    if !FileExist(versionFile) {
        LabUpdaterLog("version.ini missing from update channel")
        return
    }

    remoteVersion := IniRead(versionFile, "Lab", "Version", "")
    if (remoteVersion = "" || !LabUpdaterIsNewer(remoteVersion, currentVersion))
        return

    notes := IniRead(versionFile, "Lab", "Notes", "")
    message := "Strategy Lab " remoteVersion " is available.`nCurrent Lab version: " currentVersion
    if (notes != "")
        message .= "`n`nWhat's new:`n" StrReplace(notes, "|", "`n")
    message .= "`n`nUpdate now? The updater only replaces Lab-owned files; strategies and AppData settings are preserved."

    if MsgBox(message, "Strategy Lab Update", "YesNo Iconi") != "Yes"
        return

    LabUpdaterLaunchInstaller(remoteVersion)
}

LabUpdaterLaunchInstaller(remoteVersion) {
    updater := A_ScriptDir "\submacros\lab_update.ps1"
    if !FileExist(updater) {
        MsgBox("Lab updater helper is missing:`n" updater, "Strategy Lab Update", "Iconx")
        return
    }

    tempUpdater := A_Temp "\UltimateMacroStrategyLab_update_" A_TickCount ".ps1"
    try FileCopy(updater, tempUpdater, true)
    catch Error as err {
        MsgBox("Could not prepare the Lab updater:`n" err.Message, "Strategy Lab Update", "Iconx")
        return
    }

    pid := DllCall("GetCurrentProcessId")
    cmd := 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' tempUpdater
        . '" -InstallDir "' A_ScriptDir
        . '" -CacheDir "' LabUpdaterCacheRepo()
        . '" -ExpectedVersion "' remoteVersion
        . '" -ParentPid ' pid
    try {
        Run(cmd, , "Hide")
        ExitApp()
    } catch Error as err {
        MsgBox("Could not start the Lab updater:`n" err.Message, "Strategy Lab Update", "Iconx")
    }
}
