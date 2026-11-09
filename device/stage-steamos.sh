#!/usr/bin/env bash
# device/stage-steamos.sh —— 在平板已装好的 Ubuntu 里执行（root），把 SteamOS 铺到
# linux_home 分区，然后把 linux_root / linux_home 两个 GPT 分区名互换。
#
# 为什么这样换根：不能在运行中的 Ubuntu 根上删文件。做法是
#   linux_home（大分区，Ubuntu 的 /home）→ 格式化成 ext4、解 SteamOS → 改名为 linux_root
#   linux_root（32 GiB，Ubuntu 根）→ 改名成 linux_home
# 换完重启，我们自己编译的 boot.img（boot/init 只认 PARTNAME=linux_root）就会挂到 SteamOS。
#
# 用法（Ubuntu 终端里）：
#   sudo bash stage-steamos.sh https://github.com/<user>/<repo>/releases/download/<tag>
#   sudo REBOOT=1 bash stage-steamos.sh <url>
#
# 回滚：sudo bash stage-steamos.sh --rollback
set -euo pipefail

log()  { echo "[stage] $*"; }
die()  { echo "[stage] 错误: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "必须 root"

ROOT_DEV="$(findmnt -no SOURCE / )"
DISK="$(lsblk -no PKNAME "$ROOT_DEV" | head -1)"
[[ -n "$DISK" ]] || die "找不到根分区所在的磁盘"
DISK="/dev/$DISK"
log "根分区 $ROOT_DEV  磁盘 $DISK"

part_label() { lsblk -no PARTLABEL "$1"; }
partnum()    { lsblk -no PARTN "$1"; }

find_by_label() {
  local want="$1" p
  while read -r p; do
    [[ "$(part_label "$p")" == "$want" ]] && { echo "$p"; return 0; }
  done < <(lsblk -lnpo NAME,TYPE "$DISK" | awk '$2=="part"{print $1}')
  return 1
}

ROOT_PART="$(find_by_label linux_root || true)"
HOME_PART="$(find_by_label linux_home || true)"
[[ -n "$ROOT_PART" && -n "$HOME_PART" ]] || die "分区名不是 linux_root/linux_home，先确认是双系统布局"

if [[ "${1:-}" == "--rollback" ]]; then
  log "回滚：把名字换回来"
  R_NUM="$(partnum "$ROOT_PART")"; H_NUM="$(partnum "$HOME_PART")"
  e2label "$ROOT_PART" LIUQIN_ROOT; e2label "$HOME_PART" LIUQIN_HOME
  sfdisk --part-label "$DISK" "$R_NUM" linux_root
  sfdisk --part-label "$DISK" "$H_NUM" linux_home
  partprobe "$DISK" || true
  log "已换回；重启进 Ubuntu"
  exit 0
fi

BASE_URL="${1:-}"
[[ -n "$BASE_URL" ]] || die "用法: stage-steamos.sh <release-url>"

ROOT_SIZE_G="$(lsblk -bno SIZE "$ROOT_PART" | awk '{printf "%d", $1/1073741824}')"
HOME_SIZE_G="$(lsblk -bno SIZE "$HOME_PART" | awk '{printf "%d", $1/1073741824}')"
log "linux_root=${ROOT_SIZE_G}G  linux_home=${HOME_SIZE_G}G"

TMP="$(mktemp -d /var/tmp/steamos.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

log "下载 payload 分卷"
if command -v curl >/dev/null; then DL="curl -fL --retry 3 -O"; else DL="wget -q"; fi
$DL "$BASE_URL/parts.sha256" || log "没有 parts.sha256，跳过校验"
if [[ -f parts.sha256 ]]; then
  while read -r sum name; do $DL "$BASE_URL/$name"; done < parts.sha256
  sha256sum -c parts.sha256
else
  for n in 0 1 2 3 4 5; do
    $DL "$BASE_URL/steamos-liuqin-rootfs.tar.gz.part-$(printf %02d $n)" || break
  done
fi
[[ -n "$(ls steamos-liuqin-rootfs.tar.gz.part-* 2>/dev/null)" ]] || die "没下到分卷"

log "合并"
cat steamos-liuqin-rootfs.tar.gz.part-* > rootfs.tar.gz
if [[ -f steamos-liuqin-rootfs.tar.gz.sha256 ]]; then
  echo "$(cut -d' ' -f1 steamos-liuqin-rootfs.tar.gz.sha256)  rootfs.tar.gz" | sha256sum -c -
fi

log "格式化 $HOME_PART 为 ext4（会清空 Ubuntu 的 /home）"
umount /home 2>/dev/null || true
mkfs.ext4 -F -L LIUQIN_ROOT -m 0 "$HOME_PART"

log "解包 SteamOS"
mkdir -p /mnt/steamos-new
mount "$HOME_PART" /mnt/steamos-new
tar -xzf rootfs.tar.gz -C /mnt/steamos-new --xattrs --numeric-owner --same-owner
sync
umount /mnt/steamos-new

log "互换分区名与标签"
e2label "$ROOT_PART" LIUQIN_HOME
R_NUM="$(partnum "$ROOT_PART")"; H_NUM="$(partnum "$HOME_PART")"
sfdisk --part-label "$DISK" "$R_NUM" linux_home
sfdisk --part-label "$DISK" "$H_NUM" linux_root
partprobe "$DISK" || true
lsblk -no NAME,PARTLABEL,LABEL,SIZE "$DISK"

log "完成。现在用 PC 刷 boot_a："
log "  fastboot flash boot_a boot-steamos-liuqin.img"
log "然后重启。要回 Ubuntu：sudo stage-steamos.sh --rollback（在 Ubuntu 里已进不去时用 fastboot 刷回上游 boot.img）"

if [[ "${REBOOT:-0}" == 1 ]]; then
  log "10 秒后重启"; sleep 10; reboot
fi
