"""Иконка заставки/вступления темы «Рентген»: иконка 176 pt, скругление 40, свечение accent 25 %.

Холст с запасом под свечение: 240 pt (иконка по центру). Запуск:

    upstream/venv-tools/bin/python -I tools/branding/make_launch.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "branding" / "xraygram-icon-1024.png"
OUT = ROOT / "branding" / "launch"
ICON_PT, RADIUS_PT, CANVAS_PT = 176, 40, 240
ACCENT = (62, 242, 200)


def render(scale: int) -> Image.Image:
    icon_px, r_px, canvas_px = ICON_PT * scale, RADIUS_PT * scale, CANVAS_PT * scale
    off = (canvas_px - icon_px) // 2
    out = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))

    # свечение: размытая заливка accent 25 %
    glow = Image.new("RGBA", out.size, ACCENT + (0,))
    ga = Image.new("L", out.size, 0)
    ImageDraw.Draw(ga).rounded_rectangle([off, off, off + icon_px, off + icon_px], radius=r_px, fill=int(255 * 0.25))
    ga = ga.filter(ImageFilter.GaussianBlur(14 * scale))
    glow.putalpha(ga)
    out.alpha_composite(glow)

    icon = Image.open(SRC).convert("RGBA").resize((icon_px, icon_px), Image.LANCZOS)
    m = Image.new("L", (icon_px * 4, icon_px * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, icon_px * 4 - 1, icon_px * 4 - 1], radius=r_px * 4, fill=255)
    icon.putalpha(m.resize((icon_px, icon_px), Image.LANCZOS))
    out.alpha_composite(icon, (off, off))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for scale in (1, 2, 3):
        render(scale).save(OUT / f"LaunchIcon{'' if scale == 1 else f'@{scale}x'}.png", optimize=True)
    # Android splash: тот же рисунок, xxxhdpi-холст 240 dp → 960 px
    render(4).save(OUT / "android-splash-xxxhdpi.png", optimize=True)


if __name__ == "__main__":
    main()
