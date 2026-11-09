# 10 · 起点是 Fedora 时怎么接

平板现在是 Fedora 45，不是 Ubuntu。这**不一定**是问题：换根脚本认的是 GPT 分区名
（`linux_root` / `linux_home`），不认发行版。但 Fedora 的装法可能和上游 yzddmr6 的
双系统布局不同，所以先取证，再决定走哪条路。

**不要先刷 boot、不要先格式化任何分区。** 先跑下面这段只读取证。

## 一、只读取证（在 Fedora 终端里跑，全部只读）

```bash
# 1) 分区、文件系统、GPT 名、卷标、挂载点
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,LABEL,MOUNTPOINTS

# 2) GPT 全表（把 sda 换成 lsblk 里那块盘）
sudo sgdisk -p /dev/sda

# 3) 当前根与启动参数
findmnt -no SOURCE,FSTYPE,SIZE /
cat /proc/cmdline
uname -r

# 4) 有没有上游的双系统切换目录（有 → 说明是 yzddmr6 布局）
sudo ls -la /var/lib/liuqin/switch/ 2>/dev/null || echo "没有 liuqin/switch"

# 5) Fedora 是不是 btrfs 子卷布局
findmnt -no FSTYPE,OPTIONS / | head -1
sudo btrfs subvolume list / 2>/dev/null | head
```

把 1、2、3、4 的输出贴回来就够判断。

## 二、看结果分三种情况

### 情况 A：有 `linux_root`（≈32G）+ `linux_home`（剩余）

说明 Fedora 装在和上游一致的双系统布局里（大概率是拿 yzddmr6 的安装器装的）。

→ **直接走 `docs/09` 第 2 步**：

```bash
sudo bash stage-steamos.sh \
  https://github.com/zhao20100913/steam-liuqin/releases/download/v0.1.0-pre2
```

脚本只做三件事：格式化 `linux_home` → 解 SteamOS → 两个分区名互换。Fedora 的根会被
改名成 `linux_home` 挂到 `/home`（内容还在，只是不再是根）。**Fedora 会被换掉，不是并存。**

### 情况 B：只有一个 Linux 分区（Fedora 占满剩余空间）

没有第二块分区可以“先铺后换”，而运行中的根又不能自己格式化自己。

两条出路：

1. **重新分区（推荐，干净）**：用上游 `install.py --layout dual` 重建布局。
   这需要原厂 Fastboot ROM（`OS2.0.6.0.VMYCNXM`）+ 上游 v0.6.0 资产，会清空 userdata。
   装完是 Ubuntu 双系统，再按 `docs/09` 第 2 步换根。
2. **原地替换（省事，但中间没有可用系统）**：先确认 Fedora 的 boot 也是“boot_a 里放自定义
   boot.img”的模式；若是，可以在 Fedora 里把根分区**改名 + 清空前**先备份 boot.img，
   然后从 USB 启动一个 live Linux 格式化它。没有 live USB 时不要走这条。

判断依据：`cat /proc/cmdline` 里是否有 `PARTNAME=linux_root` 或 `root=PARTLABEL=...`；
`/var/lib/liuqin/switch/` 是否存在。

### 情况 C：Fedora 装在 `userdata` 里（没有独立 Linux 分区）

这是最不规范的一种，等于 Android 的数据分区被 Linux 占了。必须先用上游安装器恢复
原厂分区表（`--restore-partition-table`）再重装，否则 `fastboot` 和后续布局都会打架。

## 三、不管哪种情况，先做这两件事

```bash
# 1) 把当前的 boot_a 读出来留底（PC 上，平板进 fastboot 后）
fastboot getvar current-slot
fastboot flash boot_a /dev/null   # 不要执行！这是反例
# 正确做法：
fastboot boot boot-steamos-liuqin.img   # 先临时启动，不写分区（见下）

# 2) 记录 Fedora 的内核与启动方式
uname -a
cat /proc/cmdline
```

> `fastboot boot <img>` 是**临时启动**，不写 `boot_a`，用来先验证我们的 boot.img 能不能
> 找到根分区。第一次测试建议先用它：起不来就断电重开，Fedora 一点没动。

## 四、第一次测试的安全顺序

1. `fastboot boot boot-steamos-liuqin.img` —— 验证 init 能否找到 `linux_root`
2. 找到根、进 TTY → 说明 boot 链路成立
3. 再 `fastboot flash boot_a ...` 持久化
4. 仍然保留上游/Fedora 的 boot.img 做回滚
