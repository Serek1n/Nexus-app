"""Генерирует логотип, иконку приложения и значки трея Nexus.

Запуск: python tool/make_icons.py   (нужен Pillow)
Форма — скруглённый квадрат (суперэллипс), внутри — буква N одной линией
со скруглёнными концами и стыками; мятная точка — «узел» соединения.
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'icon'
SS = 4  # суперсэмплинг

VIOLET = (0x9A, 0x8C, 0xFF)
INDIGO = (0x5E, 0x5A, 0xEB)
MINT = (0x3D, 0xDC, 0x97)
GRAY = (0x9A, 0x9A, 0xA6)
WHITE = (255, 255, 255)


def squircle(w, box, n=4.6):
    """Маска суперэллипса внутри box=(x0, y0, x1, y1)."""
    m = Image.new('L', (w, w), 0)
    x0, y0, x1, y1 = box
    cx, cy, a, b = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + a * math.copysign(abs(c) ** (2 / n), c),
                    cy + b * math.copysign(abs(s) ** (2 / n), s)))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def gradient(w, top, bottom):
    g = Image.new('RGBA', (w, w))
    d = ImageDraw.Draw(g)
    for y in range(w):
        t = y / max(w - 1, 1)
        d.line([(0, y), (w, y)],
               fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    return g


def n_path(w, cx, cy, h, stroke, node=True):
    """Маски буквы N (одна линия) и точки-узла."""
    half_w = h * 0.40
    x0, x1 = cx - half_w, cx + half_w
    y0, y1 = cy - h / 2, cy + h / 2
    pts = [(x0, y1), (x0, y0), (x1, y1), (x1, y0)]
    m = Image.new('L', (w, w), 0)
    d = ImageDraw.Draw(m)
    d.line(pts, fill=255, width=int(stroke), joint='curve')
    r = stroke / 2
    for x, y in pts[:1] + pts[-1:]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    # Узел: в правом верхнем конце
    dot = Image.new('L', (w, w), 0)
    rd = stroke * 0.85
    dx, dy = x1, y0
    ImageDraw.Draw(dot).ellipse([dx - rd, dy - rd, dx + rd, dy + rd], fill=255)
    # Зазор вокруг узла вырезаем из линии — узел «отделён» от буквы.
    gap = Image.new('L', (w, w), 0)
    rg = rd + stroke * 0.42
    ImageDraw.Draw(gap).ellipse([dx - rg, dy - rg, dx + rg, dy + rg], fill=255)
    if node:
        m = ImageChops.subtract(m, gap)
    return m, dot, (dx, dy, rd)


def tile(size, on=True, pad=0.0, dot=True, glyph_scale=1.0, stroke_k=0.105):
    """Плитка-суперэллипс с буквой N. pad — поля в долях размера."""
    w = size * SS
    p = w * pad
    shape = squircle(w, (p, p, w - p, w - p))
    inner = w - 2 * p
    stroke = max(inner * stroke_k, 2 * SS) if size <= 24 else inner * stroke_k
    if size <= 20:
        stroke = 2.2 * SS * size / 16
    h = inner * 0.44 * glyph_scale
    letter, node, (dx, dy, rd) = n_path(w, w / 2, w / 2 + inner * 0.01, h, stroke,
                                       node=on and dot)

    if on:
        body = gradient(w, VIOLET, INDIGO)
        # мягкий блик сверху
        hl = Image.new('L', (w, w), 0)
        ImageDraw.Draw(hl).ellipse([-w * 0.3, -w * 0.9, w * 1.3, w * 0.42], fill=40)
        hl = hl.filter(ImageFilter.GaussianBlur(w * 0.06))
        white = Image.new('RGBA', (w, w), WHITE + (255,))
        white.putalpha(hl)
        body.alpha_composite(white)
        body.putalpha(shape)
        glyph = Image.new('RGBA', (w, w), WHITE + (255,))
        glyph.putalpha(letter)
        body.alpha_composite(glyph)
        if dot:
            m = Image.new('RGBA', (w, w), MINT + (255,))
            m.putalpha(node)
            body.alpha_composite(m)
    else:
        body = Image.new('RGBA', (w, w), GRAY + (255,))
        body.putalpha(ImageChops.subtract(shape, letter))
    return body.resize((size, size), Image.LANCZOS)


def foreground(size=1024):
    """Передний план адаптивной иконки Android (безопасная зона ~66%)."""
    w = size * SS
    inner = w * 0.62
    stroke = inner * 0.105
    letter, node, (dx, dy, rd) = n_path(w, w / 2, w / 2, inner * 0.44 * 1.25, stroke * 1.2)
    img = Image.new('RGBA', (w, w), (0, 0, 0, 0))
    g = Image.new('RGBA', (w, w), WHITE + (255,))
    g.putalpha(letter)
    img.alpha_composite(g)
    m = Image.new('RGBA', (w, w), MINT + (255,))
    m.putalpha(node)
    img.alpha_composite(m)
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Иконка приложения (Windows и старые Android) и логотип в интерфейсе
    tile(1024, pad=0.06).save(OUT / 'app_icon.png')
    tile(256, pad=0.0).save(OUT / 'logo_mark.png')
    # Адаптивная иконка Android
    gradient(1024, VIOLET, INDIGO).save(OUT / 'app_icon_background.png')
    foreground().save(OUT / 'app_icon_foreground.png')
    # Трей
    sizes = [16, 20, 24, 32, 48, 64, 256]
    for on, name in ((True, 'tray_on.ico'), (False, 'tray_off.ico')):
        ims = [tile(s, on=on, pad=0.02, dot=s >= 20 or on) for s in sizes]
        ims[-1].save(OUT / name, sizes=[(s, s) for s in sizes], append_images=ims[:-1])


if __name__ == '__main__':
    main()
