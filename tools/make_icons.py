"""Generates the placeholder tool icons for Priority Probe: two plain road signs, no scenery.
Left: priority road (yellow diamond). Right: give way (red-bordered triangle).
Usage: python3 tools/make_icons.py <output dir>
Writes priority_tool@2x.tga (240x150, 32 bpp) and priority_tool_preview@2x.tga (720x405, 24 bpp), plus PNG copies."""
import sys, os
from PIL import Image, ImageDraw

SS = 4  # supersampling
BG = (58, 64, 68)

def diamond(d, cx, cy, r, b):
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=(255, 255, 255))
    r2 = r - b
    d.polygon([(cx, cy - r2), (cx + r2, cy), (cx, cy + r2), (cx - r2, cy)], fill=(244, 196, 30))

def giveway(d, cx, cy, r, b):
    def tri(rr): return [(cx - rr, cy - rr * 0.78), (cx + rr, cy - rr * 0.78), (cx, cy + rr * 0.92)]
    d.polygon(tri(r), fill=(205, 32, 32))
    d.polygon(tri(r - b), fill=(255, 255, 255))

def draw(w, h, alpha):
    W, H = w * SS, h * SS
    im = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(im)
    s = H * 0.30
    diamond(d, int(W * 0.30), H // 2, int(s * 1.25), int(s * 0.17))
    giveway(d, int(W * 0.70), H // 2, int(s * 1.12), int(s * 0.19))
    im = im.resize((w, h), Image.LANCZOS)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=int(H * 0.07), fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    if alpha:
        im.putalpha(mask)
        return im
    return im.convert("RGB")

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    icon, prev = draw(240, 150, True), draw(720, 405, False)
    icon.save(os.path.join(out, "priority_tool@2x.tga"))
    prev.save(os.path.join(out, "priority_tool_preview@2x.tga"))
    icon.save(os.path.join(out, "priority_tool@2x.png"))
    prev.save(os.path.join(out, "priority_tool_preview@2x.png"))

main()
