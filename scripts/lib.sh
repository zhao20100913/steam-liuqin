#!/usr/bin/env bash
# scripts/lib.sh —— 公共函数。所有脚本 set -euo pipefail 后 source 本文件。
# shellcheck shell=bash

log()  { printf '[%s] %s\n' "${0##*/}" "$*"; }
warn() { printf '[%s] 警告: %s\n' "${0##*/}" "$*" >&2; }
die()  { printf '[%s] 错误: %s\n' "${0##*/}" "$*" >&2; exit 1; }

require_root() { [[ "${EUID}" -eq 0 ]] || die "需要 root（CI 里用 sudo bash 调用）"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

# 流式下载到 stdout。curl 23 = 下游读够就关管，属预期，按成功处理。
dload() {
  local url="$1" rc=0
  curl -fL --retry 3 --retry-delay 5 --connect-timeout 20 -o - "$url" || rc=$?
  case "$rc" in 0|23) return 0;; *) die "下载失败（curl $rc）: $url";; esac
}

# 解析镜像前 4 MiB 里的 GPT，打印 start_lba sectors name（按名称过滤 rootfs-A）。
gpt_find() {
  local head="$1" want="${2:-rootfs-A}"
  python3 - "$head" "$want" <<'PY'
import struct, sys
head, want = sys.argv[1], sys.argv[2]
data = open(head, 'rb').read()
sig = data[512:520]
if sig != b'EFI PART':
    sys.exit('no GPT signature at LBA1')
entries_lba = struct.unpack_from('<Q', data, 512 + 72)[0]
num = struct.unpack_from('<I', data, 512 + 80)[0]
esz = struct.unpack_from('<I', data, 512 + 84)[0]
off = entries_lba * 512
table = data[off: off + num * esz]
found = None
for i in range(num):
    e = table[i * esz:(i + 1) * esz]
    if len(e) < 128 or e[:16] == b'\x00' * 16:
        continue
    first = struct.unpack_from('<Q', e, 32)[0]
    last = struct.unpack_from('<Q', e, 40)[0]
    name = e[56:128].decode('utf-16-le').rstrip('\x00')
    print(f'{name}\t{first}\t{last - first + 1}', file=sys.stderr)
    if name == want:
        found = (first, last - first + 1)
if not found:
    sys.exit(f'partition {want} not found')
print(found[0], found[1])
PY
}

# 判断文件系统类型（无 blkid 时按魔数兜底）。
fs_type() {
  local img="$1"
  if command -v blkid >/dev/null 2>&1; then
    blkid -o value -s TYPE "$img" 2>/dev/null && return 0
  fi
  if dd if="$img" bs=1 skip=65536 count=8 status=none 2>/dev/null | grep -q '_BHRfS_M'; then
    echo btrfs
  fi
}
