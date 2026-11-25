"""Draws the Image Date app icon and writes the iOS and Windows icon files.

Run from the repository root: python3 tool/make_icon.py  (needs Pillow)
"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # draw big, then scale down for smooth edges
A = (0xFF, 0x5F, 0x6D)
B = (0xA8, 0x55, 0xF7)


def gradient(w, h, c1, c2):
    """Diagonal gradient from top-left c1 to bottom-right c2."""
    g = Image.new("RGB", (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = (x + y) / (w + h - 2)
            px[x, y] = tuple(round(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return g


def big_gradient(w, h, c1, c2):
    small = gradient(64, 64, c1, c2)
    return small.resize((w, h), Image.BICUBIC)


def heart(cx, cy, size, steps=400):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * size / 32, cy - y * size / 32))
    return pts


def card_layer(w, h, radius, fill, content=None):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=fill)
    if content:
        content(layer)
    return layer


def front_content(layer):
    w, h = layer.size
    pad = int(w * 0.085)
    # Photo area.
    x0, y0, x1, y1 = pad, pad, w - pad, int(h * 0.80)
    area_w, area_h = x1 - x0, y1 - y0
    photo = big_gradient(area_w, area_h, (0xFF, 0xE4, 0xE7), (0xEE, 0xE0, 0xFF)).convert("RGBA")
    pd = ImageDraw.Draw(photo)
    # Mountains.
    mtn = big_gradient(area_w, area_h, A, B).convert("RGBA")
    mask = Image.new("L", (area_w, area_h), 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(-area_w * 0.05, area_h), (area_w * 0.36, area_h * 0.38), (area_w * 0.72, area_h)], fill=255)
    md.polygon([(area_w * 0.38, area_h), (area_w * 0.70, area_h * 0.56), (area_w * 1.05, area_h)], fill=200)
    photo.paste(mtn, (0, 0), mask)
    # Heart as the sun.
    hm = Image.new("L", (area_w, area_h), 0)
    ImageDraw.Draw(hm).polygon(heart(area_w * 0.73, area_h * 0.30, area_w * 0.30), fill=255)
    photo.paste(Image.new("RGBA", (area_w, area_h), A + (255,)), (0, 0), hm)
    rmask = Image.new("L", (area_w, area_h), 0)
    ImageDraw.Draw(rmask).rounded_rectangle((0, 0, area_w - 1, area_h - 1), radius=int(w * 0.07), fill=255)
    layer.paste(photo, (x0, y0), rmask)
    # Two text bars under the photo, like a profile card.
    d = ImageDraw.Draw(layer)
    bar_h = int(h * 0.045)
    by = int(h * 0.855)
    d.rounded_rectangle((pad, by, pad + int(area_w * 0.55), by + bar_h), radius=bar_h // 2, fill=(0x2A, 0x22, 0x33, 255))
    by2 = by + int(bar_h * 1.7)
    d.rounded_rectangle((pad, by2, pad + int(area_w * 0.32), by2 + int(bar_h * 0.8)), radius=bar_h // 2,
                        fill=(0xC9, 0xC2, 0xD3, 255))


def paste_rotated(base, layer, angle, center, shadow=True):
    rot = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - rot.width / 2)
    y = int(center[1] - rot.height / 2)
    if shadow:
        m = int(S * 0.08)  # margin so the blur is not cut off
        alpha = Image.new("L", (rot.width + 2 * m, rot.height + 2 * m), 0)
        alpha.paste(rot.split()[3].point(lambda a: int(a * 0.35)), (m, m))
        alpha = alpha.filter(ImageFilter.GaussianBlur(S * 0.02))
        sh = Image.new("RGBA", alpha.size, (40, 0, 40, 0))
        sh.putalpha(alpha)
        base.alpha_composite(sh, (x - m + int(S * 0.012), y - m + int(S * 0.03)))
    base.alpha_composite(rot, (x, y))


def draw_icon():
    base = big_gradient(S, S, A, B).convert("RGBA")
    cw, ch = int(S * 0.50), int(S * 0.64)
    radius = int(S * 0.055)
    back = card_layer(cw, ch, radius, (255, 255, 255, 105))
    paste_rotated(base, back, 14, (S * 0.43, S * 0.515), shadow=False)
    front = card_layer(cw, ch, radius, (255, 255, 255, 255), front_content)
    paste_rotated(base, front, -7, (S * 0.545, S * 0.50))
    return base.convert("RGB")


def main():
    icon = draw_icon()
    ios = icon.resize((1024, 1024), Image.LANCZOS)
    ios.save("ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png")
    ios.save("assets/icon/app_icon.png")
    # Windows: rounded square with transparent corners, many sizes in one .ico.
    win = icon.resize((1024, 1024), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=200, fill=255)
    win.putalpha(mask)
    win.save("windows/runner/resources/app_icon.ico",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icons written")


if __name__ == "__main__":
    main()
