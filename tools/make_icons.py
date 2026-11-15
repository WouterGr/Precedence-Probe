"""Generates the placeholder tool icons for Priority Probe (original artwork, TF3 menu style).
Usage: python3 tools/make_icons.py <output dir>
Writes priority_tool@2x.tga (240x150, 32 bpp) and priority_tool_preview@2x.tga (720x405, 24 bpp), plus PNG copies."""
import sys, os, math, random
from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def vgrad(w, h, top, bot):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(top, bot, y / max(1, h - 1)))
    return im

def noise(im, amt, seed):
    rnd = random.Random(seed)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            n = rnd.randint(-amt, amt)
            r, g, b = px[x, y][:3]
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))
    return im

def diamond(d, cx, cy, r, border):
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=(255, 255, 255))
    r2 = r - border
    d.polygon([(cx, cy - r2), (cx + r2, cy), (cx, cy + r2), (cx - r2, cy)], fill=(244, 196, 30))

def giveway(d, cx, cy, r, border):
    pts = lambda rr: [(cx - rr, cy - rr * 0.75), (cx + rr, cy - rr * 0.75), (cx, cy + rr * 0.9)]
    d.polygon(pts(r), fill=(200, 30, 30))
    d.polygon(pts(r - border), fill=(255, 255, 255))
    d.polygon(pts(r - border * 2.6), fill=(255, 255, 255))

def make_icon():
    W, H = 240 * SS, 150 * SS
    road = vgrad(W, H, (96, 102, 104), (66, 72, 74))
    noise(road, 5, 1)
    d = ImageDraw.Draw(road)
    # T junction seen from above: main road horizontal, side road from the bottom
    mh = int(H * 0.30)                      # main road half-height... top edge y
    top, bot = int(H * 0.22), int(H * 0.58)
    sl, sr = int(W * 0.40), int(W * 0.60)
    asphalt = (58, 63, 65)
    d.rectangle([0, top, W, bot], fill=asphalt)
    d.rectangle([sl, bot - 4, sr, H], fill=asphalt)
    # pavements
    kerb = (150, 152, 148)
    d.line([(0, top), (W, top)], fill=kerb, width=SS * 3)
    d.line([(0, bot), (sl, bot)], fill=kerb, width=SS * 3)
    d.line([(sr, bot), (W, bot)], fill=kerb, width=SS * 3)
    d.line([(sl, bot), (sl, H)], fill=kerb, width=SS * 3)
    d.line([(sr, bot), (sr, H)], fill=kerb, width=SS * 3)
    # markings: dashed centre line of the main road, stop line on the side road
    cy = (top + bot) // 2
    x = 0
    while x < W:
        if not (sl - 10 * SS < x < sr):
            d.rectangle([x, cy - SS, x + 14 * SS, cy + SS], fill=(235, 235, 230))
        x += 26 * SS
    cx = (sl + sr) // 2
    y = bot + 10 * SS
    while y < H:
        d.rectangle([cx - SS, y, cx + SS, y + 12 * SS], fill=(235, 235, 230))
        y += 24 * SS
    d.rectangle([sl + 4 * SS, bot + 3 * SS, cx - 3 * SS, bot + 9 * SS], fill=(235, 235, 230))
    # priority flow: a blue lane arrow along the main road, a red one that yields from the side road
    blue, red = (60, 120, 230), (225, 60, 50)
    d.line([(int(W * 0.08), cy + 22 * SS), (int(W * 0.92), cy + 22 * SS)], fill=blue, width=SS * 5)
    d.polygon([(int(W * 0.92) + 14 * SS, cy + 22 * SS), (int(W * 0.92) - 4 * SS, cy + 12 * SS), (int(W * 0.92) - 4 * SS, cy + 32 * SS)], fill=blue)
    d.line([(cx + 18 * SS, H - 8 * SS), (cx + 18 * SS, bot + 22 * SS)], fill=red, width=SS * 5)
    d.arc([cx + 18 * SS - 40 * SS, bot - 20 * SS, cx + 18 * SS + 2 * SS, bot + 22 * SS], 270, 360, fill=red, width=SS * 5)
    # signs
    diamond(d, int(W * 0.17), int(H * 0.40) - 22 * SS, 17 * SS, 3 * SS)
    giveway(d, int(W * 0.80), int(H * 0.78), 16 * SS, 3 * SS)
    road = road.resize((240, 150), Image.LANCZOS).convert("RGBA")
    # ticket-shaped outline with notches, like the game's tiles
    mask = Image.new("L", (W, H), 0)
    m = ImageDraw.Draw(mask)
    m.rounded_rectangle([0, 0, W - 1, H - 1], radius=10 * SS, fill=255)
    for (nx, ny) in [(0, H // 2), (W - 1, H // 2)]:
        m.ellipse([nx - 9 * SS, ny - 9 * SS, nx + 9 * SS, ny + 9 * SS], fill=0)
    mask = mask.resize((240, 150), Image.LANCZOS)
    road.putalpha(mask)
    return road

def make_preview():
    W, H = 720 * SS // 2, 405 * SS // 2   # supersample x2 only, the scene is big
    sky = vgrad(W, int(H * 0.42), (118, 160, 196), (206, 224, 232))
    im = Image.new("RGB", (W, H), (96, 130, 70))
    im.paste(sky, (0, 0))
    d = ImageDraw.Draw(im)
    hor = int(H * 0.42)
    # distant tree line
    rnd = random.Random(7)
    for i in range(70):
        x = rnd.randint(-20, W + 20)
        r = rnd.randint(10, 26)
        d.ellipse([x - r, hor - r, x + r, hor + r // 2], fill=(52 + rnd.randint(-8, 8), 86 + rnd.randint(-10, 10), 50))
    # field
    for y in range(hor, H):
        t = (y - hor) / (H - hor)
        d.line([(0, y), (W, y)], fill=lerp((108, 138, 74), (78, 108, 52), t))
    # perspective: vanishing point
    vx, vy = int(W * 0.55), hor
    def P(x, y): return (x, y)
    asphalt = (62, 66, 68)
    # main road (left to right across the foreground), side road going away to the vanishing point
    d.polygon([(0, int(H * 0.72)), (W, int(H * 0.68)), (W, int(H * 0.98)), (0, H)], fill=asphalt)
    d.polygon([(int(W * 0.30), int(H * 0.72)), (int(W * 0.62), int(H * 0.69)), (vx + 18, vy + 6), (vx - 14, vy + 6)], fill=asphalt)
    # junction mouth widening
    d.polygon([(int(W * 0.26), int(H * 0.73)), (int(W * 0.30), int(H * 0.72)), (int(W * 0.62), int(H * 0.69)), (int(W * 0.68), int(H * 0.69)), (int(W * 0.7), int(H * 0.8)), (int(W * 0.2), int(H * 0.82))], fill=asphalt)
    # markings
    yel = (232, 190, 40)
    d.line([(vx, vy + 8), (int(W * 0.47), int(H * 0.70))], fill=yel, width=3)
    d.line([(0, int(H * 0.86)), (int(W * 0.25), int(H * 0.835))], fill=(230, 230, 225), width=4)
    d.line([(int(W * 0.7), int(H * 0.8)), (W, int(H * 0.82))], fill=(230, 230, 225), width=4)
    for k in range(0, 8):
        x0 = int(W * (0.72 + k * 0.04)); 
    # stop line + give way markings on the side road
    d.polygon([(int(W * 0.40), int(H * 0.715)), (int(W * 0.54), int(H * 0.705)), (int(W * 0.54), int(H * 0.72)), (int(W * 0.40), int(H * 0.73))], fill=(232, 232, 226))
    # signs on posts
    def post(x, y, h):
        d.rectangle([x - 4, y - h, x + 4, y], fill=(150, 156, 160))
        d.ellipse([x - 22, y - 5, x + 22, y + 5], fill=(30, 40, 24))
    post(int(W * 0.26), int(H * 0.80), int(H * 0.30)); diamond(d, int(W * 0.26), int(H * 0.80) - int(H * 0.30) - 40, 52, 8)
    post(int(W * 0.69), int(H * 0.74), int(H * 0.26)); giveway(d, int(W * 0.69), int(H * 0.74) - int(H * 0.26) - 40, 50, 8)
    im = im.filter(ImageFilter.GaussianBlur(0.6)).resize((720, 405), Image.LANCZOS)
    return noise(im, 3, 3)

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    icon, prev = make_icon(), make_preview()
    icon.save(os.path.join(out, "priority_tool@2x.tga"))
    prev.save(os.path.join(out, "priority_tool_preview@2x.tga"))
    icon.save(os.path.join(out, "priority_tool@2x.png"))
    prev.save(os.path.join(out, "priority_tool_preview@2x.png"))

main()
