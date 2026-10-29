# phone/phone.py — drives the replica on the owner's iPhone over USB (see app/README.md, "Testing on the owner's iPhone").
#
# Needs: the phone on USB and trusted, the replica sideloaded (get-task-allow), pymobiledevice3 in `tools/idevice-venv`
# (`python -m venv tools/idevice-venv; tools/idevice-venv/Scripts/pip install pymobiledevice3`). Run it with that venv's python;
# from Git Bash prefix `MSYS_NO_PATHCONV=1` (else `/tap` becomes `E:/Git/tap`). Screenshots need the developer disk image once per
# phone boot: `tools/idevice-venv/Scripts/pymobiledevice3 mounter auto-mount` (retry if cryptexd times out).
#
#   phone.py shot <file.png>       screenshot (1320x2868 on the owner's phone = 3x the logical 440x956)
#   phone.py list                  accessibility elements of the foreground app (caption | spoken description)
#   phone.py press <text> [n]      accessibility press: native iOS controls only, Flutter buttons ignore it
# QA driver (app/lib/dev/qa_driver.dart, off unless switched on here; coordinates in logical pixels):
#   phone.py qa-on | qa-off        pushes / removes <documents>/.qa_driver with a fresh token and relaunches the app
#   phone.py texts                 visible texts (hit-testable ones) with their centres
#   phone.py sem                   semantics labels (buttons, icons) with their centres; [tap] = tappable
#   phone.py tapt <text> [n]       taps the n-th visible text containing <text>;  taps <label> [n]: same for semantics labels
#                                  (first match wins: 「设置」 also matches 「亮度设置」, use coordinates when in doubt)
#   phone.py d <path> [k=v ...]    raw request: d /size | d /tap x= y= | d /long x= y= ms= | d /drag x1= y1= x2= y2= ms= |
#                                  d /type s=斩神 (replaces the focused field) | d /submit | d /back
# Switch the driver off (qa-off) when done. QREAD_BUNDLE overrides the bundle id (Sideloadly adds a team suffix).
#
# Installing a new CI build without Sideloadly's window (2026-10-29): Sideloadly keeps the free developer certificate and its key in
# %APPDATA%\sideloadly (cert-<apple id>.pem, key.pem) and the phone holds the matching 7-day profile; re-sign the unsigned IPA with
# zsign (tools/zsign/zsign.exe, GitHub release v1.1.3, sha256 checked) and install it as an upgrade (data stays):
#   tools/zsign/zsign.exe -k %APPDATA%/sideloadly/key.pem -c %APPDATA%/sideloadly/cert-*.pem -m <profile>.mobileprovision #       -b com.kieranchan.qreadreplica.newread.3L3D6T66V5 -z 6 -o signed.ipa newread-unsigned.ipa
#   pymobiledevice3 provision dump <dir>        # the profile: newest CreationDate for the app id above (expires after 7 days)
#   pymobiledevice3 apps install signed.ipa    # "Installation succeed."; the app's container is kept
# When the profile has expired, one Sideloadly run by the owner refreshes it (and the key stays the same).
import asyncio
import json
import os
import secrets
import subprocess
import sys
import tempfile
import urllib.parse

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit

sys.stdout.reconfigure(encoding="utf-8")


async def elements():
    lockdown = await create_using_usbmux() if asyncio.iscoroutinefunction(create_using_usbmux) else create_using_usbmux()
    async with AccessibilityAudit(lockdown) as ax:
        out = []
        async for e in ax.iter_elements():
            out.append(e)
            if len(out) > 200:
                break
        return lockdown, out


async def cmd_list():
    _, els = await elements()
    for i, e in enumerate(els):
        print(f"{i:3d}  {e.caption or ''}  |  {e.spoken_description or ''}")


async def cmd_press(text, n=1):
    lockdown = await create_using_usbmux() if asyncio.iscoroutinefunction(create_using_usbmux) else create_using_usbmux()
    async with AccessibilityAudit(lockdown) as ax:
        hits = 0
        async for e in ax.iter_elements():
            label = f"{e.caption or ''} {e.spoken_description or ''}"
            if text in label:
                hits += 1
                if hits == n:
                    await ax.perform_press(e.element.identifier)
                    # the press is sent without a reply: closing the service right away can drop it
                    await asyncio.sleep(1.5)
                    print("pressed:", label.strip())
                    return
        print("not found:", text)


def cmd_shot(path):
    exe = sys.executable.replace("python.exe", "pymobiledevice3.exe")
    r = subprocess.run([exe, "developer", "dvt", "screenshot", path], capture_output=True, text=True, encoding="utf-8")
    print("ok" if r.returncode == 0 else r.stderr[-400:])


BUNDLE = os.environ.get("QREAD_BUNDLE", "com.kieranchan.qreadreplica.newread.3L3D6T66V5")
# the token stays in the git-ignored tools/ folder
TOKEN_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", ".qa_token")
CLI = sys.executable.replace("python.exe", "pymobiledevice3.exe")


def cli(*args):
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    return subprocess.run([CLI, *args], capture_output=True, text=True, encoding="utf-8", env=env)


def relaunch():
    r = cli("developer", "dvt", "launch", "--kill-existing", BUNDLE)
    print("relaunched" if r.returncode == 0 else r.stderr[-400:])


def qa_on():
    token = secrets.token_hex(16)
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt") as f:
        f.write(token + "\n")
    r = cli("apps", "push", BUNDLE, f.name, "/Documents/.qa_driver")
    os.unlink(f.name)
    if r.returncode != 0:
        print(r.stderr[-400:])
        return
    with open(TOKEN_FILE, "w") as f:
        f.write(token)
    relaunch()


def qa_off():
    r = cli("apps", "rm", BUNDLE, "/Documents/.qa_driver")
    print("removed" if r.returncode == 0 else r.stderr[-400:])
    if os.path.exists(TOKEN_FILE):
        os.unlink(TOKEN_FILE)
    relaunch()


async def request(path, params):
    from pymobiledevice3.usbmux import select_device
    with open(TOKEN_FILE) as f:
        params = dict(params, k=f.read().strip())
    dev = await select_device()
    sock = await dev.connect(8765)
    sock.setblocking(True)
    sock.settimeout(30)
    try:
        q = urllib.parse.urlencode(params)
        sock.sendall(f"GET {path}?{q} HTTP/1.0\r\nHost: localhost\r\n\r\n".encode())
        data = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    finally:
        sock.close()
    head, _, body = data.partition(b"\r\n\r\n")
    status = head.split(b"\r\n")[0].decode()
    if " 200 " not in status:
        raise SystemExit(status + " " + body.decode("utf-8", "replace"))
    return json.loads(body.decode("utf-8"))


def d(path, **params):
    return asyncio.run(request(path, params))


def centre(r):
    return (r[0] + r[2]) / 2, (r[1] + r[3]) / 2


def tap_match(items, key, text, n):
    hits = [i for i in items if text in i[key] and i.get("hit", True)]
    if len(hits) < n:
        print("not found:", text)
        return
    x, y = centre(hits[n - 1]["r"])
    d("/tap", x=x, y=y)
    print(f"tapped {hits[n - 1][key]!r} at {x:.0f},{y:.0f}")


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else "list"
    if c == "list":
        asyncio.run(cmd_list())
    elif c == "press":
        asyncio.run(cmd_press(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1))
    elif c == "shot":
        cmd_shot(sys.argv[2])
    elif c == "qa-on":
        qa_on()
    elif c == "qa-off":
        qa_off()
    elif c == "texts":
        for t in d("/texts"):
            if t["hit"]:
                x, y = centre(t["r"])
                print(f"{x:4.0f},{y:4.0f}  {t['t']}")
    elif c == "sem":
        for t in d("/sem"):
            x, y = centre(t["r"])
            print(f"{x:4.0f},{y:4.0f}  {'[tap] ' if t.get('tap') else ''}{t['l']}")
    elif c == "tapt":
        tap_match(d("/texts"), "t", sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    elif c == "taps":
        tap_match(d("/sem"), "l", sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    elif c == "d":
        print(json.dumps(d(sys.argv[2], **dict(a.split("=", 1) for a in sys.argv[3:])), ensure_ascii=False)[:4000])
