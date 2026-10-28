# PPT沙漏 pptglass

<p align="center">
  <img src="docs/icon.png" width="128" alt="PPT沙漏">
</p>

一个极简的 PPT / WPS 放映计时器：屏幕右上角一张深色卡片，双击即开始计时并启动放映，放映结束自动复位。

<p align="center">
  <img src="docs/card_2x.png" alt="计时卡片（深色金主题）" width="480">
</p>

## 功能

- **自动计时**：检测到 PowerPoint / WPS 进入放映，自动开始倒计时；退出放映自动停止复位
- **双击联动**：双击卡片 = 开始计时 + 启动当前打开的演示文稿放映（PowerPoint / WPS 均支持，COM 联动）
- **预铃提醒**：剩余 N 分钟时数字变橙、弹出提示并播放声音（0–30 分钟可配）
- **超时提醒**：到点后数字红色闪烁并**持续超时正计时**（00:01、00:02…），弹出自定义提示语并播放声音
- **更新检测**：启动后自动检查 GitHub 最新版本，发现新版弹出升级提示（点击直达下载页）；关于窗显示远程版本，右键菜单/托盘可手动「检查更新」
- **手动控制**：F12 开始 / Ctrl+F12 停止 / Win+ESC 退出（可在 ini 修改），也可双击、悬停按钮或右键菜单操作
- **悬停交互**：悬停卡片浮出 ⚙ 设置 / ℹ 关于 / ✕ 退出，按住卡片可拖动
- **设置**：限时（1–99 分钟）、预铃、提示音文件、超时提示语、自动隐藏（仅放映时显示）、开机自启——均持久化到 ini
- **深色金主题**：深色渐变底 + 金色数字 + 琥珀进度条（倒计时从长到短，超时后从短到长循环），按状态变色（运行金、预铃橙、暂停灰蓝、超时红闪）；透明度可调

## 使用

**方式一（推荐）**：从 [Releases](https://github.com/dataclaw2026/PPTGlass/releases) 下载 `PPTGlass.exe` 直接运行（提示音与图标已内嵌，首次运行自动解包），然后打开你的 PPT / WPS 演示文稿，双击右上角卡片即可。

**方式二（源码运行）**：安装 [AutoHotkey 1.1](https://www.autohotkey.com/) 后：

```
git clone https://github.com/dataclaw2026/PPTGlass.git
cd PPTGlass\src
copy ..\sounds\alarm1.wav .      rem 脚本同目录需有 alarm1.wav / alarm2.wav / pptglass_gold.ico
copy ..\sounds\alarm2.wav .
```

运行 `src\pptglass.ahk`（或右键用 AutoHotkey 打开）。配置保存在脚本目录的 `PPTGlass.ini`（在设置窗保存时写入）。

**编译单文件 exe**：安装 AutoHotkey 1.1 与 Ahk2Exe（随 AHK 附带）后执行 `src\build.cmd`（或 PowerShell：`src\compile.ps1`），输出仓库根目录 `PPTGlass.exe`。

## 实现原理

程序本体是 [AutoHotkey 1.1](https://www.autohotkey.com/) 单文件脚本，界面与逻辑全在 `src/pptglass.ahk`（约 840 行，含注释）：

1. **放映检测**（`PollShow`/`IsSlideShow`）：250ms 轮询——PowerPoint 放映窗口类，以及 WPS 演示进程（wpp.exe/wps.exe）中"可见 + 置顶 + 全屏"的窗口（双策略，兼容新版 WPS 类名变化）
2. **卡片渲染**（`DrawCard`）：GDI+ 绘制深色渐变圆角卡片 → `STM_SETIMAGE` 送入 Picture 控件呈现；数字用微软雅黑加粗 + 渐变笔刷着色，无外部字体依赖
3. **放映联动**（`StartSlideshow`）：COM（`ComObjActive`）挂接已运行的 PowerPoint / WPS 实例，`SlideShowSettings.Run()` 启动放映
4. **交互**：悬停浮出按钮、按住拖动（`WM_NCLBUTTONDOWN`）、右键菜单、托盘菜单；单文件版用 `FileInstall` 内嵌声音与图标，运行时解包到 `%TEMP%`

## 源码结构

```
src/pptglass.ahk       全部源码：界面绘制、放映检测、倒计时、设置窗、弹窗
src/pptglass_gold.ico  应用图标（编译用）
src/build.cmd          编译单文件 exe（批处理）
src/compile.ps1        编译单文件 exe（PowerShell）
sounds/alarm1.wav      预铃提示音（FileInstall 内嵌）
sounds/alarm2.wav      结束提示音
docs/                  README 截图与图标
tests/uitest.py        消息驱动回归/UI 测试（python uitest.py 全部或指定阶段 1|2|2b|3|4|5|6）
```

改配色搜 `c1 :=`，改尺寸搜 `CW :=`，改检测逻辑搜 `IsSlideShow`。

## 开发

| 工具 | 用途 |
|---|---|
| [AutoHotkey 1.1.37](https://www.autohotkey.com/) | 脚本运行时 |
| [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe) | 编译为单文件 exe（FileInstall 内嵌资源） |
| GDI+ / Win32 API | 卡片绘制、放映窗口检测、COM 联动 |
| Python + ctypes | tests/uitest.py 消息驱动回归测试 |

## 作者

**dataclaw2026** · [github.com/dataclaw2026](https://github.com/dataclaw2026)

灵感与功能清单参考陈家琪老师的《PPT播放提示钟》（2003）。

## 许可证

[MIT License](LICENSE)
