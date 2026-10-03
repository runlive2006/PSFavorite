# PSFavorite

> **PowerShell 7 命令收藏夹**
> A command bookmark manager for PowerShell 7.

把刚执行过的命令一键收藏，之后用编号或自定义缩写随时调出来重跑——不用再翻历史记录、不用复制粘贴。

## 特性

- **一键收藏**：`fav -a` 直接把你**上一条命令**收进收藏夹。
- **标题 + 缩写**：给收藏配个人可读的标题，再配一个短缩写，之后敲 `fav gs` 就能执行。
- **自动去重**：同一条命令重复收藏不会产生副本；此时可用标题/缩写**更新**已有记录。
- **编号 / 缩写双通道**：执行与删除都支持编号（`fav 3`）或缩写（`fav gs`）两种写法。
- **零依赖、纯本地**：只有一个 `.ps1` 脚本加一个 JSON 数据文件，不联网、不需要管理员权限。

## 安装

1. 把 `fav.ps1` 放到一个固定目录，例如：

   ```
   D:\Scripts\PSFavorite\fav.ps1
   ```

2. 在 `$PROFILE` 里加**一行**（注意开头的 `.` 和紧跟的空格，这是 dot-source 语法，不能省）：

   ```powershell
   . "D:\Scripts\PSFavorite\fav.ps1"
   ```

3. 让它生效：

   ```powershell
   . $PROFILE
   ```

   或直接重开一个终端窗口。

### 找不到 $PROFILE？

```powershell
$PROFILE                                        # 查看路径
Test-Path $PROFILE                              # 判断是否存在
if (!(Test-Path $PROFILE)) {                    # 不存在则创建
    New-Item -ItemType File -Path $PROFILE -Force
}
notepad $PROFILE                                # 或 code $PROFILE
```

> PowerShell 7（`pwsh`）与 Windows PowerShell 5.1 的 `$PROFILE` 是**两套互相独立的文件**，改一个不影响另一个。以 `$PROFILE` 变量的实际输出为准。

### 两个最常见的坑

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| `fav` 不是可识别的命令 | profile 里只写了一行路径字符串，**漏掉了开头的 `. `**，那只是对字符串求值，什么也没加载 | 改成 `. "D:\Scripts\PSFavorite\fav.ps1"` |
| 提示"未进行数字签名，无法运行" | 脚本文件带了 **MOTW**（来自互联网的标记）。`RemoteSigned` 放行本地脚本，但会拦截下载来的未签名脚本 | `Unblock-File -Path "D:\Scripts\PSFavorite\fav.ps1"` |

如果是解压整个下载的压缩包，可以一次性处理整个目录：

```powershell
Get-ChildItem -Path "D:\Scripts\PSFavorite" -Recurse | Unblock-File
```

## 用法

| 命令 | 说明 |
| --- | --- |
| `fav` | 浏览收藏夹，输入编号或缩写执行（`q` 退出） |
| `fav <编号\|缩写>` | 直接执行，如 `fav 3` / `fav gs` |
| `fav -a [标题]` | 收藏上一条命令，标题可选 |
| `fav -a -c <缩写> [标题]` | 收藏并指定命令缩写 |
| `fav -a [标题] -c <缩写>` | 同上，`-c` 放在前面或后面都行 |
| `fav -a [新标题] [-c 新缩写]` | 命令已在收藏夹中时，改为**更新**其标题/缩写 |
| `fav -d <编号\|缩写>` | 删除，如 `fav -d 3` / `fav -d gs` |
| `fav -l` | 仅列出收藏夹 |
| `fav -h` | 显示帮助 |

### 一次典型会话

```powershell
PS> npm view @deepseek-ai/dsh dist-tags --json
...

PS> fav -a -c dsh 检查 dsh 版本      # 收藏上一条命令，缩写 dsh
已收藏 #1 [dsh] : npm view @deepseek-ai/dsh dist-tags --json
  标题: 检查 dsh 版本

PS> fav -l

#     缩写             时间                   标题 / 命令
----------------------------------------------------------------------------------------
#1    dsh             2026-09-30 10:01:16  检查 dsh 版本
                                            npm view @deepseek-ai/dsh dist-tags --json

PS> fav dsh                          # 用缩写重跑
执行 #1 [dsh]: npm view @deepseek-ai/dsh dist-tags --json

PS> fav -a 检查 dsh 最新版本           # 同一条命令再次收藏 → 视为更新标题
该命令已收藏过，已更新 #1 [dsh]:
  标题: 「检查 dsh 版本」→ 「检查 dsh 最新版本」

PS> fav -d dsh                       # 按缩写删除
已删除 #1 [dsh] : npm view @deepseek-ai/dsh dist-tags --json
```

### 规则

- **缩写必须唯一**，且**不能是纯数字**（否则会与编号混淆）。
- 缩写匹配**不区分大小写**，`fav GS` 与 `fav gs` 等效。
- **同一命令只存一条**。不带标题/缩写再次收藏时，只会提示它现有的编号与缩写，不会新增。
- 带标题/缩写再次收藏时视为更新：只给标题就只改标题，只给缩写就只改缩写，两个都给就一起改。

## 数据存放

收藏数据保存在 **`fav.ps1` 同目录**下的 `.fav_commands.json`：

```
D:\Scripts\PSFavorite\
├── fav.ps1
├── .fav_commands.json      ← 收藏数据
└── README.md
```

内容是一个 JSON 数组：

```json
[
  {
    "id": 1,
    "cmd": "Get-Date",
    "title": "当前时间",
    "abbr": "now",
    "time": "2026-09-30 10:01:16"
  }
]
```

| 字段 | 含义 |
| --- | --- |
| `id` | 编号，也是 `fav <编号>` / `fav -d <编号>` 使用的编号 |
| `cmd` | 命令原文 |
| `title` | 标题，可为空字符串 |
| `abbr` | 命令缩写，可为空字符串 |
| `time` | 收藏时间 |

几点说明：

- 纯文本 UTF-8，可以直接用编辑器打开修改，也可以直接拷贝来备份/迁移收藏。
- 编号**只增不减**：删掉 `#1` 后新收藏的是 `#2`，不会复用旧编号。
- 数据文件跟随脚本位置：整个目录搬到别处，收藏也跟着走。

## 工作原理

- **"上一条命令"从哪里取**：不使用 `Get-History`（在函数内部、非交互场景下常常取不到），而是读取 PSReadLine 的历史文件 `(Get-PSReadLineOption).HistorySavePath`，从末尾向前回溯，并自动跳过 `fav` 自身的调用，取最近一条真实命令；若 PSReadLine 不可用则回退到 `Get-History`。
- **dot-source 守卫**：脚本末尾只在"**非** dot-source 调用**且**带参数"时才自动执行 `fav`。这样把脚本 dot-source 进 `$PROFILE` 时不会因为无参数而误进交互浏览模式、卡住每次开 shell。
- **参数解析**：单遍从左到右扫描 token，所以 `-c` 与标题的先后顺序随意。
- **写入健壮性**：保存空列表时显式写入 `[]`（`ConvertTo-Json` 在没有输入时不会产生输出，会导致 `Set-Content` 不覆盖旧文件、删除后记录残留）；读取时对记录做字段规范化，兼容早期版本写入的、缺少 `abbr`/`title` 字段的旧数据。

## 已知限制

- 暂不支持**清空**已有的标题或缩写（空值被视作"不修改"）。
- `fav -a` 依赖 PSReadLine 历史。在某些 IDE 内嵌终端或非交互方式下会回退到 `Get-History`，可能取不到上一条命令，此时会给出提示。
- 仅面向 Windows PowerShell / PowerShell 7 的**交互式命令行**使用。

## 兼容性

以 **PowerShell 7** 为主要目标平台，同时兼容 **Windows PowerShell 5.1**（脚本未使用 PS7 独有语法）。

## 卸载

1. 从 `$PROFILE` 中删掉 dot-source 那一行。
2. 删除 `fav.ps1` 与 `.fav_commands.json`。

## 隐私提醒

`.fav_commands.json` 保存的是你的**真实命令历史**，其中可能包含本地路径、主机名、内网地址甚至明文令牌。如果你把存放目录作为 Git 仓库，**务必把它加入 `.gitignore`**（本仓库已附带一份提供参考）。

## 许可证

本项目基于 [MIT License](LICENSE) 开源，Copyright (c) 2026 runlive2006。
