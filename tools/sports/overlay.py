"""Draw world-stud geometry over georeferenced DVRPC aerial crops."""
import math
from PIL import ImageDraw, ImageEnhance

from tools.sports.aerial import crop


def box_corners(cx, cz, L, W, yaw):
    """Corners of a ParkBuilder box: local +X along L, CFrame.Angles(0, yaw, 0)."""
    a = math.radians(yaw)
    ux, uz = math.cos(a), -math.sin(a)   # local +X in world (x, z)
    vx, vz = math.sin(a), math.cos(a)    # local +Z in world
    return [(cx + sx * L / 2 * ux + sz * W / 2 * vx, cz + sx * L / 2 * uz + sz * W / 2 * vz)
            for sx, sz in ((1, 1), (1, -1), (-1, -1), (-1, 1))]


def local_to_world(cx, cz, yaw, lx, lz):
    a = math.radians(yaw)
    return cx + lx * math.cos(a) + lz * math.sin(a), cz - lx * math.sin(a) + lz * math.cos(a)


class Sheet:
    def __init__(self, cx, cz, half, ppx, half_z=None, enhance=1.0):
        self.img, self.to_px = crop(cx, cz, half, ppx, half_z)
        if enhance != 1.0:
            self.img = ImageEnhance.Contrast(self.img).enhance(enhance)
        self.draw = ImageDraw.Draw(self.img)

    def poly(self, pts, color, width=2, closed=True):
        px = [self.to_px(x, z) for x, z in pts]
        self.draw.line(px + ([px[0]] if closed else []), fill=color, width=width)

    def box(self, b, color, width=2):
        self.poly(box_corners(*b), color, width)

    def dot(self, x, z, color, r=4):
        px, py = self.to_px(x, z)
        self.draw.ellipse((px - r, py - r, px + r, py + r), outline=color, width=2)

    def text(self, x, z, s, color="yellow"):
        self.draw.text(self.to_px(x, z), s, fill=color)

    def save(self, path):
        self.img.save(path)
