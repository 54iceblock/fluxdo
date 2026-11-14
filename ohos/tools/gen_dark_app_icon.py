#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 FluxDO 鸿蒙「深色模式」图标资源（纯标准库，无 Pillow 依赖）。

两种模式：

1) 默认：桌面备用图标（1024×1024），产出三个文件到 AppScope/resources/base/media/
     app_icon_dark.json    分层图标描述（background=纯色背景层，foreground=经典图标圆）
     app_icon_dark_bg.png  1024x1024 不透明 #1C1C1E（深色底）
     app_icon_dark_fg.png  1024x1024 RGBA 透明底，经典图标圆形前景

2) --start-icon：启动窗深色图标（192×192），产出到
   entry/src/main/resources/dark/media/start_window_icon.png
   与 base/media/icon.png 同尺寸，圆外完全透明，叠在深色启动窗背景（#111419）上不出现白色方块。

前景几何取自 Android 侧同款资源
（repo/android/app/src/main/res/drawable/ic_launcher_foreground.xml），
按 1024 画布定义，再按画布尺寸等比缩放：
  中心 (size/2, size/2)
  底圆        r = 448*S*size/1024  #F0F0F0   （421~448 之间露出的部分 = 深色底上的浅色外环）
  上段  r<=421*S 且 y <= 中心-188*S  #1C1C1E
  下段  r<=421*S 且 y >= 中心+188*S  #FFB003

注意：Android 的 ic_launcher_foreground.xml 带 group scale=0.65，那是自适应图标
108dp/72dp 安全区的需要；鸿蒙分层图标由桌面按设备形状裁切，前景应铺满安全区，
所以这里 S 默认 1.0（1024 画布上圆直径 896/1024 = 87.5%，192 画布上 168/192 = 87.5%），
与 repo/assets/images/icon_default_dark_preview.png 的比例一致，不要照搬 0.65。

抗锯齿：每像素 4x4 超采样；内部纯色区走快速路径。

用法：
  python gen_dark_app_icon.py                        # 桌面备用图标，默认 S=1.0
  python gen_dark_app_icon.py --scale 0.9            # 调整前景缩放
  python gen_dark_app_icon.py --start-icon           # 只生成 192×192 深色启动图标
  python gen_dark_app_icon.py --start-icon --out-dir D:\\tmp   # 输出到别处（沙箱预览用）
"""

import argparse
import math
import os
import struct
import zlib

SIZE = 1024            # 桌面备用图标画布
START_ICON_SIZE = 192  # 启动窗图标画布（与 base/media/icon.png 一致）

COLOR_BG = (0x1C, 0x1C, 0x1E)     # 深色底 / 上段
COLOR_LIGHT = (0xF0, 0xF0, 0xF0)  # 底圆（外环 + 中间带）
COLOR_ORANGE = (0xFF, 0xB0, 0x03)  # 下段

R_OUTER = 448.0
R_INNER = 421.0
BAND_HALF = 188.0

SS = 4  # 每像素每轴超采样数
OFFSETS = [(i + 0.5) / SS - 0.5 for i in range(SS)]

_HERE = os.path.dirname(os.path.abspath(__file__))

MEDIA_DIR = os.path.join(_HERE, '..', 'AppScope', 'resources', 'base', 'media')
START_ICON_DIR = os.path.join(
    _HERE, '..', 'entry', 'src', 'main', 'resources', 'dark', 'media',
)


def write_png(path, rows_rgba, size):
    """rows_rgba: list[bytearray]，每行 size*4 字节（RGBA），8bit。"""
    raw = bytearray()
    for row in rows_rgba:
        raw.append(0)  # filter type 0 (None)
        raw += row

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)
    print('  wrote %s (%d bytes)' % (path, len(png)))


def gen_background(size=SIZE):
    row = bytearray()
    for _ in range(size):
        row += bytes((COLOR_BG[0], COLOR_BG[1], COLOR_BG[2], 255))
    return [bytearray(row) for _ in range(size)]


def gen_foreground(scale, size=SIZE):
    """经典图标圆：透明画布 + 浅色底圆 + 上段深色 + 下段橙色。"""
    center = size / 2.0
    unit = size / 1024.0          # 几何按 1024 画布定义，等比缩放到目标画布
    r_out = R_OUTER * scale * unit
    r_in = R_INNER * scale * unit
    y_top = center - BAND_HALF * scale * unit   # 上段下边界
    y_bot = center + BAND_HALF * scale * unit   # 下段上边界

    r_out2 = r_out * r_out
    r_in2 = r_in * r_in

    # 只遍历圆的包围盒，盒外整像素透明
    bx0 = max(0, int(math.floor(center - r_out)) - 1)
    bx1 = min(size - 1, int(math.ceil(center + r_out)) + 1)

    # 区域编号：0=上段深色 1=中间浅色 2=下段橙色
    rgb = (COLOR_BG, COLOR_LIGHT, COLOR_ORANGE)

    transparent_row = bytearray(size * 4)
    out = []

    total = SS * SS
    inv = 1.0 / total

    for y in range(size):
        if y < bx0 or y > bx1:
            out.append(bytearray(transparent_row))
            continue
        row = bytearray(size * 4)
        dy0 = y - center
        ylo = y - 0.5          # 像素覆盖的绝对 y 范围
        yhi = y + 0.5
        # 4 个子采样行的区域归属（0=上段深色 1=中间浅色 2=下段橙色）
        band_of_sub = [0 if (y + oy) <= y_top
                       else (2 if (y + oy) >= y_bot else 1)
                       for oy in OFFSETS]
        # 整像素都落在同一条横带内？
        band_stable = (yhi <= y_top) or (ylo >= y_bot) or (ylo >= y_top and yhi <= y_bot)
        band_whole = 0 if yhi <= y_top else (2 if ylo >= y_bot else 1)

        for x in range(bx0, bx1 + 1):
            dx0 = x - center
            # 快速路径 1：整像素在圆外 → 透明
            ax = abs(dx0) - 0.5
            ay = abs(dy0) - 0.5
            if ax < 0:
                ax = 0.0
            if ay < 0:
                ay = 0.0
            if ax * ax + ay * ay > r_out2:
                continue
            # 快速路径 2：整像素在内圆内且不跨横带 → 纯色
            if band_stable:
                bx = abs(dx0) + 0.5
                by = abs(dy0) + 0.5
                if bx * bx + by * by <= r_in2:
                    c = rgb[band_whole]
                    o = x * 4
                    row[o] = c[0]
                    row[o + 1] = c[1]
                    row[o + 2] = c[2]
                    row[o + 3] = 255
                    continue

            # 超采样
            cnt = [0, 0, 0]  # 深色 / 浅色 / 橙色
            for sy in range(SS):
                dy = dy0 + OFFSETS[sy]
                dy2 = dy * dy
                b = band_of_sub[sy]
                for sx in range(SS):
                    dx = dx0 + OFFSETS[sx]
                    d2 = dx * dx + dy2
                    if d2 <= r_in2:
                        cnt[b] += 1
                    elif d2 <= r_out2:
                        cnt[1] += 1
            covered = cnt[0] + cnt[1] + cnt[2]
            if covered == 0:
                continue
            o = x * 4
            # 预乘后反预乘，避免透明边缘出现黑边
            row[o] = int(round((COLOR_BG[0] * cnt[0] + COLOR_LIGHT[0] * cnt[1] +
                                COLOR_ORANGE[0] * cnt[2]) / covered))
            row[o + 1] = int(round((COLOR_BG[1] * cnt[0] + COLOR_LIGHT[1] * cnt[1] +
                                    COLOR_ORANGE[1] * cnt[2]) / covered))
            row[o + 2] = int(round((COLOR_BG[2] * cnt[0] + COLOR_LIGHT[2] * cnt[1] +
                                    COLOR_ORANGE[2] * cnt[2]) / covered))
            row[o + 3] = int(round(255.0 * covered * inv))
        out.append(row)
    return out


def gen_desktop_icons(media_dir, scale):
    print('生成深色备用图标: S=%.3f  圆直径=%.1fpx (%.1f%%)' %
          (scale, R_OUTER * 2 * scale, R_OUTER * 2 * scale / SIZE * 100))
    write_png(os.path.join(media_dir, 'app_icon_dark_bg.png'),
              gen_background(SIZE), SIZE)
    write_png(os.path.join(media_dir, 'app_icon_dark_fg.png'),
              gen_foreground(scale, SIZE), SIZE)

    json_path = os.path.join(media_dir, 'app_icon_dark.json')
    with open(json_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('{\n'
                '  "layered-image": {\n'
                '    "background": "$media:app_icon_dark_bg",\n'
                '    "foreground": "$media:app_icon_dark_fg"\n'
                '  }\n'
                '}\n')
    print('  wrote %s' % json_path)


def gen_start_icon(media_dir, scale):
    diameter = R_OUTER * 2 * scale * START_ICON_SIZE / 1024.0
    print('生成深色启动窗图标: %dx%d  S=%.3f  圆直径=%.1fpx (%.1f%%)' %
          (START_ICON_SIZE, START_ICON_SIZE, scale, diameter,
           diameter / START_ICON_SIZE * 100))
    write_png(os.path.join(media_dir, 'start_window_icon.png'),
              gen_foreground(scale, START_ICON_SIZE), START_ICON_SIZE)


def main():
    ap = argparse.ArgumentParser(description='生成 FluxDO 鸿蒙深色模式图标资源')
    ap.add_argument('--scale', type=float, default=1.0,
                    help='前景整体缩放系数 S（默认 1.0；1024 画布上圆直径 = 896*S px）')
    ap.add_argument('--start-icon', action='store_true',
                    help='生成启动窗深色图标 start_window_icon.png（192x192）'
                         '到 entry/src/main/resources/dark/media/，不生成桌面图标')
    ap.add_argument('--out-dir', default='',
                    help='输出目录（默认按模式写 AppScope 或 entry 的 media 目录；'
                         '沙箱下只想预览时可指向别处）')
    args = ap.parse_args()

    if args.start_icon:
        default_dir = START_ICON_DIR
    else:
        default_dir = MEDIA_DIR
    media = os.path.normpath(args.out_dir) if args.out_dir else os.path.normpath(default_dir)
    os.makedirs(media, exist_ok=True)

    if args.start_icon:
        gen_start_icon(media, args.scale)
    else:
        gen_desktop_icons(media, args.scale)
    print('完成。')


if __name__ == '__main__':
    main()
