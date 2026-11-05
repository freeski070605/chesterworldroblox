"""Draw the facade window textures (one bay x one storey each, transparent around
the window so the wall material shows). Output: build/facades/*.png
    python tools/make_facade_textures.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "build" / "facades"
S = 256


def glass(draw, box, frame=(236, 232, 222, 255), border=8, mullions=1, transoms=1):
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=frame)
    gx0, gy0, gx1, gy1 = x0 + border, y0 + border, x1 - border, y1 - border
    # glass: dark with a lighter upper reflection
    for y in range(gy0, gy1):
        t = (y - gy0) / max(gy1 - gy0, 1)
        shade = int(70 - 40 * t)
        draw.line([(gx0, y), (gx1, y)], fill=(shade, shade + 10, shade + 22, 255))
    for i in range(1, mullions + 1):
        mx = gx0 + (gx1 - gx0) * i // (mullions + 1)
        draw.rectangle((mx - border // 2, gy0, mx + border // 2, gy1), fill=frame)
    for i in range(1, transoms + 1):
        my = gy0 + (gy1 - gy0) * i // (transoms + 1)
        draw.rectangle((gx0, my - border // 2, gx1, my + border // 2), fill=frame)


def residential():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    glass(d, (84, 52, 172, 196), mullions=0, transoms=1)
    d.rectangle((76, 196, 180, 206), fill=(200, 196, 186, 255))  # sill
    d.rectangle((84, 44, 172, 52), fill=(200, 196, 186, 255))    # lintel
    return img


def commercial():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    glass(d, (24, 60, 232, 200), border=7, mullions=2, transoms=0)
    d.rectangle((16, 200, 240, 210), fill=(190, 186, 176, 255))
    return img


def industrial():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    glass(d, (20, 40, 236, 130), frame=(90, 96, 100, 255), border=6, mullions=5, transoms=1)
    return img


def ground_residential():
    """Rowhouse unit ground storey: front door (left) and one window (right)."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # door with frame, transom light and a step
    d.rectangle((26, 52, 110, 242), fill=(236, 232, 222, 255))
    d.rectangle((34, 92, 102, 242), fill=(58, 40, 32, 255))
    d.rectangle((34, 60, 102, 84), fill=(54, 64, 78, 255))
    for y in (110, 170):
        d.rectangle((44, y, 92, y + 44), outline=(40, 28, 22, 255), width=3)
    d.ellipse((88, 168, 96, 176), fill=(200, 170, 80, 255))
    d.rectangle((18, 242, 118, 255), fill=(176, 172, 164, 255))
    # window
    glass(d, (150, 70, 230, 190), mullions=0, transoms=1)
    d.rectangle((142, 190, 238, 200), fill=(200, 196, 186, 255))
    return img


def ground_storefront():
    """Shop ground storey: sign band, display glass, central door."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 18, 255, 58), fill=(46, 54, 50, 255))          # sign band
    d.rectangle((0, 58, 255, 66), fill=(120, 116, 110, 255))       # cornice line
    glass(d, (8, 70, 98, 236), border=6, mullions=0, transoms=0)
    glass(d, (158, 70, 248, 236), border=6, mullions=0, transoms=0)
    d.rectangle((104, 70, 152, 250), fill=(60, 62, 64, 255))      # door frame
    d.rectangle((110, 78, 146, 250), fill=(80, 96, 110, 255))     # door glass
    d.rectangle((140, 150, 143, 180), fill=(200, 200, 196, 255))  # handle
    d.rectangle((0, 236, 255, 255), fill=(150, 146, 138, 255))    # kick plate
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, img in (("window_residential", residential()), ("window_commercial", commercial()),
                      ("window_industrial", industrial()), ("ground_residential", ground_residential()),
                      ("ground_storefront", ground_storefront())):
        img.save(OUT / f"{name}.png")
    print("wrote", sorted(p.name for p in OUT.glob("*.png")))


if __name__ == "__main__":
    main()
