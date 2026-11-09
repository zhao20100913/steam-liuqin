#!/usr/bin/env bash
# scripts/fetch-frame.sh —— 从 Valve 的 Steam Frame 恢复镜像里只取出 rootfs-A 分区。
#
# 底包形态（steamframe-oobe-repair-20260922.5153644-0.3.0，实测）：
#   .img.bz2（约 4 GB）→ 7.5 GB GPT 整盘镜像；分区：
#     esp(256M) / efi-A(64M) / rootfs-A(5G, btrfs, label=rootfs-A) / var-A(256M) / home(100M)
#   rootfs-A 是 btrfs（超块 _BHRfS_M 在 65536），不是 ext4+zstd。
#
# 两遍流式：先只取前 4 MiB 解 GPT，再 curl|bunzip2|dd 精确切出 5 GB 分区，
# 全程不落 7.5 GB 整盘镜像（GitHub 托管 runner 只有约 14 GB 盘）。
#
# 环境变量：FRAME_URL（默认版本化地址）、WORK（默认 /mnt/steamos-work）
set -euo pipefail
source "$(dirname "$0")/lib.sh"

FRAME_URL="${FRAME_URL:-https://steamdeck-images.steamos.cloud/recovery/steamframe-oobe-repair-20260922.5153644-0.3.0.img.bz2}"
WORK="${WORK:-/mnt/steamos-work}"
OUT="${OUT:-$WORK/out}"
mkdir -p "$WORK" "$OUT"

HEAD="$WORK/frame-head.bin"
ROOTFS="$OUT/rootfs.frame"
rm -f "$HEAD" "$ROOTFS"

need_cmd curl; need_cmd bunzip2; need_cmd python3; need_cmd dd
log "下载 URL: $FRAME_URL（两遍流式）"

log "第 1 遍：取前 4 MiB 解 GPT"
# 下游 head 读够就关管，上游 curl/bunzip2 会拿到 SIGPIPE —— 只认最终文件大小，不认管道退出码。
dload "$FRAME_URL" | bunzip2 -c | head -c 4194304 > "$HEAD" || true
[[ "$(stat -c %s "$HEAD")" -ge 4096 ]] || die "头部过短，底包可能损坏"

read -r START SECTORS < <(gpt_find "$HEAD" rootfs-A) || die "在 GPT 里找不到 rootfs-A"
START="${START//[^0-9]/}"; SECTORS="${SECTORS//[^0-9]/}"
[[ -n "$START" && -n "$SECTORS" ]] || die "GPT 解析结果为空"
log "rootfs-A: start_lba=$START sectors=$SECTORS（$((SECTORS / 2048)) MiB）"

log "第 2 遍：流式切出 rootfs-A"
set +e
dload "$FRAME_URL" | bunzip2 -c \
  | dd of="$ROOTFS" bs=512 skip="$START" count="$SECTORS" conv=sparse status=none
RC=$?
set -e
[[ "$RC" -eq 0 || "$RC" -eq 141 ]] || die "切分区失败（rc=$RC, sectors=$SECTORS）"

TSIZE=$((SECTORS * 512))
ACTUAL="$(stat -c %s "$ROOTFS")"
[[ "$ACTUAL" -ge "$TSIZE" ]] || die "输出大小 $ACTUAL < $TSIZE"

FSTYPE="$(fs_type "$ROOTFS" || true)"
[[ "$FSTYPE" == btrfs ]] || die "rootfs-A 不是 btrfs（识别为 '${FSTYPE}'），底包结构可能变了"
log "rootfs-A 校验通过：btrfs，$((ACTUAL / 1048576)) MiB"

rm -f "$HEAD"
printf '%s\n' "$FRAME_URL" > "$OUT/frame-source.txt"
printf '%s\n' "$TSIZE" > "$OUT/rootfs.frame.bytes"
log "完成: $ROOTFS"
