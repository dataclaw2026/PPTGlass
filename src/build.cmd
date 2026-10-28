@echo off
rem 编译单文件 exe（需先安装 AutoHotkey 1.1；Ahk2Exe 在 AHK 安装目录 Compiler 下）
rem 本目录需已含 alarm1.wav / alarm2.wav（从 ..\sounds\ 复制）与 pptglass_gold.ico
set AHK=C:\Program Files\AutoHotkey
"%AHK%\Compiler\Ahk2Exe.exe" /silent verbose /in "%~dp0pptglass.ahk" /out "%~dp0..\PPTGlass.exe" /base "%AHK%\AutoHotkeyU64.exe" /icon "%~dp0pptglass_gold.ico" /compress 0
echo done: ..\PPTGlass.exe
