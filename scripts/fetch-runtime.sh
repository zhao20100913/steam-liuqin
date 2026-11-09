#!/usr/bin/env bash
# scripts/fetch-runtime.sh —— 从上游 Ubuntu v0.6.0 底包里只抠 liuqin 运行时：
#   /lib/modules/<kver>（与 boot.img 同内核，vermagic 必须一致）
#   /lib/firmware（a730_zap/adsp/cdsp/slpi、novatek 触控、cs35l41、wcd938x……）
#
# 不重新编内核：v0.6.0 的 boot.img 与这份模块是同一二进制产出的，直接复用最稳。
# 传入 RUNTIME_BASE 可换成别的 release 资产目录。
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="${WORK:-/mnt/steamos-work}"
BASE="${RUNTIME_BASE:-https://github.com/yzddmr6/xiaomipad-6pro-mainline/releases/download/v0.6.0}"
PARTS=(rootfs.tar.gz.part-00 rootfs.tar.gz.part-01 rootfs.tar.gz.part-02)

mkdir -p "$WORK/dl" "$WORK/liuqin"
cd "$WORK/dl"

for p in "${PARTS[@]}"; do
  if [[ -s "$p" ]]; then log "已有 $p"; continue; fi
  log "下载 $p"
  curl -fL --retry 3 --retry-delay 5 -o "$p" "$BASE/$p"
done

ARCHIVE="$WORK/dl/rootfs.tar.gz"
if [[ ! -s "$ARCHIVE" ]]; then
  log "合并分卷"
  cat "${PARTS[@]}" > "$ARCHIVE"
fi
SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
log "底包 sha256: $SHA"
printf '%s\n' "$SHA" > "$WORK/liuqin/ubuntu-rootfs.sha256"

log "只解出 /lib/modules 与 /lib/firmware"
rm -rf "$WORK/liuqin/extract"; mkdir -p "$WORK/liuqin/extract"
# 前缀可能是 ./lib/... 也可能是 lib/...，两套模式都试；不匹配的模式让 tar 报错但不致命。
tar -xzf "$ARCHIVE" -C "$WORK/liuqin/extract" --wildcards \
  './lib/modules/*' 'lib/modules/*' './lib/firmware/*' 'lib/firmware/*' \
  './usr/lib/firmware/*' 'usr/lib/firmware/*' './usr/lib/modules/*' 'usr/lib/modules/*' \
  2>&1 | tail -5 || true

for d in extract/lib/modules extract/usr/lib/modules; do
  [[ -d "$WORK/liuqin/$d" ]] || continue
  mkdir -p "$WORK/liuqin/modules"
  cp -a "$WORK/liuqin/$d/." "$WORK/liuqin/modules/"
done
for d in extract/lib/firmware extract/usr/lib/firmware; do
  [[ -d "$WORK/liuqin/$d" ]] || continue
  mkdir -p "$WORK/liuqin/firmware"
  cp -a "$WORK/liuqin/$d/." "$WORK/liuqin/firmware/"
done

KVER="$(ls "$WORK/liuqin/modules" 2>/dev/null | head -1)"
[[ -n "$KVER" ]] || die "没抠出内核模块（底包布局变了？）"
log "内核: $KVER；模块 $(find "$WORK/liuqin/modules" -name '*.ko*' | wc -l) 个；固件 $(find "$WORK/liuqin/firmware" -type f | wc -l) 个"

for f in qcom/sm8475/liuqin/a730_zap.mbn qcom/sm8475/liuqin/adsp.mbn novatek/liuqin/novatek_nt36532_m81_fw_csot.bin; do
  [[ -e "$WORK/liuqin/firmware/$f" ]] && log "固件 OK: $f" || warn "固件缺失: $f"
done

rm -rf "$WORK/liuqin/extract"
log "清理底包分区文件（保留 sha256 证据）"
rm -f "$ARCHIVE" "$WORK/dl"/rootfs.tar.gz.part-*
