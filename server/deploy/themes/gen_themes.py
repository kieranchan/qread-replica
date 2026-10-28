# Builds the colour themes published on the owner's theme plaza (主题广场): for every entry a theme package (zip with
# `theme.json`, the replica's ThemeModel) and a preview PNG drawn from the theme's own colours. The original's plaza themes live
# on its service and are not used. Run with the project venv (Pillow):
#   tools\venv\Scripts\python.exe -I server\deploy\themes\gen_themes.py <out_dir>
# then upload with `qread-admin add-theme --id <id> --name <title> --mode day|night --category 复刻配色 --zip <id>.zip --image <id>.png`
# (`publish.sh` in this folder does that over SSH).
import json
import os
import sys
import time
import zipfile

from PIL import Image, ImageDraw, ImageFont

# id, title, description, day?, seed, page background, tab bar, selected, text, card
THEMES = [
    ('rep-day-bamboo', '青竹', '清爽的竹青色，护眼的浅绿底', True, '#4E7D4E', '#F4F7F1', '#EAF0E6', '#4E7D4E', '#1F2A1F', '#FFFFFF'),
    ('rep-day-sea', '海盐', '海盐蓝配浅灰白，干净利落', True, '#3B6EA5', '#F3F6FA', '#E7EEF6', '#3B6EA5', '#1C2633', '#FFFFFF'),
    ('rep-day-sun', '暖阳', '暖橙色，适合午后阅读', True, '#C46A2B', '#FBF6F0', '#F4EADF', '#C46A2B', '#2E2117', '#FFFDFA'),
    ('rep-day-sakura', '樱粉', '柔和的樱花粉', True, '#C2577A', '#FBF4F6', '#F4E6EB', '#C2577A', '#2E1C22', '#FFFFFF'),
    ('rep-day-parchment', '羊皮纸', '复古纸张的米黄与棕', True, '#8B6B3E', '#F6EFE1', '#EEE3CE', '#8B6B3E', '#2B2418', '#FBF7EE'),
    ('rep-day-lavender', '薰衣草', '淡紫色，安静温和', True, '#7A5BA8', '#F6F3FA', '#ECE5F5', '#7A5BA8', '#241C2E', '#FFFFFF'),
    ('rep-night-dusk', '夜幕', '深蓝夜色，夜间阅读不刺眼', False, '#7FA7D9', '#12161C', '#1A2029', '#7FA7D9', '#E3E8EF', '#1B222C'),
    ('rep-night-forest', '深林', '墨绿夜色', False, '#7FB77E', '#111612', '#19211A', '#7FB77E', '#E1EAE0', '#1A231B'),
    ('rep-night-charcoal', '炭黑', '纯粹的深灰黑', False, '#C9C9C9', '#121212', '#1C1C1C', '#E0E0E0', '#E6E6E6', '#1E1E1E'),
    ('rep-night-nebula', '星紫', '深紫夜色', False, '#B39DDB', '#15121C', '#1F1A29', '#B39DDB', '#E8E3F0', '#211B2C'),
]

FONT = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'app', 'lib', 'util', 'epub', 'assets', 'dist', 'NotoSansSC-Regular.ttf')


def argb(hex_rgb):
    return int('FF' + hex_rgb.lstrip('#'), 16)


def rgb(hex_rgb):
    h = hex_rgb.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def theme_json(t, now):
    tid, title, desc, day, seed, bg, tab, sel, text, card = t
    return {
        'id': tid,
        'version': '1.0.0',
        'title': title,
        'description': desc,
        'icon': '',
        'author': '轻悦复刻',
        'contact': '',
        'isLightMode': day,
        'navFont': '',
        'titleFont': '',
        'regularFont': '',
        'defaultCover': '',
        'useDefaultCoverForAll': False,
        'startupScreen': '',
        'regularStyle': {'backgroundImage': '', 'backgroundColor': argb(bg), 'tableOpacity': 0, 'showboxShadow': day},
        'styles': [],
        'unselectedTabIcons': [],
        'selectedTabIcons': [],
        'showTitleWhenSelected': True,
        'showTitleWhenUnselected': True,
        'tabBarColor': argb(tab),
        'tabBarSelectedColor': argb(sel),
        'textColor': argb(text),
        'colorScheme': json.dumps({'seedColor': seed, 'primary': sel, 'surface': bg}, ensure_ascii=False),
        'createdAt': now,
        'updatedAt': now,
    }


def preview(t, path):
    tid, title, desc, day, seed, bg, tab, sel, text, card = t
    w, h = 540, 1170
    im = Image.new('RGB', (w, h), rgb(bg))
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype(FONT, 44)
    small = ImageFont.truetype(FONT, 26)
    d.text((40, 90), '书架', font=big, fill=rgb(text))
    # book covers
    for i in range(3):
        x = 40 + i * 160
        d.rounded_rectangle((x, 190, x + 140, 390), 14, fill=rgb(card), outline=rgb(tab), width=2)
        d.rectangle((x + 20, 220, x + 120, 236), fill=rgb(sel))
        d.rectangle((x + 20, 252, x + 100, 262), fill=rgb(tab))
        d.text((x, 400), ['星河旅人', '山城旧事', '夜航'][i], font=small, fill=rgb(text))
    # list cards
    for i in range(3):
        y = 480 + i * 130
        d.rounded_rectangle((40, y, w - 40, y + 110), 18, fill=rgb(card))
        d.ellipse((64, y + 30, 114, y + 80), fill=rgb(sel))
        d.rectangle((140, y + 34, 380, y + 50), fill=rgb(text))
        d.rectangle((140, y + 64, 300, y + 74), fill=rgb(tab))
    # tab bar
    d.rectangle((0, h - 150, w, h), fill=rgb(tab))
    for i, label in enumerate(['书架', '发现', '探索', '我的']):
        cx = 68 + i * 135
        on = i == 0
        if on:
            d.rounded_rectangle((cx - 44, h - 128, cx + 44, h - 84), 22, fill=rgb(sel))
        d.ellipse((cx - 14, h - 120, cx + 14, h - 92), fill=rgb(bg if on else text))
        d.text((cx - 26, h - 74), label, font=small, fill=rgb(sel if on else text))
    d.text((40, h - 210), f'{title} · {"白天" if day else "夜间"}', font=small, fill=rgb(sel))
    im.save(path, optimize=True)


def main(out):
    os.makedirs(out, exist_ok=True)
    now = int(time.time() * 1000)
    rows = []
    for t in THEMES:
        tid = t[0]
        png = os.path.join(out, f'{tid}.png')
        preview(t, png)
        z = os.path.join(out, f'{tid}.zip')
        with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.writestr('theme.json', json.dumps(theme_json(t, now), ensure_ascii=False, indent=2))
        rows.append({'id': tid, 'title': t[1], 'desc': t[2], 'mode': 'day' if t[3] else 'night'})
    with open(os.path.join(out, 'themes.json'), 'w', encoding='utf-8') as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
    print(len(rows), 'themes ->', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'themes-out')
