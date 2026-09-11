# 给你喜爱的 agent 更换衣服 👔

> Dress Your Agent — 让 Claude 桌面版（Windows）穿上你喜欢的壁纸
>
> 深色主题 + 全屏壁纸 + 半透明卡片，效果与你见过的任何"透明终端"一致：
> 系统保持浅色不受影响，Claude 锁定深色，界面各层透出壁纸。

![screenshot-placeholder](docs/screenshot.png)

## 这是什么

一个纯本地的补丁脚本集，给 **Claude Desktop for Windows**（MSIX 商店版）做三件事：

1. **壁纸主题**：聊天界面铺上你指定的图片（暗色渐变压底、卡片半透明）
2. **锁定深色**：Claude 桌面版没有独立的深浅色设置，跟随 Windows；
   本脚本给主进程注入 `nativeTheme.themeSource = "dark"`，
   让 Claude **永远深色**，系统浅色/深色随意切
3. **可恢复**：首次运行自动备份原文件，随时可一键还原

## 原理（为什么不是简单改个文件）

Claude 桌面版的防护分三层，逐层都有对应解法：

| 防护 | 表现 | 解法 |
|---|---|---|
| `claude.exe` 内嵌 **asar 完整性哈希** | 重新打包的 app.asar 一律秒退（`Failed to read header size` / 退出码 -36861） | 重打包后重新计算 asar 头部 SHA256，**等长覆盖** exe 里 `resources\\app.asar","alg":"SHA256","value":"…` 处的 64 位哈希 |
| UI 本体不在 asar 里，而在 `resources/ion-dist/`（`app://localhost` 协议加载），**不受完整性保护** | —— | 壁纸与透明化 CSS 直接追加进 ion-dist 的样式表（改这个**不需要**动 asar/exe） |
| Claude 桌面版无独立主题设置 | 界面跟随系统 | 主进程启动时强制 `nativeTheme.themeSource = "dark"` |

> 灵感与参考：[javaht/claude-desktop-zh-cn](https://github.com/javaht/claude-desktop-zh-cn)
> （中文本地化项目，其 Windows 完整模式给出了 exe 内嵌哈希改写的思路）。

## 两种模式，先读这段再选

**🎉 好消息（2026-09 实测）**：新版 Claude 桌面版（1.52386+）**自带独立的主题设置**
（设置里的外观选项，配置持久化在 `%LOCALAPPDATA%\Claude-3p\config.json` 的
`"userThemeMode": "dark"`）。也就是说：

> **在 Claude 界面里把主题调成深色，系统保持浅色，壁纸照常生效。**
> 轻量模式 + 新版自带设置 = 完整效果，**完全不需要改 exe**！

**⚠️ 历史坑位（旧版本才需要看）**：旧版 Claude 没有独立的主题设置，
社区方案是改 exe 内嵌哈希同步 asar。但实测发现：exe 被修改后（签名变
`HashMismatch`），**Cowork 工作区服务会拒绝该客户端**（服务日志
`Client signature verified` 不再出现），表现为工作区报
`Failed to start Claude's workspace / RPC pipe closed`，工作区内技能（如
PPT 解析）全部失效。且该问题**与杀软无关**，还原官方文件后立即消失。

| 模式 | 命令 | 主题效果 | 工作区/PPT |
|---|---|---|---|
| **轻量模式（强烈推荐）** | `scripts/apply-ion-theme.ps1` | Claude 内置深色设置 + 壁纸 | ✅ 完好 |
| 完整模式（仅旧版 Claude，不推荐） | `install.ps1` | 强制深色+壁纸 | ❌ 不可用 |

日常使用**选轻量模式**：
1. 跑 `scripts/apply-ion-theme.ps1` 注入样式（UAC 一次）
2. 在 Claude 界面里把主题调成深色（新版本自带）
3. 若注入后看不到壁纸 → 清缓存（见常见问题）

## 环境要求

- Windows 10/11，Claude 桌面版（`Get-AppxPackage Claude` 能查到）
- [Node.js](https://nodejs.org) ≥ 18（用于 `npx @electron/asar` 解包/重打包）
- 一次管理员授权（UAC）：写入 `C:\Program Files\WindowsApps` 需要改文件所有权

> ⚠️ 公司电脑注意：本脚本会修改带厂商签名的应用文件，杀毒/EDR（如奇安信天擎）
> 可能拦截甚至"清零"文件。若被拦，把 `C:\Program Files\WindowsApps\Claude_*`
> 加入杀软信任区，或接受"坏了就重跑脚本"。企业设备请先确认公司安全政策。

## 快速开始

```powershell
# 1. 克隆项目
git clone https://github.com/<you>/dress-your-agent.git
cd dress-your-agent

# 2. 放一张你喜欢的壁纸，命名为 wallpaper.jpg（支持 jpg/png）
#    放在项目根目录即可

# 3. 右键"使用 PowerShell 运行" install.ps1，或在终端执行：
powershell -ExecutionPolicy Bypass -File .\install.ps1
#    UAC 弹窗点"是"

# 4. 完成后关闭并重新打开 Claude —— 穿上新衣服了
```

## 配置

编辑 `install.ps1` 顶部：

```powershell
$WallpaperPath = Join-Path $PSScriptRoot "wallpaper.jpg"   # 壁纸图片
$OverlayAlpha  = 0.45                                       # 暗色遮罩浓度 0~1，越大越暗
$ForceDark     = $true                                      # 是否锁定深色（false 则跟随系统）
```

## 恢复原状

```powershell
powershell -ExecutionPolicy Bypass -File .\restore.ps1
```

首次运行时的备份存放在 `C:\Program Files\WindowsApps\Claude_*\app\resources\_dressup-backup\`，
`restore.ps1` 会把 app.asar、claude.exe、ion-dist 的改动全部还原。

## 已知问题与对策

| 现象 | 原因 | 处理 |
|---|---|---|
| 启动秒退，日志报 `Failed to read header size from …app.asar` | asar 被清零/损坏（常见于杀软"处理"了被修改的文件，或更新中途中断） | 重跑 `install.ps1` |
| Claude 自动更新后主题消失 | 更新覆盖了全部官方文件，属预期行为 | 重跑 `install.ps1`（新版本同样适用） |
| **注入样式后看不到壁纸** | **应用缓存了旧的样式表**（ion-dist 的 CSS 会被磁盘缓存） | 关闭 Claude，删除 `%LOCALAPPDATA%\Claude-3p\Cache` 和 `Code Cache`，再启动 |
| 杀软把 app.asar 清零 | 厂商签名校验失败被判定为篡改 | 杀软信任区加入 `C:\Program Files\WindowsApps\Claude_*`；或重跑脚本 |
| 想换图标？ | **不要**改安装目录里的任何文件！只改快捷方式的"属性 → 更改图标" | —— |

## 项目结构

```
dress-your-agent/
├── install.ps1               # 完整模式（含 exe 哈希改写，注意工作区权衡）
├── restore.ps1               # 完整模式的一键还原
├── scripts/
│   ├── apply-ion-theme.ps1   # 轻量模式（推荐）：仅注入 ion-dist 主题
│   ├── asar-patch.js         # 完整模式用：asar 内容补丁（强制深色钩子等）
│   └── theme-remote.css      # 完整模式用：运行时透明化样式
├── wallpaper.jpg             # ← 你的壁纸放这里（自行添加）
├── docs/screenshot.png       # 效果截图（自行添加）
└── README.md
```

## 免责声明

- 本项目**不分发任何 Anthropic 的代码或资源**，所有脚本仅修改你本机已合法安装的应用文件
- 修改已安装应用超出了厂商预期，可能违反其服务条款，请自行斟酌；仅建议个人学习/美化用途
- 企业管控设备（EDR/天擎/Defender for Endpoint 等）请遵循公司安全政策，勿擅自加白名单
- Claude 更新后请重跑脚本；如遇异常，`restore.ps1` 或重装官方包可完整还原
