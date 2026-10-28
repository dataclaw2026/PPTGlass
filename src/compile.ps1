# 编译单文件 exe：powershell -File src\compile.ps1（输出 ..\PPTGlass.exe）
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$ahkRoot = 'C:\Program Files\AutoHotkey'
if (!(Test-Path "$ahkRoot\Compiler\Ahk2Exe.exe")) {
    Write-Host "未找到 Ahk2Exe：请安装 AutoHotkey 1.1，或修改 `$ahkRoot"; exit 1
}
& "$ahkRoot\Compiler\Ahk2Exe.exe" /in "$src\pptglass.ahk" /out "$src\..\PPTGlass.exe" /base "$ahkRoot\AutoHotkeyU64.exe" /icon "$src\pptglass_gold.ico" /compress 0 /silent
Write-Host ("Ahk2Exe exit=" + $LASTEXITCODE)
