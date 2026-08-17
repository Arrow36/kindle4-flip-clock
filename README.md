# Kindle 4 Flip Clock

[English](README_EN.md) · 专为 Kindle 4 Non-Touch（K4NT）制作的 KUAL 全屏翻页时钟。

![Kindle 4 Flip Clock 预览](docs/preview.svg)

它把闲置的 Kindle 4 变成一块墨水屏时钟：显示时间、公历日期、星期、农历和电量，并可通过实体按键直接切换方向、12/24 小时制和浅深色主题。

> 当前版本采用“翻页钟外观 + 分钟直接刷新”，没有中间过渡帧。这样更适合 Kindle 4 的刷新速度，也能减少残影与无意义刷新。

## 功能

- 四种屏幕方向：竖屏按键在下、竖屏按键在上、横屏按键在右、横屏按键在左
- 12 小时制与 24 小时制
- 浅色与深色主题
- 公历日期、星期和农历日期
- 电量百分比精确到小数点后一位（Kindle 4 的电量来源仍为整数，因此末位通常是 `.0`）
- 抖音美好体，数字、AM/PM 和电量文字使用同一字体
- 每分钟直接重绘；定期全刷以减轻墨水屏残影
- 实体键实时控制，设置会写入 `settings.conf` 并在下次启动时保留
- 启动前先验证首帧，渲染失败时不会先关闭 Kindle 原界面
- Home 或返回键安全退出并恢复 Kindle framework
- 不主动开关 Wi-Fi，运行时不需要联网

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

1. 下载 Release 中的 ZIP 并解压。
2. 通过 USB 将整个 `kclock` 文件夹复制到 Kindle 的 `extensions` 目录。
3. 最终路径必须是：

   ```text
   /mnt/us/extensions/kclock
   ```

4. 安全弹出 Kindle。
5. 在 KUAL 中选择 `Flip Clock`。

不要重命名 `kclock` 文件夹；当前脚本使用固定路径。

## 时钟运行时的实体键

| 实体键 | 功能 | Kindle 4 键码 |
|---|---|---:|
| 左侧翻上一页 | 上一个屏幕方向 | 193 |
| 左侧翻下一页 | 下一个屏幕方向 | 104 |
| 右侧翻上一页 | 切换浅色/深色 | 109 |
| 五向键确认 | 切换 12/24 小时制 | 194 |
| 菜单键 | 显示/关闭快捷键说明 | 139 |
| 返回键 | 退出时钟 | 158 |
| Home | 退出时钟 | 102 |

方向键和键盘键暂未分配功能。右侧翻下一页键也未使用。

## 刷新方式

1. 启动时先在后台生成首帧 PNG，并检查文件是否有效。
2. 首帧成功后停止 Kindle framework，并阻止自动休眠。
3. 到达新的分钟时生成一张新的 600×800 灰度 PNG，再通过 `eips` 显示。
4. 每 10 次刷新执行一次全屏清除；手动切换设置时也会全刷。
5. Home 或返回键退出后，恢复休眠策略并重新启动 Kindle framework。

这里的“重新启动 framework”只是恢复 Kindle 图形界面，不是重启整台设备。

## 配置

配置文件位于 `kclock/settings.conf`：

```sh
ORIENTATION=landscape_right
HOUR_MODE=24
THEME=light
TIMEZONE=CST-8
```

可用值：

- `ORIENTATION`：`portrait`、`portrait_down`、`landscape_right`、`landscape_left`
- `HOUR_MODE`：`12` 或 `24`
- `THEME`：`light` 或 `dark`
- `TIMEZONE`：POSIX TZ 字符串；中国标准时间使用 `CST-8`

POSIX TZ 的正负号与常见 UTC 写法相反。例如 UTC+8 写作 `CST-8`。

## 更换字体

默认字体文件是：

```text
kclock/fonts/DouyinSansBold.ttf
```

可以用另一份 TTF 替换它，但必须保持相同文件名；新字体需要覆盖日期中使用的中文字符。若要修改文件名，请同步修改 `src/render.lua` 中的 `font_path`。

项目附带的抖音美好体来自 [ByteDance Fonts](https://github.com/bytedance/fonts)，按 SIL Open Font License 1.1 分发；许可证见 `kclock/fonts/OFL.txt`。

## 目录结构

```text
kindle4-flip-clock/
├─ kclock/                 # 可直接复制到 Kindle/extensions
│  ├─ config.xml           # KUAL 扩展元数据
│  ├─ menu.json            # KUAL 菜单
│  ├─ settings.conf        # 默认设置
│  ├─ fonts/
│  │  ├─ DouyinSansBold.ttf
│  │  └─ OFL.txt
│  ├─ output/              # 运行时图片、日志、PID 和按键事件
│  └─ src/
│     ├─ start.sh          # 生命周期、时间刷新和实体键事件
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
/tmp/root/kclock.log
/mnt/us/extensions/kclock/output/render.log
```

常见原因是 KOReader 不在 `/mnt/us/koreader`，或字体文件缺失。

### 白屏

当前版本会在停止 framework 前验证首帧，因此普通渲染错误不应再留下白屏。如果仍出现白屏，可按 Home 或返回键退出，并查看上述日志。

### 菜单中看不到扩展

确认目录不是多套了一层：

```text
正确：extensions/kclock/menu.json
错误：extensions/kclock/kclock/menu.json
```

退出并重新打开 KUAL，让动态菜单重新载入。

### 按键不匹配

公开版使用 Kindle 4 Non-Touch 的固定键码。若在其他 Kindle 型号上移植，需要修改 `src/start.sh` 的 `watch_keys()` 键码映射，并重新适配画布尺寸与旋转。

## 卸载

退出时钟后，通过 USB 删除：

```text
/mnt/us/extensions/kclock
```

本扩展不会修改 Kindle 系统分区；越狱、KUAL 和 KOReader 需要分别按各自文档卸载。

## 已知限制

- 目前只针对 Kindle 4 Non-Touch 的 600×800 屏幕与实体键码。
- 时钟保持唤醒，长时间运行会比普通待机更耗电。
- 电量读取依赖 `gasgauge-info -c`；其他型号输出格式可能不同。
- 农历换算支持 1900–2100 年。
- 没有秒数，也没有逐秒刷新；这是为墨水屏残影、性能和功耗做出的选择。
- 没有翻页过渡动画，分钟变化时直接显示新时间。

## 开发与发布

Shell 脚本以 Kindle 4 的 BusyBox `/bin/sh` 为目标。提交前至少检查：

```sh
sh -n kclock/src/start.sh
```

制作 Release 时，应让 ZIP 解压后直接得到 `kclock/` 文件夹。不要把设备运行时的 `output/*`、日志或备份文件放入发布包。

## 致谢与许可

- 项目灵感来自 [LaisRast/kclock](https://github.com/LaisRast/kclock)。公开版已移除原项目的 SVG、`rsvg-convert`、`pngcrush` 及其动态库，改用新的 Lua/KOReader 渲染实现。
- 图形运行时由 [KOReader](https://github.com/koreader/koreader) 提供，本仓库不重新分发 KOReader。
- 抖音美好体来自 [ByteDance Fonts](https://github.com/bytedance/fonts)，使用 SIL Open Font License 1.1。

除字体外，本仓库代码使用 [MIT License](LICENSE)。字体仍受其独立的 [OFL-1.1](kclock/fonts/OFL.txt) 约束。详见 [NOTICE.md](NOTICE.md)。

使用越狱和第三方扩展存在风险，请自行确认设备型号并保留备份。
