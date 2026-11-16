"""Draws the MeaSure launcher icon and splash image and writes every Android density.

A yellow ruler (dark tick marks) inside white AR-style corner brackets, on near-black.
Re-run after changing the design:  python3 tool/generate_icons.py   (needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"

WHITE = (255, 255, 255, 255)
YELLOW = (255, 214, 10, 255)
DARK = (17, 20, 24, 255)
CLEAR = (0, 0, 0, 0)

SS = 4  # supersampling for smooth edges


def symbol(size: int, mono: bool = False) -> Image.Image:
    """The mark on a transparent square that stands for the 108 dp adaptive-icon canvas.

    Everything important sits inside the central 66 dp, which is what Android never crops.
    With mono=True it is a single-colour silhouette for themed (Android 13) icons.
    """
    n = size * SS
    u = n / 108
    img = Image.new("RGBA", (n, n), CLEAR)
    d = ImageDraw.Draw(img)

    # Corner brackets (the "AR frame").
    arm, stroke = 13, 4.6
    for x0, y0, dx, dy in [(27, 27, 1, 1), (81, 27, -1, 1), (27, 81, 1, -1), (81, 81, -1, -1)]:
        pts = [((x0 + dx * arm) * u, y0 * u), (x0 * u, y0 * u), (x0 * u, (y0 + dy * arm) * u)]
        d.line(pts, fill=WHITE, width=round(stroke * u), joint="curve")
        for px, py in (pts[0], pts[2]):  # round caps
            r = stroke * u / 2
            d.ellipse([px - r, py - r, px + r, py + r], fill=WHITE)

    # The ruler.
    d.rounded_rectangle([31 * u, 44 * u, 77 * u, 64 * u], radius=4 * u, fill=WHITE if mono else YELLOW)
    ticks = zip([36, 42, 48, 54, 60, 66, 72], [10, 5, 7, 5, 7, 5, 10])
    for x, length in ticks:
        d.rectangle([(x - 1.1) * u, 44 * u, (x + 1.1) * u, (44 + length) * u], fill=CLEAR if mono else DARK)

    return img.resize((size, size), Image.LANCZOS)


def legacy_icon(size: int) -> Image.Image:
    """Full-bleed rounded square for Android < 8 (no adaptive icons)."""
    n = size * SS
    base = Image.new("RGBA", (n, n), CLEAR)
    grad = Image.new("RGBA", (n, n))
    gd = ImageDraw.Draw(grad)
    top, bottom = (29, 33, 39), (14, 16, 19)
    for y in range(n):
        t = y / (n - 1)
        gd.line([(0, y), (n, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, n - 1, n - 1], radius=round(0.22 * n), fill=255)
    base.paste(grad, (0, 0), mask)
    # Bracket frame (54 of 108 units) fills ~60 % of the icon.
    mark = symbol(round(size * 1.2), mono=False).resize((round(n * 1.2),) * 2, Image.LANCZOS)
    off = (n - mark.width) // 2
    base.alpha_composite(mark, (off, off)) if off >= 0 else base.paste(mark, (off, off), mark)
    return base.resize((size, size), Image.LANCZOS)


def splash_icon(density_scale: float) -> Image.Image:
    """288 dp canvas for the Android 12 splash (only a 192 dp circle is shown), mark inside."""
    px = round(288 * density_scale)
    out = Image.new("RGBA", (px, px), CLEAR)
    inner = round(240 * density_scale)  # bracket frame ends up 120 dp wide: well inside the circle
    mark = symbol(inner)
    out.alpha_composite(mark, ((px - inner) // 2, (px - inner) // 2))
    return out


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)


DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

for name, scale in DENSITIES.items():
    save(legacy_icon(round(48 * scale)), RES / f"mipmap-{name}/ic_launcher.png")
    save(symbol(round(108 * scale)), RES / f"drawable-{name}/ic_launcher_foreground.png")
    save(symbol(round(108 * scale), mono=True), RES / f"drawable-{name}/ic_launcher_monochrome.png")
    save(splash_icon(scale), RES / f"drawable-{name}/splash_icon.png")

# Used by the Flutter loading screen so it continues the native splash seamlessly.
save(symbol(512), ROOT / "assets/logo.png")
print("icons written")
