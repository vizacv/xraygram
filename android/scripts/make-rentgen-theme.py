#!/usr/bin/env python3
"""Xraygram (FEAT-20, PAR-22): build the built-in «Рентген» theme for Telegram Android.

Input:  upstream TMessagesProj/src/main/assets/darkblue.attheme (the upstream dark theme, base for key coverage)
Output: TMessagesProj/src/main/assets/rentgen.attheme

Every colour of the base is re-mapped to the «Рентген» tokens (branding/theme-rentgen.md) by its role:
  * greys / navy greys  → the bg / surface / surface-2 / border / text-3 / text-2 / text ramp by lightness;
  * blues (Telegram accent family) → the accent ramp (dark teal … accent … accent-hi) by lightness;
  * reds → error, yellows/oranges → warn; other hues (code syntax, gifts, secret-chat green) stay.
Then the keys that carry a role in FEAT-20 §5 get exact token values (OVERRIDES). The table key → role is also in
android/decisions.md. Alpha is kept from the base unless the override says otherwise.

Usage: make-rentgen-theme.py <tg-android root>
"""
import colorsys
import re
import sys
from pathlib import Path

# ---- tokens (branding/theme-rentgen.md)
BG, SURFACE, SURFACE2 = 0x0B1220, 0x121B2E, 0x18233A
BORDER, BORDER2, SEPARATOR = 0x1C2840, 0x22304A, 0x16213A
TEXT, TEXT2, TEXT3 = 0xE6F1FF, 0x8EA3BF, 0x5F7391
ACCENT, ACCENT_HI, ON_ACCENT = 0x3EF2C8, 0x8FFBE0, 0x04211B
BUBBLE_OUT, BUBBLE_OUT_TIME = 0x10403A, 0x7FD9C2
WARN, ERROR = 0xF2B33E, 0xFF6B6B
AVATARS = [0xF28CB1, 0x7FB2FF, 0x3EF2C8, 0xB49CFF, 0xF2B33E, 0x8EE07A]
DEEP = 0x070C17  # below bg: section gaps, shadows of the list

# lightness of the base colour → target (grey ramp)
GREY_RAMP = [(0.00, 0x000000), (0.10, DEEP), (0.15, BG), (0.18, SURFACE), (0.22, SURFACE2), (0.27, BORDER2),
             (0.36, 0x33435E), (0.42, TEXT3), (0.53, TEXT2), (0.75, 0xB9CAE0), (0.90, TEXT), (1.00, TEXT)]
# lightness of a blue → target (accent ramp)
BLUE_RAMP = [(0.00, 0x02110E), (0.25, BUBBLE_OUT), (0.40, 0x1E8C74), (0.55, ACCENT), (0.75, ACCENT_HI),
             (0.92, 0xD8FFF4), (1.00, 0xFFFFFF)]


def lerp_rgb(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rgb(c):
    return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF


def ramp(ramp_, l):
    for (l0, c0), (l1, c1) in zip(ramp_, ramp_[1:]):
        if l <= l1:
            t = 0 if l1 == l0 else (l - l0) / (l1 - l0)
            r, g, b = lerp_rgb(rgb(c0), rgb(c1), max(0.0, min(1.0, t)))
            return (r << 16) | (g << 8) | b
    return ramp_[-1][1]


def remap(argb):
    a = (argb >> 24) & 0xFF
    r, g, b = rgb(argb)
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    hue = h * 360
    if s < 0.30 or l > 0.93:
        new = ramp(GREY_RAMP, l)
    elif 185 <= hue <= 235:
        new = ramp(BLUE_RAMP, l)
    elif (hue >= 340 or hue <= 15) and s > 0.45 and 0.40 <= l <= 0.80:
        new = ERROR
    elif 30 <= hue <= 55 and s > 0.5 and 0.40 <= l <= 0.80:
        new = WARN
    else:
        new = argb & 0xFFFFFF
    return (a << 24) | new


def op(c, alpha=1.0):
    return (round(alpha * 255) << 24) | c


OVERRIDES = {
    # backgrounds
    "windowBackgroundWhite": op(BG), "windowBackgroundGray": op(DEEP), "chat_wallpaper": op(BG),
    "windowBackgroundUnchecked": op(BG), "chats_menuBackground": op(BG),
    "actionBarDefault": op(SURFACE), "actionBarDefaultArchived": op(SURFACE), "actionBarDefaultSubmenuBackground": op(SURFACE),
    "actionBarActionModeDefault": op(SURFACE), "chat_messagePanelBackground": op(SURFACE), "chat_topPanelBackground": op(SURFACE),
    "dialogBackground": op(SURFACE), "dialogBackgroundGray": op(BG), "chat_emojiPanelBackground": op(SURFACE),
    "chats_menuTopBackground": op(SURFACE), "chats_menuTopBackgroundCats": op(SURFACE), "avatar_backgroundActionBarBlue": op(SURFACE),
    "inappPlayerBackground": op(SURFACE), "chat_goDownButton": op(SURFACE), "graySection": op(DEEP),
    "chats_pinnedOverlay": op(TEXT, 0.03), "chats_tabletSelectedOverlay": op(ACCENT, 0.08),
    # separators
    "divider": op(SEPARATOR), "chat_emojiPanelShadowLine": op(SEPARATOR), "windowBackgroundWhiteInputField": op(BORDER2),
    "windowBackgroundWhiteInputFieldActivated": op(ACCENT), "dialogInputField": op(BORDER2), "dialogInputFieldActivated": op(ACCENT),
    # text
    "windowBackgroundWhiteBlackText": op(TEXT), "chats_name": op(TEXT), "chats_nameMessage": op(TEXT),
    "chats_nameMessage_threeLines": op(TEXT), "dialogTextBlack": op(TEXT), "actionBarDefaultTitle": op(TEXT),
    "actionBarDefaultIcon": op(TEXT), "chat_messageTextIn": op(TEXT), "chat_messageTextOut": op(TEXT),
    "chats_message": op(TEXT2), "chats_message_threeLines": op(TEXT2), "chats_date": op(TEXT2), "chats_draft": op(ERROR),
    "windowBackgroundWhiteGrayText": op(TEXT2), "windowBackgroundWhiteGrayText2": op(TEXT2), "windowBackgroundWhiteGrayText3": op(TEXT3),
    "windowBackgroundWhiteGrayText4": op(TEXT2), "windowBackgroundWhiteGrayText5": op(TEXT3), "windowBackgroundWhiteGrayText6": op(TEXT2),
    "windowBackgroundWhiteGrayText7": op(TEXT3), "windowBackgroundWhiteGrayText8": op(TEXT2), "windowBackgroundWhiteHintText": op(TEXT3),
    "dialogTextGray": op(TEXT2), "dialogTextGray2": op(TEXT2), "dialogTextGray3": op(TEXT3), "dialogTextHint": op(TEXT3),
    "chat_inTimeText": op(TEXT2), "chat_inViews": op(TEXT2), "chat_inFileInfoText": op(TEXT2),
    # accent
    "chats_unreadCounter": op(ACCENT), "chats_unreadCounterText": op(ON_ACCENT), "chats_unreadCounterMuted": op(TEXT3),
    "chats_actionBackground": op(ACCENT), "chats_actionPressedBackground": op(ACCENT_HI), "chats_actionIcon": op(ON_ACCENT),
    "chats_onlineCircle": op(ACCENT), "chats_sentCheck": op(ACCENT), "chats_sentReadCheck": op(ACCENT),
    "chats_verifiedBackground": op(ACCENT), "chats_verifiedCheck": op(ON_ACCENT), "chats_menuItemCheck": op(ACCENT),
    "chat_messageLinkIn": op(ACCENT), "chat_messageLinkOut": op(ACCENT_HI), "windowBackgroundWhiteLinkText": op(ACCENT),
    "windowBackgroundWhiteBlueText": op(ACCENT), "windowBackgroundWhiteBlueText2": op(ACCENT), "windowBackgroundWhiteBlueText3": op(ACCENT),
    "windowBackgroundWhiteBlueText4": op(ACCENT), "windowBackgroundWhiteBlueText5": op(ACCENT), "windowBackgroundWhiteBlueText6": op(ACCENT),
    "windowBackgroundWhiteBlueText7": op(ACCENT), "windowBackgroundWhiteBlueHeader": op(ACCENT), "windowBackgroundWhiteBlueButton": op(ACCENT),
    "windowBackgroundWhiteBlueIcon": op(ACCENT), "dialogTextBlue": op(ACCENT), "dialogTextBlue2": op(ACCENT), "dialogTextLink": op(ACCENT),
    "dialogButton": op(ACCENT), "dialogLineProgress": op(ACCENT), "dialogRoundCheckBox": op(ACCENT), "dialogRoundCheckBoxCheck": op(ON_ACCENT),
    "featuredStickers_addButton": op(ACCENT), "featuredStickers_addButtonPressed": op(ACCENT_HI), "featuredStickers_buttonText": op(ON_ACCENT),
    "featuredStickers_buttonProgress": op(ON_ACCENT), "featuredStickers_unread": op(ACCENT),
    "switchTrackChecked": op(ACCENT, 0.55), "switchTrackBlueChecked": op(ACCENT, 0.55), "switchTrackBlueThumbChecked": op(ACCENT),
    "switch2TrackChecked": op(ACCENT), "checkbox": op(ACCENT), "checkboxCheck": op(ON_ACCENT), "checkboxSquareBackground": op(ACCENT),
    "checkboxSquareCheck": op(ON_ACCENT), "radioBackgroundChecked": op(ACCENT), "dialogRadioBackgroundChecked": op(ACCENT),
    "dialogCheckboxSquareBackground": op(ACCENT), "dialogCheckboxSquareCheck": op(ON_ACCENT),
    "chat_messagePanelSend": op(ACCENT), "chat_messagePanelVoiceBackground": op(ACCENT), "chat_messagePanelVoicePressed": op(ON_ACCENT),
    "chat_status": op(ACCENT), "profile_status": op(ACCENT), "actionBarTabActiveText": op(ACCENT), "actionBarTabLine": op(ACCENT),
    "chat_goDownButtonCounterBackground": op(ACCENT), "chat_goDownButtonCounter": op(ON_ACCENT),
    "chat_attachCheckBoxBackground": op(ACCENT), "chat_attachCheckBoxCheck": op(ON_ACCENT), "player_progress": op(ACCENT),
    "listSelectorSDK21": op(ACCENT, 0.08), "actionBarDefaultSelector": op(ACCENT, 0.12), "chat_textSelectBackground": op(ACCENT, 0.30),
    "chat_linkSelectBackground": op(ACCENT, 0.25), "chat_inTextSelectionHighlight": op(ACCENT, 0.30),
    # bubbles
    "chat_inBubble": op(SURFACE2), "chat_inBubbleSelected": op(0x223152), "chat_inBubbleShadow": op(0x000000, 0.20),
    "chat_outBubble": op(BUBBLE_OUT), "chat_outBubbleGradient": op(BUBBLE_OUT), "chat_outBubbleSelected": op(0x155148),
    "chat_outBubbleShadow": op(ACCENT, 0.30),  # the 30 % accent outline of the outgoing bubble, as a soft edge
    "chat_outTimeText": op(BUBBLE_OUT_TIME), "chat_outViews": op(BUBBLE_OUT_TIME), "chat_outSentCheck": op(BUBBLE_OUT_TIME),
    "chat_outSentCheckRead": op(ACCENT), "chat_outSentClock": op(BUBBLE_OUT_TIME), "chat_outFileInfoText": op(BUBBLE_OUT_TIME),
    "chat_outReplyLine": op(ACCENT), "chat_outReplyNameText": op(ACCENT), "chat_inReplyLine": op(ACCENT), "chat_inReplyNameText": op(ACCENT),
    "chat_inForwardedNameText": op(ACCENT), "chat_outForwardedNameText": op(ACCENT_HI), "chat_outPreviewLine": op(ACCENT),
    # warn / error
    "text_RedRegular": op(ERROR), "text_RedBold": op(ERROR), "chats_attachMessage": op(ACCENT), # avatars: placeholders in the six colours, text on them bg
    "avatar_text": op(BG),
    "avatar_backgroundRed": op(AVATARS[0]), "avatar_background2Red": op(AVATARS[0]),
    "avatar_backgroundBlue": op(AVATARS[1]), "avatar_background2Blue": op(AVATARS[1]),
    "avatar_backgroundCyan": op(AVATARS[2]), "avatar_background2Cyan": op(AVATARS[2]),
    "avatar_backgroundViolet": op(AVATARS[3]), "avatar_background2Violet": op(AVATARS[3]),
    "avatar_backgroundOrange": op(AVATARS[4]), "avatar_background2Orange": op(AVATARS[4]),
    "avatar_backgroundGreen": op(AVATARS[5]), "avatar_background2Green": op(AVATARS[5]),
    "avatar_backgroundPink": op(AVATARS[0]), "avatar_background2Pink": op(AVATARS[0]),
    "avatar_backgroundSaved": op(ACCENT), "avatar_background2Saved": op(ACCENT),
    "avatar_backgroundInProfileBlue": op(AVATARS[1]),
}
# keys removed so they fall back to their solid counterparts (no gradient on the outgoing bubble)
DROP = {"chat_outBubbleGradient2", "chat_outBubbleGradient3", "chat_outBubbleGradientAnimated", "chat_wallpaper_gradient_to",
        "chat_wallpaper_gradient_to2", "chat_wallpaper_gradient_to3", "chat_wallpaper_gradient_rotation"}


def parse(path):
    out = {}
    for line in Path(path).read_text(encoding="latin1").splitlines():
        line = line.strip()
        if "=" not in line or line.startswith("WPS"):
            continue
        k, v = line.split("=", 1)
        v = v.strip()
        try:
            out[k] = int(v[1:], 16) & 0xFFFFFFFF if v.startswith("#") else int(v) & 0xFFFFFFFF
        except ValueError:
            continue
    return out


def known_keys(root):
    src = (Path(root) / "TMessagesProj/src/main/java/org/telegram/ui/ActionBar/ThemeColors.java").read_text()
    return set(re.findall(r'colorKeysMap\.put\(key_\w+, "(\w+)"\)', src))


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    assets = root / "TMessagesProj/src/main/assets"
    base = parse(assets / "darkblue.attheme")
    keys = known_keys(root)
    result = {k: remap(v) for k, v in base.items() if k not in DROP}
    unknown = [k for k in OVERRIDES if k not in keys]
    if unknown:
        print("unknown keys (skipped):", " ".join(sorted(unknown)), file=sys.stderr)
    for k, v in OVERRIDES.items():
        if k in keys:
            result[k] = v
    lines = []
    for k in sorted(result):
        v = result[k]
        if v >= 0x80000000:
            v -= 0x100000000
        lines.append(f"{k}={v}")
    (assets / "rentgen.attheme").write_text("\n".join(lines) + "\n", encoding="latin1")
    print(f"rentgen.attheme: {len(result)} keys ({len(base)} from darkblue, {sum(1 for k in OVERRIDES if k in keys)} set by role)")


if __name__ == "__main__":
    main()
