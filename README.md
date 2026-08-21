# kfc（Kindle Flip Clock）

[English](README_EN.md) · 专为 Kindle 4 Non-Touch（K4NT）制作的 KUAL 全屏翻页时钟。

**当前版本：2.4.5** · [下载最新版](https://github.com/Arrow36/kindle4-flip-clock/releases/latest) · [更新记录](CHANGELOG.md)

![kfc 预览](docs/preview.svg)

它把闲置的 Kindle 4 变成一块墨水屏时钟：显示时间、公历日期、星期、农历和电量，并可通过实体按键直接切换方向、12/24 小时制和浅深色主题。

> 当前版本采用“翻页钟外观 + 数字卡片缓存 + 下一分钟变化区域预生成”。普通分钟只更新发生变化的一至两个数字，不生成完整 PNG，也没有中间过渡帧。

## 2.4.5 的主要修改

本次更新不是单纯调整刷新参数，而是重新整理了分钟渲染、休眠和日志链路：

- 新增常驻 LuaJIT 渲染进程，通过 FIFO 接收 `PING`、`RENDER`、`PREPARE` 和 `DISPLAY` 命令；启动时必须通过 `PING/PONG` 自检。
- FreeType 字体、0–9 数字卡片、Framebuffer 映射和下一分钟区域常驻内存，避免每分钟重新加载 KOReader 图形库。
- 普通分钟比较四位数字，只预生成变化卡片的最小联合区域；例如 `18:01→18:02` 更新一个数字，`18:09→18:10` 更新两个数字。
- Kindle 4 直接将 8 位灰度区域复制到 `/dev/fb0`，并使用 `FBIO_EINK_UPDATE_DISPLAY_AREA` 请求 eInkFB 局刷；兼容代码仍保留 MXCFB 分支。
- 启动时先联网 SNTP 校时，随后强制关闭 Wi-Fi；运行中只有键盘键手动校时时会临时联网。
- 无按键 60 秒后进入 RTC Suspend，每分钟计划提前 3 秒唤醒；数字局刷固定按 800 ms、整屏刷新固定按 1400 ms 安排，不再根据驱动返回时间自动学习。
- 整点完整刷新后保持清醒 40 秒再读取电量，普通分钟沿用该电量，避免电池采样触发整屏重画。
- `kfc.log` 限制为 512 KiB，并保留上一轮 `kfc.log.1`；普通状态约每分钟一条摘要，`DEBUG_LOG=1` 可开启详细调度记录。
- 常驻渲染器、FIFO、Framebuffer 或局刷失败时会逐级回退到一次性 LuaJIT 和完整 PNG，不会直接中断时钟。

详细版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## 功能

- 四种屏幕方向：竖屏按键在下、竖屏按键在上、横屏按键在右、横屏按键在左
- 12 小时制与 24 小时制
- 浅色与深色主题
- 公历日期、星期和农历日期
- 电量百分比精确到小数点后一位（Kindle 4 的电量来源仍为整数，因此末位通常是 `.0`）
- 抖音美好体，数字、AM/PM 和电量文字使用同一字体
- 提前生成下一分钟变化的数字区域，并尝试让墨水屏刷新过程跨过整分钟边界
- 启动、每个整点和成功校时后执行全屏清除并重画
- 返回键可随时强制全刷；Home 安全退出
- 键盘键直接使用 KOReader LuaSocket SNTP 手动校时
- 默认使用阿里云 `ntp1.aliyun.com`、`ntp2.aliyun.com`、`ntp.aliyun.com`
- 实体键实时控制，设置会写入 `settings.conf` 并在下次启动时保留
- 启动前先验证首帧，渲染失败时不会先关闭 Kindle 原界面
- 时钟运行时关闭 Wi-Fi，仅校时时临时开启；退出后恢复启动前状态
- 启动或最后一次按键后清醒 60 秒，随后在分钟间隔进入 RTC Suspend；电源键可人工唤醒
- 普通分钟通过 eInkFB 局部刷新变化数字；整点、设置变化和故障回退仍使用完整 PNG
- 显示分钟从启动或 SNTP 校准建立的时间锚点按 60 秒推进
- 帧、PID 和事件位于 `/tmp/kfc`，日志持久保存在 `kfc/logs`

## 已测试环境

- Kindle 4 Non-Touch（K4NT）
- Kindle 固件 4.1.4
- 已越狱并安装 KUAL
- KOReader 位于 `/mnt/us/koreader`

其他 Kindle 型号的分辨率、Framebuffer 旋转和实体键码可能不同，目前不保证兼容。

## 前置条件

1. 已越狱的 Kindle 4 Non-Touch。
2. 已安装 [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)。
3. 已安装 [KOReader](https://github.com/koreader/koreader)，且目录为 `/mnt/us/koreader`。

本项目调用 KOReader 自带的 LuaJIT、FreeType 和 BlitBuffer 完成渲染，但不会修改 KOReader。

## 安装

1. 从 [Releases](https://github.com/Arrow36/kindle4-flip-clock/releases) 下载最新版 ZIP 并解压。
2. 通过 USB 将整个 `kfc` 文件夹复制到 Kindle 的 `extensions` 目录。
3. 最终路径必须是：

   ```text
   /mnt/us/extensions/kfc
   ```

4. 安全弹出 Kindle。
5. 在 KUAL 中选择 `kfc`。

不要重命名 `kfc` 文件夹；当前脚本使用固定路径。

### 从旧版本升级

2.2.3 已将扩展目录从 `kclock` 改为小写 `kfc`。升级前先退出正在运行的时钟，并备份旧目录中的 `settings.conf`。2.4.5 的设置版本为 4，首次启动会把旧的 RTC 提前 2 秒迁移为 3 秒，并补充电池刷新、调试和日志限制参数。确认新版能够从 KUAL 正常启动后，再删除旧的 `/mnt/us/extensions/kclock`，以免菜单中同时出现两个入口。

## 时钟运行时的实体键

| 实体键 | 功能 | Kindle 4 键码 |
|---|---|---:|
| 左侧翻上一页 | 上一个屏幕方向 | 193 |
| 左侧翻下一页 | 下一个屏幕方向 | 104 |
| 右侧翻上一页 | 切换浅色/深色 | 109 |
| 五向键确认 | 切换 12/24 小时制 | 194 |
| 键盘键 | 立即联网校时 | 29 |
| 菜单键 | 显示/关闭快捷键说明 | 139 |
| 返回键 | 清屏并强制完整重画 | 158 |
| Home | 退出时钟 | 102 |

方向键和右侧翻下一页键暂未分配功能。

## 刷新方式

1. 启动时先执行 SNTP 校时并关闭 Wi-Fi，然后启动常驻 LuaJIT；FIFO 完成 `PING/PONG` 后才启用常驻路径。
2. 生成并验证当前完整 PNG；成功后停止 Kindle framework，清屏并显示首帧。
3. 常驻渲染器提前比较当前分钟和下一分钟，只组装变化数字的 BB8 区域并保存在内存中。
4. 普通分钟将该区域复制进 `/dev/fb0`，再调用 Kindle 4 eInkFB 局刷 ioctl；`09→10` 等进位更新两个数字。
5. 启动、整点、设置或说明变化、成功校时、返回键和局刷回退仍生成完整 PNG，并通过 `eips` 显示。
6. 启动或实体键后保持清醒 60 秒；之后在下一分钟缓存准备完成时进入 RTC Suspend，计划在边界前 3 秒唤醒。
7. 唤醒后的最后一秒使用 `/proc/uptime` 记录百分之一秒调度数据；局刷采用固定 800 ms 估计，整屏采用固定 1400 ms 估计。
8. eInkFB ioctl 可能在物理波形结束前返回，因此测得耗时只写日志，不用于自动修改刷新参数。
9. 每个整点完整刷新后等待 40 秒再读取一次电量，其他分钟沿用该值。
10. Home 退出后停止后台任务、取消 RTC、恢复 Wi-Fi 原状态、休眠策略和 Kindle framework。

这里的“重新启动 framework”只是恢复 Kindle 图形界面，不是重启整台设备。

## 配置

配置文件位于 `kfc/settings.conf`：

```sh
SETTINGS_VERSION=4
ORIENTATION=landscape_left
HOUR_MODE=12
THEME=dark
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
IDLE_SUSPEND_SECONDS=60
RTC_WAKE_LEAD_SECONDS=3
PARTIAL_REFRESH_DURATION_MS=800
FULL_REFRESH_DURATION_MS=1400
BATTERY_REFRESH_SETTLE_SECONDS=40
DEBUG_LOG=0
LOG_MAX_BYTES=524288
```

可用值：

- `ORIENTATION`：`portrait`、`portrait_down`、`landscape_right`、`landscape_left`
- `HOUR_MODE`：`12` 或 `24`
- `THEME`：`light` 或 `dark`
- `TIMEZONE`：POSIX TZ 字符串；中国标准时间使用 `CST-8`
- `TIME_SYNC_TIMEOUT`：手动校时等待 Wi-Fi 联网的最长秒数，允许 10–180
- `NTP_SERVERS`：NTP 服务器列表，默认使用三个阿里云公网地址
- `IDLE_SUSPEND_SECONDS`：最后一次实体键后保持清醒的秒数，默认 60，允许 60–3600
- `RTC_WAKE_LEAD_SECONDS`：分钟边界前提前唤醒的秒数，默认 3，允许 1–10
- `PARTIAL_REFRESH_DURATION_MS`：普通分钟刷新预计可见耗时，默认 800 毫秒，允许 100–5000
- `FULL_REFRESH_DURATION_MS`：整点清屏重画预计可见耗时，默认 1400 毫秒，允许 100–5000
- `BATTERY_REFRESH_SETTLE_SECONDS`：整点全刷后等待电量计稳定的秒数，默认 40，允许 5–50
- `DEBUG_LOG`：`1` 记录详细的渲染、RTC 和调度信息；默认 `0`
- `LOG_MAX_BYTES`：`kfc.log` 最大字节数，默认 524288

POSIX TZ 的正负号与常见 UTC 写法相反。例如 UTC+8 写作 `CST-8`。

## 更换字体

默认字体文件是：

```text
kfc/fonts/DouyinSansBold.ttf
```

可以用另一份 TTF 替换它，但必须保持相同文件名；新字体需要覆盖日期中使用的中文字符。若要修改文件名，请同步修改 `src/render.lua` 中的 `font_path`。

项目附带的抖音美好体来自 [ByteDance Fonts](https://github.com/bytedance/fonts)，按 SIL Open Font License 1.1 分发；许可证见 `kfc/fonts/OFL.txt`。

## 目录结构

```text
kindle4-flip-clock/
├─ kfc/                    # 可直接复制到 Kindle/extensions
│  ├─ config.xml           # KUAL 扩展元数据
│  ├─ menu.json            # KUAL 菜单
│  ├─ settings.conf        # 默认设置
│  ├─ fonts/
│  │  ├─ DouyinSansBold.ttf
│  │  └─ OFL.txt
│  ├─ logs/                # 启动与运行日志，首次启动时创建
│  └─ src/
│     ├─ start.sh          # 生命周期、时间刷新和实体键事件
│     ├─ time_sync.sh      # Wi-Fi 与 NTP 客户端调度
│     ├─ sntp.lua          # KOReader LuaSocket SNTP 客户端
│     ├─ render.lua        # 一次性完整 PNG 渲染入口
│     ├─ render_server.lua # 常驻 FIFO 渲染服务
│     ├─ clock_renderer.lua # 完整画面、数字缓存和局刷实现
│     └─ lunar.lua         # 公历转农历
├─ tests/
│  └─ test_refresh_timing.sh
├─ docs/
├─ CHANGELOG.md
├─ CONTRIBUTING.md
├─ LICENSE
└─ NOTICE.md
```

## 日志与故障排查

### 启动后立刻返回 KUAL

检查：

```text
/mnt/us/extensions/kfc/logs/launcher.log
/mnt/us/extensions/kfc/logs/kfc.log
```

常见原因是 KOReader 不在 `/mnt/us/koreader`，或字体文件缺失。校时失败不会阻止时钟离线运行；上述日志会记录 Wi-Fi、客户端和服务器的尝试结果。

正常情况下 `kfc.log` 约每分钟一条摘要，最大 512 KiB；新一轮启动会把上一轮保留为 `kfc.log.1`。需要诊断时可暂时把 `DEBUG_LOG` 改为 `1`。

### 白屏

当前版本会在停止 framework 前验证首帧，因此普通渲染错误不应再留下白屏。如果出现残影可按返回键强制全刷；如需退出则按 Home，并查看上述日志。

### 菜单中看不到扩展

确认目录不是多套了一层：

```text
正确：extensions/kfc/menu.json
错误：extensions/kfc/kfc/menu.json
```

退出并重新打开 KUAL，让动态菜单重新载入。

### 按键不匹配

公开版使用 Kindle 4 Non-Touch 的固定键码。若在其他 Kindle 型号上移植，需要修改 `src/start.sh` 的 `watch_keys()` 键码映射，并重新适配画布尺寸与旋转。

## 卸载

退出时钟后，通过 USB 删除：

```text
/mnt/us/extensions/kfc
```

本扩展不会修改 Kindle 系统分区；越狱、KUAL 和 KOReader 需要分别按各自文档卸载。

## 已知限制

- 目前只针对 Kindle 4 Non-Touch 的 600×800 屏幕与实体键码。
- RTC 低功耗和相位调度依赖 Kindle 4 的 `/sys/devices/platform/mxc_rtc.0/wakeup_enable` 与同目录下的 `rtc_pmic_epoch_time`；不可用时会保持清醒并使用系统时间继续更新。
- 电量读取依赖 `gasgauge-info -c`；其他型号输出格式可能不同。
- 农历换算支持 1900–2100 年。
- 没有秒数，也没有逐秒刷新；这是为墨水屏残影、性能和功耗做出的选择。
- 没有翻页过渡动画，分钟变化时直接显示新时间。
- Kindle 4 的休眠恢复可能让系统时钟逐渐走快；长时间无人值守时仍建议定期手动 SNTP 校时。
- eInkFB 局刷 ioctl 的返回表示请求已经提交，不等同于肉眼可见的墨水波形结束。
- 手动校时如果正好跨越整分钟边界，可能先触发一次完整回退刷新；校时完成后的重新锚定会恢复正确画面。
- Kindle 系统找不到亚秒 `usleep` 时会退化为整数秒等待，刷新提交可能晚于计划；详细偏移可从 `kfc.log` 判断。

## 开发与发布

Shell 脚本以 Kindle 4 的 BusyBox `/bin/sh` 为目标。提交前至少检查：

```sh
sh -n kfc/src/start.sh
sh tests/test_refresh_timing.sh
```

制作 Release 时，应让 ZIP 解压后直接得到 `kfc/` 文件夹。不要把设备运行时的 `/tmp/kfc` 文件或 `kfc/logs` 放入发布包。

手动发布前应同步更新 `README.md`、`README_EN.md`、`CHANGELOG.md`、`kfc/README.txt` 和 `kfc/config.xml` 中的版本号。然后从仓库根目录打包 `kfc/`，在 GitHub Releases 页面创建同版本的 `vX.Y.Z` Tag，并上传 ZIP。

## 致谢与许可

- 项目灵感来自 [LaisRast/kclock](https://github.com/LaisRast/kclock)。公开版已移除原项目的 SVG、`rsvg-convert`、`pngcrush` 及其动态库，改用新的 Lua/KOReader 渲染实现。
- 图形运行时由 [KOReader](https://github.com/koreader/koreader) 提供，本仓库不重新分发 KOReader。
- 抖音美好体来自 [ByteDance Fonts](https://github.com/bytedance/fonts)，使用 SIL Open Font License 1.1。

除字体外，本仓库代码使用 [MIT License](LICENSE)。字体仍受其独立的 [OFL-1.1](kfc/fonts/OFL.txt) 约束。详见 [NOTICE.md](NOTICE.md)。

使用越狱和第三方扩展存在风险，请自行确认设备型号并保留备份。
