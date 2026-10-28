# -*- coding: utf-8 -*-
"""
PPT沙漏 PPTGlass.exe 消息驱动回归/UI 测试
阶段: T1 干净启动渲染 | T2 设置保存落盘+自启reg | T3 计时启停 | T4 超时弹窗对齐
      T5 预铃弹窗自动关 | T6 浏览选择器链路 | T7 试听链路 | T8 版本检测升级提示(mock)
      T9 设置参数校验(预铃≥限时/声音不存在) | T10 放映联动自动开始停止(fake窗)
用法: python uitest.py [阶段号...]  缺省全部
"""
import ctypes, os, sys, subprocess, time, glob
from ctypes import c_void_p, c_int, c_uint

u = ctypes.windll.user32
u.SetProcessDPIAware()

EXE   = r"D:\pywin\rev-skills\PPTGlass\PPTGlass.exe"
INIP  = r"D:\pywin\rev-skills\PPTGlass\PPTGlass.ini"
ALARM1= r"D:\pywin\rev-skills\PPTGlass\alarm1.wav"
ALARM2= r"D:\pywin\rev-skills\PPTGlass\alarm2.wav"
VER   = "1.1.8"  # 与源码 ptVer 保持一致（每次发布同步更新）
MSG_NEW = "测试超时提醒语"

WM_SETTEXT=0x000C; WM_GETTEXT=0x000D; WM_CLOSE=0x0010
WM_LBUTTONDBLCLK=0x0203
BM_GETCHECK=0x00F0; BM_SETCHECK=0x00F1; BM_CLICK=0x00F5
PW_RENDERFULLCONTENT=2

RESULTS = []
def check(name, ok, note=""):
    RESULTS.append((name, ok, note))
    print(("PASS " if ok else "FAIL ") + name + (("  | " + note) if note else ""))

def find_tops(prefix):
    """returns list of (hwnd, title, visible, pid)"""
    out = []
    def cb(h, _):
        n = u.GetWindowTextLengthW(h)
        if n:
            buf = ctypes.create_unicode_buffer(n+2)
            u.GetWindowTextW(h, buf, n+2)
            if prefix in buf.value:
                pid = c_int(0)
                u.GetWindowThreadProcessId(h, ctypes.byref(pid))
                out.append((h, buf.value, bool(u.IsWindowVisible(h)), pid.value))
        return True
    u.EnumWindows(ctypes.WINFUNCTYPE(c_int, c_void_p, c_void_p)(cb), 0)
    return out

def one(prefix, visible=True):
    for h, t, v, p in find_tops(prefix):
        if v == visible:
            return (h, t, v, p)
    return None

def wait_until(fn, timeout=6.0, step=0.25):
    t0 = time.time()
    while time.time() - t0 < timeout:
        r = fn()
        if r:
            return r
        time.sleep(step)
    return None

def children(hwnd, cls=None):
    out = []
    def cb(h, _):
        c = ctypes.create_unicode_buffer(64)
        u.GetClassNameW(h, c, 64)
        if cls is None or c.value == cls:
            n = u.GetWindowTextLengthW(h)
            buf = ctypes.create_unicode_buffer(n+2) if n else ctypes.create_unicode_buffer(2)
            u.GetWindowTextW(h, buf, n+2)
            out.append((h, c.value, buf.value))
        return True
    u.EnumChildWindows(hwnd, ctypes.WINFUNCTYPE(c_int, c_void_p, c_void_p)(cb), 0)
    return out

def get_text(hwnd):
    n = u.GetWindowTextLengthW(hwnd) + 4
    buf = ctypes.create_unicode_buffer(n)
    u.SendMessageW(hwnd, WM_GETTEXT, n, buf)
    return buf.value

def kill_exe():
    subprocess.run(["taskkill","/F","/IM","PPTGlass.exe"], capture_output=True)
    time.sleep(1.0)

def launch():
    kill_exe()
    p = subprocess.Popen([EXE], cwd=os.path.dirname(EXE))
    time.sleep(2.8)
    return p

def write_ini(main_lines=(), debug=None):
    """main_lines: list of (k,v); debug: None or dict"""
    txt = "[Main]\n"
    d = dict(main_lines)
    base = {"LimitHour":"0","LimitMin":"10","PreAlarm":"2","Opacity":"242",
            "TimeoutMsg":"时间到！请结束演讲","AutoHide":"0","AutoRun":"0",
            "showWindowClasses":"ZZ_PPTGLASS_TEST_NOMATCH","showProcesses":"ZZ_nomatch.exe"}
    base.update(d)
    for k in sorted(base):
        txt += f"{k}={base[k]}\n"
    txt += "[shortcuts]\nstartKey=F12\nstopKey=^F12\nquitKey=#ESC\n"
    if debug:
        txt += "[Debug]\n" + "".join(f"{k}={v}\n" for k,v in debug.items())
    open(INIP, "w", encoding="utf-16").write(txt)

def write_prod_ini():
    """正式配置（无测试隔离键）"""
    txt = ("[Main]\nLimitHour=0\nLimitMin=10\nPreAlarm=2\nOpacity=242\n"
           "TimeoutMsg=时间到！请结束演讲\nAutoHide=0\nAutoRun=0\n"
           "[shortcuts]\nstartKey=F12\nstopKey=^F12\nquitKey=#ESC\n")
    open(INIP, "w", encoding="utf-16").write(txt)

def read_ini():
    try:
        return open(INIP, encoding="utf-16").read()
    except Exception:
        return open(INIP, encoding="utf-8", errors="replace").read()

def capture(hwnd, w, h):
    g = ctypes.windll.gdi32
    class RECT(ctypes.Structure):
        _fields_=[("l",c_int),("t",c_int),("r",c_int),("b",c_int)]
    r = RECT(); u.GetWindowRect(hwnd, ctypes.byref(r))
    W, H = r.r-r.l, r.b-r.t
    if W<=0 or H<=0: return None, 0, 0
    hs = u.GetDC(0); hdc = g.CreateCompatibleDC(hs)
    class BIH(ctypes.Structure):
        _fields_=[("sz",c_int),("w",c_int),("h",c_int),("pl",ctypes.c_short),("bc",ctypes.c_short),
                  ("comp",c_int),("szi",c_uint),("xppm",c_int),("yppm",c_int),("cu",c_uint),("ci",c_uint)]
    hdr = BIH(); hdr.sz=40; hdr.w=W; hdr.h=-H; hdr.pl=1; hdr.bc=32; hdr.comp=0
    bpp = ctypes.POINTER(ctypes.c_uint32)()
    hbm = g.CreateDIBSection(hdc, ctypes.byref(hdr), 0, ctypes.byref(bpp), 0, 0)
    old = g.SelectObject(hdc, hbm)
    ok = u.PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT)
    buf = ctypes.string_at(bpp, W*H*4)
    g.SelectObject(hdc, old); g.DeleteObject(hbm); g.DeleteDC(hdc); u.ReleaseDC(0, hs)
    if not ok: return None, W, H
    from PIL import Image
    return Image.frombuffer("RGBA",(W,H),buf,"raw","BGRA",0,1).convert("RGB"), W, H

def sample(im, fx, fy):
    w,h = im.size
    return im.getpixel((min(int(w*fx),w-1), min(int(h*fy),h-1)))

# ---------------- T1 干净启动 ----------------
def T1():
    write_ini()
    p = launch()
    card = wait_until(lambda: one("PPT沙漏-计时"))
    if not card:
        check("T1 卡片窗口出现", False); return
    h, t, v, pid = card
    check("T1 卡片可见", v, f"title={t}")
    check("T1 idle 标题 10:00", "计时 10:00" in t, t)
    st = one("PPT沙漏-设置"); ab = one("PPT沙漏-关于")
    check("T1 设置窗未显示", (st is None) or (not st[2]))
    check("T1 关于窗未显示", (ab is None) or (not ab[2]))
    im, W, H = capture(h, W, H) if False else (None,0,0)
    im, W, H = capture(h, 0, 0)
    if im is None:
        check("T1 卡片像素捕获", False); return
    bg = sample(im, 0.5, 0.12)
    check("T1 idle 深色底", bg[0]<40 and bg[1]<40 and bg[2]<50, f"#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}")
    gold = sum(1 for px in im.getdata() if px[0]>220 and 130<px[1]<230 and px[2]<140)
    check("T1 金色数字渲染", gold > 150, f"gold={gold}")
    bar = sample(im, 0.5, 0.93)
    check("T1 进度条空闲满格(剩余全满)", bar[0] > 200 and 100 < bar[1] < 200 and bar[2] < 90, f"#{bar[0]:02X}{bar[1]:02X}{bar[2]:02X}")

# ---------------- T2 设置窗消息驱动 + 保存 + 自启 ----------------
def open_settings_and_about():
    write_ini(debug={"Open":"1"})
    launch()
    s = wait_until(lambda: one("PPT沙漏-设置") if one("PPT沙漏-设置") and one("PPT沙漏-设置")[2] else None, 6)
    a = wait_until(lambda: one("PPT沙漏-关于") if one("PPT沙漏-关于") and one("PPT沙漏-关于")[2] else None, 6)
    return s, a

def get_set_controls():
    s = one("PPT沙漏-设置")
    if not s: return None
    hs = s[0]
    edits = [c for c in children(hs, "Edit")]
    btns  = [c for c in children(hs, "Button")]
    browse = [b for b in btns if b[2].startswith("浏览")]
    testb  = [b for b in btns if b[2] == "试听"]
    saveb  = [b for b in btns if "保存" in b[2]]
    ckhide = [b for b in btns if "自动隐藏" in b[2]]
    ckrun  = [b for b in btns if "自动" in b[2] and "启动" in b[2]]
    return dict(hwnd=hs, edits=edits, browse=browse, test=testb, save=saveb,
                ckhide=ckhide, ckrun=ckrun)

def T2():
    s, a = open_settings_and_about()
    check("T2 设置窗弹出(Debug.Open)", bool(s and s[2]))
    check("T2 关于窗弹出(Debug.Open)", bool(a and a[2]))
    if not s:
        return
    C = get_set_controls()
    if not C or len(C["edits"]) != 5:
        check("T2 控件枚举(5 Edit)", False, str(len(C['edits']) if C else 'no win')); return
    e = C["edits"]
    check("T2 限时初值=10", get_text(e[0][0]) == "10", get_text(e[0][0]))
    check("T2 预铃初值=2", get_text(e[1][0]) == "2", get_text(e[1][0]))
    u.SendMessageW(e[0][0], WM_SETTEXT, 0, "5")
    u.SendMessageW(e[1][0], WM_SETTEXT, 0, "1")
    u.SendMessageW(e[2][0], WM_SETTEXT, 0, ALARM1)
    u.SendMessageW(e[3][0], WM_SETTEXT, 0, ALARM2)
    u.SendMessageW(e[4][0], WM_SETTEXT, 0, MSG_NEW)
    if C["ckrun"]:
        u.SendMessageW(C["ckrun"][0][0], BM_SETCHECK, 1, 0)
    if C["ckhide"]:
        u.SendMessageW(C["ckhide"][0][0], BM_SETCHECK, 1, 0)
    rc_run = u.SendMessageW(C["ckrun"][0][0], BM_GETCHECK, 0, 0) if C["ckrun"] else -1
    check("T2 自启checkbox置位", rc_run == 1, str(rc_run))
    if not C["save"]:
        check("T2 找到保存按钮", False); return
    u.SendMessageW(C["save"][0][0], BM_CLICK, 0, 0)
    time.sleep(1.2)
    s2 = one("PPT沙漏-设置")
    check("T2 保存后设置窗关闭", (s2 is None) or (not s2[2]))
    ini = read_ini()
    ok = all(k in ini for k in []) 
    import re
    def ini_val(k):
        m = re.search(rf"^{k}=(.*)$", ini, re.M)
        return m.group(1).strip() if m else None
    check("T2 ini LimitMin=5", ini_val("LimitMin") == "5", str(ini_val("LimitMin")))
    check("T2 ini PreAlarm=1", ini_val("PreAlarm") == "1", str(ini_val("PreAlarm")))
    check("T2 ini TimeoutMsg", ini_val("TimeoutMsg") == MSG_NEW, str(ini_val("TimeoutMsg")))
    check("T2 ini PreAlarmFile", ini_val("PreAlarmFile") == ".\\alarm1.wav", str(ini_val("PreAlarmFile")))
    check("T2 ini EndAlarmFile", ini_val("EndAlarmFile") == ".\\alarm2.wav", str(ini_val("EndAlarmFile")))
    check("T2 ini AutoRun=1", ini_val("AutoRun") == "1", str(ini_val("AutoRun")))
    check("T2 ini AutoHide=1", ini_val("AutoHide") == "1", str(ini_val("AutoHide")))
    rq = subprocess.run(["reg","query",r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run","/v","PPTGlass"],
                        capture_output=True, text=True, errors="replace")
    check("T2 自启注册表项写入", rq.returncode == 0 and "PPTGlass" in rq.stdout, rq.stdout.strip()[:80])
    cards = [x for x in find_tops("PPT沙漏-计时")]
    card = cards[0] if cards else None
    check("T2 卡片镜像新限时 05:00", card and "05:00" in card[1], card[1] if card else "no card")
    check("T2 AutoHide=1 卡片隐藏", card and not card[2])

def T2b():
    """恢复：取消自启/自动隐藏，验证 reg 项删除 + 卡片恢复显示"""
    s, a = open_settings_and_about()
    if not s:
        check("T2b 重开设置窗", False); return
    C = get_set_controls()
    if not C or len(C["edits"]) != 5:
        check("T2b 控件枚举", False); return
    u.SendMessageW(C["ckrun"][0][0], BM_SETCHECK, 0, 0)
    u.SendMessageW(C["ckhide"][0][0], BM_SETCHECK, 0, 0)
    u.SendMessageW(C["save"][0][0], BM_CLICK, 0, 0)
    time.sleep(1.2)
    rq = subprocess.run(["reg","query",r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run","/v","PPTGlass"],
                        capture_output=True, text=True, errors="replace")
    check("T2b 自启注册表项删除", rq.returncode != 0)
    ini = read_ini()
    import re
    ah = re.search(r"^AutoHide=(.*)$", ini, re.M)
    check("T2b ini AutoHide=0", ah and ah.group(1).strip() == "0")
    card = wait_until(lambda: one("PPT沙漏-计时") and one("PPT沙漏-计时")[2], 4)
    check("T2b 卡片恢复显示", bool(card))

# ---------------- T3 计时启停 ----------------
def T3():
    write_ini(debug={"NoSlide": "1"})
    launch()
    card = wait_until(lambda: one("PPT沙漏-计时"))
    if not card:
        check("T3 卡片出现", False); return
    h = card[0]
    pics = children(h, "Static")
    target = pics[0][0] if pics else h
    lparam = (60 << 16) | 100
    u.PostMessageW(target, WM_LBUTTONDBLCLK, 1, lparam)
    time.sleep(2.0)
    t1 = one("PPT沙漏-计时")
    check("T3 双击开始计时(标题变化)", t1 and "10:00" not in t1[1], t1[1] if t1 else "")
    time.sleep(1.6)
    t2 = one("PPT沙漏-计时")
    def sec(title):
        try: return int(title.split("计时 ")[1][:2])*60 + int(title.split("计时 ")[1][3:5])
        except Exception: return -1
    check("T3 倒计时递减", t1 and t2 and sec(t2[1]) < sec(t1[1]), f"{t1[1]} -> {t2[1]}")
    u.PostMessageW(target, WM_LBUTTONDBLCLK, 1, lparam)
    time.sleep(1.5)
    t3 = one("PPT沙漏-计时")
    check("T3 再双击停止回 10:00", t3 and "10:00" in t3[1], t3[1] if t3 else "")

# ---------------- T4 超时弹窗 ----------------
def T4():
    write_ini(debug={"Popup":"1"})
    launch()
    pop = wait_until(lambda: (lambda p: p if (p and p[2]) else None)(one("PPT沙漏-提示")), 5)
    check("T4 超时弹窗出现", bool(pop))
    if not pop: return
    hp = pop[0]
    statics = children(hp, "Static")
    txt = get_text(statics[0][0]) if statics else ""
    check("T4 弹窗文本=ini超时提示语", txt == "时间到！请结束演讲", txt)
    card = one("PPT沙漏-计时")
    popR = ctypes.wintypes.RECT() if hasattr(ctypes,"wintypes") else None
    import ctypes.wintypes as wt
    r1 = wt.RECT(); r2 = wt.RECT()
    u.GetWindowRect(hp, ctypes.byref(r1))
    u.GetWindowRect(card[0], ctypes.byref(r2))
    W = u.GetSystemMetrics(0)
    cx = (r1.left + r1.right)//2
    check("T4 弹窗水平居中", abs(cx - W//2) <= 8, f"cx={cx} vs {W//2}")
    check("T4 弹窗与卡片同高", abs(r1.top - r2.top) <= 2, f"pop={r1.top} card={r2.top}")
    import re as _re
    def ov_sec(t):
        m = _re.match(r"^PPT沙漏-计时 00:(\d\d)$", t)
        return int(m.group(1)) if m else -1
    t_a = ov_sec(card[1]) if card else -1
    check("T4 卡片 over 红色正计时", t_a >= 0, card[1] if card else "")
    time.sleep(1.3)
    card2 = one("PPT沙漏-计时")
    t_b = ov_sec(card2[1]) if card2 else -1
    check("T4 超时正计时递增", t_a >= 0 and t_b > t_a, f"{t_a}s -> {t_b}s")
    im1, Wc, Hc = capture(card[0], 0, 0)
    time.sleep(1.1)
    im2, _, _ = capture(card[0], 0, 0)
    time.sleep(1.1)
    im3, _, _ = capture(card[0], 0, 0)
    def lightred(im):
        return sum(1 for px in im.getdata() if px[0] > 190 and 100 < px[1] < 175 and 90 < px[2] < 175)
    cs = [lightred(i) for i in (im1, im2, im3) if i]
    if im1 and len(cs) >= 2:
        check("T4 卡片红色闪烁交替", max(cs) > 100 and min(cs) < max(cs) * 0.3, f"lightred={cs}")
    elif im1:
        check("T4 卡片红色闪烁交替", False, f"capture失败={cs}")
    imp, Wp, Hp = capture(hp, 0, 0)
    if imp:
        white = sum(1 for px in imp.getdata() if px[0]>240 and px[1]>240 and px[2]>240)
        check("T4 弹窗深底", white/(Wp*Hp) < 0.5, f"white={white/(Wp*Hp):.0%}")

# ---------------- T5 预铃弹窗 ----------------
def T5():
    write_ini(debug={"Popup":"2"})
    launch()
    pop = wait_until(lambda: (lambda p: p if (p and p[2]) else None)(one("PPT沙漏-提示")), 5)
    check("T5 预铃弹窗出现", bool(pop))
    if not pop: return
    statics = children(pop[0], "Static")
    txt = get_text(statics[0][0]) if statics else ""
    check("T5 弹窗文本=还剩2分钟", txt.replace(" ","") == "还剩2分钟", txt)
    gone = wait_until(lambda: (lambda p: True if (p is None or not p[2]) else None)(one("PPT沙漏-提示")), 10, 0.5)
    check("T5 弹窗6s后自动关闭", bool(gone))

# ---------------- T6 浏览选择器 + T7 试听 ----------------
def T6():
    s, a = open_settings_and_about()
    if not s:
        check("T6 设置窗弹出", False); return
    C = get_set_controls()
    if not C or not C["browse"]:
        check("T6 浏览按钮存在", False); return
    before = get_text(C["edits"][2][0])
    u.SendMessageW(C["browse"][0][0], BM_CLICK, 0, 0)
    dlg = wait_until(lambda: (lambda p: p if (p and p[2]) else None)(one("选择预铃声音文件")), 12)
    if not dlg:
        # 诊断：打印所有可见顶层窗口标题
        vis = [t for h,t,v,p in find_tops("") if v and t]
        check("T6 文件选择对话框弹出", False, "可见窗: " + " / ".join(vis[:8]))
    else:
        check("T6 文件选择对话框弹出", True, dlg[1])
    if dlg:
        u.PostMessageW(dlg[0], WM_CLOSE, 0, 0)
        time.sleep(1.8)
    after = get_text(C["edits"][2][0])
    check("T6 取消后路径未变", after == before, f"{before!r} -> {after!r}")
    # T7 试听: set real file then click 试听
    u.SendMessageW(C["edits"][2][0], WM_SETTEXT, 0, ALARM1)
    proc_alive = wait_until(lambda: one("PPT沙漏-设置"), 2)
    u.SendMessageW(C["test"][0][0], BM_CLICK, 0, 0)
    time.sleep(1.2)
    still = one("PPT沙漏-设置")
    check("T7 试听后进程/窗口正常", bool(still and still[2]))
    # nonexist path -> TrayTip path (no crash)
    u.SendMessageW(C["edits"][2][0], WM_SETTEXT, 0, r"D:\不存在的声音.wav")
    u.SendMessageW(C["test"][0][0], BM_CLICK, 0, 0)
    time.sleep(1.2)
    still2 = one("PPT沙漏-设置")
    check("T7 试听不存在文件不崩溃", bool(still2 and still2[2]))

# ---------------- T8 版本检测与升级提示（mock GitHub API） ----------------
def T8():
    import http.server, threading, json as _json
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = _json.dumps({"tag_name": "v9.9.9", "name": "mock"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *a):
            pass
    srv = http.server.HTTPServer(("127.0.0.1", 8899), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    write_ini(main_lines=[("UpdateUrl", "http://127.0.0.1:8899/latest.json")], debug={"Abt": "1"})
    launch()
    pop = wait_until(lambda: one("PPT沙漏-升级提示"), 9)
    check("T8 升级弹窗出现", bool(pop))
    if pop:
        txts = " | ".join(get_text(s[0]) for s in children(pop[0], "Static"))
        check("T8 弹窗含新版本号", "v9.9.9" in txts, txts)
        check("T8 弹窗含当前版本", f"当前 v{VER}" in txts, txts)
    abt = wait_until(lambda: one("PPT沙漏-关于"), 6)
    if abt:
        atxts = " | ".join(get_text(s[0]) for s in children(abt[0], "Static"))
        check("T8 关于窗显示远程版本", "远程版本：v9.9.9" in atxts, atxts[-160:])
    srv.shutdown()

# ---------------- T9 设置参数校验（预铃≥限时 / 声音文件不存在） ----------------
def T9():
    write_ini(debug={"Open": "1"})
    launch()
    s = wait_until(lambda: one("PPT沙漏-设置"), 6)
    if not s:
        check("T9 设置窗弹出", False); return
    C = get_set_controls()
    if not C or len(C["edits"]) < 3:
        check("T9 控件枚举", False); return

    def top_dialog():
        res = []
        def cb(h, _):
            buf = ctypes.create_unicode_buffer(64)
            u.GetClassNameW(h, buf, 64)
            if buf.value == "#32770" and u.IsWindowVisible(h):
                n = u.GetWindowTextLengthW(h)
                tb = ctypes.create_unicode_buffer(n + 2)
                u.GetWindowTextW(h, tb, n + 2)
                if tb.value == "PPT沙漏-参数校验":
                    res.append(h)
            return True
        u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
        return res[0] if res else None

    def dismiss():
        d = wait_until(lambda: top_dialog(), 4)
        if not d:
            return None
        oks = children(d, "Button")
        if oks:
            u.SendMessageW(oks[0][0], BM_CLICK, 0, 0)
        # 等弹窗消失 + 设置窗重新可用（AHK MsgBox 关闭后首个保存点击会被吞，多等一会）
        t0 = time.time()
        while time.time() - t0 < 3:
            if not top_dialog():
                time.sleep(1.2)
                return d
            time.sleep(0.2)
        return d

    def try_save():
        # 保存点击：若未弹窗且窗口仍在（被吞），重试一次
        for _ in range(2):
            u.SendMessageW(C["save"][0][0], BM_CLICK, 0, 0)
            time.sleep(0.9)
            if top_dialog() or not (one("PPT沙漏-设置") and one("PPT沙漏-设置")[2]):
                return
            time.sleep(0.3)

    # 场景1：预铃 5 ≥ 限时 3 → 报错且拒绝保存
    u.SendMessageW(C["edits"][0][0], WM_SETTEXT, 0, "3")
    u.SendMessageW(C["edits"][1][0], WM_SETTEXT, 0, "5")
    try_save()
    d1 = dismiss()
    check("T9 预铃≥限时报错弹窗", bool(d1))
    st = one("PPT沙漏-设置")
    check("T9 预铃超限保存被拒(窗仍开)", bool(st and st[2]))
    ini = read_ini()
    check("T9 ini 限时未被写入", "LimitMin=3" not in ini, str([ln for ln in ini.splitlines() if "LimitMin" in ln]))

    # 场景2：预铃声音文件不存在 → 报错且拒绝保存
    u.SendMessageW(C["edits"][0][0], WM_SETTEXT, 0, "10")
    u.SendMessageW(C["edits"][1][0], WM_SETTEXT, 0, "1")
    u.SendMessageW(C["edits"][2][0], WM_SETTEXT, 0, r"D:\不存在的铃声.wav")
    try_save()
    d2 = dismiss()
    check("T9 声音不存在报错弹窗", bool(d2))
    st2 = one("PPT沙漏-设置")
    check("T9 声音不存在保存被拒", bool(st2 and st2[2]))

    # 场景3：目录外文件（同盘符，真实存在）→ 自动转 ..\ 相对路径
    import shutil
    outside = r"D:\pywin\ppttest_outside.wav"
    shutil.copyfile(ALARM1, outside)
    u.SendMessageW(C["edits"][2][0], WM_SETTEXT, 0, outside)
    try_save()
    time.sleep(0.5)
    d3 = dismiss()
    check("T9 目录外文件保存不弹错", d3 is None)
    ini3 = read_ini()
    import re
    m = re.search(r"^PreAlarmFile=(.*)$", ini3, re.M)
    check("T9 ini 目录外文件转相对", m and m.group(1) == r"..\..\ppttest_outside.wav", m.group(1) if m else "")
    os.remove(outside)

# ---------------- T10 放映联动（fake screenClass：自动开始/停止 + AutoHide） ----------------
_fake_wndproc = None
def _create_fake_show():
    global _fake_wndproc
    WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p)
    def _p(h, m, w, l):
        return u.DefWindowProcW(h, m, w, l)
    _fake_wndproc = WNDPROC(_p)
    class WNDCLASSW(ctypes.Structure):
        _fields_ = [("style", ctypes.c_uint), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
                    ("cbWndExtra", ctypes.c_int), ("hInstance", ctypes.c_void_p), ("hIcon", ctypes.c_void_p),
                    ("hCursor", ctypes.c_void_p), ("hbrBackground", ctypes.c_void_p),
                    ("lpszMenuName", ctypes.c_wchar_p), ("lpszClassName", ctypes.c_wchar_p)]
    wc = WNDCLASSW(0, _fake_wndproc, 0, 0, None, None, None, None, None, "screenClass")
    u.RegisterClassW(ctypes.byref(wc))
    return u.CreateWindowExW(0, "screenClass", "ppt-fake-show", 0, -32000, -32000, 120, 90, None, None, None, None)

def _destroy_fake_show(hw):
    if hw:
        u.DestroyWindow(hw)

def T10():
    def real_show():
        res = []
        def cb(h, _):
            buf = ctypes.create_unicode_buffer(64)
            u.GetClassNameW(h, buf, 64)
            if buf.value == "screenClass" and u.IsWindowVisible(h):
                res.append(1)
            return True
        u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(cb), 0)
        return bool(res)
    if real_show():
        check("T10 放映联动(真实放映在跑，跳过)", True, "skip: real slideshow active")
        return
    write_ini(main_lines=[("showWindowClasses", "screenClass"),
                          ("showProcesses", "ZZ_nomatch.exe"),
                          ("AutoHide", "1")])
    launch()
    hid = wait_until(lambda: one("PPT沙漏-计时", visible=False), 6)
    check("T10 AutoHide=1 无放映时卡片隐藏", bool(hid), "hidden card found" if hid else "not found")
    check("T10 初始不可见", one("PPT沙漏-计时", visible=True) is None)
    hw = _create_fake_show()
    card = wait_until(lambda: one("PPT沙漏-计时", visible=True), 5)
    check("T10 放映开始→卡片显示", bool(card))
    # Show 与 DoStart 之间可能被其他定时器插入，等待标题变化而非立即断言
    t1 = wait_until(lambda: (lambda c: c[1] if (c and "10:00" not in c[1]) else None)(one("PPT沙漏-计时", visible=True)), 4)
    check("T10 放映开始→自动计时", bool(t1), t1 if t1 else "still 10:00")
    time.sleep(1.6)
    card2 = one("PPT沙漏-计时", visible=True)
    def secs(t):
        try: return int(t.split("计时 ")[1][:2])*60 + int(t.split("计时 ")[1][3:5])
        except Exception: return -1
    t1s = t1 if isinstance(t1, str) else ""
    check("T10 自动倒计时递减", card2 and secs(card2[1]) < secs(t1s), f"{t1s} -> {card2[1] if card2 else ''}")
    _destroy_fake_show(hw)
    time.sleep(1.0)
    check("T10 放映结束→卡片重新隐藏", one("PPT沙漏-计时", visible=True) is None)
    tops = [t for h, t, v, p in find_tops("PPT沙漏-计时")]
    check("T10 放映结束→自动停止复位 10:00", tops and "10:00" in tops[0], tops[0] if tops else "")

ALL = {"1":T1, "2":T2, "2b":T2b, "3":T3, "4":T4, "5":T5, "6":T6, "8":T8, "9":T9, "10":T10}
ORDER = ["1","2","2b","3","4","5","6","8","9","10"]

if __name__ == "__main__":
    stages = sys.argv[1:] or ORDER
    try:
        for sname in stages:
            print(f"\n===== 阶段 T{sname} =====")
            try:
                ALL[sname]()
            except Exception as e:
                check(f"T{sname} 异常", False, repr(e))
    finally:
        kill_exe()
        write_prod_ini()
    print("\n========== 汇总 ==========")
    npass = sum(1 for _,ok,_ in RESULTS if ok)
    for name, ok, note in RESULTS:
        print(("PASS " if ok else "FAIL ") + name + (("  | " + note) if note else ""))
    print(f"\n{npass}/{len(RESULTS)} 项通过")
