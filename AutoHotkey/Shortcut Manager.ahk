#Requires AutoHotkey v2.0
#SingleInstance Force

; Remap "Ctrl+[" to "Esc".
^[:: Send("{Esc}")

; If LibreWolf is focused.
#HotIf WinActive("ahk_exe librewolf.exe")
    ; Enable ergonomic tab navigation.
    ^+l:: Send("^{Tab}")
    ^+h:: Send("^+{Tab}")

    ; Remap "Ctrl+[" to a triple "Esc".
    ; Needed to escape the URL bar.
    ^[:: Send("{Esc 3}")
#HotIf

; If Obsidian is focused.
#HotIf WinActive("ahk_exe Obsidian.exe")
    ; Remap "Ctrl+[" to a double "Esc".
    ; Needed to escape Wikilinks.
    ^[:: Send("{Esc 2}")
#HotIf

GenerateLowercaseUUID() {
    static buf := Buffer(16, 0), str := Buffer(78)
    if DllCall("ole32\CoCreateGuid", "ptr", buf.Ptr, "int") != 0
        return ""
    if DllCall("ole32\StringFromGUID2", "ptr", buf.Ptr, "ptr", str.Ptr, "int", 39, "int") < 39
        return ""
    return StrLower(SubStr(StrGet(str, "UTF-16"), 2, 36))
}

; Map "Alt+U" to insert a random lowercase UUID.
!u:: SendText GenerateLowercaseUUID()