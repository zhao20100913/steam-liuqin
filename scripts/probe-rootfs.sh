#!/usr/bin/env bash
# scripts/probe-rootfs.sh —— 只读勘察 SteamOS 树，把事实打到 CI 日志。
# 目的：第一轮构建先拿到「Frame 用户态到底长什么样」的证据，再定改动，而不是瞎写配置。
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="${WORK:-/mnt/steamos-work}"
TREE="$WORK/tree"
[[ -d "$TREE/usr" ]] || die "没有 $TREE"

sec() { printf '\n===== %s =====\n' "$*"; }

sec "os-release"
cat "$TREE/usr/lib/os-release" 2>/dev/null || cat "$TREE/etc/os-release" 2>/dev/null || echo 缺失

sec "大小与顶层"
du -sh "$TREE"; ls -1 "$TREE"

sec "用户"
head -5 "$TREE/etc/passwd"; grep -E '^(wheel|sudo|video|render|input|audio|plugdev):' "$TREE/etc/group" || true

sec "systemd 默认目标"
readlink -f "$TREE/etc/systemd/system/default.target" 2>/dev/null || true

sec "图形会话"
ls "$TREE/usr/share/wayland-sessions" 2>/dev/null || echo 无 wayland-sessions
ls "$TREE/usr/share/xsessions" 2>/dev/null || true
grep -H '^Exec=' "$TREE/usr/share/wayland-sessions/"*.desktop 2>/dev/null | head -5 || true
readlink -f "$TREE/etc/systemd/system/display-manager.service" 2>/dev/null || true
for b in sddm startplasma-wayland greetd; do
  [[ -e "$TREE/usr/bin/$b" ]] && echo "有 $b" || echo "无 $b"
done

sec "关键程序"
for p in usr/bin/steam usr/bin/gamescope usr/bin/gamescope-session usr/bin/steamos-session-select \
         usr/bin/plasmashell usr/bin/gnome-shell usr/bin/fex usr/bin/box64 usr/bin/wine \
         usr/bin/kwin_wayland usr/bin/Xwayland; do
  [[ -e "$TREE/$p" ]] && echo "有 $p" || echo "无 $p"
done

sec "Vulkan ICD / Mesa"
ls "$TREE/usr/share/vulkan/icd.d" 2>/dev/null || echo "无 icd.d"
find "$TREE/usr/lib" -maxdepth 3 -name 'libvulkan*.so*' -o -maxdepth 3 -name 'libvulkan_freedreno*' 2>/dev/null | head
find "$TREE/usr/lib" -maxdepth 2 -name 'libEGL*' 2>/dev/null | head -3

sec "SteamOS/Valve 私有目录"
for d in usr/lib/steamos usr/lib/steam usr/share/steamos var/lib/steamos home; do
  [[ -d "$TREE/$d" ]] && echo "有 $d: $(ls -1 "$TREE/$d" 2>/dev/null | head -5 | tr '\n' ' ')"
done

sec "首启/OOBE 服务（含 wants 软链）"
find "$TREE/etc/systemd/system" -maxdepth 2 -type l -name '*.service' 2>/dev/null | sed 's|.*/||' | sort -u | head -40

sec "包管理痕迹"
for f in etc/pacman.conf var/lib/pacman usr/lib/os-release etc/apt; do
  [[ -e "$TREE/$f" ]] && echo "有 $f"
done

sec "模块/固件"
ls "$TREE/usr/lib/modules" 2>/dev/null || echo 无模块
ls "$TREE/lib/firmware" 2>/dev/null | head -10 || echo 无固件

sec "磁盘占用前 10"
du -sh "$TREE"/* 2>/dev/null | sort -h | tail -10

log "勘察完成"
