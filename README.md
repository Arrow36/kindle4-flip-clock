# kfc（Kindle Flip Clock）

[English](README_EN.md) · 专为 Kindle 4 Non-Touch（K4NT）制作的 KUAL 全屏翻页时钟。

**当前版本：2.2.3** · [下载最新版](https://github.com/Arrow36/kindle4-flip-clock/releases/latest) · [更新记录](CHANGELOG.md)

![kfc 预览](docs/preview.svg)

它把闲置的 Kindle 4 变成一块墨水屏时钟：显示时间、公历日期、星期、农历和电量，并可通过实体按键直接切换方向、12/24 小时制和浅深色主题。

> 当前版本采用“翻页钟外观 + 下一分钟后台预生成”。整分钟边界直接显示准备好的画面，没有中间过渡帧。

## 功能

- 四种屏幕方向：竖屏按键在下、竖屏按键在上、横屏按键在右、横屏按键在左
- 12 小时制与 24 小时制
- 浅色与深色主题
- 公历日期、星期和农历日期
- 电量百分比精确到小数点后一位（Kindle 4 的电量来源仍为整数，因此末位通常是 `.0`）
- 抖音美好体，数字、AM/PM 和电量文字使用同一字体
- 提前生成下一分钟画面，在绝对整分钟边界直接显示
- 启动、每个整点和成功校时后执行全屏清除并重画
- 返回键可随时强制全刷；Home 安全退出
- 键盘键直接使用 KOReader LuaSocket SNTP 手动校时
- 默认使用阿里云 `ntp1.aliyun.com`、`ntp2.aliyun.com`、`ntp.aliyun.com`
- 实体键实时控制，设置会写入 `settings.conf` 并在下次启动时保留
- 启动前先验证首帧，渲染失败时不会先关闭 Kindle 原界面
- 时钟运行时关闭 Wi-Fi，仅校时时临时开启；退出后恢复启动前状态
- 启动或最后一次按键后清醒 10 分钟，随后在分钟间隔进入 RTC Suspend；电源键可人工唤醒
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

### 从 2.1.0 升级

2.2.3 已将扩展目录从 `kclock` 改为小写 `kfc`。升级前先退出正在运行的时钟；如需保留方向、主题等设置，可备份旧目录中的 `settings.conf`，安装后再按新配置项合并。确认新版能够从 KUAL 正常启动后，删除旧的 `/mnt/us/extensions/kclock`，以免菜单中同时出现两个入口。

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

1. 启动时在 `/tmp/kfc` 生成并验证当前帧；成功后停止 Kindle framework并全屏显示。
2. 当前帧显示后，后台生成下一分钟的 600×800 灰度 PNG；设置改变时会取消过时的预生成任务。
3. 主循环按绝对时间等待，到达整分钟边界后直接显示已经准备好的下一帧；若预生成失败则现场重画兜底。
4. 启动、每个整点和成功校时后执行 `eips -c` 清屏，再用 `eips -g` 完整重画。
5. 返回键立即对当前画面执行同样的清屏重画；普通分钟和设置变化只画一次 PNG。
6. 键盘键启动后台校时：临时打开 Wi-Fi，直接运行 KOReader LuaSocket SNTP，结束后关闭 Wi-Fi。
7. 启动或清醒期间的任意实体键会开始 10 分钟清醒计时；无按键达到 10 分钟后，下一分钟预生成完成便进入 RTC Suspend，并在分钟边界前 3 秒或电源键触发时唤醒。
8. 如果实际恢复时间比 RTC 计划时间至少早约 2 秒，则判定为电源键等人工唤醒，立即重新开始 10 分钟清醒计时；正常的分钟 RTC 唤醒不会重置计时。
9. 能产生输入事件的唤醒按键会继续交给原有按键逻辑处理；电源键即使不进入 `waitforkey`，也能通过提前恢复时间被识别。
10. Home 退出后恢复 Wi-Fi 原状态、休眠策略和 Kindle framework。

这里的“重新启动 framework”只是恢复 Kindle 图形界面，不是重启整台设备。

## 配置

配置文件位于 `kfc/settings.conf`：

```sh
ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
TIME_SYNC_TIMEOUT=45
NTP_SERVERS="ntp1.aliyun.com ntp2.aliyun.com ntp.aliyun.com"
IDLE_SUSPEND_SECONDS=600
RTC_WAKE_LEAD_SECONDS=3
```

可用值：

- `ORIENTATION`：`portrait`、`portrait_down`、`landscape_right`、`landscape_left`
- `HOUR_MODE`：`12` 或 `24`
- `THEME`：`light` 或 `dark`
- `TIMEZONE`：POSIX TZ 字符串；中国标准时间使用 `CST-8`
- `TIME_SYNC_TIMEOUT`：手动校时等待 Wi-Fi 联网的最长秒数，允许 10–180
- `NTP_SERVERS`：NTP 服务器列表，默认使用三个阿里云公网地址
- `IDLE_SUSPEND_SECONDS`：最后一次实体键后保持清醒的秒数，默认 600，允许 60–3600
- `RTC_WAKE_LEAD_SECONDS`：分钟边界前提前唤醒的秒数，默认 3，允许 1–10

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
│     ├─ render.lua        # KOReader 图形栈渲染器
│     └─ lunar.lua         # 公历转农历
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
- RTC 低功耗模式依赖 Kindle 4 的 `/sys/devices/platform/mxc_rtc.0/wakeup_enable`；不可用时会保持清醒并继续正常更新时间。
- 电量读取依赖 `gasgauge-info -c`；其他型号输出格式可能不同。
- 农历换算支持 1900–2100 年。
- 没有秒数，也没有逐秒刷新；这是为墨水屏残影、性能和功耗做出的选择。
- 没有翻页过渡动画，分钟变化时直接显示新时间。

## 开发与发布

Shell 脚本以 Kindle 4 的 BusyBox `/bin/sh` 为目标。提交前至少检查：

```sh
sh -n kfc/src/start.sh
```

制作 Release 时，应让 ZIP 解压后直接得到 `kfc/` 文件夹。不要把设备运行时的 `/tmp/kfc` 文件或 `kfc/logs` 放入发布包。

## 致谢与许可

- 项目灵感来自 [LaisRast/kclock](https://github.com/LaisRast/kclock)。公开版已移除原项目的 SVG、`rsvg-convert`、`pngcrush` 及其动态库，改用新的 Lua/KOReader 渲染实现。
- 图形运行时由 [KOReader](https://github.com/koreader/koreader) 提供，本仓库不重新分发 KOReader。
- 抖音美好体来自 [ByteDance Fonts](https://github.com/bytedance/fonts)，使用 SIL Open Font License 1.1。

除字体外，本仓库代码使用 [MIT License](LICENSE)。字体仍受其独立的 [OFL-1.1](kfc/fonts/OFL.txt) 约束。详见 [NOTICE.md](NOTICE.md)。

使用越狱和第三方扩展存在风险，请自行确认设备型号并保留备份。
