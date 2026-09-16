#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =========================================================
; AUDIO CORE - AHK v2
; =========================================================

; Control volume of audio sessions by groups with hotkeys and OSD.
; Requires Windows 7 or later. Uses COM interfaces for audio session management.

; =========================================================
; CONFIGURATION
; =========================================================

global ConfigFile := "C:\Audio\config.ini"
global GroupsFile := "C:\Audio\groups.txt"
global Step := 2
global DebounceTime := 60
global LastRefreshTime := 0
global OSDTime := 1200
global GroupOrder := ["media", "games", "chat"]
global DefaultGroupVolume := 50
global Hotkeys := Map(
    "Group1Up", "F13",
    "Group1Down", "F14",
    "Group2Up", "F15",
    "Group2Down", "F16",
    "Group3Up", "F17",
    "Group3Down", "F18",
    "SystemUp", "F19",
    "SystemDown", "F20"
)
global OSDWidth := 320
global OSDHeight := 20
global OSDYOffset := 100
global OSDBarColor := "00ffff"
global OSDBackgroundColor := "202020"
global OSDTransparentKeyColor := "010203"
global OSDFont := "Segoe UI"
global OSDFontSize := 10
global OSDOpacity := 192
global CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
global IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
global IID_IAudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
global IID_IAudioSessionControl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
global IID_ISimpleAudioVolume := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"
global IID_IUnknown := "{00000000-0000-0000-C000-000000000046}"
global IID_IAudioSessionNotification := "{641DD20B-4D41-49CC-ABA3-174B9477BB08}"
global Groups := Map()
global GroupVolumes := Map()
global PendingChanges := Map()
global ChangeTimers := Map()
global GroupChangeCallbacks := Map()
global AudioSessions := Map()
global KnownSessions := Map()
global InitializedSessionVolumes := Map()
global IsRefreshingSessions := false
global IsProcessingNotifications := false
global LastAudioErrorTime := 0
global CurrentAudioDeviceId := ""
global AudioDeviceChanged := false
global PendingSystemVolume := 0
global SystemVolumeTimerActive := false
global SaveVolumesScheduled := false
global RegisteredHotkeys := Map()
global NotificationState := Map(
    "VTable", 0,
    "Object", 0,
    "CallbackQI", 0,
    "CallbackAddRef", 0,
    "CallbackRelease", 0,
    "CallbackCreated", 0,
    "Device", 0,
    "Manager", 0,
    "Registered", false,
    "RefCount", 1
)
global NotificationCallbackActive := 0
global PendingNotifiedSessions := []
global NotificationProcessingScheduled := false
global VolumeGui := 0
global VolumeBgGui := 0
global VolumeBar := 0
global VolumeLabel := 0
global OSDVisible := false

; =========================================================
; START
; =========================================================

EnsureConfigDirectory()
LoadConfig()
ValidateConfiguration()
LoadGroups()
InitializeGroups()
LoadVolumes()
OnExit(SaveVolumesOnExit)
for group in GroupOrder {
    GroupChangeCallbacks[group] := ApplyGroupChange.Bind(group)
}
CreateVolumeOSD()
RefreshAudioSessions()
RegisterAudioSessionNotifications()
ValidateHotkeys()
RegisterHotkeys()
SetTimer(CheckAudioDevice, 2000)
SetTimer(RefreshAudioSessionsIfNeeded, 5000)

; =========================================================
; KONFIGURACJA
; =========================================================

EnsureConfigDirectory() {
    global ConfigFile

    SplitPath(ConfigFile, , &configDir)
    if configDir != "" && !DirExist(configDir) {
        DirCreate(configDir)
    }
}

LoadConfig() {
    global ConfigFile, GroupsFile, Step, DebounceTime, OSDTime, GroupOrder, DefaultGroupVolume, Hotkeys, OSDWidth,
        OSDHeight, OSDYOffset, OSDBarColor, OSDBackgroundColor, OSDTransparentKeyColor, OSDFont, OSDFontSize,
        OSDOpacity

    if !FileExist(ConfigFile) {
        SaveConfig()
        return
    }

    try {
        GroupsFile := IniRead(ConfigFile, "Paths", "GroupsFile", GroupsFile)
        Step := ReadIniInt("Volume", "Step", Step)
        DebounceTime := ReadIniInt("Volume", "DebounceTime", DebounceTime)
        OSDTime := ReadIniInt("Volume", "OSDTime", OSDTime)
        orderText := IniRead(ConfigFile, "Groups", "Order", "media,games,chat")
        GroupOrder := ParseGroupOrder(orderText)
        DefaultGroupVolume := ReadIniInt("Groups", "DefaultVolume", DefaultGroupVolume)
        for name, defaultKey in Hotkeys {
            Hotkeys[name] := IniRead(ConfigFile, "Hotkeys", name, defaultKey)
        }
        OSDWidth := ReadIniInt("OSD", "Width", OSDWidth)
        OSDHeight := ReadIniInt("OSD", "Height", OSDHeight)
        OSDYOffset := ReadIniInt("OSD", "YOffset", OSDYOffset)
        OSDBarColor := NormalizeHexColor(IniRead(ConfigFile, "OSD", "BarColor", OSDBarColor), OSDBarColor)
        OSDBackgroundColor := NormalizeHexColor(IniRead(ConfigFile, "OSD", "BackgroundColor", OSDBackgroundColor),
        OSDBackgroundColor)
        OSDTransparentKeyColor := NormalizeHexColor(IniRead(ConfigFile, "OSD", "TransparentKeyColor",
            OSDTransparentKeyColor), OSDTransparentKeyColor)
        OSDFont := IniRead(ConfigFile, "OSD", "Font", OSDFont)
        OSDFontSize := ReadIniInt("OSD", "FontSize", OSDFontSize)
        OSDOpacity := ReadIniInt("OSD", "Opacity", OSDOpacity)
    } catch Error as err {
        TrayTip("Error reading config.ini", err.Message, 5)
    }
}

ReadIniInt(section, key, defaultValue) {
    global ConfigFile

    try {
        return Integer(IniRead(ConfigFile, section, key, defaultValue))
    } catch {
        return defaultValue
    }
}

ParseGroupOrder(text) {
    result := []
    seen := Map()

    for item in StrSplit(text, ",") {
        group := StrLower(Trim(item))
        if group = "" || seen.Has(group) {
            continue
        }
        seen[group] := true
        result.Push(group)
    }

    return result.Length ? result : ["media", "games", "chat"]
}

SaveConfig() {
    global ConfigFile, GroupsFile, Step, DebounceTime, OSDTime, GroupOrder, DefaultGroupVolume, Hotkeys, OSDWidth,
        OSDHeight, OSDYOffset, OSDBarColor, OSDBackgroundColor, OSDTransparentKeyColor, OSDOpacity, OSDFont,
        OSDFontSize

    try {
        EnsureConfigDirectory()
        IniWrite(GroupsFile, ConfigFile, "Paths", "GroupsFile")
        IniWrite(Step, ConfigFile, "Volume", "Step")
        IniWrite(DebounceTime, ConfigFile, "Volume", "DebounceTime")
        IniWrite(OSDTime, ConfigFile, "Volume", "OSDTime")
        IniWrite(JoinArray(GroupOrder), ConfigFile, "Groups", "Order")
        IniWrite(DefaultGroupVolume, ConfigFile, "Groups", "DefaultVolume")
        for name, hotkeyName in Hotkeys {
            IniWrite(hotkeyName, ConfigFile, "Hotkeys", name)
        }
        IniWrite(OSDWidth, ConfigFile, "OSD", "Width")
        IniWrite(OSDHeight, ConfigFile, "OSD", "Height")
        IniWrite(OSDYOffset, ConfigFile, "OSD", "YOffset")
        IniWrite(OSDBarColor, ConfigFile, "OSD", "BarColor")
        IniWrite(OSDBackgroundColor, ConfigFile, "OSD", "BackgroundColor")
        IniWrite(OSDTransparentKeyColor, ConfigFile, "OSD", "TransparentKeyColor")
        IniWrite(OSDFont, ConfigFile, "OSD", "Font")
        IniWrite(OSDFontSize, ConfigFile, "OSD", "FontSize")
        IniWrite(OSDOpacity, ConfigFile, "OSD", "Opacity")
    } catch Error as err {
        TrayTip("Error saving config.ini", err.Message, 5)
        OutputDebug("SaveConfig error: " err.Message)
    }
}

JoinArray(items, separator := ",") {
    result := ""

    for item in items {
        result .= (result = "" ? "" : separator) item
    }

    return result
}

InitializeGroups() {
    global GroupOrder, DefaultGroupVolume, GroupVolumes, PendingChanges, ChangeTimers

    for group in GroupOrder {
        if !GroupVolumes.Has(group) {
            GroupVolumes[group] := DefaultGroupVolume
        }
        if !PendingChanges.Has(group) {
            PendingChanges[group] := 0
        }
        if !ChangeTimers.Has(group) {
            ChangeTimers[group] := false
        }
    }
}

ValidateConfiguration() {
    global Step, DebounceTime, OSDTime, DefaultGroupVolume, OSDWidth, OSDHeight, OSDYOffset, OSDBarColor,
        OSDBackgroundColor, OSDTransparentKeyColor, OSDFontSize, OSDOpacity

    Step := Max(1, Min(100, Step))
    DebounceTime := Max(0, Min(5000, DebounceTime))
    OSDTime := Max(0, Min(60000, OSDTime))
    DefaultGroupVolume := Max(0, Min(100, DefaultGroupVolume))
    OSDWidth := Max(50, Min(2000, OSDWidth))
    OSDHeight := Max(10, Min(500, OSDHeight))
    OSDYOffset := Max(0, Min(2000, OSDYOffset))
    OSDFontSize := Max(6, Min(100, OSDFontSize))
    OSDOpacity := Max(0, Min(255, OSDOpacity))
    OSDBarColor := NormalizeHexColor(OSDBarColor, "00ffff")
    OSDBackgroundColor := NormalizeHexColor(OSDBackgroundColor, "202020")
    OSDTransparentKeyColor := NormalizeHexColor(OSDTransparentKeyColor, "010203")
}

NormalizeHexColor(value, fallback) {
    value := Trim(value)
    value := RegExReplace(value, "i)^0x")

    return RegExMatch(value, "i)^[0-9A-F]{6}$")
        ? StrUpper(value)
        : fallback
}

IsHexColor(value) {
    value := Trim(value)
    value := RegExReplace(value, "i)^0x")

    return RegExMatch(value, "i)^[0-9A-F]{6}$") != 0
}

; =========================================================
; FILES AND GROUPS
; =========================================================

LoadGroups() {
    global Groups, GroupsFile, GroupOrder, GroupVolumes, PendingChanges, ChangeTimers, DefaultGroupVolume

    if !FileExist(GroupsFile) {
        CreateDefaultGroupsFile()
    }
    try {
        content := FileRead(GroupsFile, "UTF-8")
    } catch Error as err {
        MsgBox("Error reading groups file:`n`n" err.Message, "Audio Groups", "Iconx")
        ExitApp()
    }
    Groups := Map()
    currentGroup := ""

    for line in StrSplit(content, "`n", "`r") {
        line := Trim(line)

        if line = "" || SubStr(line, 1, 1) = "#" {
            continue
        }
        line := Trim(RegExReplace(line, "\s*[;].*$"))
        if line = "" {
            continue
        }
        if RegExMatch(line, "^\[([^\]]+)\]$", &match) {
            currentGroup := StrLower(Trim(match[1]))
            if !Groups.Has(currentGroup) {
                Groups[currentGroup] := Map()
            }
            continue
        }
        if currentGroup = "" {
            continue
        }
        line := Trim(line)
        line := StrReplace(line, Chr(34), "")
        line := StrLower(line)
        if !RegExMatch(line, "i)\.exe$") {
            line .= ".exe"
        }
        Groups[currentGroup][line] := true
    }

    for group in GroupOrder {
        if !Groups.Has(group) {
            Groups[group] := Map()
        }
        if !GroupVolumes.Has(group) {
            GroupVolumes[group] := DefaultGroupVolume
        }
        if !PendingChanges.Has(group) {
            PendingChanges[group] := 0
        }
        if !ChangeTimers.Has(group) {
            ChangeTimers[group] := false
        }
    }
}

CreateDefaultGroupsFile() {
    global GroupsFile

    try {
        EnsureConfigDirectory()
        defaultContent := "; Audio Groups Configuration`n"
            . "; Add process names to control their volume`n`n"
            . "[media]`n"
            . "; Media players, browsers, streaming`n"
            . "spotify.exe`n"
            . "firefox.exe`n"
            . "chrome.exe`n"
            . "msedge.exe`n`n"
            . "[games]`n"
            . "; Games and game launchers`n"
            . "ac.exe`n"
            . "ams2.exe`n"
            . "fh5.exe`n`n"
            . "[chat]`n"
            . "; Communication apps`n"
            . "discord.exe`n"
            . "teams.exe`n"
            . "skype.exe`n"
        FileAppend(defaultContent, GroupsFile, "UTF-8")
        TrayTip("Audio Core", "Created default groups.txt`nEdit it to add your applications.", 10)
    } catch Error as err {
        MsgBox("Error creating groups.txt:`n`n" err.Message, "Audio Groups", "Iconx")
        ExitApp()
    }
}

LoadVolumes() {
    global ConfigFile, GroupVolumes, GroupOrder, DefaultGroupVolume

    for group in GroupOrder {
        defaultVolume := GroupVolumes.Has(group) ? GroupVolumes[group] : DefaultGroupVolume
        try {
            value := Integer(IniRead(ConfigFile, "Volumes", group, defaultVolume))
        } catch {
            value := defaultVolume
        }
        GroupVolumes[group] := Max(0, Min(100, value))
    }

    try {
        savedSystemVolume := IniRead(ConfigFile, "Volumes", "System", "")
        if savedSystemVolume != "" {
            savedSystemVolume := Integer(savedSystemVolume)
            if savedSystemVolume >= 0 && savedSystemVolume <= 100 {
                SoundSetVolume(savedSystemVolume)
            }
        }
    }
}

SaveVolumes() {
    global ConfigFile, GroupVolumes, GroupOrder, SaveVolumesScheduled

    SaveVolumesScheduled := false

    try {
        EnsureConfigDirectory()

        for group in GroupOrder {
            if GroupVolumes.Has(group) {
                IniWrite(GroupVolumes[group], ConfigFile, "Volumes", group)
            }
        }

        IniWrite(Round(SoundGetVolume()), ConfigFile, "Volumes", "System")
    } catch Error as err {
        OutputDebug("SaveVolumes error: " err.Message)
    }
}

ScheduleSaveVolumes() {
    global SaveVolumesScheduled

    if SaveVolumesScheduled {
        SetTimer(SaveVolumes, 0)
    }
    SaveVolumesScheduled := true
    SetTimer(SaveVolumes, -300)
}

SaveVolumesOnExit(reason, code) {
    SetTimer(SaveVolumes, 0)
    UnregisterAudioSessionNotifications()
    SaveVolumes()
}

; =========================================================
; VOLUME CHANGES
; =========================================================

QueueGroupChange(group, amount) {
    global PendingChanges, ChangeTimers, DebounceTime, GroupChangeCallbacks

    if !PendingChanges.Has(group) {
        return
    }
    PendingChanges[group] += amount
    callback := GroupChangeCallbacks[group]
    if DebounceTime <= 0 {
        ApplyGroupChange(group)
        return
    }
    if ChangeTimers[group] {
        SetTimer(callback, 0)
    }
    ChangeTimers[group] := true
    SetTimer(callback, -DebounceTime)
}

ApplyGroupChange(group) {
    global PendingChanges, ChangeTimers, GroupVolumes

    amount := PendingChanges[group]
    PendingChanges[group] := 0
    ChangeTimers[group] := false
    if amount = 0 {
        return
    }
    GroupVolumes[group] := Max(0, Min(100, GroupVolumes[group] + amount))

    ApplyVolumeToGroup(group, GroupVolumes[group])
    ScheduleSaveVolumes()
    RefreshAudioSessionsIfNeeded()
    ShowVolumeOSD(group, GroupVolumes[group])
}

ApplyVolumeToGroup(group, volume) {
    global Groups, AudioSessions

    if !Groups.Has(group) {
        return
    }
    for , session in AudioSessions {
        if Groups[group].Has(session["ProcessName"]) {
            SetSessionVolume(session["Interface"], volume)
        }
    }
}

QueueSystemVolume(amount) {
    global PendingSystemVolume, SystemVolumeTimerActive, DebounceTime

    PendingSystemVolume += amount
    if DebounceTime <= 0 {
        ApplySystemVolume()
        return
    }
    if SystemVolumeTimerActive {
        SetTimer(ApplySystemVolume, 0)
    }
    SystemVolumeTimerActive := true
    SetTimer(ApplySystemVolume, -DebounceTime)
}

ApplySystemVolume() {
    global PendingSystemVolume, SystemVolumeTimerActive

    amount := PendingSystemVolume
    PendingSystemVolume := 0
    SystemVolumeTimerActive := false
    if amount = 0 {
        return
    }
    try {
        current := SoundGetVolume()
        target := Max(0, Min(100, current + amount))
        SoundSetVolume(target)
        ScheduleSaveVolumes()
        RefreshAudioSessionsIfNeeded()
        ShowVolumeOSD("system", Round(target))
    } catch Error as err {
        TrayTip("Error modifying system volume", err.Message, 3)
    }
}

SetSessionVolume(sessionControl, volume) {
    global IID_ISimpleAudioVolume

    try {
        simpleVolume := ComObjQuery(sessionControl, IID_ISimpleAudioVolume)
        if !simpleVolume {
            return false
        }
        level := Max(0, Min(100, volume)) / 100.0
        hr := ComCall(3, simpleVolume, "Float", level, "Ptr", 0)
        return hr = 0
    } catch {
        return false
    }
}

; =========================================================
; AUDIO SESSION
; =========================================================

RefreshAudioSessions() {
    global IsRefreshingSessions

    if IsRefreshingSessions {
        return
    }
    IsRefreshingSessions := true
    try {
        RefreshAudioSessionsInternal()
    } finally {
        IsRefreshingSessions := false
    }
}

RefreshAudioSessionsInternal() {
    global AudioSessions, KnownSessions, NotificationState, AudioDeviceChanged

    newSessions := Map()
    for session in EnumerateAudioSessions() {
        processName := session["ProcessName"]
        pid := session["Pid"]
        interface := session["Interface"]
        instanceId := session["InstanceId"]
        key := instanceId != "" ? instanceId : pid ":" processName
        newSessions[key] := session
        if !KnownSessions.Has(key) {
            ApplyInitialVolume(processName, interface, key)
        }
    }
    KnownSessions := newSessions
    AudioSessions := newSessions
    if AudioDeviceChanged {
        AudioDeviceChanged := false
        if NotificationState["Registered"] {
            SetTimer(ReRegisterAudioNotifications, -1)
        }
    }
}

RefreshAudioSessionsIfNeeded() {
    global LastRefreshTime

    if (LastRefreshTime = 0) || (A_TickCount - LastRefreshTime > 5000) {
        RefreshAudioSessions()
        LastRefreshTime := A_TickCount
    }
}

ApplyInitialVolume(processName, sessionControl, key) {
    global Groups, GroupVolumes, GroupOrder, InitializedSessionVolumes

    if InitializedSessionVolumes.Has(key) {
        return
    }

    for group in GroupOrder {
        if Groups.Has(group) && Groups[group].Has(processName) {
            SetSessionVolume(sessionControl, GroupVolumes[group])
            InitializedSessionVolumes[key] := true
            return
        }
    }
}

EnumerateAudioSessions() {
    global CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator, IID_IAudioSessionManager2, IID_IAudioSessionControl2,
        CurrentAudioDeviceId, AudioDeviceChanged, KnownSessions, AudioSessions, LastAudioErrorTime

    result := []
    try {
        deviceEnumerator := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)
        hr := ComCall(4, deviceEnumerator, "Int", 0, "Int", 1, "Ptr*", &devicePtr := 0)
        if hr != 0 || !devicePtr {
            return result
        }
        device := ComValue(13, devicePtr, 1)
        hr := ComCall(5, device, "Ptr*", &deviceIdPtr := 0)
        deviceId := ""
        if hr = 0 && deviceIdPtr {
            try {
                deviceId := StrGet(deviceIdPtr, 4096, "UTF-16")
            } finally {
                DllCall("ole32\CoTaskMemFree", "Ptr", deviceIdPtr)
            }
        }
        if CurrentAudioDeviceId != "" && CurrentAudioDeviceId != deviceId {
            KnownSessions := Map()
            AudioSessions := Map()
            PendingNotifiedSessions := []
            AudioDeviceChanged := true
        }
        CurrentAudioDeviceId := deviceId
        iid := Buffer(16, 0)
        hr := DllCall("ole32\CLSIDFromString", "WStr", IID_IAudioSessionManager2, "Ptr", iid, "UInt")
        if hr != 0 {
            return result
        }
        hr := ComCall(3, device, "Ptr", iid.Ptr, "UInt", 23, "Ptr", 0, "Ptr*", &managerPtr := 0)
        if hr != 0 || !managerPtr {
            return result
        }
        manager := ComValue(13, managerPtr, 1)
        hr := ComCall(5, manager, "Ptr*", &enumeratorPtr := 0)
        if hr != 0 || !enumeratorPtr {
            return result
        }
        enumerator := ComValue(13, enumeratorPtr, 1)
        hr := ComCall(3, enumerator, "Int*", &count := 0)
        if hr != 0 {
            return result
        }
        loop count {
            hr := ComCall(4, enumerator, "Int", A_Index - 1, "Ptr*", &sessionPtr := 0)
            if hr != 0 || !sessionPtr {
                continue
            }
            sessionControl := ComValue(13, sessionPtr, 1)
            control2 := ComObjQuery(sessionControl, IID_IAudioSessionControl2)
            if !control2 {
                continue
            }
            hr := ComCall(14, control2, "UInt*", &pid := 0)
            if hr != 0 || pid = 0 {
                OutputDebug("Skipping session without valid PID")
                continue
            }
            try {
                processName := StrLower(ProcessGetName(pid))
            } catch {
                processName := ""
            }
            if processName = "" {
                continue
            }
            result.Push(Map(
                "Pid", pid,
                "ProcessName", processName,
                "InstanceId", GetSessionInstanceIdentifier(control2),
                "Interface", sessionControl
            ))
        }
    } catch Error as err {
        if A_TickCount - LastAudioErrorTime > 5000 {
            LastAudioErrorTime := A_TickCount
            OutputDebug("Audio enumeration error: " err.Message)
        }
    }
    return result
}

GetSessionInstanceIdentifier(control2) {
    try {
        hr := ComCall(15, control2, "Ptr*", &stringPtr := 0)
        if hr != 0 || !stringPtr {
            return ""
        }

        try {
            return StrGet(stringPtr, 4096, "UTF-16")
        } finally {
            DllCall("ole32\CoTaskMemFree", "Ptr", stringPtr)
        }
    } catch {
        return ""
    }
}

; =========================================================
; AUDIO DEVICE CHECK
; =========================================================

CheckAudioDevice() {
    global CurrentAudioDeviceId, AudioDeviceChanged, CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator

    try {
        deviceEnumerator := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)
        hr := ComCall(4, deviceEnumerator, "Int", 0, "Int", 1, "Ptr*", &devicePtr := 0)
        if hr != 0 || !devicePtr {
            return
        }
        device := ComValue(13, devicePtr, 1)
        hr := ComCall(5, device, "Ptr*", &deviceIdPtr := 0)
        deviceId := ""
        if hr = 0 && deviceIdPtr {
            try {
                deviceId := StrGet(deviceIdPtr, 4096, "UTF-16")
            } finally {
                DllCall("ole32\CoTaskMemFree", "Ptr", deviceIdPtr)
            }
        }

        if CurrentAudioDeviceId != "" && CurrentAudioDeviceId != deviceId {
            CurrentAudioDeviceId := deviceId
            AudioDeviceChanged := true
            RefreshAudioSessions()
        } else if CurrentAudioDeviceId = "" {
            CurrentAudioDeviceId := deviceId
        }
    } catch Error as err {
        OutputDebug("CheckAudioDevice error: " err.Message)
    }
}

; =========================================================
; IAudioSessionNotification
; =========================================================

RegisterAudioSessionNotifications() {
    global NotificationState, CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator, IID_IAudioSessionManager2

    if NotificationState["Registered"] {
        return true
    }
    try {
        NotificationState["Device"] := ComObject(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)
        hr := ComCall(4, NotificationState["Device"], "Int", 0, "Int", 1, "Ptr*", &devicePtr := 0)
        if hr != 0 || !devicePtr {
            return false
        }
        device := ComValue(13, devicePtr, 1)
        iid := Buffer(16, 0)
        hr := DllCall("ole32\CLSIDFromString", "WStr", IID_IAudioSessionManager2, "Ptr", iid, "UInt")
        if hr != 0 {
            return false
        }
        hr := ComCall(3, device, "Ptr", iid.Ptr, "UInt", 23, "Ptr", 0, "Ptr*", &managerPtr := 0)
        if hr != 0 || !managerPtr {
            return false
        }
        NotificationState["Manager"] := ComValue(13, managerPtr, 1)
        NotificationState["RefCount"] := 1
        NotificationState["VTable"] := Buffer(A_PtrSize * 4, 0)
        NotificationState["CallbackQI"] := CallbackCreate(Notification_QueryInterface, "", 3)
        NotificationState["CallbackAddRef"] := CallbackCreate(Notification_AddRef, "", 1)
        NotificationState["CallbackRelease"] := CallbackCreate(Notification_Release, "", 1)
        NotificationState["CallbackCreated"] := CallbackCreate(Notification_OnSessionCreated, "", 2)
        NumPut("Ptr", NotificationState["CallbackQI"], NotificationState["VTable"], A_PtrSize * 0)
        NumPut("Ptr", NotificationState["CallbackAddRef"], NotificationState["VTable"], A_PtrSize * 1)
        NumPut("Ptr", NotificationState["CallbackRelease"], NotificationState["VTable"], A_PtrSize * 2)
        NumPut("Ptr", NotificationState["CallbackCreated"], NotificationState["VTable"], A_PtrSize * 3)
        NotificationState["Object"] := Buffer(A_PtrSize, 0)
        NumPut("Ptr", NotificationState["VTable"].Ptr, NotificationState["Object"], 0)
        hr := ComCall(8, NotificationState["Manager"], "Ptr", NotificationState["Object"].Ptr)
        if hr != 0 {
            ResetNotificationState()
            return false
        }
        NotificationState["Registered"] := true
        RefreshAudioSessions()
        return true
    } catch Error as err {
        OutputDebug("RegisterSessionNotification error: " err.Message)
        ResetNotificationState()
        return false
    }
}

UnregisterAudioSessionNotifications() {
    global NotificationState

    if NotificationState["Registered"] && NotificationState["Manager"] != 0 && NotificationState["Object"] != 0 {
        try {
            hr := ComCall(9, NotificationState["Manager"], "Ptr", NotificationState["Object"].Ptr)
            if hr != 0 {
                OutputDebug("UnregisterSessionNotification failed: " Format("0x{:08X}", hr & 0xFFFFFFFF))
            }
        }
    }

    NotificationState["Registered"] := false
    ResetNotificationState()
}

ResetNotificationState() {
    global NotificationState

    FreeNotificationCallbacks()
    NotificationState["VTable"] := 0
    NotificationState["Object"] := 0
    NotificationState["Device"] := 0
    NotificationState["Manager"] := 0
    NotificationState["Registered"] := false
    NotificationState["RefCount"] := 1
}

FreeNotificationCallbacks() {
    global NotificationState

    for address in [
        NotificationState["CallbackQI"],
        NotificationState["CallbackAddRef"],
        NotificationState["CallbackRelease"],
        NotificationState["CallbackCreated"]
    ] {
        if address {
            try CallbackFree(address)
        }
    }
    NotificationState["CallbackQI"] := 0
    NotificationState["CallbackAddRef"] := 0
    NotificationState["CallbackRelease"] := 0
    NotificationState["CallbackCreated"] := 0
}

GuidPointerToString(guidPtr) {
    buffer := Buffer(80, 0)
    result := DllCall("ole32\StringFromGUID2", "Ptr", guidPtr, "Ptr", buffer.Ptr, "Int", 40, "Int")
    if result <= 0 {
        return ""
    }
    return StrGet(buffer, "UTF-16")
}

Notification_QueryInterface(this, riid, ppvObject) {
    global IID_IUnknown, IID_IAudioSessionNotification

    if !ppvObject {
        return 0x80004003
    }
    NumPut("Ptr", 0, ppvObject, 0)
    if !riid {
        return 0x80004002
    }
    iidText := GuidPointerToString(riid)
    if StrLower(iidText) != StrLower(IID_IUnknown)
    && StrLower(iidText) != StrLower(IID_IAudioSessionNotification) {
        return 0x80004002
    }
    NumPut("Ptr", this, ppvObject, 0)
    Notification_AddRef(this)
    return 0
}

Notification_AddRef(this) {
    global NotificationState

    NotificationState["RefCount"] += 1
    return NotificationState["RefCount"]
}

Notification_Release(this) {
    global NotificationState

    if NotificationState["RefCount"] > 0 {
        NotificationState["RefCount"] -= 1
    }
    return NotificationState["RefCount"]
}

Notification_OnSessionCreated(this, newSessionPtr) {
    global PendingNotifiedSessions, NotificationProcessingScheduled, NotificationCallbackActive

    NotificationCallbackActive += 1
    try {
        if !newSessionPtr {
            return 0
        }
        sessionControl := ComValue(13, newSessionPtr, 1)

        if PendingNotifiedSessions.Length >= 100 {
            return 0
        }

        PendingNotifiedSessions.Push(sessionControl)
        if !NotificationProcessingScheduled {
            NotificationProcessingScheduled := true
            SetTimer(ProcessPendingNotifiedSessions, -1)
        }
    } finally {
        NotificationCallbackActive -= 1
    }
    return 0
}

ProcessPendingNotifiedSessions() {
    global PendingNotifiedSessions, NotificationProcessingScheduled, IsProcessingNotifications

    NotificationProcessingScheduled := false
    if IsProcessingNotifications {
        SetTimer(ProcessPendingNotifiedSessions, -50)
        return
    }
    IsProcessingNotifications := true
    try {
        loop Min(5, PendingNotifiedSessions.Length) {
            sessionControl := PendingNotifiedSessions.RemoveAt(1)
            ProcessNotifiedSession(sessionControl)
        }
        if PendingNotifiedSessions.Length {
            SetTimer(ProcessPendingNotifiedSessions, -50)
        }
    } finally {
        IsProcessingNotifications := false
    }
}

ProcessNotifiedSession(sessionControl) {
    global AudioSessions, KnownSessions, IID_IAudioSessionControl2

    try {
        control2 := ComObjQuery(sessionControl, IID_IAudioSessionControl2)
        if !control2 {
            return
        }
        hr := ComCall(14, control2, "UInt*", &pid := 0)
        if hr != 0 || pid = 0 {
            return
        }
        try {
            processName := StrLower(ProcessGetName(pid))
        } catch {
            processName := ""
        }
        if processName = "" {
            return
        }
        instanceId := GetSessionInstanceIdentifier(control2)
        key := instanceId != "" ? instanceId : pid ":" processName
        if KnownSessions.Has(key) {
            return
        }
        sessionData := Map(
            "Pid", pid,
            "ProcessName", processName,
            "InstanceId", instanceId,
            "Interface", sessionControl
        )
        AudioSessions[key] := sessionData
        KnownSessions[key] := sessionData
        ApplyInitialVolume(processName, sessionControl, key)
    } catch Error as err {
        OutputDebug("ProcessNotifiedSession error: " err.Message)
    }
}

ReRegisterAudioNotifications() {
    global NotificationState
    if NotificationState["Registered"] {
        UnregisterAudioSessionNotifications()
    }
    RegisterAudioSessionNotifications()
}

; =========================================================
; OSD
; =========================================================

CreateVolumeOSD() {
    global VolumeGui, VolumeBgGui, VolumeBar, VolumeLabel, OSDWidth, OSDHeight, OSDBarColor, OSDBackgroundColor,
        OSDFont, OSDFontSize, OSDOpacity, OSDTransparentKeyColor

    VolumeBgGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000", "Audio OSD Background")
    VolumeBgGui.BackColor := OSDBackgroundColor
    VolumeBgGui.MarginX := 0
    VolumeBgGui.MarginY := 0
    VolumeGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000", "Audio OSD Foreground")
    VolumeGui.BackColor := OSDTransparentKeyColor
    VolumeGui.MarginX := 0
    VolumeGui.MarginY := 0
    VolumeBar := VolumeGui.Add("Text", "x0 y0 w1 h" OSDHeight " Background" OSDBarColor)
    VolumeBar.Visible := false
    VolumeGui.SetFont("s" OSDFontSize " Bold", OSDFont)
    textHeight := OSDFontSize + 12
    textY := Round((OSDHeight - textHeight) / 2, 0)
    VolumeLabel := VolumeGui.Add("Text", "x0 y" textY " w" OSDWidth " h" textHeight " Center cEBEAEA BackgroundTrans",
        "50%")
    VolumeBgGui.Show("Hide w" OSDWidth " h" OSDHeight)
    VolumeGui.Show("Hide w" OSDWidth " h" OSDHeight)
    WinSetRegion("0-0 w" OSDWidth " h" OSDHeight " r" OSDHeight "-" OSDHeight, VolumeBgGui)
    WinSetRegion("0-0 w" OSDWidth " h" OSDHeight " r" OSDHeight "-" OSDHeight, VolumeGui)
    WinSetTransColor(OSDTransparentKeyColor, VolumeGui)
    WinSetTransparent(OSDOpacity, VolumeBgGui)
}

ShowVolumeOSD(source, volume) {
    global VolumeGui, VolumeBgGui, VolumeBar, VolumeLabel, OSDVisible, OSDTime, OSDOpacity, OSDWidth, OSDHeight,
        OSDYOffset

    volume := Max(0, Min(100, Round(volume)))
    barWidth := Round(OSDWidth * volume / 100)
    VolumeBar.Opt("-Redraw")
    if barWidth <= 0 {
        VolumeBar.Visible := false
        VolumeBar.Move(0, 0, 1, OSDHeight)
    } else {
        VolumeBar.Visible := true
        VolumeBar.Move(0, 0, barWidth, OSDHeight)
    }
    VolumeBar.Opt("+Redraw")
    VolumeLabel.Text := volume "%"

    monitorNum := MonitorGetPrimary()
    MonitorGet(monitorNum, &left, &top, &right, &bottom)

    x := left + ((right - left - OSDWidth) // 2)
    y := bottom - OSDYOffset - OSDHeight

    SetTimer(HideVolumeOSD, 0)
    wasVisible := OSDVisible
    if !wasVisible {
        WinSetTransparent(OSDOpacity, VolumeBgGui)
    }
    VolumeBgGui.Show(Format("NA x{} y{} w{} h{}", x, y, OSDWidth, OSDHeight))
    VolumeGui.Show(Format("NA x{} y{} w{} h{}", x, y, OSDWidth, OSDHeight))
    OSDVisible := true
    if OSDTime > 0 {
        SetTimer(HideVolumeOSD, -OSDTime)
    }
}

HideVolumeOSD() {
    global VolumeGui, VolumeBgGui, OSDVisible

    if OSDVisible {
        VolumeGui.Hide()
        VolumeBgGui.Hide()
        OSDVisible := false
    }
}

; =========================================================
; HOTKEYS
; =========================================================

ValidateHotkeys() {
    global Hotkeys

    seen := Map()

    for action, key in Hotkeys {
        normalized := StrLower(Trim(key))

        if normalized = "" || normalized = "none" {
            continue
        }

        if seen.Has(normalized) {
            TrayTip(
                "Audio Core",
                "Duplicate hotkey:`n" action " conflicts with " seen[normalized],
                5
            )
        } else {
            seen[normalized] := action
        }
    }
}

RegisterHotkeys() {
    global Hotkeys, Step, GroupOrder, RegisteredHotkeys

    UnregisterHotkeys()
    RegisterHotkeyInternal(Hotkeys["SystemUp"], "system", Step)
    RegisterHotkeyInternal(Hotkeys["SystemDown"], "system", -Step)

    for index, group in GroupOrder {
        upKey := Hotkeys.Has("Group" index "Up")
            ? Hotkeys["Group" index "Up"]
            : "None"

        downKey := Hotkeys.Has("Group" index "Down")
            ? Hotkeys["Group" index "Down"]
            : "None"

        RegisterHotkeyInternal(upKey, group, Step)
        RegisterHotkeyInternal(downKey, group, -Step)
    }
}

RegisterHotkeyInternal(keyName, target, amount) {
    global RegisteredHotkeys

    if Trim(keyName) = "" || StrLower(Trim(keyName)) = "none" {
        return
    }
    try {
        callback := target = "system"
            ? (*) => QueueSystemVolume(amount)
                : (*) => QueueGroupChange(target, amount)

        Hotkey(keyName, callback)
        RegisteredHotkeys[keyName] := true
    } catch Error as err {
        TrayTip("Error with hotkey: " keyName, err.Message, 5)
    }
}

UnregisterHotkeys() {
    global RegisteredHotkeys

    for keyName in RegisteredHotkeys {
        try Hotkey(keyName, "Off")
    }

    RegisteredHotkeys.Clear()
}
