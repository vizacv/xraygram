"""Собирает иконки Xraygram из исходника branding/source/xraygram-xray-chatgpt.webp («рентген обезьянки»).

Запуск (из корня репо): upstream/venv-tools/bin/python -I tools/branding/make_icons.py

Исходник — уже готовая иконка, но со скруглёнными углами на чёрном фоне и содержимым у самых краёв.
Скрипт:
  1. Заливает чёрные углы фоном (продолжает соседние пиксели) → квадрат без скругления (скругляет ОС).
  2. Для круглых масок (Android) уменьшает картинку и подкладывает под неё размытое продолжение фона,
     чтобы кончик самолётика и рука не обрезались.
  3. Экспортирует наборы для iOS, macOS и Android в branding/.
(Первая версия иконки — обезьянка с самолётиком — в git-истории и в branding/source/xraygram-mockup.jpg.)
"""
from pathlib import Path
import shutil
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "branding/source/xraygram-xray-chatgpt.webp"
OUT = ROOT / "branding"


def corner_mask(rgb):
    """Тёмные пиксели, связанные с краем картинки (углы и рамка), — не путать со зрачками."""
    dark = rgb.sum(axis=2) < 90
    h, w = dark.shape
    mask = np.zeros_like(dark)
    stack = [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)] + \
            [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
    while stack:
        y, x = stack.pop()
        if y < 0 or x < 0 or y >= h or x >= w or mask[y, x] or not dark[y, x]:
            continue
        mask[y, x] = True
        stack.extend(((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))
    # захватить сглаженный край скругления
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))
    return np.asarray(m) > 0


def fill_corners(img):
    """Заливает углы, продолжая соседние пиксели фона (диффузия от края), потом слегка размывает заливку."""
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    hole = corner_mask(rgb)
    col = rgb.copy()
    known = ~hole
    col[hole] = 0
    shifts = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))
    for _ in range(600):
        if known.all():
            break
        k = known.astype(np.float32)
        s = sum(np.roll(np.roll(col * k[..., None], dy, 0), dx, 1) for dy, dx in shifts)
        c = sum(np.roll(np.roll(k, dy, 0), dx, 1) for dy, dx in shifts)
        new = (c > 0) & ~known
        col[new] = s[new] / c[new][:, None]
        known = known | new
    res = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    blur = res.filter(ImageFilter.GaussianBlur(18))
    m = Image.fromarray((hole * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))
    return Image.composite(blur, res, m)


def padded(square, size, scale):
    """Картинка уменьшена до scale, вокруг — размытое продолжение фона, край растушёван."""
    bg = square.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(size / 25))
    s = round(size * scale)
    fg = square.resize((s, s), Image.LANCZOS)
    feather = Image.new("L", (s, s), 0)
    pad = max(2, s // 14)
    ImageDraw.Draw(feather).rectangle((pad, pad, s - pad, s - pad), fill=255)
    feather = feather.filter(ImageFilter.GaussianBlur(pad))
    bg.paste(fg, ((size - s) // 2, (size - s) // 2), feather)
    return bg


def rounded_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((inset, inset, size - 1 - inset, size - 1 - inset), radius, fill=255)
    return m


def circle_mask(size):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size - 1, size - 1), fill=255)
    return m


def main():
    square = fill_corners(Image.open(SRC)).resize((1024, 1024), Image.LANCZOS)
    OUT.mkdir(exist_ok=True)
    for old in ("xraygram-character.png",):
        (OUT / old).unlink(missing_ok=True)

    # Мастер: квадрат без скруглений, без прозрачности.
    square.save(OUT / "xraygram-icon-1024.png")
    # Для круглых масок: уменьшенный, с фоном вокруг.
    round_safe = padded(square, 1024, 0.86)
    round_safe.save(OUT / "xraygram-icon-1024-roundsafe.png")

    # iOS: квадрат, ОС сама скругляет углы (как было на исходнике).
    ios = OUT / "ios"; ios.mkdir(exist_ok=True)
    square.save(ios / "AppIcon-1024.png")

    # macOS: скруглённый квадрат по сетке Apple (824 в 1024) с тенью → .icns
    mac = OUT / "macos"; mac.mkdir(exist_ok=True)
    body = square.resize((824, 824), Image.LANCZOS).convert("RGBA")
    body.putalpha(rounded_mask(824, 0, 185))
    mac_img = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow.putalpha(rounded_mask(1024, 100, 185).filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.35)))
    mac_img.alpha_composite(shadow, (0, 10))
    mac_img.alpha_composite(body, (100, 100))
    mac_img.save(mac / "xraygram-macos-1024.png")
    iconset = mac / "Xraygram.iconset"
    shutil.rmtree(iconset, ignore_errors=True); iconset.mkdir()
    for s in (16, 32, 128, 256, 512):
        mac_img.resize((s, s), Image.LANCZOS).save(iconset / f"icon_{s}x{s}.png")
        mac_img.resize((s * 2, s * 2), Image.LANCZOS).save(iconset / f"icon_{s}x{s}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(mac / "Xraygram.icns")], check=True)
    shutil.rmtree(iconset)

    # Android: адаптивная иконка. Слой 108dp (432 px), видимая часть 72dp (288 px) в центре, ОС режет кругом/сквиркл.
    # Фон — размытое продолжение, передний план — вся картинка в видимой зоне (с растушёвкой), круг её не режет.
    an = OUT / "android"; an.mkdir(exist_ok=True)
    # Всё в фоновом слое (бесшовно), передний план прозрачный: круг/сквиркл ОС режут только размытый фон.
    bgl = padded(square, 432, 288 * 0.86 / 432)
    bgl.save(an / "ic_launcher_background.png")
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    fg.save(an / "ic_launcher_foreground.png")
    for name, sz in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        d = an / f"mipmap-{name}"; d.mkdir(exist_ok=True)
        sq = round_safe.resize((sz, sz), Image.LANCZOS).convert("RGBA")
        rr = sq.copy(); rr.putalpha(rounded_mask(sz, 0, round(sz * 0.18))); rr.save(d / "ic_launcher.png")
        rd = sq.copy(); rd.putalpha(circle_mask(sz)); rd.save(d / "ic_launcher_round.png")
    square.resize((512, 512), Image.LANCZOS).save(an / "play-store-512.png")

    # Превью: iOS-маска, macOS, круг Android (адаптивная: фон + передний план, видимая зона).
    prev = Image.new("RGBA", (1024 * 3 + 80, 1024 + 40), (240, 242, 245, 255))
    a = square.convert("RGBA"); a.putalpha(rounded_mask(1024, 0, 225)); prev.alpha_composite(a, (20, 20))
    prev.alpha_composite(mac_img, (1024 + 40, 20))
    adaptive = bgl.convert("RGBA"); adaptive.alpha_composite(fg)
    vis = adaptive.crop((72, 72, 360, 360)).resize((1024, 1024), Image.LANCZOS)
    vis.putalpha(circle_mask(1024)); prev.alpha_composite(vis, (2 * 1024 + 60, 20))
    prev.convert("RGB").resize((prev.width // 2, prev.height // 2), Image.LANCZOS).save(OUT / "preview.png")
    print("ok")


if __name__ == "__main__":
    main()
