#!/usr/bin/env bash
# scripts/pack-rootfs.sh —— 把树打成可给平板用的 rootfs.tar.gz，并按 2 GB 分卷。
#
# 平板上的装机器用 /bin/ash 起的脚本解包；tar.gz + xattr/ACL 是上游 Ubuntu 包已验证的格式。
# 分卷与上游 release 一致：rootfs.tar.gz.part-NN，用户端 cat 合并后 install.py 校验整包 sha256。
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="${WORK:-/mnt/steamos-work}"
TREE="$WORK/tree"
OUT="${OUT:-$WORK/out}"
PART_BYTES="${PART_BYTES:-2000000000}"   # 与上游 1,992,294,400 B 同量级
[[ -d "$TREE/usr" ]] || die "没有 $TREE"
mkdir -p "$OUT"

rm -f "$OUT"/steamos-liuqin-rootfs.tar.gz*
log "打包（gzip -1，保留 xattr/ACL/硬链接/属主）"
tar -C "$TREE" --xattrs --xattrs-exclude='btrfs.*' --acls --numeric-owner -cf - . \
  | gzip -1 > "$OUT/steamos-liuqin-rootfs.tar.gz"

SIZE="$(stat -c %s "$OUT/steamos-liuqin-rootfs.tar.gz")"
log "tar.gz 大小: $SIZE B"
split -b "$PART_BYTES" -d -a 2 --additional-suffix=.part \
  "$OUT/steamos-liuqin-rootfs.tar.gz" "$OUT/steamos-liuqin-rootfs.tar.gz.part-"
sha256sum "$OUT/steamos-liuqin-rootfs.tar.gz" | tee "$OUT/steamos-liuqin-rootfs.tar.gz.sha256"
rm -f "$OUT/steamos-liuqin-rootfs.tar.gz"
log "分卷:"; ls -l "$OUT"/steamos-liuqin-rootfs.tar.gz.part-*
