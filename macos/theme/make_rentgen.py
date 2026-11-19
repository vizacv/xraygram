#!/usr/bin/env python3
"""Тема «Рентген» для tdesktop (FEAT-20, PAR-22).

Берёт ночную тему upstream (Telegram/Resources/night.tdesktop-theme) и
перекрашивает её в токены branding/theme-rentgen.md:
  1. явные значения для ключей с ролью из FEAT-20 (таблица ROLES ниже);
  2. остальные цвета — общим правилом по HSL: тёмные нейтральные → шкала
     bg/surface/border, светлые нейтральные → text/text-2/text-3, синие
     акценты upstream → бирюзовый accent (тёмные синие → bubble-out),
     красные/оранжевые/зелёные/фиолетовые и прозрачности — как есть.

Пишет:
  macos/theme/rentgen.tdesktop-theme — zip: colors.tdesktop-theme +
      background.png (1×1 #0B1220: сплошной фон чата без узора);
  macos/theme/rentgen-roles.md — таблица «ключ → роль/правило → цвет».

  python3 macos/theme/make_rentgen.py [путь/к/night.tdesktop-theme]
"""
import colorsys
import io
import re
import struct
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_NIGHT = ROOT / "upstream/tdesktop/Telegram/Resources/night.tdesktop-theme"
OUT_THEME = ROOT / "macos/theme/rentgen.tdesktop-theme"
OUT_ROLES = ROOT / "macos/theme/rentgen-roles.md"

# Токены branding/theme-rentgen.md.
T = {
    "bg": "#0b1220",
    "surface": "#121b2e",
    "surface-2": "#18233a",
    "border": "#1c2840",
    "border-2": "#22304a",
    "separator": "#16213a",
    "text": "#e6f1ff",
    "text-2": "#8ea3bf",
    "text-3": "#5f7391",
    "accent": "#3ef2c8",
    "accent-over": "#6af6d4",  # между accent и accent-hi
    "accent-hi": "#8ffbe0",
    "on-accent": "#04211b",
    "bubble-out": "#10403a",
    "bubble-out-over": "#155247",
    "bubble-out-edge": "#3ef2c84d",  # rgba(62,242,200,.3)
    "bubble-out-time": "#7fd9c2",
    "warn": "#f2b33e",
    "error": "#ff6b6b",
}
AVATARS = ["#f28cb1", "#7fb2ff", "#3ef2c8", "#b49cff", "#f2b33e", "#8ee07a"]

# Ключ → токен (или "#hex"). Роли FEAT-20 п. 5.
ROLES = {
    # фон экранов, список чатов, фон чата
    "windowBg": "bg", "dialogsBg": "bg", "boxBg": "bg", "boxSearchBg": "bg",
    "lightButtonBg": "bg", "windowShadowFgFallback": "bg",
    "introCoverTopBg": "bg", "introCoverBottomBg": "bg",
    # шапки, панель ввода, поля, карточки, меню
    "topBarBg": "surface", "historyComposeAreaBg": "surface", "menuBg": "surface",
    "titleBg": "surface", "titleBgActive": "surface", "emojiPanBg": "surface",
    "emojiPanCategories": "surface", "filterInputInactiveBg": "surface",
    "filterInputBorderFg": "border-2", "historyPinnedBg": "surface",
    "historyComposeButtonBg": "surface", "tooltipBg": "surface-2",
    "tooltipBorderFg": "border-2", "historyToDownBg": "surface-2",
    "windowBgOver": "surface", "dialogsBgOver": "surface", "windowBgRipple": "surface-2",
    "dialogsRippleBg": "surface-2", "lightButtonBgOver": "surface",
    "lightButtonBgRipple": "surface-2", "menuBgRipple": "surface-2",
    # разделители и обводки
    "inputBorderFg": "border-2", "menuSeparatorFg": "separator",
    "historyUnreadBarBg": "surface",
    # пузыри
    "msgInBg": "surface-2", "msgOutBg": "bubble-out", "msgOutShadow": "bubble-out-edge",
    "msgInDateFg": "text-2", "msgOutDateFg": "bubble-out-time",
    "historyTextInFg": "text", "historyTextOutFg": "text",
    # текст
    "windowFg": "text", "windowBoldFg": "text", "windowBoldFgOver": "text",
    "windowFgOver": "text", "boxTitleFg": "text", "introTitleFg": "text",
    "dialogsNameFg": "text", "tooltipFg": "text",
    "windowSubTextFg": "text-2", "windowSubTextFgOver": "text-2",
    "dialogsTextFg": "text-2", "dialogsDateFg": "text-2", "boxTitleAdditionalFg": "text-2",
    "dialogsTextFgOver": "text-2", "dialogsDateFgOver": "text-2",
    "placeholderFg": "text-3", "placeholderFgActive": "text-3", "menuIconFg": "text-2",
    "menuFgDisabled": "text-3",
    # акцент: кнопки, ссылки, бейджи, «в сети», галочки, переключатели
    "windowBgActive": "accent", "windowActiveTextFg": "accent",
    "activeButtonBg": "accent", "activeButtonBgOver": "accent-over",
    "activeButtonBgRipple": "accent-hi", "activeButtonFg": "on-accent",
    "activeButtonFgOver": "on-accent", "activeButtonSecondaryFg": "#04211bb3",
    "activeLineFg": "accent", "lightButtonFg": "accent", "boxTextFgGood": "accent",
    "dialogsUnreadBg": "accent", "dialogsUnreadBgOver": "accent",
    "dialogsUnreadFg": "on-accent", "dialogsOnlineBadgeFg": "accent",
    "dialogsSentIconFg": "accent", "dialogsSentIconFgOver": "accent",
    "dialogsVerifiedIconBg": "accent", "dialogsVerifiedIconBgOver": "accent",
    "dialogsVerifiedIconFg": "bg", "dialogsTextFgService": "accent",
    "dialogsTextFgServiceOver": "accent",
    "historyOutIconFg": "accent", "historyLinkInFg": "accent", "historyLinkOutFg": "accent",
    "historyLinkInFgSelected": "accent-hi", "historyLinkOutFgSelected": "accent-hi",
    "msgInServiceFg": "accent", "msgOutServiceFg": "accent",
    "msgInReplyBarColor": "accent", "msgOutReplyBarColor": "accent",
    "profileVerifiedCheckFg": "on-accent", "overviewCheckFgActive": "on-accent",
    # выбранный чат: тёмно-бирюзовый, текст светлый
    "dialogsBgActive": "bubble-out", "dialogsRippleBgActive": "bubble-out-over",
    "dialogsNameFgActive": "text", "dialogsDateFgActive": "text",
    "dialogsTextFgActive": "text", "dialogsUnreadFgActive": "bubble-out",
    "dialogsOnlineBadgeFgActive": "text",
    # windowFgActive — текст на windowBgActive (accent); ссылки на него ниже
    # переопределены там, где фон не акцентный.
    "windowFgActive": "on-accent",
    "msgServiceFg": "text", "toastFg": "text", "historyForwardChooseFg": "text",
    "historyUnreadBarFg": "text",
    # предупреждения и ошибки
    "attentionButtonFg": "error", "attentionButtonFgOver": "error",
    "boxTextFgError": "error", "activeLineFgError": "error",
    "dialogsDraftFg": "error",
    # аватары-заглушки: 8 цветов upstream → 6 цветов темы, текст #0B1220
    "historyPeerUserpicFg": "bg",
    # ссылки на windowFgActive (теперь on-accent) поверх тёмных фонов
    "radialFg": "text", "titleButtonCloseFgOver": "text", "stickerPanDeleteFg": "text",
    "youtubePlayIconFg": "text", "mainMenuCoverFg": "text", "mediaviewMenuFg": "text",
    "mediaviewControlFg": "text", "callBarFg": "text",
    # иконки поверх акцентных заливок (файл, звонок)
    "historyFileInIconFg": "on-accent", "historyFileInIconFgSelected": "on-accent",
    "historyFileInRadialFg": "on-accent", "historyFileOutIconFg": "on-accent",
    "historyFileOutIconFgSelected": "on-accent", "historyFileOutRadialFg": "on-accent",
    "historyFileOutRadialFgSelected": "on-accent",
    "msgFile1Bg": "#1f8a73", "msgFile1BgDark": "#176b59", "msgFile1BgOver": "#1a7663",
    "callAnswerBg": "#20b890", "callAnswerRipple": "#3ef2c8",
}
# Ключи, которых нет в ночной теме (берутся из lib_ui/ui/colors.palette).
EXTRA = {
    "sideBarBadgeFg": "on-accent",
}
# Порядок upstream: 1 красный, 2 зелёный, 3 жёлтый, 4 синий, 5 фиолетовый,
# 6 розовый, 7 голубой, 8 оранжевый.
PEER_AVATAR = {1: 0, 2: 5, 3: 4, 4: 1, 5: 3, 6: 0, 7: 2, 8: 4}
for n, i in PEER_AVATAR.items():
    ROLES[f"historyPeer{n}UserpicBg"] = AVATARS[i]
    ROLES[f"historyPeer{n}UserpicBg2"] = AVATARS[i]


def parse(hexv):
    h = hexv.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    a = int(h[6:8], 16) if len(h) == 8 else None
    return r, g, b, a


def fmt(r, g, b, a=None):
    clamp = lambda x: max(0, min(255, int(round(x))))
    s = "#%02x%02x%02x" % (clamp(r), clamp(g), clamp(b))
    return s + ("%02x" % a if a is not None else "")


def from_hls(h, l, s, a):
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360.0, max(0, min(1, l)), max(0, min(1, s)))
    return fmt(r * 255, g * 255, b * 255, a)


def remap(hexv):
    """Общее правило для ключей без явной роли. Возвращает (цвет, правило)."""
    r, g, b, a = parse(hexv)
    if a == 0:
        return hexv, "прозрачный"
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    h *= 360
    if (r, g, b) in ((255, 255, 255), (0, 0, 0)):
        if (r, g, b) == (255, 255, 255) and a is None:
            return T["text"], "белый → text"
        return hexv, "чёрный/белый с прозрачностью"
    neutral = s < 0.12 or (s < 0.45 and 195 <= h <= 235 and l < 0.75 and not (l > 0.45 and s > 0.35))
    if neutral and l < 0.32:
        # 0.13 (#17212b) → bg, 0.24 (#313c49) → border-2
        nl = 0.085 + (l - 0.13) * (0.21 - 0.085) / (0.24 - 0.13)
        return from_hls(221, max(0.03, min(0.32, nl)), 0.45, a), "тёмный нейтральный → шкала bg…border"
    if neutral:
        if l >= 0.82:
            return from_hls(213, max(l, 0.92), 1.0, a), "светлый нейтральный → text"
        if l >= 0.52:
            return from_hls(215, l + 0.04, 0.29, a), "серый → text-2"
        return from_hls(215, l, 0.21, a), "тёмно-серый → text-3"
    if 190 <= h <= 240:
        if l < 0.45:
            return from_hls(168, l * 0.55, 0.6, a), "тёмный синий → bubble-out"
        return from_hls(166, 0.596 + (l - 0.6) * 0.6, 0.87, a), "синий акцент → accent"
    return hexv, "цветной (не синий) — как в upstream"


def main():
    night = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_NIGHT
    with zipfile.ZipFile(night) as z:
        source = z.read("colors.tdesktop-theme").decode("utf-8")

    line_re = re.compile(r"^(\s*)([A-Za-z0-9_]+)(\s*:\s*)([^;]+)(;.*)$")
    out_lines, rows = [], []
    for line in source.splitlines():
        m = line_re.match(line)
        if not m:
            out_lines.append(line)
            continue
        indent, key, sep, value, rest = m.groups()
        value = value.strip()
        if key in ROLES:
            role = ROLES[key]
            new = T.get(role, role)
            rule = role if role in T else "явно"
        elif value.startswith("#"):
            new, rule = remap(value)
        else:
            new, rule = value, "ссылка на ключ"
        out_lines.append(f"{indent}{key}{sep}{new}{rest}")
        rows.append((key, value, new, rule))

    for key, role in EXTRA.items():
        new = T.get(role, role)
        out_lines.append(f"{key}: {new}; // Xraygram")
        rows.append((key, "(палитра по умолчанию)", new, role))

    colors = ("// Xraygram «Рентген» (FEAT-20). Сгенерировано macos/theme/make_rentgen.py\n"
              "// из night.tdesktop-theme upstream, не править руками.\n"
              + "\n".join(out_lines) + "\n").encode("utf-8")

    def png_1x1(hexv):
        r, g, b, _ = parse(hexv)
        chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        return (b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes([0, r, g, b])))
                + chunk(b"IEND", b""))

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in (("colors.tdesktop-theme", colors), ("background.png", png_1x1(T["bg"]))):
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 19, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    OUT_THEME.write_bytes(buf.getvalue())

    md = ["# «Рентген»: ключ темы tdesktop → роль (FEAT-20, PAR-22)", "",
          "Сгенерировано `macos/theme/make_rentgen.py` из `night.tdesktop-theme` upstream. "
          "Роль — токен `branding/theme-rentgen.md` (явное назначение) или общее правило.", "",
          "| Ключ | upstream (ночь) | Рентген | Роль / правило |", "|---|---|---|---|"]
    md += [f"| `{k}` | `{o}` | `{n}` | {r} |" for k, o, n, r in rows]
    OUT_ROLES.write_text("\n".join(md) + "\n", encoding="utf-8")
    explicit = sum(1 for k, *_ in rows if k in ROLES)
    print(f"{OUT_THEME.relative_to(ROOT)}: {len(rows)} ключей, явно {explicit}")


if __name__ == "__main__":
    main()
