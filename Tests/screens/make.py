#!/usr/bin/env python3
"""Realistic screenshot test sets: everyday screens and a held-out set.
Each case: the screen (HTML rendered by headless Chrome), what a good name must mention
(written BEFORE running neatly), and a reference name. Run: make.py tuned|held <outdir>   (needs Google Chrome to draw the screens)"""
import json, os, subprocess, sys, html as H

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SET = sys.argv[1]
OUT = os.path.abspath(sys.argv[2])
os.makedirs(OUT, exist_ok=True)

CSS = """
body{margin:0;font-family:-apple-system,'SF Pro Text','Helvetica Neue',sans-serif;background:#cfd6e0;}
.menubar{height:24px;background:rgba(240,240,240,.9);font-size:13px;display:flex;gap:18px;padding:0 14px;align-items:center}
.menubar b{font-weight:700}.menubar .r{margin-left:auto;display:flex;gap:14px}
.desk{position:relative;height:calc(100% - 24px)}
.win{background:#fff;border-radius:12px;box-shadow:0 20px 50px rgba(0,0,0,.35);overflow:hidden;position:absolute}
.tb{height:38px;background:#f3f3f3;border-bottom:1px solid #ddd;display:flex;align-items:center;padding:0 12px;font-size:13px;color:#444}
.dots span{display:inline-block;width:12px;height:12px;border-radius:6px;margin-right:7px}
.url{margin:0 auto;background:#e6e6e6;border-radius:7px;padding:4px 60px;color:#555;font-size:12px}
.c{padding:22px;font-size:15px;color:#222}
.icon{position:absolute;right:30px;width:70px;text-align:center;font-size:11px;color:#fff;text-shadow:0 1px 2px #000}
.icon div{width:52px;height:60px;margin:0 auto 4px;background:#fff;border-radius:4px;opacity:.9}
.bub{max-width:62%;padding:9px 14px;border-radius:18px;margin:6px 0;font-size:15px;line-height:1.35}
.me{background:#0a84ff;color:#fff;margin-left:auto}.them{background:#e9e9eb}
small{color:#888}
"""

def window(title, body, url=None, w=1000, h=680, x=180, y=60, tbcolor="#f3f3f3"):
    bar = f'<div class="url">{url}</div>' if url else f'<div style="margin:0 auto;font-weight:600">{title}</div>'
    return (f'<div class="win" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">'
            f'<div class="tb" style="background:{tbcolor}"><span class="dots"><span style="background:#ff5f57"></span>'
            f'<span style="background:#febc2e"></span><span style="background:#28c840"></span></span>{bar}</div>'
            f'<div class="c">{body}</div></div>')

def screen(app, win, full=True, desk_icons=("Screenshot 2026-11-02 at 10.14.22", "IMG_4471.HEIC", "budget-final-v3.xlsx")):
    icons = "".join(f'<div class="icon" style="top:{30+i*100}px"><div></div>{H.escape(n)}</div>' for i, n in enumerate(desk_icons))
    menu = (f'<div class="menubar"><span></span><b>{app}</b><span>File</span><span>Edit</span><span>View</span>'
            f'<span>Window</span><span>Help</span><span class="r"><span>100%</span><span>Fri 14 Nov  16:42</span></span></div>')
    bg = "linear-gradient(135deg,#3a6186,#89253e)"
    if full:
        return f'<html><head><style>{CSS}</style></head><body style="width:1440px;height:900px;background:{bg}">{menu}<div class="desk">{icons}{win}</div></body></html>', (1440, 900)
    return f'<html><head><style>{CSS}</style></head><body style="background:transparent">{win}</body></html>', None

def chat(name, msgs):
    rows = "".join(f'<div class="bub {"me" if m else "them"}">{H.escape(t)}</div>' for m, t in msgs)
    return (f'<div style="text-align:center;margin-bottom:10px"><div style="width:44px;height:44px;border-radius:22px;background:#bbb;margin:0 auto"></div>'
            f'<div style="font-size:12px">{name}</div></div><div style="display:flex;flex-direction:column">{rows}</div>')

C = []
def case(id, must, ideal, page, size=None, **kw):
    C.append(dict(id=id, must=must, ideal=ideal, page=page, size=size))

def full(id, must, ideal, app, win):
    page, size = screen(app, win)
    case(id, must, ideal, page, size)

def only(id, must, ideal, win, w, h):
    page = f'<html><head><style>{CSS}</style></head><body style="width:{w}px;height:{h}px;background:#fff">{win}</body></html>'
    case(id, must, ideal, page, (w, h))

HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, 'tuned.py' if SET == 'tuned' else 'held.py')).read())

meta = []
for c in C:
    p = os.path.join(OUT, c["id"] + ".html"); open(p, "w").write(c["page"])
    w, h = c["size"]
    png = os.path.join(OUT, f"Screenshot 2026-11-{10 + len(meta) % 18:02d} at {9 + len(meta) % 12}.{len(meta) % 60:02d}.{(len(meta) * 7) % 60:02d}.png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
                    f"--screenshot={png}", f"--window-size={w},{h}", "file://" + p], capture_output=True)
    os.remove(p)
    meta.append(dict(id=c["id"], file=os.path.basename(png), must=c["must"], ideal=c["ideal"]))
json.dump(meta, open(os.path.join(OUT, "cases.json"), "w"), indent=1)
print(len(meta), "screenshots")
