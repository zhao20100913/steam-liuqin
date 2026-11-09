#!/usr/bin/env python3
"""mk-bootimg.py —— 纯 Python 的 Android boot image v2 重打包器。

为什么不用 `pip install mkbootimg`：GitHub 的 ubuntu-24.04-arm runner 上
pip 拉 PyPI 失败（`from versions: none`）。v2 格式本身很简单，直接复用上游
boot.img 的头部与 kernel/dtb，只替换 ramdisk 即可，零依赖。

用法：
  mk-bootimg.py --orig boot.img --ramdisk initramfs.cpio.gz --output out.img
"""
import argparse
import struct
import sys

MAGIC = b'ANDROID!'
HDR_V2 = 1660
ID_OFF = 576


def align(n, page):
    return (n + page - 1) // page * page


def parse(data):
    if data[:8] != MAGIC:
        raise SystemExit('不是 Android boot image（magic 不对）')
    version = struct.unpack_from('<I', data, 40)[0]
    if version != 2:
        raise SystemExit(f'只支持 header v2，实际 v{version}')
    page = struct.unpack_from('<I', data, 36)[0]
    kernel_size = struct.unpack_from('<I', data, 8)[0]
    ramdisk_size = struct.unpack_from('<I', data, 16)[0]
    second_size = struct.unpack_from('<I', data, 24)[0]
    dtbo_size = struct.unpack_from('<I', data, 1632)[0]
    dtb_size = struct.unpack_from('<I', data, 1648)[0]

    off = page
    sizes = [kernel_size, ramdisk_size, second_size, dtbo_size, dtb_size]
    spans = []
    for size in sizes:
        spans.append((off, size))
        off = align(off + size, page)
    return page, spans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--orig', required=True)
    ap.add_argument('--ramdisk', required=True)
    ap.add_argument('--output', required=True)
    args = ap.parse_args()

    orig = open(args.orig, 'rb').read()
    page, spans = parse(orig)
    ramdisk = open(args.ramdisk, 'rb').read()

    header = bytearray(orig[:page])
    struct.pack_into('<I', header, 16, len(ramdisk))  # ramdisk_size
    header[ID_OFF:ID_OFF + 32] = b'\0' * 32           # id 在 v2 已废弃

    # 顺序：header | kernel | ramdisk | second | recovery_dtbo | dtb
    segs = []
    for (off, size), idx in zip(spans, range(5)):
        if idx == 1:
            segs.append(ramdisk)
        else:
            segs.append(orig[off:off + size])

    buf = bytearray(header)
    for seg in segs:
        buf += seg
        buf += b'\0' * (align(len(buf), page) - len(buf))

    open(args.output, 'wb').write(buf)
    print(f'wrote {args.output}: {len(buf)} bytes (page={page}, ramdisk={len(ramdisk)})')


if __name__ == '__main__':
    sys.exit(main())
