#!/usr/bin/env bash
# scripts/assemble-rootfs.sh —— 把 Frame 的 btrfs rootfs 铺成普通目录树，并换上 liuqin 的模块/固件。
#
# 输入：$OUT/rootfs.frame（fetch-frame.sh 产物）
#       $WORK/liuqin/modules/<kver>/…（Ubuntu 底包里抠出来的 /lib/modules）
#       $WORK/liuqin/firmware/…（Ubuntu 底包里抠出来的 /lib/firmware）
# 输出：$WORK/tree（SteamOS 用户态 + liuqin 内核模块/固件）
#
# btrfs 布局按 zhao 的脚本处理：subvolid=5 挂载才能看到根子卷与 @var/@home 平级子卷；
# 根子卷内容 rsync 进树，@var→/var、@home→/home 合并进去。
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="${WORK:-/mnt/steamos-work}"
OUT="${OUT:-$WORK/out}"
TREE="$WORK/tree"
MNT="$WORK/frame"
ROOTFS="$OUT/rootfs.frame"

require_root
need_cmd rsync; need_cmd mount
[[ -f "$ROOTFS" ]] || die "缺少 $ROOTFS（先跑 fetch-frame.sh）"
[[ "$(fs_type "$ROOTFS" || true)" == btrfs ]] || die "$ROOTFS 不是 btrfs"

mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
mount -o loop,ro,subvolid=5 "$ROOTFS" "$MNT" || die "挂载 btrfs subvolid=5 失败"
trap 'umount "$MNT" 2>/dev/null || true' EXIT

log "根目录内容:"; ls -1 "$MNT" | head -30

# 定位根子卷：能提供 /usr/lib/os-release 的那一个。
ROOT_SUBVOL=""
for cand in "" @ rootfs @rootfs @steamos; do
  if [[ -f "$MNT/$cand/usr/lib/os-release" ]]; then ROOT_SUBVOL="$cand"; break; fi
done
[[ -n "$ROOT_SUBVOL" ]] || die "找不到根子卷（没有任何候选含 usr/lib/os-release）"
log "根子卷: '${ROOT_SUBVOL:-<顶层>}'"

# 平级子卷：@var→var、@home→home（存在则合并）。
EXTRAS=()
for cand in @var var @home home; do
  if [[ -d "$MNT/$cand" && "$cand" != "$ROOT_SUBVOL" ]]; then
    case "$cand" in
      @var|var) EXTRAS+=("@var:var") ;;
      @home|home) EXTRAS+=("@home:home") ;;
    esac
  fi
done

rm -rf "$TREE"; mkdir -p "$TREE"
log "rsync 根子卷 → $TREE（-aHAX，保留 xattr/ACL/硬链接）"
rsync -aHAX --numeric-ids "$MNT/$ROOT_SUBVOL/." "$TREE/"

for pair in "${EXTRAS[@]}"; do
  src="$MNT/${pair%%:*}"; dst="$TREE/${pair##*:}"
  [[ -d "$src" ]] || continue
  log "合并子卷 ${pair%%:*} → ${pair##*:}"
  mkdir -p "$dst"
  rsync -aHAX --numeric-ids "$src/." "$dst/"
done

umount "$MNT"
trap - EXIT

# 清掉 Steam Frame 的内核与启动文件：liuqin 用 boot.img 里的内核 + dtb。
log "清理 /boot 与 /usr/lib/modules"
rm -rf "$TREE/boot"/* "$TREE/usr/lib/modules"/* 2>/dev/null || true
rm -f "$TREE/etc/fstab"

# 注入 liuqin 内核模块与固件（来自 v0.6.0 底包，保证与 boot.img 的 vermagic 一致）。
if [[ -d "$WORK/liuqin/modules" ]]; then
  log "注入内核模块"
  mkdir -p "$TREE/usr/lib/modules"
  rsync -aHAX --numeric-ids "$WORK/liuqin/modules/." "$TREE/usr/lib/modules/"
else
  warn "没有 $WORK/liuqin/modules —— 树里将没有 liuqin 模块（Wi-Fi/触控/音频多半起不来）"
fi
if [[ -d "$WORK/liuqin/firmware" ]]; then
  log "注入固件"
  mkdir -p "$TREE/lib/firmware"
  rsync -aHAX --numeric-ids "$WORK/liuqin/firmware/." "$TREE/lib/firmware/"
else
  warn "没有 $WORK/liuqin/firmware"
fi

# 硬性自检：底包里那几个关键固件必须在。
for f in qcom/sm8475/liuqin/a730_zap.mbn qcom/sm8475/liuqin/adsp.mbn novatek/liuqin/novatek_nt36532_m81_fw_csot.bin; do
  if [[ -e "$TREE/lib/firmware/$f" || -e "$TREE/usr/lib/firmware/$f" ]]; then
    log "固件 OK: $f"
  else
    warn "固件缺失: $f（若底包结构变化，改用 FIRMWARE_URL 单独取）"
  fi
done

log "完成: $TREE（$(du -sh "$TREE" | cut -f1)）"
