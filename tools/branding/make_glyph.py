"""Монохромный знак Xraygram: голова обезьянки в гарнитуре (силуэт по иконке).

Для мест, где нужен одноцветный знак: значок уведомлений Android, monochrome-слой адаптивной иконки,
шаблонная иконка меню-бара macOS, CallKit iOS, центр QR. Запуск:

    upstream/venv-tools/bin/python -I tools/branding/make_glyph.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "branding" / "glyph"
S = 2048  # рабочее разрешение; сетка 24×24
U = S / 24


def box(x0, y0, x1, y1):
    return [x0 * U, y0 * U, x1 * U, y1 * U]


def circle(cx, cy, r):
    return box(cx - r, cy - r, cx + r, cy + r)


def alpha_mask(detail: bool = True) -> Image.Image:
    a = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(a)
    # дужка наушников
    d.arc(box(4.4, 3.6, 19.6, 18.8), 180, 360, fill=255, width=int(1.7 * U))
    # голова
    d.ellipse(circle(12, 12.9, 6.6), fill=255)
    # чашки наушников
    d.rounded_rectangle(box(2.2, 10.0, 6.3, 16.6), radius=1.7 * U, fill=255)
    d.rounded_rectangle(box(17.7, 10.0, 21.8, 16.6), radius=1.7 * U, fill=255)
    # хохолок
    d.polygon([(x * U, y * U) for x, y in
               [(10.9, 6.6), (11.6, 4.3), (13.1, 3.4), (12.7, 4.9), (14.6, 4.3), (13.7, 6.7)]], fill=255)
    # лицевая маска — вырез
    d.ellipse(box(8.1, 12.4, 15.9, 18.0), fill=0)
    d.ellipse(circle(9.7, 11.6, 2.35), fill=0)
    d.ellipse(circle(14.3, 11.6, 2.35), fill=0)
    # глаза
    d.ellipse(circle(9.9, 11.9, 1.05), fill=255)
    d.ellipse(circle(14.1, 11.9, 1.05), fill=255)
    # ноздри (мелкие — не для значков ~22 px)
    if detail:
        d.ellipse(circle(11.35, 14.1, 0.38), fill=255)
        d.ellipse(circle(12.65, 14.1, 0.38), fill=255)
    # улыбка (открытый рот)
    d.pieslice(box(10.0, 14.2, 14.0, 17.4), 0, 180, fill=255)
    return a


def colored(a: Image.Image, rgb) -> Image.Image:
    img = Image.new("RGBA", a.size, rgb + (0,))
    img.putalpha(a)
    return img


def fit(img: Image.Image, canvas: int, glyph: int) -> Image.Image:
    g = img.resize((glyph, glyph), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    off = (canvas - glyph) // 2
    out.alpha_composite(g, (off, off))
    return out


def save(img, rel):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p, optimize=True)


def main():
    a = alpha_mask()
    white = colored(a, (255, 255, 255))
    black = colored(a, (0, 0, 0))

    save(white.resize((1024, 1024), Image.LANCZOS), "xraygram-glyph-white-1024.png")
    save(black.resize((1024, 1024), Image.LANCZOS), "xraygram-glyph-black-1024.png")

    # Android: значок в шторке (24 dp, белый на прозрачном), по плотностям
    for name, px in {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}.items():
        save(fit(white, px, round(px * 22 / 24)), f"android/drawable-{name}/ic_stat_xraygram.png")
    # Android: monochrome-слой адаптивной иконки (108 dp → 432 px, знак в безопасной зоне ~66 dp)
    save(fit(white, 432, 264), "android/ic_launcher_monochrome.png")

    # iOS: CallKit (iconTemplateImageData, 40 pt) — важна только альфа
    for scale in (1, 2, 3):
        save(fit(white, 40 * scale, 36 * scale), f"ios/CallKitIcon{'' if scale == 1 else f'@{scale}x'}.png")

    # macOS: шаблон для меню-бара/трея (18 pt), чёрный + альфа, суффикс Template
    for scale in (1, 2):
        save(fit(black, 18 * scale, 18 * scale), f"macos/XraygramTemplate{'' if scale == 1 else '@2x'}.png")

    # macOS: иконка трея tdesktop (альфа-маска, перекрашивается под строку меню), 22/44/66 px, без ноздрей
    simple = colored(alpha_mask(detail=False), (0, 0, 0))
    for scale in (1, 2, 3):
        p = ROOT / "branding" / "macos" / "tray" / f"mac_tray_icon{'' if scale == 1 else f'@{scale}x'}.png"
        p.parent.mkdir(parents=True, exist_ok=True)
        fit(simple, 22 * scale, 20 * scale).save(p, optimize=True)

    # превью: знак на фоне темы «Рентген» и на светлом
    prev = Image.new("RGBA", (720, 260), (11, 18, 32, 255))
    acc = colored(a, (62, 242, 200)).resize((200, 200), Image.LANCZOS)
    prev.alpha_composite(acc, (30, 30))
    for i, px in enumerate((96, 48, 24)):
        prev.alpha_composite(white.resize((px, px), Image.LANCZOS), (270 + i * 110, 130 - px // 2))
    light = Image.new("RGBA", (180, 200), (243, 245, 247, 255))
    light.alpha_composite(black.resize((140, 140), Image.LANCZOS), (20, 30))
    prev.alpha_composite(light, (520, 30))
    save(prev, "preview.png")


if __name__ == "__main__":
    main()
