#!/usr/bin/env bash
# scripts/make-boot-img.sh —— 用上游 v0.6.0 的内核 + dtb，套我们自己的最小 initramfs。
#
# 产物：$OUT/boot-steamos-liuqin.img
#   kernel : 从上游 boot.img 原样取出（liuqin 6.17，mainline + yzddmr6 补丁）
#   dtb    : 从上游 boot.img 末尾取出（sm8475-xiaomi-liuqin.dtb）
#   ramdisk: boot/init + 静态 busybox（ubuntu ports 的 busybox-static arm64）
#
# 平板 fastboot 用法（解锁后）：fastboot flash boot_a boot-steamos-liuqin.img
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="${WORK:-/mnt/steamos-work}"
OUT="${OUT:-$WORK/out}"
BOOT_URL="${BOOT_URL:-https://github.com/yzddmr6/xiaomipad-6pro-mainline/releases/download/v0.6.0/boot.img}"
BUSYBOX_URL="${BUSYBOX_URL:-http://ports.ubuntu.com/pool/main/b/busybox/busybox-static_1.36.1-6ubuntu3.1_arm64.deb}"
BUSYBOX_SHA="${BUSYBOX_SHA:-d96535e0402c011e0ee43449799df2f4504d44b842e4f2b3a6cbc845508eaafc}"
BIN_SHA="${BIN_SHA:-52151e7f322f926b64049cdaa1410dc3ea6485525e0624b05813791c219ae933}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$WORK/boot" "$OUT"

need_cmd python3; need_cmd cpio; need_cmd gzip; need_cmd curl

[[ -f "$WORK/boot/upstream-boot.img" ]] || {
  log "下载上游 boot.img"
  curl -fL --retry 3 -o "$WORK/boot/upstream-boot.img" "$BOOT_URL"
}

log "拆出 kernel / dtb"
python3 - "$WORK/boot/upstream-boot.img" "$WORK/boot" <<'PY'
import sys
img, outdir = sys.argv[1], sys.argv[2]
b = open(img, 'rb').read()
assert b[:8] == b'ANDROID!', 'not an Android boot image'
hv = int.from_bytes(b[0x28:0x2c], 'little')
assert hv == 2, f'header version {hv} unsupported here'
page = int.from_bytes(b[0x24:0x28], 'little')
ks = int.from_bytes(b[0x08:0x0c], 'little')
rs = int.from_bytes(b[0x10:0x14], 'little')
def ceil_div(a, b): return (a + b - 1) // b
k_off = page
r_off = page * (1 + ceil_div(ks, page))
d_off = page * (1 + ceil_div(ks, page) + ceil_div(rs, page))
open(f'{outdir}/kernel', 'wb').write(b[k_off:k_off + ks])
open(f'{outdir}/ramdisk.upstream.gz', 'wb').write(b[r_off:r_off + rs])
open(f'{outdir}/dtb', 'wb').write(b[d_off:])
print(f'page={page} kernel={ks} ramdisk={rs} dtb={len(b) - d_off}')
PY
[[ "$(head -c 4 "$WORK/boot/dtb" | od -An -tx1 | tr -d ' \n')" == d00dfeed ]] || die "dtb 魔数不对"

if [[ ! -x "$WORK/boot/busybox/usr/bin/busybox" ]]; then
  log "下载静态 busybox"
  curl -fL --retry 3 -o "$WORK/boot/busybox.deb" "$BUSYBOX_URL"
  echo "$BUSYBOX_SHA  $WORK/boot/busybox.deb" | sha256sum -c -
  rm -rf "$WORK/boot/busybox"; mkdir -p "$WORK/boot/busybox"
  dpkg-deb -x "$WORK/boot/busybox.deb" "$WORK/boot/busybox"
  echo "$BIN_SHA  $WORK/boot/busybox/usr/bin/busybox" | sha256sum -c -
fi

log "组装 initramfs"
IR="$WORK/boot/initramfs"
rm -rf "$IR"; mkdir -p "$IR"/{bin,sbin,proc,sys,dev,newroot,run,tmp}
cp "$WORK/boot/busybox/usr/bin/busybox" "$IR/bin/busybox"
chmod 755 "$IR/bin/busybox"
for link in sh ash mount umount switch_root sleep grep cat ls mkdir dmesg; do
  ln -sf busybox "$IR/bin/$link"
done
for link in mkdir; do ln -sf ../bin/busybox "$IR/sbin/$link" 2>/dev/null || true; done
cp "$ROOT/boot/init" "$IR/init"; chmod 755 "$IR/init"
( cd "$IR" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$WORK/boot/initramfs.cpio.gz"

log "打包 boot.img"
if ! command -v mkbootimg >/dev/null 2>&1; then
  python3 -m pip install --quiet --break-system-packages mkbootimg 2>/dev/null \
    || python3 -m pip install --quiet --user mkbootimg \
    || die "装不上 mkbootimg"
  export PATH="$HOME/.local/bin:$PATH"
fi
mkbootimg \
  --kernel "$WORK/boot/kernel" \
  --ramdisk "$WORK/boot/initramfs.cpio.gz" \
  --dtb "$WORK/boot/dtb" \
  --header_version 2 --pagesize 4096 \
  --output "$OUT/boot-steamos-liuqin.img"

ls -l "$OUT/boot-steamos-liuqin.img"
sha256sum "$OUT/boot-steamos-liuqin.img" | tee "$OUT/boot-steamos-liuqin.img.sha256"
log "完成"
