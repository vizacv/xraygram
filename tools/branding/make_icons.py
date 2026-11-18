"""Собирает иконки Xraygram из макета branding/source/xraygram-mockup.jpg.

Запуск (из корня репо): upstream/venv-tools/bin/python -I tools/branding/make_icons.py

Что делает:
  1. Вырезает «персонажа» (кольцо + обезьяна + самолётик) с макета: убирает белые поля,
     надписи XRAYGRAM / TELEGRAM FORK + XRAY CORE и фон квадрата.
  2. Кладёт его на чистый фон (тот же сине-голубой градиент) так, чтобы самолётик не вылезал
     за край: иконки обрезаются маской ОС.
  3. Экспортирует наборы для iOS, macOS и Android в branding/.
"""
from pathlib import Path
import subprocess
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "branding/source/xraygram-mockup.jpg"
OUT = ROOT / "branding"

# Геометрия макета (найдена по кольцу, см. историю в docs): центр и радиус кольца.
CX, CY, R_RING = 696.6, 323.7, 187.5
R_DISK = R_RING + 11          # внешний край белого кольца
TEXT_TOP = 512                # ниже этой линии внутри квадрата — только надписи


def load():
    return np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32)


def margin_mask(im):
    """Белые поля и тень вокруг квадрата: заливка от краёв по светлым серо-белым пикселям."""
    h, w, _ = im.shape
    light = im.min(axis=2) > 175
    sat = im.max(axis=2) - im.min(axis=2)
    cand = light & (sat < 60)
    mask = np.zeros((h, w), bool)
    stack = [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]
    while stack:
        y, x = stack.pop()
        if y < 0 or x < 0 or y >= h or x >= w or mask[y, x] or not cand[y, x]:
            continue
        mask[y, x] = True
        stack.extend(((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))
    return mask


def fit_background(im, margin):
    """Фон квадрата — плоскость по x, y на каждый канал (по заведомо фоновым полосам)."""
    h, w, _ = im.shape
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx - CX, yy - CY)
    strip = (~margin) & (d > R_DISK + 25) & (yy > 140) & (yy < TEXT_TOP - 10) & (
        ((xx > 440) & (xx < 495)) | ((xx > 905) & (xx < 970)))
    # без рук/самолётика: берём только «синие» пиксели
    blue = (im[..., 2] > im[..., 0] + 80)
    s = strip & blue
    A = np.c_[xx[s], yy[s], np.ones(s.sum())]
    coef = [np.linalg.lstsq(A, im[..., c][s], rcond=None)[0] for c in range(3)]
    return coef


def bg_at(coef, xx, yy):
    return np.stack([c[0] * xx + c[1] * yy + c[2] for c in coef], axis=-1)


def extract_character(im):
    h, w, _ = im.shape
    margin = margin_mask(im)
    coef = fit_background(im, margin)
    yy, xx = np.mgrid[0:h, 0:w]
    bg = bg_at(coef, xx, yy)
    dist = np.abs(im - bg).sum(axis=2)
    d = np.hypot(xx - CX, yy - CY)

    disk = d <= R_DISK
    # край старого квадрата (сглаженная рамка) — не персонаж: отступаем от полей на 18 px,
    # кроме зоны самолётика справа сверху, который выходил за рамку.
    near_margin = np.asarray(Image.fromarray((margin * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(37))) > 0
    plane_zone = (xx > 860) & (yy < 330)
    inside_sq = ~margin & (~near_margin | plane_zone)
    fg = disk | (inside_sq & (dist > 70) & (yy < TEXT_TOP))
    # убрать мелкий мусор и сгладить край
    alpha = Image.fromarray((fg * 255).astype(np.uint8))
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    rgba = Image.fromarray(im.astype(np.uint8)).convert("RGBA")
    rgba.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 20 else 0).getbbox()
    return rgba.crop(bbox), coef


def gradient(size, coef, src_box=(430, 108, 985, 663)):
    """Тот же градиент, что на макете, растянутый на квадрат size×size."""
    x0, y0, x1, y1 = src_box
    t = np.linspace(0, 1, size)
    xx = x0 + t[None, :] * (x1 - x0)
    yy = y0 + t[:, None] * (y1 - y0)
    xx, yy = np.broadcast_arrays(xx, yy)
    rgb = np.clip(bg_at(coef, xx, yy), 0, 255).astype(np.uint8)
    return Image.fromarray(rgb, "RGB").convert("RGBA")


def compose(char, coef, size=1024, content=0.84, transparent_bg=False):
    """Персонаж по центру: самая длинная сторона = content * size."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0)) if transparent_bg else gradient(size, coef)
    cw, ch = char.size
    k = content * size / max(cw, ch)
    c = char.resize((round(cw * k), round(ch * k)), Image.LANCZOS)
    canvas.alpha_composite(c, ((size - c.width) // 2, (size - c.height) // 2))
    return canvas


def squircle_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((inset, inset, size - inset, size - inset), radius, fill=255)
    return m


def main():
    im = load()
    char, coef = extract_character(im)
    OUT.mkdir(exist_ok=True)
    char.save(OUT / "xraygram-character.png")

    # Мастер: квадрат без скруглений и без прозрачности (iOS/Android скругляют сами).
    master = compose(char, coef, 1024, 0.76)
    master.convert("RGB").save(OUT / "xraygram-icon-1024.png")

    # iOS: AppIcon 1024, без альфы.
    ios = OUT / "ios"; ios.mkdir(exist_ok=True)
    master.convert("RGB").save(ios / "AppIcon-1024.png")

    # macOS: скруглённый квадрат с полями по сетке Apple (824 в 1024, радиус ~185) → .icns
    mac = OUT / "macos"; mac.mkdir(exist_ok=True)
    body = compose(char, coef, 824, 0.80)
    mac_img = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    sm = squircle_mask(1024, 100, 185).filter(ImageFilter.GaussianBlur(14))
    shadow.putalpha(sm.point(lambda v: v * 0.35))
    mac_img.alpha_composite(shadow, (0, 10))
    body.putalpha(squircle_mask(824, 0, 185))
    mac_img.alpha_composite(body, (100, 100))
    mac_img.save(mac / "xraygram-macos-1024.png")
    iconset = mac / "Xraygram.iconset"
    shutil.rmtree(iconset, ignore_errors=True); iconset.mkdir()
    for s in (16, 32, 128, 256, 512):
        mac_img.resize((s, s), Image.LANCZOS).save(iconset / f"icon_{s}x{s}.png")
        mac_img.resize((s * 2, s * 2), Image.LANCZOS).save(iconset / f"icon_{s}x{s}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(mac / "Xraygram.icns")], check=True)
    shutil.rmtree(iconset)

    # Android: адаптивная иконка (фон + передний план 432, безопасная зона 66%) и старые mipmap.
    an = OUT / "android"; an.mkdir(exist_ok=True)
    gradient(432, coef).convert("RGB").save(an / "ic_launcher_background.png")
    compose(char, coef, 432, 0.62, transparent_bg=True).save(an / "ic_launcher_foreground.png")
    legacy = compose(char, coef, 1024, 0.76)
    for name, s in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        d = an / f"mipmap-{name}"; d.mkdir(exist_ok=True)
        sq = legacy.resize((s, s), Image.LANCZOS)
        rr = sq.copy(); rr.putalpha(squircle_mask(s, 0, round(s * 0.18)))
        rr.save(d / "ic_launcher.png")
        rd = sq.copy(); m = Image.new("L", (s, s), 0); ImageDraw.Draw(m).ellipse((0, 0, s - 1, s - 1), fill=255)
        rd.putalpha(m); rd.save(d / "ic_launcher_round.png")
    legacy.convert("RGB").resize((512, 512), Image.LANCZOS).save(an / "play-store-512.png")

    # Превью для глаз: как будет выглядеть с масками.
    prev = Image.new("RGBA", (1024 * 3 + 80, 1024 + 40), (240, 242, 245, 255))
    a = master.copy(); a.putalpha(squircle_mask(1024, 0, 225)); prev.alpha_composite(a, (20, 20))
    prev.alpha_composite(mac_img, (1024 + 40, 20))
    c = master.copy(); m = Image.new("L", (1024, 1024), 0); ImageDraw.Draw(m).ellipse((0, 0, 1023, 1023), fill=255)
    c.putalpha(m); prev.alpha_composite(c, (2 * 1024 + 60, 20))
    prev.convert("RGB").resize((prev.width // 2, prev.height // 2), Image.LANCZOS).save(OUT / "preview.png")
    print("ok")


if __name__ == "__main__":
    main()
