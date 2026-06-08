#!/usr/bin/env python3

from __future__ import annotations

import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PACKAGING_DIR = PROJECT_ROOT / "Packaging"
MASTER_PATH = PACKAGING_DIR / "AppIcon-master.png"
ICONSET_DIR = PACKAGING_DIR / "AppIcon.iconset"
ICNS_PATH = PACKAGING_DIR / "AppIcon.icns"

CANVAS = 1024
CORNER_RADIUS = 232


def main() -> None:
    PACKAGING_DIR.mkdir(parents=True, exist_ok=True)
    image = build_icon(CANVAS)
    image.save(MASTER_PATH)
    export_iconset(image)

    if ICNS_PATH.exists():
        ICNS_PATH.unlink()
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)],
        check=True,
    )
    print(ICNS_PATH)


def build_icon(size: int) -> Image.Image:
    scale = 4
    rs = size * scale
    base = make_background(rs)
    draw_glass_card(base, scale)
    draw_crosshair(base, scale)
    draw_crop_marks(base, scale)

    mask = rounded_mask(rs, CORNER_RADIUS * scale)

    # Fill corners with the background gradient color before applying the mask.
    # This prevents white fringe when macOS composites the icon against light backgrounds.
    bg_fill = make_background(rs)
    base.paste(bg_fill, mask=invert_mask(mask))

    base.putalpha(mask)
    return base.resize((size, size), Image.Resampling.LANCZOS)


def make_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    pixels = image.load()

    # Vibrant gradient: purple-blue top-left to teal-cyan bottom-right
    tl = (88, 40, 180)
    tr = (40, 80, 200)
    bl = (60, 50, 160)
    br = (20, 160, 180)

    for y in range(size):
        ny = y / (size - 1)
        for x in range(size):
            nx = x / (size - 1)
            upper = lerp_color(tl, tr, nx)
            lower = lerp_color(bl, br, nx)
            pixels[x, y] = (*lerp_color(upper, lower, ny), 255)

    # Soft colored orbs for depth
    orbs = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(orbs)
    draw.ellipse((-100, -200, size // 2 + 200, size // 2), fill=(130, 80, 240, 50))
    draw.ellipse((size // 2 - 100, size // 2, size + 200, size + 200), fill=(0, 200, 200, 45))
    draw.ellipse((size // 3, -100, size * 2 // 3 + 300, size // 3 + 200), fill=(200, 100, 255, 30))
    orbs = orbs.filter(ImageFilter.GaussianBlur(size // 6))
    image.alpha_composite(orbs)

    return image


def draw_glass_card(image: Image.Image, s: int) -> None:
    size = image.size[0]
    cx, cy = size // 2, size // 2 + 12 * s
    half = 240 * s
    rect = (cx - half, cy - half, cx + half, cy + half)
    radius = 72 * s

    # Capture the background region for the "frosted" effect
    card_region = image.crop(rect)
    blurred = card_region.filter(ImageFilter.GaussianBlur(28 * s))

    # Brighten + desaturate the blurred region to simulate frosted glass
    frost_tint = Image.new("RGBA", blurred.size, (255, 255, 255, 100))
    blurred.alpha_composite(frost_tint)

    # Create rounded mask for the glass card
    card_w = rect[2] - rect[0]
    card_h = rect[3] - rect[1]
    card_mask = Image.new("L", (card_w, card_h), 0)
    ImageDraw.Draw(card_mask).rounded_rectangle(
        (0, 0, card_w, card_h), radius=radius, fill=255
    )

    # Drop shadow
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (rect[0] + 8 * s, rect[1] + 12 * s, rect[2] + 8 * s, rect[3] + 12 * s),
        radius=radius, fill=(0, 0, 0, 80),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(24 * s))
    image.alpha_composite(shadow)

    # Composite the frosted glass onto the image
    glass = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glass_card = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    glass_card.paste(blurred, mask=card_mask)
    glass.paste(glass_card, (rect[0], rect[1]))
    image.alpha_composite(glass)

    # Inner white tint for glass feel
    tint = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tint_draw = ImageDraw.Draw(tint)
    tint_draw.rounded_rectangle(rect, radius=radius, fill=(255, 255, 255, 35))
    image.alpha_composite(tint)

    # Top highlight (specular reflection on glass)
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    hl_rect = (rect[0] + 20 * s, rect[1] + 8 * s, rect[2] - 20 * s, rect[1] + half // 2)
    hl_draw.rounded_rectangle(hl_rect, radius=radius // 2, fill=(255, 255, 255, 40))
    highlight = highlight.filter(ImageFilter.GaussianBlur(16 * s))
    # Clip to card shape
    hl_mask_full = Image.new("L", (size, size), 0)
    ImageDraw.Draw(hl_mask_full).rounded_rectangle(rect, radius=radius, fill=255)
    highlight.putalpha(
        Image.composite(highlight.split()[3], Image.new("L", (size, size), 0), hl_mask_full)
    )
    image.alpha_composite(highlight)

    # Border: thin white outline for glass edge
    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        rect, radius=radius, outline=(255, 255, 255, 80), width=3 * s
    )
    image.alpha_composite(border)


def draw_crosshair(image: Image.Image, s: int) -> None:
    size = image.size[0]
    cx, cy = size // 2, size // 2 + 12 * s
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    line_len = 80 * s
    gap = 18 * s
    stroke = 6 * s
    color = (255, 255, 255, 180)

    # Horizontal lines
    draw.line([(cx - gap - line_len, cy), (cx - gap, cy)], fill=color, width=stroke)
    draw.line([(cx + gap, cy), (cx + gap + line_len, cy)], fill=color, width=stroke)
    # Vertical lines
    draw.line([(cx, cy - gap - line_len), (cx, cy - gap)], fill=color, width=stroke)
    draw.line([(cx, cy + gap), (cx, cy + gap + line_len)], fill=color, width=stroke)

    # Center dot
    dot_r = 8 * s
    draw.ellipse(
        (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
        fill=(255, 255, 255, 140),
    )

    image.alpha_composite(layer)


def draw_crop_marks(image: Image.Image, s: int) -> None:
    size = image.size[0]
    cx, cy = size // 2, size // 2 + 12 * s
    half = 240 * s
    rect = (cx - half, cy - half, cx + half, cy + half)

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    inset = 40 * s
    arm = 72 * s
    stroke = 20 * s
    color = (255, 255, 255, 230)

    x0, y0, x1, y1 = rect
    left = x0 + inset
    top = y0 + inset
    right = x1 - inset
    bottom = y1 - inset

    corners = [
        ((left, top + arm), (left, top), (left + arm, top)),
        ((right - arm, top), (right, top), (right, top + arm)),
        ((left, bottom - arm), (left, bottom), (left + arm, bottom)),
        ((right - arm, bottom), (right, bottom), (right, bottom - arm)),
    ]

    for start, pivot, end in corners:
        draw.line([start, pivot, end], fill=color, width=stroke, joint="curve")

    # Subtle glow
    glow = layer.filter(ImageFilter.GaussianBlur(4 * s))
    image.alpha_composite(glow)
    image.alpha_composite(layer)


def export_iconset(master: Image.Image) -> None:
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, target_size in sizes.items():
        resized = master.resize((target_size, target_size), Image.Resampling.LANCZOS)
        resized.save(ICONSET_DIR / filename)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size, size), radius=radius, fill=255
    )
    return mask


def invert_mask(mask: Image.Image) -> Image.Image:
    return Image.eval(mask, lambda v: 255 - v)


def lerp(a: float, b: float, t: float) -> float:
    return a * (1 - t) + b * t


def lerp_color(a, b, t: float):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


if __name__ == "__main__":
    main()
