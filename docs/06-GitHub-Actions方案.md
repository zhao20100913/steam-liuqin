# 06 GitHub Actions 云构建方案

用户选择：不依赖本地 Linux，用 GitHub Actions 构建，产物在 Release 下载后由安装器刷入。

## 前提

| 项 | 要求 |
|---|---|
| 仓库 | 自己的 GitHub 仓库，**public** 才能用 `ubuntu-24.04-arm` 原生 ARM64 runner（私有仓库的 arm64 runner 需付费或不可用；x86_64 runner 需 qemu-user + binfmt，慢且不稳） |
| 磁盘 | GitHub 托管 runner 约 14 GB 可用；Frame 整盘镜像 7.5 GB + 装配目录 6–8 GB，必须流式取包、用完即删（`docs/05` S1/S2） |
| 单次时长 | 上限 6 小时；内核构建 40–60 分钟，装配 20–40 分钟，足够 |
| 固件 | liuqin 的 `qcom/sm8475/liuqin/*.mbn` 与 `novatek/liuqin/*.bin` 不在公开 linux-firmware；需要用户提供固件归档（可从 liuqin Ubuntu rootfs 的 `/lib/firmware` 提取），作为 workflow 输入或仓库内小文件 |
| 原厂 ROM | 双系统安装需要 `OS2.0.6.0.VMYCNXM` 解包目录；不上传仓库，放在用户 PC 上，安装时本地校验 |

## 工作流设计（`.github/workflows/build.yml`）

`workflow_dispatch` 输入：

| 输入 | 默认 | 说明 |
|---|---|---|
| `steamos_source` | 官方 `steamframe-repair-latest.img.bz2` | 也接受用户自己上传的镜像/压缩包直链 |
| `steamos_sha256` | 空 | 给了就校验，防止底包漂移 |
| `kernel_repository` | `yzddmr6/linux-sm8450-liuqin` | 内核源 |
| `kernel_commit` | `fe81794b...` | 固定提交 |
| `firmware_url` | 空 | liuqin 固件归档（tar.gz/xz/zst），必填才能通过 |
| `rootfs_size` | `12G` | 装配用临时盘；最终 tar 不受此限 |

步骤：

1. **取内核**：`actions/checkout` 内核仓（`fetch-depth: 1`，指定 commit），用 `xiaomipad-6pro-mainline` 的 `tools/build-liuqin-kernel.py` 与 `device/configs/*.config` 生成 `.config`，编译 `Image`、`dtb`、`modules_install`。
2. **取 SteamOS 源**：流式下载 → 解 bz2 → 解析 GPT → 只切出 `rootfs-A`（5 GB）→ 删整盘镜像。
3. **铺 rootfs**：btrfs `subvolid=5` 挂载，`rsync -aHAX` 到工作目录；并入 `@var`/`@home`；删 `/boot/*`、`/usr/lib/modules/*`、`/etc/fstab`；停用 `steamos-manager`/`steamos-update`/`atomupd`/`rauc`/`bootc`。
4. **注入 liuqin 资产**：内核 `Image`/dtb 到 `/boot`，模块到 `/usr/lib/modules/<release>`，固件归档到 `/lib/firmware`；校验 5 个必需固件路径存在（缺失即失败）。
5. **chroot 配置**（arm64 原生 runner 可直接 chroot）：
   - 建 `steamos` 用户/组，设置默认图形会话；
   - 写 `/etc/fstab`：`PARTLABEL=linux_root /`、`PARTLABEL=linux_home /home`；
   - 关闭 VR/Frame 专属服务（清单见 `docs/04` TD-02）；
   - 记录 `os-release` 与底包版本。
6. **打包**：`tar -C rootfs -caf rootfs.tar.gz`（或 zstd），≤ 2 GB 分片（Release 单文件上限 2 GB）。
7. **组装 bundle**：下载 v0.6.0 的 `boot.img`、`installer.img`、`install.py`、`liuqin_layout.py`、`liuqin-rom-images.json`、`dualboot-tools.zip`；写 `bundle.json`（`files` 为 name→sha256）；`install.py --check` 自检。
8. **发布**：上传到 Release（或 artifact，artifact 上限 10 GB）。

## 本地安装（用户 PC）

```sh
# 1) 下载 Release 里全部文件到 bundle/
python3 install.py --bundle bundle --check

# 2) 平板进 Fastboot（已解锁、电量 ≥30%）
python3 install.py --bundle bundle \
  --serial <序列号> --backup ./backup-$(date +%s) --erase-userdata \
  --layout dual --rom-dir /path/to/liuqin_images_OS2.0.6.0.VMYCNXM \
  --host-address <PC 在 USB 网络里的地址>
```

首次启动后按 `docs/05` S5 逐项验收；失败用备份恢复（同一安装器的 `--restore-partition-table`）。

## 风险与限制

- ARM64 runner 对 public 仓库免费；私有仓库请先确认可用性，否则退回本地构建。
- 磁带机式 14 GB 盘：内核编译产物（≈3 GB）+ 装配目录（≈6 GB）+ tar（≈3 GB）可能超限；措施：编译后只保留 `modules_install` 与 `Image`/dtb，删除 `vmlinux` 与中间对象；tar 直接写 `/mnt` 并在上传后清理。
- 首次构建大概率在「SteamOS 服务假设」上失败（TD-02）；workflow 需保留失败日志与根因，不要靠重跑碰运气。
- 底包与固件都不入库；仓库只放脚本、配置与校验和。
