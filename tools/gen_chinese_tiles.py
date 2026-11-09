#!/usr/bin/env python3
"""生成中式麻将牌 PNG：万子/筒子/条子/红中。

用 PIL + 中文字体直接画，风格对齐国内常见的麻将牌：
- 万子：黑字 + 红「萬」
- 筒子：彩色圆点
- 条子：绿色竹节
- 红中：红「中」
"""
import pathlib
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = pathlib.Path("App/Resources/Tiles").resolve()
OUT.mkdir(parents=True, exist_ok=True)

W, H = 150, 220  # 牌面尺寸

FONT_PATHS = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
]
FONT_REG = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
]


def font(size, bold=True):
    paths = FONT_PATHS if bold else FONT_REG
    for p in paths:
        if pathlib.Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def bg():
    """牌面底色：米白渐变"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            # 从 #faf5e8 到 #f0e6cc
            t = y / H
            r = int(250 * (1 - t) + 240 * t)
            g = int(245 * (1 - t) + 230 * t)
            b = int(232 * (1 - t) + 204 * t)
            px[x, y] = (r, g, b, 255)
    return img


def draw_wan(n, name):
    """万子：上面黑色数字，下面红色「萬」"""
    img = bg()
    d = ImageDraw.Draw(img)
    nums = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
    # 上面数字
    f1 = font(64)
    d.text((W // 2, 55), nums[n - 1], fill=(30, 30, 30, 255), font=f1, anchor="mm")
    # 下面「萬」
    f2 = font(52)
    d.text((W // 2, 155), "萬", fill=(180, 40, 35, 255), font=f2, anchor="mm")
    img.save(OUT / f"{name}.png")


# 筒子颜色：标准配色
TONG_COLORS = [
    (50, 80, 160),   # 蓝
    (180, 40, 35),   # 红
    (40, 120, 60),   # 绿
    (50, 80, 160),
    (180, 40, 35),
    (40, 120, 60),
    (180, 40, 35),
    (50, 80, 160),
    (180, 40, 35),
]


def draw_tong(n, name):
    """筒子：彩色圆点"""
    img = bg()
    d = ImageDraw.Draw(img)
    R = 16  # 圆点半径
    # 布局：根据数量排列
    positions = []
    if n == 1:
        # 1筒：1个大圆
        positions = [(W // 2, H // 2)]
    elif n == 2:
        positions = [(W // 2, 70), (W // 2, 150)]
    elif n == 3:
        positions = [(W // 2 - 30, 60), (W // 2, 110), (W // 2 + 30, 160)]
    elif n == 4:
        positions = [(50, 60), (100, 60), (50, 160), (100, 160)]
    elif n == 5:
        positions = [(50, 55), (100, 55), (W // 2, 110), (50, 165), (100, 165)]
    elif n == 6:
        positions = [(45, 60), (75, 60), (105, 60), (45, 160), (75, 160), (105, 160)]
    elif n == 7:
        positions = [(50, 55), (80, 55), (110, 55), (65, 110), (50, 165), (80, 165), (110, 165)]
    elif n == 8:
        positions = [(50, 50), (80, 50), (110, 50), (65, 90), (95, 90), (50, 170), (80, 170), (110, 170)]
    elif n == 9:
        positions = [(45, 55), (75, 55), (105, 55), (45, 110), (75, 110), (105, 110), (45, 165), (75, 165), (105, 165)]

    for i, (x, y) in enumerate(positions):
        color = TONG_COLORS[i % len(TONG_COLORS)]
        # 外圈
        d.ellipse([x - R, y - R, x + R, y + R], fill=color + (255,), outline=(255, 255, 255, 255), width=2)
        # 内圈
        r2 = R - 6
        d.ellipse([x - r2, y - r2, x + r2, y + r2], fill=(255, 255, 255, 255), outline=color + (255,), width=2)
        # 中心
        r3 = R - 10
        d.ellipse([x - r3, y - r3, x + r3, y + r3], fill=color + (255,))
    img.save(OUT / f"{name}.png")


def draw_sou(n, name):
    """条子：绿色竹节"""
    img = bg()
    d = ImageDraw.Draw(img)
    green = (40, 120, 60, 255)
    lw = 6  # 竹节宽度
    if n == 1:
        # 1条：一只小麻雀（简化）
        # 身体
        d.ellipse([55, 80, 95, 130], fill=(220, 60, 50, 255), outline=(180, 40, 35, 255), width=2)
        # 头
        d.ellipse([65, 60, 90, 85], fill=(240, 240, 230, 255), outline=(180, 40, 35, 255), width=2)
        # 嘴
        d.polygon([(85, 70), (100, 75), (85, 80)], fill=(200, 150, 50, 255))
        # 翅膀
        d.ellipse([60, 95, 90, 125], fill=(240, 240, 230, 255))
        # 脚
        d.line([(70, 130), (70, 150)], fill=(180, 140, 50, 255), width=2)
        d.line([(85, 130), (85, 150)], fill=(180, 140, 50, 255), width=2)
    else:
        # 竹节竖条
        positions = []
        if n == 2:
            positions = [(65, 80), (85, 150)]
        elif n == 3:
            positions = [(75, 60), (55, 140), (95, 140)]
        elif n == 4:
            positions = [(55, 70), (90, 70), (55, 160), (90, 160)]
        elif n == 5:
            positions = [(50, 60), (95, 60), (72, 110), (50, 165), (95, 165)]
        elif n == 6:
            positions = [(45, 65), (75, 65), (105, 65), (45, 165), (75, 165), (105, 165)]
        elif n == 7:
            positions = [(55, 55), (85, 55), (70, 110), (50, 165), (80, 165), (110, 165)]
        elif n == 8:
            positions = [(50, 55), (80, 55), (110, 55), (65, 105), (95, 105), (50, 170), (80, 170), (110, 170)]
        elif n == 9:
            positions = [(45, 55), (75, 55), (105, 55), (45, 110), (75, 110), (105, 110), (45, 165), (75, 165), (105, 165)]

        for x, y in positions:
            # 竖条竹节
            d.rounded_rectangle([x - lw, y - 22, x + lw, y + 22], radius=3, fill=green, outline=(30, 90, 45, 255), width=1)
            # 中间节
            d.line([(x - lw, y), (x + lw, y)], fill=(30, 90, 45, 255), width=1)
    img.save(OUT / f"{name}.png")


def draw_chun():
    """红中：红色「中」"""
    img = bg()
    d = ImageDraw.Draw(img)
    f = font(110)
    d.text((W // 2, H // 2), "中", fill=(180, 40, 35, 255), font=f, anchor="mm")
    img.save(OUT / "Chun.png")


if __name__ == "__main__":
    for i in range(1, 10):
        draw_wan(i, f"Man{i}")
        draw_tong(i, f"Pin{i}")
        draw_sou(i, f"Sou{i}")
    draw_chun()
    print(f"Generated {len(list(OUT.glob('*.png')))} tiles")
