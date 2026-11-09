#!/usr/bin/env bash
# scripts/configure-rootfs.sh —— chroot 进 SteamOS 树做 liuqin 适配（只在 arm64 runner 上跑）。
#
# 做的事（故意很少，一次只改一类东西）：
#   1. /etc/fstab：linux_root / ext4；linux_home /home ext4,nofail
#   2. hostname = liuqin
#   3. 建 steamos 用户（若镜像里没有 UID 1000 用户），密码 steamos
#   4. 停掉依赖 Valve 服务器/VR 硬件的更新服务（steamos-update、atomupd、rauc、bootc、steamos-manager）
#   5. 默认开 SSH 由 ENABLE_SSH=1 控制（首次调试要开，发布固件建议关）
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="${WORK:-/mnt/steamos-work}"
TREE="$WORK/tree"
ENABLE_SSH="${ENABLE_SSH:-0}"

require_root
[[ -d "$TREE/usr" ]] || die "没有 $TREE 树（先跑 assemble-rootfs.sh）"

cleanup() {
  for m in dev/pts dev proc sys run; do
    mountpoint -q "$TREE/$m" && umount -l "$TREE/$m" 2>/dev/null || true
  done
}
trap cleanup EXIT

for m in dev dev/pts proc sys run; do
  mkdir -p "$TREE/$m"
  mount --bind "/$m" "$TREE/$m"
done
cp -f /etc/resolv.conf "$TREE/etc/resolv.conf"

cat > "$TREE/etc/fstab" <<'EOF'
# <file system>            <mount point> <type> <options>              <dump> <pass>
PARTLABEL=linux_root       /             ext4   defaults,noatime       0      1
PARTLABEL=linux_home       /home         ext4   defaults,nofail        0      2
tmpfs                      /tmp          tmpfs  defaults,nosuid,nodev  0      0
EOF
log "已写 /etc/fstab"

echo liuqin > "$TREE/etc/hostname"

chroot "$TREE" /bin/bash -euo pipefail <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
if ! getent passwd 1000 >/dev/null; then
  groupadd -f wheel || true
  useradd -m -u 1000 -s /bin/bash -G wheel,video,render,input,audio -c "SteamOS" steamos || true
  echo 'steamos:steamos' | chpasswd
  echo "已建用户 steamos（密码 steamos，登录后立刻改）"
else
  echo "UID 1000 已存在: $(getent passwd 1000 | cut -d: -f1)"
fi
# 离线停用：删 wants 软链并 mask（不依赖 dbus）
# 前一组是 Valve 更新链（依赖 Valve 服务器/只读根），后一组是 Steam Frame 的
# VR/FPGA/风扇/电源监测/adb 等专用服务——liuqin 上没有这些硬件，留着只会刷失败日志。
for unit in steamos-update.service atomupd.service atomupd-daemon.service rauc.service \
            bootc-fetch-apply-updates.service steamos-manager.service steamos-boot.service \
            deckard-audio-setup.service deckard-boot-images.service deckard-charger.service \
            deckard-fan-control.service deckard-fpga-resume.service deckard-fpga.service \
            deckard-led-control.service deckard-power-monitor.service deckard-typec-logger.service \
            dsp_service.service steamvr-program-ble.service steamvr-set-kernel-thread-priorities.service \
            steamvr-v4l2loopback.service gpu-trace.service iris-driver-rebind.service \
            setubootenv.service adbd.service adbd-pre.service adbd-post.service usb-gadget.service; do
  find /etc/systemd/system -maxdepth 3 -type l -name "$unit" -delete 2>/dev/null || true
  ln -sfn /dev/null "/etc/systemd/system/$unit" 2>/dev/null || true
done
CHROOT

if [[ "$ENABLE_SSH" == 1 ]]; then
  chroot "$TREE" /bin/bash -c 'systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || echo "没有 ssh 服务，跳过"' || true
  log "SSH 已尝试启用"
else
  chroot "$TREE" /bin/bash -c 'systemctl disable ssh 2>/dev/null; systemctl disable sshd 2>/dev/null; true' || true
fi

# 首启先停在 multi-user：真机第一次进桌面若黑屏，TTY 与 SSH 还在，能继续查。
# 验证过 TTY/网络后再把 default.target 切回 graphical.target（`systemctl set-default graphical`）。
if [[ "${DEBUG_BOOT:-1}" == 1 ]]; then
  ln -sfn /usr/lib/systemd/system/multi-user.target "$TREE/etc/systemd/system/default.target"
  log "default.target → multi-user（调试期；验证后 systemctl set-default graphical.target）"
fi

log "configure 完成"
