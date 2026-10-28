; PPTGlass.ahk — PPT沙漏（PPTGlass）现代版 v1.1.8
; 功能：PPT/WPS 放映自动开始/停止倒计时、手动计时、预铃（声音+弹窗）、限时到点
; （声音+超时正计时+闪红）、暂停/继续、音量调节（设置窗内，退出还原）、自动隐藏、
; 开机自启、ini 记忆（exe 同目录）、托盘/右键菜单。
; 风格：冰白 + 蓝紫 + 琥珀 统一设计（banner 同款）：计时卡与关于面板全部 GDI+ 自绘
; （圆角卡片、渐变数字、沙漏插画），设置窗为浅色主题；到点/预铃弹窗位于屏幕顶部、
; 与计时卡同高居中。
;@Ahk2Exe-SetName PPT沙漏 pptglass
;@Ahk2Exe-SetVersion 1.1.0
;@Ahk2Exe-SetDescription PPT沙漏
;@Ahk2Exe-SetCopyright Copyright (c) 2026 dataclaw2026
; --- embedded resources (声音文件：优先 exe 同目录，写不进去则退回 TEMP) ---
FileInstall, alarm1.wav, %A_ScriptDir%\pptglass_pre.wav
FileInstall, alarm2.wav, %A_ScriptDir%\pptglass_end.wav
FileInstall, pptglass_gold.ico, %A_Temp%\pptglass_gold.ico, 1
preSnd := A_ScriptDir "\pptglass_pre.wav"
endSnd := A_ScriptDir "\pptglass_end.wav"
; 本工具链缺 FileExist 命令，用 FileGetTime 等价实现
PtFileExists(f) {
    t := ""
    FileGetTime, t, %f%
    return (t != "")
}

; 任意绝对路径转相对 exe 目录（本目录内用 .\ 前缀，目录外用 ..\ 上跳）；空/不同盘符/UNC 原样保留
RelPath(p) {
    global
    if (p = "")
        return p
    p := StrReplace(p, "/", "\")
    if (SubStr(p, 1, 2) = "\\")
        return p
    if (StrLen(p) > 1 && SubStr(p, 2, 1) = ":" && SubStr(p, 1, 1) != SubStr(A_ScriptDir, 1, 1))
        return p
    base := A_ScriptDir
    if (InStr(p, base "\") = 1)
        return ".\" SubStr(p, StrLen(base) + 2)
    bp := StrSplit(base, "\")
    pp := StrSplit(p, "\")
    n := 1
    while (n <= bp.Length() && n <= pp.Length() && bp[n] = pp[n])
        n++
    rel := ""
    Loop, % bp.Length() - (n - 1)
        rel .= "..\"
    start := n
    while (start <= pp.Length())
    {
        rel .= pp[start]
        if (start < pp.Length())
            rel .= "\"
        start++
    }
    return rel
}

; 相对路径按 exe 目录解析为绝对并规范化（处理 .\ 与 ..\）；已是绝对（盘符/UNC）则原样返回
ResolvePath(p) {
    global
    if (p = "")
        return p
    p := StrReplace(p, "/", "\")
    if (InStr(p, ":\") = 2 || SubStr(p, 1, 1) = "\")
        return p
    full := A_ScriptDir "\" p
    parts := []
    Loop, parse, full, \
    {
        if (A_LoopField = "" || A_LoopField = ".")
            continue
        if (A_LoopField = "..")
        {
            if (parts.Length() > 1)
                parts.RemoveAt(parts.Length())
            continue
        }
        parts.Push(A_LoopField)
    }
    out := parts[1]
    Loop, % parts.Length() - 1
        out .= "\" parts[A_Index + 1]
    return out
}
if (!PtFileExists(preSnd))
{
    FileInstall, alarm1.wav, %A_Temp%\pptglass_alarm1.wav, 1
    preSnd := A_Temp "\pptglass_alarm1.wav"
}
if (!PtFileExists(endSnd))
{
    FileInstall, alarm2.wav, %A_Temp%\pptglass_alarm2.wav, 1
    endSnd := A_Temp "\pptglass_alarm2.wav"
}
#SingleInstance force
#NoEnv
SetBatchLines, -1
DllCall("SetProcessDPIAware")

ptIni := A_ScriptDir "\PPTGlass.ini"
IniRead, ptHour, %ptIni%, Main, LimitHour, 0
IniRead, ptMin, %ptIni%, Main, LimitMin, 10
IniRead, ptPre, %ptIni%, Main, PreAlarm, 2
IniRead, ptOpacity, %ptIni%, Main, Opacity, 215
IniRead, ptPreFile, %ptIni%, Main, PreAlarmFile, %preSnd%
IniRead, ptEndFile, %ptIni%, Main, EndAlarmFile, %endSnd%
ptPreFile := ResolvePath(ptPreFile)
ptEndFile := ResolvePath(ptEndFile)
IniRead, ptMsg, %ptIni%, Main, TimeoutMsg, 时间到！请结束演讲
IniRead, ptAutoHide, %ptIni%, Main, AutoHide, 0
IniRead, ptAutoRun, %ptIni%, Main, AutoRun, 0
IniRead, ptShowClasses, %ptIni%, Main, showWindowClasses, screenClass
IniRead, ptShowProcs, %ptIni%, Main, showProcesses, wpp.exe`,wps.exe
IniRead, startKey, %ptIni%, shortcuts, startKey, F12
IniRead, stopKey, %ptIni%, shortcuts, stopKey, ^F12
IniRead, quitKey, %ptIni%, shortcuts, quitKey, #ESC

ptLimit := ptHour*60 + ptMin
if (ptLimit < 1)
    ptLimit := 1
if (ptLimit > 99)
    ptLimit := 99
ptRemain := ptLimit * 60
ptState := "idle"
ptShowOn := false
ptBlink := false
ptHover := false
ptDragging := false
ptDownActive := 0
ptDownSX := 0
ptDownSY := 0

; ---------- GDI+ init ----------
VarSetCapacity(gsi, 24, 0)
NumPut(1, gsi, 0, "uint")
if (DllCall("gdiplus\GdiplusStartup", "uptr*", gToken := 0, "ptr", &gsi, "ptr", 0))
    ExitApp

; ---------- card + about windows ----------
DetectHiddenWindows, On
ptS := A_ScreenDPI / 96.0
CW := Round(200 * ptS)
CH := Round(78 * ptS)
CWu := Round(CW / ptS)
CHu := Round(CH / ptS)
AW := Round(320 * ptS)
AH := Round(150 * ptS)
AWu := 320
AHu := 150
Gui, Main:New, +HWNDhMain +AlwaysOnTop +ToolWindow -Caption +LastFound, PPT沙漏-计时
Gui, Main:Color, 000000
Gui, Main:Add, Pic, x0 y0 w%CWu% h%CHu% hwndhPic +0xE Background000000
Gui, Main:Show, Hide, PPT沙漏-计时
DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", CW, "int", CH, "int", 0, "int", 0x26200A, "ptr", 0, "ptr*", gBmp := 0)
DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", gBmp, "ptr*", gGfx := 0)
DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gGfx, "int", 4)
DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", gGfx, "int", 4)
ptVer := "1.1.8"  ; 每次发布 +1：个位先加、满 10 进位（如 1.0.9 -> 1.1.0）
; 图标对比版自标识：exe 名为 PPTGlass_iconN.exe 时，各处显示"·图标N"
ptIconNo := ""
RegExMatch(A_ScriptName, "i)PPTGlass_icon(\d+)\.exe", m)
if (m1 != "")
    ptIconNo := m1
ptIconTag := (ptIconNo != "") ? (" ·图标" ptIconNo) : ""
Gui, Abt:New, +HWNDhAbt +AlwaysOnTop -MinimizeBox -MaximizeBox, PPT沙漏-关于
Gui, Abt:Font, s12 Bold, Microsoft YaHei UI
Gui, Abt:Add, Picture, x16 y18 w56 h56, %A_Temp%\pptglass_gold.ico
Gui, Abt:Font, s16 Bold, Microsoft YaHei UI
Gui, Abt:Add, Text, x86 y12 w48 h32, PPT
Gui, Abt:Font, s16 Bold cB8860B, Microsoft YaHei UI
Gui, Abt:Add, Text, x136 y12 h32, Glass
Gui, Abt:Font, s10 Norm c808080, Microsoft YaHei UI
Gui, Abt:Add, Text, x198 y24 h22, v%ptVer%%ptIconTag%
Gui, Abt:Font, s9 Bold, Microsoft YaHei UI
Gui, Abt:Add, Text, x86 y60 w250, PPT 沙漏 · 放映倒计时器
Gui, Abt:Add, Progress, x86 y50 w260 h2 BackgroundE0E0E0
Gui, Abt:Font, s9 Norm c585858, Microsoft YaHei UI
Gui, Abt:Add, Text, x16 y86 w330, 双击计时条：开始 / 停止，并联动 PPT / WPS 放映
Gui, Abt:Add, Text, x16 y106 w330, 默认快捷键：F12 开始 · Ctrl+F12 停止 · Win+Esc 退出
Gui, Abt:Font, s8 Norm c808080, Microsoft YaHei UI
Gui, Abt:Add, Text, x16 y142 w330 Center, Copyright © 2026 dataclaw2026 · MIT 开源许可
Gui, Abt:Font, s8 Norm c0563C1 underline, Microsoft YaHei UI
Gui, Abt:Add, Text, x16 y158 w334 Center hwndhAbtLink, https://github.com/dataclaw2026/PPTGlass
Gui, Abt:Font, s8 Norm c808080, Microsoft YaHei UI
Gui, Abt:Add, Text, x16 y176 w334 Center vAbtRemote, 远程版本：检查中…
Gui, Abt:Show, Hide

; fonts: 数字/标题用微软雅黑粗体（缺则退回 Segoe UI）
DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Microsoft YaHei UI", "ptr", 0, "ptr*", famNum := 0)
if (famNum = 0)
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Segoe UI", "ptr", 0, "ptr*", famNum)
DllCall("gdiplus\GdipCreateFont", "ptr", famNum, "float", Round(52 * ptS), "int", 1, "int", 2, "ptr*", fNum := 0)
DllCall("gdiplus\GdipCreateFont", "ptr", famNum, "float", Round(44 * ptS), "int", 1, "int", 2, "ptr*", fNumSm := 0)
DllCall("gdiplus\GdipCreateFont", "ptr", famNum, "float", Round(12 * ptS), "int", 1, "int", 2, "ptr*", fBtn := 0)
DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr*", sfC := 0)
DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", sfC, "int", 1)
DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", sfC, "int", 1)

; 悬停按钮：右缘纵向三排，等间距——上 ✕ 关闭 / 中 ⚙ 配置 / 下 ℹ 关于
bh := Round(18 * ptS)
g := Round((CH - 3 * bh) / 4)
btnExitT := g, btnExitB := g + bh
btnSetT := 2 * g + bh, btnSetB := 2 * g + 2 * bh
btnAbtT := 3 * g + 2 * bh, btnAbtB := 3 * g + 3 * bh
btnXL := CW - Round(28 * ptS), btnXR := CW - Round(6 * ptS)

Gosub BuildMenu
OnMessage(0x201, "OnLDown")
OnMessage(0x203, "OnLDbl")
OnMessage(0x202, "OnLUp")
OnMessage(0x204, "OnRDown")
OnMessage(0x232, "OnMoveEnd")
OnMessage(0x439, "OnProbe")
OnProbe(w, l, m, hwnd) {
    FileAppend, PROBE w=%w% hwnd=%hwnd%`n, %A_ScriptDir%\dbg_tr.txt
}

xpos := A_ScreenWidth - CW
ptPosY := Round(32 * ptS)
Gui, Main:Show, x%xpos% y%ptPosY% w%CWu% h%CHu% NoActivate, PPT沙漏-计时
WinMove, ahk_id %hMain%,, %xpos%, %ptPosY%, %CW%, %CH%
WinGetPos, gx, gy, gw, gh, ahk_id %hMain%
if (gx + gw > A_ScreenWidth)
{
    nx := A_ScreenWidth - gw - Round(8 * ptS)
    if (nx < 0)
        nx := 0
    WinMove, ahk_id %hMain%,, %nx%, %gy%
    IniWrite, %nx%, %ptIni%, Main, PosX
}
RadC := Round(12 * ptS)
WinSet, Region, 0-0 W%CW% H%CH% R%RadC%-%RadC%, ahk_id %hMain%
WinSet, Transparent, %ptOpacity%, ahk_id %hMain%
WinSet, ExStyle, +0x20, ahk_id %hMain%
if (ptAutoHide = 1)
    Gui, Main:Hide
IniRead, ptDbgTrace, %ptIni%, Debug, Trace, 0
Gosub DrawCard
TrayTip, PPT沙漏-已启动, 双击时间条开始计时, 3, 1
SetTimer, PollShow, 250
SetTimer, HoverWatch, 120
Hotkey, %startKey%, DoStart
Hotkey, %stopKey%, DoStop
Hotkey, %quitKey%, DoQuit
; 临时调试开关（测试用，正式环境不写该段）
IniRead, ptDbgOpen, %ptIni%, Debug, Open, 0
IniRead, ptDbgPopup, %ptIni%, Debug, Popup, 0
IniRead, ptDbgTrace, %ptIni%, Debug, Trace, 0
IniRead, ptDbgAbt, %ptIni%, Debug, Abt, 0
IniRead, ptDbgNoSlide, %ptIni%, Debug, NoSlide, 0
if (ptDbgOpen = 1)
    SetTimer, DbgOpen, -1500
if (ptDbgPopup = 1)
    SetTimer, DbgOverPop, -2200
if (ptDbgPopup = 2)
    SetTimer, DbgPrePop, -2200
if (ptDbgAbt = 1)
    SetTimer, DoAbtClick, -1800
IniRead, ptUpdateUrl, %ptIni%, Main, UpdateUrl, NONE
if (ptUpdateUrl = "NONE")
    ptUpdateUrl := ""
ptRemoteVer := ""
ptUpdShown := 0
ptUpdFromMenu := 0
ptUpdBusy := 0
SetTimer, CheckUpdAsync, -3000
return

; ================= drawing helpers =================
MakeLineBrush(x1, y1, x2, y2, c1, c2) {
    VarSetCapacity(pt1, 8, 0), NumPut(x1 + 0.0, pt1, 0, "float"), NumPut(y1 + 0.0, pt1, 4, "float")
    VarSetCapacity(pt2, 8, 0), NumPut(x2 + 0.0, pt2, 0, "float"), NumPut(y2 + 0.0, pt2, 4, "float")
    DllCall("gdiplus\GdipCreateLineBrush", "ptr", &pt1, "ptr", &pt2, "uint", c1, "uint", c2, "int", 1, "ptr*", br := 0)
    return br
}

RRectPath(x, y, w, h, r) {
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", p := 0)
    DllCall("gdiplus\GdipAddPathArcI", "ptr", p, "int", x, "int", y, "int", r*2, "int", r*2, "float", 180, "float", 90)
    DllCall("gdiplus\GdipAddPathArcI", "ptr", p, "int", x+w-r*2, "int", y, "int", r*2, "int", r*2, "float", 270, "float", 90)
    DllCall("gdiplus\GdipAddPathArcI", "ptr", p, "int", x+w-r*2, "int", y+h-r*2, "int", r*2, "int", r*2, "float", 0, "float", 90)
    DllCall("gdiplus\GdipAddPathArcI", "ptr", p, "int", x, "int", y+h-r*2, "int", r*2, "int", r*2, "float", 90, "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", p)
    return p
}

DrawCard:

if (ptDbgTrace)
    FileAppend, DC0 enter`n, %A_ScriptDir%\dbg_tr.txt
ptPreHit := (ptState = "run" && ptPre > 0 && ptRemain <= ptPre*60)
DllCall("gdiplus\GdipGraphicsClear", "ptr", gGfx, "uint", 0xFF000000)
path := RRectPath(1, 1, CW - 2, CH - 2, Round(12 * ptS))
br := MakeLineBrush(0, 0, 0, CH, 0xFF0F1115, 0xFF1A1D26)
DllCall("gdiplus\GdipFillPath", "ptr", gGfx, "ptr", br, "ptr", path)
DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
pn := 0
DllCall("gdiplus\GdipCreatePen1", "uint", 0xFF2E3340, "float", 1.0 * ptS, "int", 2, "ptr*", pn := 0)
DllCall("gdiplus\GdipDrawPath", "ptr", gGfx, "ptr", pn, "ptr", path)
DllCall("gdiplus\GdipDeletePen", "ptr", pn)
DllCall("gdiplus\GdipDeletePath", "ptr", path)
led := (ptState = "over") ? FormatLed(ptOver0) : FormatLed(ptRemain)
if (ptDbgTrace)
    FileAppend, DC2 led=%led% state=%ptState%`n, %A_ScriptDir%\dbg_tr.txt
font := fNum
numH := Round(56 * ptS)
rcY := (CH - numH) / 2 - 3 * ptS
if (ptState = "over")
{
    c1 := ptBlink ? 0xFFFF5252 : 0xFFFF8A80
    c2 := c1
    barC1 := 0xFFFF5252, barC2 := 0xFFE2401A
}
else if (ptState = "pause")
{
    c1 := 0xFF9AA7C7, c2 := 0xFF6B7BA0
    barC1 := 0xFF9AA7C7, barC2 := 0xFF6B7BA0
}
else if (ptPreHit)
{
    c1 := 0xFFFFE082, c2 := 0xFFFFB300
    barC1 := 0xFFFFC44E, barC2 := 0xFFF09200
}
else
{
    c1 := 0xFFFFD75E, c2 := 0xFFF5A623
    barC1 := 0xFFFFA327, barC2 := 0xFFED7A00
}
VarSetCapacity(rcL, 16, 0)
NumPut(0.0, rcL, 0, "float"), NumPut(rcY + 0.0, rcL, 4, "float")
NumPut(CW + 0.0, rcL, 8, "float"), NumPut(numH + 0.0, rcL, 12, "float")

brNum := MakeLineBrush(0, rcY, 0, rcY + numH, c1, c2)
if (ptDbgTrace)
    FileAppend, DCNUM brNum=%brNum% rcY=%rcY% numH=%numH% c1=%c1% led=%led%`n, %A_ScriptDir%\dbg_tr.txt
DllCall("gdiplus\GdipDrawString", "ptr", gGfx, "wstr", led, "int", -1, "ptr", font, "ptr", &rcL, "ptr", sfC, "ptr", brNum)
DllCall("gdiplus\GdipDeleteBrush", "ptr", brNum)
barW := Round(120 * ptS)
uh := Round(5 * ptS)
barX := (CW - barW) / 2
barY := CH - Round(10 * ptS)
total := ptLimit * 60
if (ptState = "over")
    prog := (total > 0) ? Mod(ptOver0, total) / total : 0
else
    prog := (total > 0) ? ptRemain / total : 0
if (prog < 0)
    prog := 0
if (prog > 1)
    prog := 1
; 底轨（未用进度显示为暗色轨道）
trkPath := RRectPath(barX, barY, barW, uh, Round(2.5 * ptS))
trkBrush := MakeLineBrush(barX, barY, barX + barW, barY, 0xFF2E3340, 0xFF2E3340)
DllCall("gdiplus\GdipFillPath", "ptr", gGfx, "ptr", trkBrush, "ptr", trkPath)
DllCall("gdiplus\GdipDeleteBrush", "ptr", trkBrush)
DllCall("gdiplus\GdipDeletePath", "ptr", trkPath)
uw := Round(barW * prog)
if (uw > 0)
{
    upx := RRectPath(barX, barY, uw, uh, Round(2.5 * ptS))
    barBrush := MakeLineBrush(barX, barY, barX + uw, barY, barC1, barC2)
    DllCall("gdiplus\GdipFillPath", "ptr", gGfx, "ptr", barBrush, "ptr", upx)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", barBrush)
    DllCall("gdiplus\GdipDeletePath", "ptr", upx)
}
if (ptHover)
{
    VarSetCapacity(rcb0, 16, 0)
    NumPut(btnXL + 0.0, rcb0, 0, "float"), NumPut(btnAbtT + 0.0, rcb0, 4, "float")
    NumPut((btnXR - btnXL) + 0.0, rcb0, 8, "float"), NumPut((btnAbtB - btnAbtT) + 0.0, rcb0, 12, "float")
    VarSetCapacity(rcb1, 16, 0)
    NumPut(btnXL + 0.0, rcb1, 0, "float"), NumPut(btnSetT + 0.0, rcb1, 4, "float")
    NumPut((btnXR - btnXL) + 0.0, rcb1, 8, "float"), NumPut((btnSetB - btnSetT) + 0.0, rcb1, 12, "float")
    VarSetCapacity(rcb2, 16, 0)
    NumPut(btnXL + 0.0, rcb2, 0, "float"), NumPut(btnExitT + 0.0, rcb2, 4, "float")
    NumPut((btnXR - btnXL) + 0.0, rcb2, 8, "float"), NumPut((btnExitB - btnExitT) + 0.0, rcb2, 12, "float")
    br := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", 0xFFFFC44E, "ptr*", br := 0)
    DllCall("gdiplus\GdipDrawString", "ptr", gGfx, "wstr", "i", "int", -1, "ptr", fBtn, "ptr", &rcb0, "ptr", sfC, "ptr", br)
    DllCall("gdiplus\GdipDrawString", "ptr", gGfx, "wstr", "⚙", "int", -1, "ptr", fBtn, "ptr", &rcb1, "ptr", sfC, "ptr", br)
    DllCall("gdiplus\GdipDrawString", "ptr", gGfx, "wstr", "✕", "int", -1, "ptr", fBtn, "ptr", &rcb2, "ptr", sfC, "ptr", br)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
}
rcH := DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", gBmp, "ptr*", hbm := 0, "uint", 0xFFFFFFFF)
if (ptDbgTrace)
{
    VarSetCapacity(bi, 40, 0)
    NumPut(40, bi, 0, "int"), NumPut(CW, bi, 4, "int"), NumPut(-CH, bi, 8, "int")
    NumPut(1, bi, 12, "short"), NumPut(32, bi, 14, "short")
    hScr := DllCall("GetDC", "ptr", 0, "ptr")
    VarSetCapacity(px, CW * CH * 4, 0)
    DllCall("gdi32\GetDIBits", "ptr", hScr, "ptr", hbm, "int", 0, "int", CH, "ptr", &px, "ptr", &bi, "int", 0)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hScr)
    hF := DllCall("CreateFileW", "wstr", A_ScriptDir "\dbg_card.raw", "uint", 0x40000000, "uint", 0, "ptr", 0, "uint", 2, "uint", 0, "ptr")
    DllCall("WriteFile", "ptr", hF, "ptr", &px, "uint", CW * CH * 4, "ptr*", 0, "ptr", 0)
    DllCall("CloseHandle", "ptr", hF, "ptr")
}
oldImg := DllCall("SendMessageW", "ptr", hPic, "uint", 0x0172, "ptr", 0, "ptr", hbm, "ptr")
if (oldImg)
    DllCall("DeleteObject", "ptr", oldImg)
if (ptDbgTrace)
    FileAppend, DC led=%led% remain=%ptRemain% state=%ptState%`n, %A_ScriptDir%\dbg_tr.txt
WinSetTitle, ahk_id %hMain%,, PPT沙漏-计时 %led%%ptIconTag%
return

FormatLed(sec) {
    return Format("{:02d}:{:02d}", sec // 60, Mod(sec, 60))
}

; ================= about panel =================
OpenAbout:
abx := Round((A_ScreenWidth - Round(366 * ptS)) / 2)
aby := Round((A_ScreenHeight - Round(204 * ptS)) / 2)
if (abx < 8)
    abx := 8
Gui, Abt:Show, x%abx% y%aby% w366 h204, PPT沙漏-关于
return
AbtGuiClose:
AbtGuiEscape:
Gui, Abt:Hide
return
DoAbtClose:
Gui, Abt:Hide
return


; ================= mouse =================
OnLDown(w, l, msg, hwnd) {
    global
    if (hwnd = hAbtLink)
    {
        Run, https://github.com/dataclaw2026/PPTGlass
        return
    }
    if (hwnd = hPop)
    {
        if (ptPopKind = "upd")
            Run, https://github.com/dataclaw2026/PPTGlass/releases
        Gosub ClosePop
        return
    }
    x := l & 0xFFFF, y := l >> 16
    if (ptDbgTrace)
        FileAppend, LD hwnd=%hwnd% hMain=%hMain% hPic=%hPic% x=%x% y=%y% ptHover=%ptHover%`n, %A_ScriptDir%\dbg_tr.txt
    if (hwnd = hMain || hwnd = hPic)
    {
        if (ptHover && x >= btnXL && x <= btnXR && y >= btnAbtT && y <= btnAbtB)
            SetTimer, DoAbtClick, -1
        else if (ptHover && x >= btnXL && x <= btnXR && y >= btnSetT && y <= btnSetB)
            SetTimer, DoSetClick, -1
        else if (ptHover && x >= btnXL && x <= btnXR && y >= btnExitT && y <= btnExitB)
            SetTimer, DoExitClick, -1
    else
    {
        CoordMode, Mouse, Screen
        MouseGetPos, ptDownSX, ptDownSY
        ptDownActive := 1
    }
    return
}
}
DoSetClick:
Gosub OpenSet
return
DoExitClick:
Gosub DoQuit
return
DoAbtClick:
if (ptDbgTrace)
    FileAppend, DOABTCLICK`n, %A_ScriptDir%\dbg_tr.txt
Gosub OpenAbout
return
OnLDbl(w, l, msg, hwnd) {
    global
    x := l & 0xFFFF, y := l >> 16
    if (ptDbgTrace)
        FileAppend, LDbl hwnd=%hwnd% x=%x% y=%y%`n, %A_ScriptDir%\dbg_tr.txt
    if (hwnd = hMain || hwnd = hPic)
    {
        if (x >= btnXL - 6 && x <= btnXR + 6 && y >= btnExitT - 6 && y <= btnAbtB + 6)
            return
        if (ptState = "idle")
        {
            Gosub DoStart
            if (!IsSlideShow() && ptDbgNoSlide != 1)
                Gosub StartSlideshow
        }
        else if (ptState = "pause")
            Gosub MenuPause
        else
            Gosub DoStop
        return
    }
}
OnLUp(w, l, msg, hwnd) {
    global
    if (hwnd = hMain || hwnd = hPic)
        ptDownActive := 0
}
OnRDown(w, l, msg, hwnd) {
    global
    if (hwnd != hMain && hwnd != hPic)
        return
    Menu, PtMenu, Show
}
GearClick:
Gosub OpenSet
return
OnMoveEnd(w, l, m, hwnd) {
    global
    if (ptDbgTrace)
        FileAppend, MOVEEND`n, %A_ScriptDir%\dbg_tr.txt
    ptDragging := 0
}

; ================= menu/tray =================
BuildMenu:
Menu, PtMenu, Add, 启动计时, MenuStart
Menu, PtMenu, Add, 停止计时, MenuStop
Menu, PtMenu, Add, 暂停计时, MenuPause
Menu, PtMenu, Add
Menu, PtMenu, Add, 设置…, OpenSet
Menu, PtMenu, Add, 开机自启, MenuAutoRun
Menu, PtMenu, % (ptAutoRun = 1) ? "Check" : "UnCheck", 开机自启
Menu, PtMenu, Add, 关于…, OpenAbout
Menu, PtMenu, Add, 检查更新, CheckUpdNow
Menu, PtMenu, Add, 退出, DoQuit
Menu, Tray, NoStandard
Menu, Tray, Add, 显示主界面, MenuShow
Menu, Tray, Add
Menu, Tray, Add, 启动计时, MenuStart
Menu, Tray, Add, 停止计时, MenuStop
Menu, Tray, Add, 暂停计时, MenuPause
Menu, Tray, Add
Menu, Tray, Add, 设置…, OpenSet
Menu, Tray, Add, 关于…, OpenAbout
Menu, Tray, Add, 检查更新, CheckUpdNow
Menu, Tray, Add, 退出, DoQuit
Menu, Tray, Default, 显示主界面
Menu, Tray, Tip, PPT沙漏 pptglass%ptIconTag%
return

; ================= slideshow detect =================
PollShow:
show := IsSlideShow()
if (show && !ptShowOn)
{
    ptShowOn := true
    if (ptAutoHide = 1)
        Gui, Main:Show, NoActivate
    if (ptState = "idle")
        Gosub DoStart
}
else if (!show && ptShowOn)
{
    ptShowOn := false
    if (ptState != "idle")
        Gosub DoStop
    if (ptAutoHide = 1)
        Gui, Main:Hide
}
return

IsSlideShow() {
    global ptShowClasses, ptShowProcs
    Loop, parse, ptShowClasses, `,
    {
        cls := Trim(A_LoopField)
        if (cls = "")
            continue
        IfWinExist, % "ahk_class " cls
            return true
    }
    Loop, parse, ptShowProcs, `,
    {
        proc := Trim(A_LoopField)
        if (proc = "")
            continue
        WinGet, wl, List, % "ahk_exe " proc
        Loop, %wl%
        {
            wid := wl%A_Index%
            WinGet, st, Style, ahk_id %wid%
            WinGet, ex, ExStyle, ahk_id %wid%
            WinGetPos,,, w, h, ahk_id %wid%
            if ((st & 0x10000000) && (ex & 0x8) && w >= A_ScreenWidth*0.9 && h >= A_ScreenHeight*0.9)
                return true
        }
    }
    return false
}

; ================= timer =================
DoStart:
if (ptState = "run")
    return
if (ptState = "idle")
{
    ptPrealed := 0
    ptRemain := ptLimit * 60
}
ptState := "run"
SetTimer, Tick, 1000
Gosub Tick
return

DoStop:
SetTimer, Tick, Off
ptState := "idle"
ptRemain := ptLimit * 60
Gui, Pop:Destroy
SetTimer, ClosePop, Off
Gosub DrawCard
return

MenuStart:
Gosub DoStart
return
MenuStop:
Gosub DoStop
return
MenuShow:
Gui, Main:Show
return
MenuPause:
if (ptState = "pause")
{
    ptState := (ptRemain = 0) ? "over" : "run"
    SetTimer, Tick, 1000
    Menu, PtMenu, Rename, 继续计时, 暂停计时
    Menu, Tray, Rename, 继续计时, 暂停计时
}
else if (ptState = "run" || ptState = "over")
{
    ptState := "pause"
    SetTimer, Tick, Off
    Menu, PtMenu, Rename, 暂停计时, 继续计时
    Menu, Tray, Rename, 暂停计时, 继续计时
    Gosub DrawCard
}
return
MenuAutoRun:
ptAutoRun := (ptAutoRun = 1) ? 0 : 1
Menu, PtMenu, % (ptAutoRun = 1) ? "Check" : "UnCheck", 开机自启
Gosub ApplyAutoRun
return
ApplyAutoRun:
; 本工具链缺 RegWrite/RegDelete 命令，用 reg.exe 等价实现（一次性进程）
if (ptAutoRun = 1)
    RunWait, reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v PPTGlass /t REG_SZ /d "%A_ScriptFullPath%" /f, , Hide
else
    RunWait, reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v PPTGlass /f, , Hide
return

Tick:
if (ptState = "over")
{
    ptOver0++
    ptBlink := !ptBlink
    Gosub DrawCard
    return
}
if (ptState != "run")
    return
if (ptRemain > 0)
{
    if (ptPre > 0 && ptRemain = ptPre*60 && ptPrealed != 1)
    {
        ptPrealed := 1
        if PtFileExists(ptPreFile)
            SoundPlay, %ptPreFile%
        Gosub ShowPrePop
    }
    ptRemain--
}
else
{
    ptState := "over"
    ptOver0 := 0
    ptBlink := true
    if PtFileExists(ptEndFile)
        SoundPlay, %ptEndFile%
    Gosub ShowOverPop
}
Gosub DrawCard
return

; ================= popups (顶部居中，与计时卡同高) =================
PositionPop() {
    global hPop, ptPosY
    WinGetPos, px, py, pw, ph, ahk_id %hPop%
    nx := Round((A_ScreenWidth - pw) / 2)
    if (nx < 8)
        nx := 8
    WinMove, ahk_id %hPop%,, %nx%, %ptPosY%
}

ShowPrePop:

Gui, Pop:Destroy
Gui, Pop:New, +AlwaysOnTop +ToolWindow -Caption +HWNDhPop, PPT沙漏-提示
Gui, Pop:Color, 0F1115
Gui, Pop:Font, s12 Bold cFFE082, Microsoft YaHei UI
Gui, Pop:Add, Text, x24 y14 w200 vpopTxt Center, 还剩 %ptPre% 分钟
ptPopKind := "pre"
Gui, Pop:Show, NoActivate
PositionPop()
WinSet, Trans, 244, ahk_id %hPop%
SetTimer, ClosePop, -6000
return

ShowOverPop:

Gui, Pop:Destroy
Gui, Pop:New, +AlwaysOnTop +ToolWindow -Caption +HWNDhPop, PPT沙漏-提示
Gui, Pop:Color, 0F1115
Gui, Pop:Font, s12 Bold cFF5252, Microsoft YaHei UI
Gui, Pop:Add, Text, x24 y14 w300 vpopTxt Center, %ptMsg%
ptPopKind := "over"
Gui, Pop:Show, NoActivate
PositionPop()
WinSet, Trans, 246, ahk_id %hPop%
return

ClosePop:
SetTimer, ClosePop, Off
Gui, Pop:Destroy
return

PopGuiClose:
Gosub ClosePop
return

; ================= update check =================
VerNewer(a, b) {
    a := RegExReplace(a, "^[vV]", "")
    b := RegExReplace(b, "^[vV]", "")
    ap := StrSplit(a, "."), bp := StrSplit(b, ".")
    Loop, 3
    {
        av := (ap[A_Index] != "") ? (ap[A_Index] + 0) : 0
        bv := (bp[A_Index] != "") ? (bp[A_Index] + 0) : 0
        if (av > bv)
            return 1
        if (av < bv)
            return 0
    }
    return 0
}

UpdParse(js) {
    ; 优先 JSON（测试 mock / 自定义源），否则从 GitHub 发布页提取 tag 路径（HTML 端点不受 API 限流）
    if (RegExMatch(js, """tag_name""\s*:\s*""([^""]+)""", m))
        return m1
    if (RegExMatch(js, "releases/tag/(v[0-9]+\.[0-9]+\.[0-9]+)", m))
        return m1
    return ""
}

; 异步检查：PowerShell 子进程抓取 → 文件回传 → 定时器轮询，绝不阻塞主脚本（AHK v1 单线程，同步 WaitForResponse 会冻结计时/双击；WinHttpRequest 不支持 ComObjConnect 事件）
CheckUpdAsync:
if (ptUpdBusy = 1)
    return
url := (ptUpdateUrl != "") ? ptUpdateUrl : "https://github.com/dataclaw2026/PPTGlass/releases/latest"
url := StrReplace(url, "'", "")
ptUpdBusy := 1
ptUpdTf := A_Temp "\pptglass_upd_" A_TickCount ".txt"
ps1 := A_Temp "\pptglass_upd_" A_TickCount ".ps1"
FileDelete, %ptUpdTf%
body := ""
body .= "$ErrorActionPreference='SilentlyContinue'`n"
body .= "try { (Invoke-WebRequest -Uri '" url "' -UseBasicParsing -TimeoutSec 15).Content | Out-File -FilePath '" ptUpdTf "' -Encoding UTF8 } catch {}`n"
FileAppend, %body%, %ps1%
Run, powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ps1%", , Hide, ptUpdPid
SetTimer, UpdPoll, 400
return

UpdPoll:
Process, Exist, %ptUpdPid%
if (ErrorLevel)
    return
SetTimer, UpdPoll, Off
ptUpdBusy := 0
FileDelete, %ps1%
remote := ""
if (PtFileExists(ptUpdTf))
{
    FileRead, js, %ptUpdTf%
    FileDelete, %ptUpdTf%
    remote := UpdParse(js)
}
Gosub UpdFinishCore
return

UpdFinishCore:
ptRemoteVer := RegExReplace(remote, "^[vV]", "")
if (remote = "")
    GuiControl, Abt:Text, AbtRemote, 远程版本：网络不可用
else
    GuiControl, Abt:Text, AbtRemote, 远程版本：v%ptRemoteVer%
if (remote != "" && VerNewer(remote, ptVer))
{
    if (!ptUpdShown || ptUpdFromMenu)
        Gosub ShowUpdPop
    ptUpdShown := 1
}
else if (ptUpdFromMenu)
    TrayTip, PPT沙漏-检查更新, % (remote = "") ? "网络不可用，稍后重试" : "已是最新版本 v" ptVer, 3, 1
ptUpdFromMenu := 0
return

CheckUpdNow:
ptUpdFromMenu := 1
SetTimer, CheckUpdAsync, -1
return

ShowUpdPop:
Gui, Pop:Destroy
Gui, Pop:New, +AlwaysOnTop +ToolWindow -Caption +HWNDhPop, PPT沙漏-升级提示
Gui, Pop:Color, 0F1115
Gui, Pop:Font, s12 Bold cFFD75E, Microsoft YaHei UI
Gui, Pop:Add, Text, x24 y14 w330 vpopTxt Center, 发现新版本 v%ptRemoteVer%
Gui, Pop:Font, s9 Norm c9AA7C7, Microsoft YaHei UI
Gui, Pop:Add, Text, x24 y48 w330 vpopSub Center, 点击打开下载页面 · 当前 v%ptVer%
ptPopKind := "upd"
Gui, Pop:Show, NoActivate
PositionPop()
WinSet, Trans, 246, ahk_id %hPop%
SetTimer, ClosePop, -10000
return

; 调试用：直接预演弹窗
DbgOverPop:
ptState := "over"
ptOver0 := 0
ptBlink := true
SetTimer, Tick, 1000
Gosub DrawCard
Gosub ShowOverPop
return
DbgPrePop:
ptRemain := ptPre * 60
ptPrealed := 0
ptState := "run"
Gosub DrawCard
Gosub ShowPrePop
return
DbgOpen:
Gosub OpenSet
Gosub OpenAbout
return

; ================= settings (浅色统一风格) =================
; 本工具链缺 FileSelect 命令：用临时 .ps1 + WinForms OpenFileDialog 替代（一次性进程）
PtPickAudio(title, startFile) {
    global
    if (ptDbgTrace)
        FileAppend, PICK start title=%title%`n, %A_ScriptDir%\dbg_tr.txt
    ps1 := A_Temp "\pptglass_pick.ps1"
    out := A_Temp "\pptglass_pick_out.txt"
    FileDelete, %out%
    FileDelete, %ps1%
    ps1Body := "param([string]$Title, [string]$Filter, [string]$StartFile, [string]$Out)`n"
    ps1Body .= "Add-Type -AssemblyName System.Windows.Forms`n"
    ps1Body .= "$Ofd = New-Object System.Windows.Forms.OpenFileDialog`n"
    ps1Body .= "$Ofd.Title = $Title`n"
    ps1Body .= "$Ofd.Filter = $Filter`n"
    ps1Body .= "if (-not [string]::IsNullOrEmpty($StartFile)) { $d = Split-Path $StartFile; if (Test-Path $d -PathType Container) { $Ofd.InitialDirectory = $d } }`n"
    ps1Body .= "if ($Ofd.ShowDialog() -eq 'OK') { [System.IO.File]::WriteAllText($Out, $Ofd.FileName, [System.Text.Encoding]::Unicode) }`n"
    FileAppend, %ps1Body%, %ps1%
    if (ptDbgTrace)
        FileAppend, PICK ps1-len-before-run`n, %A_ScriptDir%\dbg_tr.txt
    RunWait, powershell -noprofile -sta -ExecutionPolicy Bypass -File "%ps1%" -Title "%title%" -Filter "音频文件 (*.wav;*.mp3;*.wma)|*.wav;*.mp3;*.wma|所有文件 (*.*)|*.*" -StartFile "%startFile%" -Out "%out%", , Hide
    if (ptDbgTrace)
    {
        have := 0
        IfExist, %out%
            have := 1
        FileAppend, PICK runwait-done out-exists=%have%`n, %A_ScriptDir%\dbg_tr.txt
    }
    res := ""
    FileRead, res, %out%, -unicode
    FileDelete, %out%
    return res
}

OpenSet:
ckHideOpt := (ptAutoHide = 1) ? "Checked" : ""
ckRunOpt := (ptAutoRun = 1) ? "Checked" : ""
preDisp := RelPath(ptPreFile)
endDisp := RelPath(ptEndFile)
Gui, Set:New, +AlwaysOnTop, PPT沙漏-设置
Gui, Set:Font, s10, Microsoft YaHei UI
Gui, Set:Add, GroupBox, x12 y8 w452 h52, 计时
Gui, Set:Add, Text, x28 y32, 限时（分钟）
Gui, Set:Add, Edit, x124 y28 w56 Center Number Range1-99 veditLimit, %ptLimit%
Gui, Set:Add, Text, x216 y32, 预铃（分钟）
Gui, Set:Add, Edit, x300 y28 w44 Center Number Range0-30 veditPre, %ptPre%
Gui, Set:Add, GroupBox, x12 y66 w452 h118, 声音与提示
Gui, Set:Add, Text, x28 y94, 预铃声音
Gui, Set:Add, Edit, x124 y90 w216 veditPreFile, %preDisp%
Gui, Set:Add, Button, x348 y88 w46 gBrowsePre, 浏览…
Gui, Set:Add, Button, x398 y88 w36 gTestPre, 试听
Gui, Set:Add, Text, x28 y126, 结束声音
Gui, Set:Add, Edit, x124 y122 w216 veditEndFile, %endDisp%
Gui, Set:Add, Button, x348 y120 w46 gBrowseEnd, 浏览…
Gui, Set:Add, Button, x398 y120 w36 gTestEnd, 试听
Gui, Set:Add, Text, x28 y158, 超时提示语
Gui, Set:Add, Edit, x124 y154 w310 veditMsg, %ptMsg%
Gui, Set:Add, Checkbox, x28 y190 vckAutoHide %ckHideOpt%, 自动隐藏（仅放映时显示）
Gui, Set:Add, Checkbox, x240 y190 vckAutoRun %ckRunOpt%, 开机自动启动
Gui, Set:Font, s10 Bold
Gui, Set:Add, Button, x332 y222 w102 h26 gSaveSet Default, 保存并关闭
Gui, Set:Show,, PPT沙漏-设置
return

BrowsePre:
fp := PtPickAudio("选择预铃声音文件", ptPreFile)
if (fp != "")
{
    GuiControl, Set:, editPreFile, % RelPath(fp)
    if PtFileExists(fp)
        SoundPlay, %fp%
}
return
BrowseEnd:
fp := PtPickAudio("选择结束声音文件", ptEndFile)
if (fp != "")
{
    GuiControl, Set:, editEndFile, % RelPath(fp)
    if PtFileExists(fp)
        SoundPlay, %fp%
}
return
TestPre:
; 先提交一次，读取编辑框内当前内容（含未失焦的输入）
Gui, Set:Submit, NoHide
tf := editPreFile
if (tf = "")
    tf := ptPreFile
tf := ResolvePath(tf)
if PtFileExists(tf)
    SoundPlay, %tf%
else
    TrayTip, PPT沙漏-提示, 声音文件不存在：%tf%, 2, 2
return
TestEnd:
Gui, Set:Submit, NoHide
tf := editEndFile
if (tf = "")
    tf := ptEndFile
tf := ResolvePath(tf)
if PtFileExists(tf)
    SoundPlay, %tf%
else
    TrayTip, PPT沙漏-提示, 声音文件不存在：%tf%, 2, 2
return

SaveSettingsFromGui() {
    global ptLimit, ptPre, ptPreFile, ptEndFile, ptMsg, ptAutoHide, ptAutoRun, ptState, ptRemain
    global editLimit, editPre, editPreFile, editEndFile, editMsg, ckAutoHide, ckAutoRun
    Gui, Set:Submit, NoHide
    lv := editLimit + 0
    if (lv < 1)
        lv := 1
    if (lv > 99)
        lv := 99
    pv := editPre + 0
    if (pv < 0)
        pv := 0
    if (pv >= lv)
    {
        maxPre := lv - 1
        MsgBox, 48, PPT沙漏-参数校验, 预铃提醒（分钟）必须小于限时（分钟）。`n当前限时 %lv% 分钟，预铃最多 %maxPre% 分钟。
        return 0
    }
    pf := ResolvePath(editPreFile)
    ef := ResolvePath(editEndFile)
    if (pf != "" && !PtFileExists(pf))
    {
        MsgBox, 48, PPT沙漏-参数校验, 预铃声音文件不存在：`n%pf%
        return 0
    }
    if (ef != "" && !PtFileExists(ef))
    {
        MsgBox, 48, PPT沙漏-参数校验, 结束声音文件不存在：`n%ef%
        return 0
    }
    oldLimit := ptLimit
    ptLimit := lv
    ptPre := pv
    ptPreFile := pf, ptEndFile := ef, ptMsg := editMsg
    ptAutoHide := (ckAutoHide + 0 = 1 ? 1 : 0), ptAutoRun := (ckAutoRun + 0 = 1 ? 1 : 0)
    if (oldLimit != ptLimit)
    {
        ; 限时变更立即生效：计时中/超时中也要重置，从新限时重新倒计时
        ptRemain := ptLimit * 60
        if (ptState = "over")
        {
            ptState := "idle"
            SetTimer, Tick, Off
        }
    }
    else if (ptState = "idle")
        ptRemain := ptLimit * 60
    Menu, PtMenu, % (ptAutoRun = 1) ? "Check" : "UnCheck", 开机自启
    if (ptAutoHide = 1 && !IsSlideShow())
        Gui, Main:Hide
    else if (ptAutoHide = 0)
        Gui, Main:Show, NoActivate
    Gosub ApplyAutoRun
    Gosub SaveIni
    return 1
}
SaveSet:
if (ptDbgTrace)
    FileAppend, SAVESET begin`n, %A_ScriptDir%\dbg_tr.txt
if (!SaveSettingsFromGui())
    return
if (ptDbgTrace)
    FileAppend, SAVESET after-func remain=%ptRemain%`n, %A_ScriptDir%\dbg_tr.txt
Gui, Set:Destroy
Gosub DrawCard
if (ptDbgTrace)
    FileAppend, SAVESET after-drawcard`n, %A_ScriptDir%\dbg_tr.txt
return
SetGuiClose:
; 关闭窗口同样保存（含 X 按钮与 Alt+F4）
if (!SaveSettingsFromGui())
    return
Gui, Set:Destroy
Gosub DrawCard
return

DoQuit:
Gosub SaveIni
ExitApp
return

SaveIni:
rp := RelPath(ptPreFile)
re := RelPath(ptEndFile)
IniWrite, 0, %ptIni%, Main, LimitHour
IniWrite, %ptLimit%, %ptIni%, Main, LimitMin
IniWrite, %ptPre%, %ptIni%, Main, PreAlarm
IniWrite, %ptOpacity%, %ptIni%, Main, Opacity
IniWrite, %rp%, %ptIni%, Main, PreAlarmFile
IniWrite, %re%, %ptIni%, Main, EndAlarmFile
IniWrite, %ptMsg%, %ptIni%, Main, TimeoutMsg
IniWrite, %ptAutoHide%, %ptIni%, Main, AutoHide
IniWrite, %ptAutoRun%, %ptIni%, Main, AutoRun
return

HoverWatch:
if (!hMain)
    return
CoordMode, Mouse, Screen
MouseGetPos, mx, my
if (ptDownActive && !ptDragging)
{
    if (Abs(mx - ptDownSX) > 6 || Abs(my - ptDownSY) > 6)
    {
        ptDownActive := 0
        ptDragging := 1
        DllCall("PostMessageW", "ptr", hMain, "uint", 0xA1, "ptr", 2, "ptr", 0)
    }
}
WinGetPos, wx, wy, ww, wh, ahk_id %hMain%
over := (mx >= wx && mx < wx + ww && my >= wy && my < wy + wh)
if (ptDbgTrace)
    FileAppend, HW mx=%mx% my=%my% wx=%wx% wy=%wy% ww=%ww% wh=%wh% over=%over% ptHover=%ptHover%`n, %A_ScriptDir%\dbg_tr.txt
if (over != ptHover)
{
    ptHover := over
    if (over)
        WinSet, ExStyle, -0x20, ahk_id %hMain%
    else
        WinSet, ExStyle, +0x20, ahk_id %hMain%
    Gosub DrawCard
}
return

StartSlideshow:
try {
    pp := ComObjActive("PowerPoint.Application")
    pp.ActivePresentation.SlideShowSettings.Run()
    return
}
try {
    wpp := ComObjActive("KWPP.Application")
    wpp.ActivePresentation.SlideShowSettings.Run()
    return
}
TrayTip, PPT沙漏-已开始计时, 未检测到播放器，请先启动 PowerPoint 或 WPS…, 4, 2
return

