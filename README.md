# SteamOS for Xiaomi Pad 6 Pro (liuqin, SM8475)

把 Valve 的 ARM64 SteamOS（Steam Frame 用户态）移植到小米平板 6 Pro。

- 方法与纪律：按 [yzddmr6/android-mainline-port](https://github.com/yzddmr6/android-mainline-port) 的九步流程推进。
- 内核/启动/分区基线：[@yzddmr6/xiaomipad-6pro-mainline](https://github.com/yzddmr6/xiaomipad-6pro-mainline) v0.6.0（liuqin 6.17 内核，真机全功能验收）。
- 用户态基线：Valve Steam Frame 官方恢复镜像 `steamframe-oobe-repair-20260922.5153644-0.3.0.img.bz2`（btrfs，rootfs-A 5 GiB）。
- 取包/装配思路参考：[zhao20100913/steamos-liuqin1](https://github.com/zhao20100913/steamos-liuqin1)。

## 路线（已定）

两步安装，不合上游装机器硬碰：

1. **用上游 v0.6.0 安装器正常装 Ubuntu 双系统**——分区、boot.img、双系统切换全部走上游已验收路径。
2. **把 SteamOS 换上去**：
   - 在 Ubuntu 里跑 `device/stage-steamos.sh`：把 SteamOS 铺到大分区（原 linux_home），再把 `linux_root` / `linux_home` 两个 GPT 分区名互换；
   - 在 PC 上 `fastboot flash boot_a boot-steamos-liuqin.img`——这是我们自己的 boot.img：上游内核 + dtb + 最小 initramfs（`boot/init`，只找 `PARTNAME=linux_root` 并 switch_root）。
   - 重启即进 SteamOS。

不用上游 boot.img 的原因：它的 init 对 rootfs 做 Ubuntu 专属契约验收（GNOME guard、snap admission、power-keyd、sensor-stack、gdm3 软链等），SteamOS 树不可能满足。我们只取它的 kernel/dtb。

## 目录

```
.github/workflows/build.yml   GitHub Actions：ubuntu-24.04-arm 上出 rootfs 分卷 + boot.img
boot/init                     最小 initramfs init（busybox）
scripts/fetch-runtime.sh      从 v0.6.0 底包抠 /lib/modules + /lib/firmware
scripts/fetch-frame.sh        两遍流式取 Frame 的 rootfs-A（btrfs，5 GiB）
scripts/assemble-rootfs.sh    btrfs 子卷 → 目录树，清 /boot 与模块，注入 liuqin 模块/固件
scripts/configure-rootfs.sh   chroot：fstab、hostname、steamos 用户、停更新服务、SSH 开关
scripts/probe-rootfs.sh       只读勘察（第一轮先拿事实）
scripts/pack-rootfs.sh        tar.gz + 2 GB 分卷 + sha256
scripts/make-boot-img.sh      上游 kernel/dtb + 我们的 initramfs → boot-steamos-liuqin.img
device/stage-steamos.sh       在平板 Ubuntu 里换根（含 --rollback）
docs/                         00 可行性 · 01 复用 · 02 硬件 · 03 决策 · 04 技术债 · 05 路线 · 06 CI
```

## 怎么构建

仓库公开后，Actions → **build-steamos-liuqin** → Run workflow：

- `frame_url`：Steam Frame 恢复镜像（默认已是版本化的 20260922 地址）
- `runtime_base`：上游 v0.6.0 release 前缀（取内核模块/固件）
- `enable_ssh`：rootfs 默认开 SSH（调试期 1，发布 0）
- `release_tag`：填了就把分卷与 boot.img 发成 Release

产物：`steamos-liuqin-rootfs.tar.gz.part-NN`、`boot-steamos-liuqin.img`、各 sha256。

## 怎么装

前提：平板已解锁、已用上游 v0.6.0 装好 Ubuntu 双系统并能启动。

```bash
# 1) 平板 Ubuntu 里（网络可用）
sudo bash stage-steamos.sh https://github.com/<you>/<repo>/releases/download/<tag>

# 2) PC 上（fastboot 可用）
fastboot flash boot_a boot-steamos-liuqin.img
fastboot reboot
```

回滚：在 SteamOS 进不去时，`fastboot flash boot_a <上游 boot.img>`（上游 v0.6.0 资产里有），再在 Ubuntu 里 `sudo bash stage-steamos.sh --rollback`。

## 已知风险

| 风险 | 处置 |
|---|---|
| Frame 用户态假设 Frame 硬件（VR 服务、gamescope 会话） | 第一轮 CI 只勘察 + 原样打包，`probe-rootfs.sh` 的日志用来决定停哪些 unit |
| SteamOS 是 btrfs+只读根的设计 | 我们铺到 ext4、可写根；A/B 更新与只读根都不启用 |
| 没有 liuqin 的 gamescope/DRM 适配 | 先验证 TTY + 网络，再上桌面；显示接管用上游已验证的 DRM 路径 |
| 分区名互换写错 | 脚本先校验两个分区都存在，`--rollback` 可逆；boot.img 可随时刷回 |
| 无人在平板旁时不要动 | 每次改启动路径都必须冷启动验证（skill 铁律） |

## 状态

| 项 | 状态 |
|---|---|
| 可行性 / 复用 / 硬件 / 决策 / 技术债 / 路线文档 | 完成（`docs/00`–`docs/06`） |
| CI 流水线 + 全部脚本 | 已写，未跑过 |
| 首次云端构建 | 等仓库地址 |
| 平板实机 | 未动 |

## 提醒

- 解锁与安装会清空 userdata；误刷启动镜像可能无法开机（Android 仍可从 A 槽恢复）。
- SteamOS 的 `steamos-update` / `atomupd` / `rauc` / `bootc` 在本布局下不可用，配置阶段已停用。
