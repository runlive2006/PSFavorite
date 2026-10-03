<#
.SYNOPSIS
    fav —— PowerShell 7 命令收藏夹
.DESCRIPTION
    把"上一条命令"收藏起来，随时浏览、执行、删除，并自动去重。
    支持给收藏起标题和"命令缩写"，之后可用编号或缩写来执行/删除。
    设计成一个函数，dot-source 到 $PROFILE 后即可当命令用。

    用法:
      fav                     浏览收藏夹，输入编号/缩写执行所选命令
      fav <编号|缩写>         直接执行          (例: fav 3 / fav gs)
      fav -a [标题]           收藏上一条命令    (标题可选)
      fav -a -c <缩写> [标题] 收藏并指定缩写    (例: fav -a -c gs 查看状态)
      fav -a [标题] -c <缩写> 同上, -c 位置可前可后
      fav -a [新标题] [-c 新缩写]
                              命令若已收藏, 则改为"更新"其标题/缩写
      fav -d <编号|缩写>      删除              (例: fav -d 3 / fav -d gs)
      fav -l                  仅列出收藏夹
      fav -h                  显示帮助

    安装:
      把本文件放到固定位置，然后在 $PROFILE 里加一行(dot-source, 开头必须有 ". "):
        . "D:\path\to\fav.ps1"
      重开终端或执行 `. $PROFILE` 生效。
      注意: 若脚本是下载来的, 先 Unblock-File 解除 Mark-of-the-Web, 否则会被执行策略拦截。
#>

# ---------- 收藏数据文件位置 ----------
# 数据文件与 fav.ps1 放在同一目录(随脚本一起迁移，不留残渣在用户主目录)。
# 正常情况下 $PSScriptRoot 就是本脚本所在目录；
# 若取不到(极少见，如被以字符串方式求值)，退回下面这个硬编码路径。
$FavDataDir = if ($PSScriptRoot) { $PSScriptRoot } else { 'D:\Inst\Software\Script\pwsh7' }
$FavFile    = Join-Path $FavDataDir '.fav_commands.json'

function fav {
    param()

    # ---------- 存储读写 ----------
    function Load-Favs {
        if (-not (Test-Path $FavFile)) { return @() }
        try {
            $data = Get-Content $FavFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $data) { return @() }
            # 规范化: 早期版本写入的记录可能缺 abbr/title 字段(属性为 $null)，
            # 统一补齐为字符串，避免后续调用 .ToString() 时报"不能对 Null 调用方法"。
            return @(@($data) | ForEach-Object {
                [PSCustomObject]@{
                    id    = [int]$_.id
                    cmd   = [string]$_.cmd
                    title = if ($_.title) { [string]$_.title } else { '' }
                    abbr  = if ($_.abbr) { [string]$_.abbr } else { '' }
                    time  = [string]$_.time
                }
            })
        } catch {
            Write-Warning "收藏文件损坏，已忽略: $FavFile"
            return @()
        }
    }

    function Save-Favs($data) {
        $dir = Split-Path $FavFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $arr = @($data)
        # 空集合必须显式写成 []，否则 ConvertTo-Json 无输入会导致 Set-Content 不覆盖旧文件
        $json = if ($arr.Count -eq 0) { '[]' } else { $arr | ConvertTo-Json -Depth 4 -Compress }
        Set-Content -Path $FavFile -Value $json -Encoding UTF8
    }

    # ---------- 取"上一条命令" ----------
    function Get-PrevCommand {
        # 1) PSReadLine 历史文件(交互会话里最可靠)
        try {
            $hp = (Get-PSReadLineOption -ErrorAction Stop).HistorySavePath
            if (Test-Path $hp) {
                $lines = Get-Content $hp -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }
                for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                    $t = $lines[$i].Trim()
                    # 跳过 fav 自身的调用，取最近一条"非 fav"命令
                    if ($t -notmatch '^\s*(fav|fav\.ps1)(\s|$|;)') { return $t }
                }
            }
        } catch { }

        # 2) 回退: 引擎历史
        try {
            $h = @(Get-History -ErrorAction SilentlyContinue)
            for ($i = $h.Count - 1; $i -ge 0; $i--) {
                $t = $h[$i].CommandLine.Trim()
                if ($t -and $t -notmatch '^\s*(fav|fav\.ps1)(\s|$|;)') { return $t }
            }
        } catch { }

        return $null
    }

    # ---------- 按"编号或缩写"查找 ----------
    function Find-Target($list, $key) {
        if ([string]::IsNullOrWhiteSpace($key)) { return $null }
        if ($key -match '^\d+$') {
            return ($list | Where-Object { $_.id -eq [int]$key } | Select-Object -First 1)
        }
        $k = $key.ToString().ToLower()
        return ($list | Where-Object { $_.abbr -and [string]$_.abbr.ToLower() -eq $k } | Select-Object -First 1)
    }

    # 显示用: 给一条记录生成 "编号[缩写]" 标签
    function Tag($f) {
        if ($f.abbr) { return "#$($f.id) [$($f.abbr)]" } else { return "#$($f.id)" }
    }

    # ---------- 解析参数 ----------
    $action = ''
    $value  = ''
    $abbr   = ''
    $titleParts = @()

    $i = 0
    while ($i -lt $args.Count) {
        $tok = [string]$args[$i]
        switch -Regex ($tok) {
            '^-a$' { $action = 'add'; $i++; continue }
            '^-d$' { $action = 'del'; $i++; if ($i -lt $args.Count) { $value = [string]$args[$i] }; $i++; continue }
            '^-c$' { $i++; if ($i -lt $args.Count) { $abbr = [string]$args[$i] }; $i++; continue }
            '^-l$' { $action = 'list'; $i++; continue }
            '^-h$' { $action = 'help'; $i++; continue }
            default {
                if ($action -eq 'add') { $titleParts += $tok }
                elseif ($action -eq '') { $action = 'run'; $value = $tok }
                $i++; continue
            }
        }
    }
    $title = ($titleParts -join ' ').Trim()

    # ---------- 帮助 ----------
    if ($action -eq 'help') {
        @'
fav —— PowerShell 7 命令收藏夹

  fav                       浏览收藏夹，输入编号或缩写执行
  fav <编号|缩写>           直接执行              (例: fav 3   /  fav gs)
  fav -a [标题]             收藏上一条命令         (标题可选)
  fav -a -c <缩写> [标题]   收藏并指定命令缩写     (例: fav -a -c gs 查看状态)
  fav -a [新标题] [-c 新缩写]
                            命令已收藏时, 改为更新其标题/缩写
  fav -d <编号|缩写>        删除                   (例: fav -d 3   /  fav -d gs)
  fav -l                    仅列出收藏夹
  fav -h                    显示本帮助

说明:
  - -c 的缩写位置可前可后: fav -a -c gs 查看状态  等价于  fav -a 查看状态 -c gs
  - 缩写必须唯一、且不能是纯数字(避免和编号冲突)。
  - 若命令已收藏: 不会重复添加。此时带标题/缩写则视为"更新":
      fav -a 新标题            只改标题
      fav -a -c 新缩写         只改缩写
      fav -a -c 新缩写 新标题   两者一起改
    不带任何标题/缩写时, 仅提示其现有编号与缩写。
  - 收藏保存在 fav.ps1 同目录下的 .fav_commands.json
'@
        return
    }

    # ---------- 添加 ----------
    if ($action -eq 'add') {
        $cmd = Get-PrevCommand
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            Write-Warning '未能取到上一条命令(可能历史为空，或 PSReadLine 未启用)。'
            return
        }
        if ($abbr) { $abbr = $abbr.Trim() }

        $favs = Load-Favs
        $norm = $cmd.Trim()

        # 查命令是否已存在: 已存在则不新增, 转而更新其标题/缩写
        $dup = $favs | Where-Object { $_.cmd.Trim() -eq $norm } | Select-Object -First 1
        if ($dup) {
            # 既没给标题也没给缩写 → 保持原样, 仅提示已存在
            if (-not $title -and -not $abbr) {
                Write-Host "该命令已在收藏夹中，$(Tag $dup) ，未重复添加。" -ForegroundColor Yellow
                Write-Host "  $($dup.cmd)"
                if ($dup.title) { Write-Host "  标题: $($dup.title)" }
                Write-Host "  (想改的话: fav -a 新标题  或  fav -a -c 新缩写 [新标题])" -ForegroundColor DarkGray
                return
            }

            $changes = @()

            # 缩写: 校验(需排除自己)后更新
            if ($abbr) {
                if ($abbr -match '^\d+$') {
                    Write-Warning "缩写不能是纯数字(会和编号冲突): $abbr"
                    return
                }
                $conflict = $favs | Where-Object {
                    $_.id -ne $dup.id -and $_.abbr -and [string]$_.abbr.ToLower() -eq $abbr.ToLower()
                } | Select-Object -First 1
                if ($conflict) {
                    Write-Warning "缩写 '$abbr' 已被 $(Tag $conflict) 占用: $($conflict.cmd)"
                    return
                }
                if ([string]$dup.abbr -ne $abbr) {
                    $oldAb = if ($dup.abbr) { "「$($dup.abbr)」→ " } else { '' }
                    $changes += "缩写: $oldAb「$abbr」"
                    $dup.abbr = $abbr
                }
            }

            # 标题: 有给才覆盖
            if ($title -and $title -ne $dup.title) {
                $oldTi = if ($dup.title) { "「$($dup.title)」→ " } else { '' }
                $changes += "标题: $oldTi「$title」"
                $dup.title = $title
            }

            if ($changes.Count -eq 0) {
                Write-Host "该命令已在收藏夹中，$(Tag $dup) ，标题与缩写均为原值，无需更新。" -ForegroundColor Yellow
                return
            }

            # $dup 是数组内同一对象引用, 上面的赋值已生效
            Save-Favs $favs
            Write-Host "该命令已收藏过，已更新 $(Tag $dup):" -ForegroundColor Green
            $changes | ForEach-Object { Write-Host "  $_" }
            return
        }

        # 缩写校验: 不能纯数字、不能与既有缩写冲突
        if ($abbr) {
            if ($abbr -match '^\d+$') {
                Write-Warning "缩写不能是纯数字(会和编号冲突): $abbr"
                return
            }
            $conflict = $favs | Where-Object { $_.abbr -and [string]$_.abbr.ToLower() -eq $abbr.ToLower() } | Select-Object -First 1
            if ($conflict) {
                Write-Warning "缩写 '$abbr' 已被 $(Tag $conflict) 占用: $($conflict.cmd)"
                return
            }
        }

        $newId = 1
        if (@($favs).Count -gt 0) { $newId = [int](@($favs).id | Measure-Object -Maximum).Maximum + 1 }
        $entry = [PSCustomObject]@{
            id    = $newId
            cmd   = $cmd
            title = $title
            abbr  = $abbr
            time  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        $favs = @($favs) + $entry
        Save-Favs $favs
        Write-Host "已收藏 #$newId$(if($abbr){" [$abbr]"}) : $cmd" -ForegroundColor Green
        if ($title) { Write-Host "  标题: $title" }
        return
    }

    # ---------- 删除 ----------
    if ($action -eq 'del') {
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Warning '用法: fav -d <编号|缩写>'
            return
        }
        $favs = Load-Favs
        $target = Find-Target $favs $value
        if (-not $target) {
            Write-Warning "找不到编号或缩写: $value"
            return
        }
        $favs = @(@($favs) | Where-Object { $_.id -ne $target.id })
        Save-Favs $favs
        Write-Host "已删除 $(Tag $target) : $($target.cmd)" -ForegroundColor Red
        return
    }

    # ---------- 列出 ----------
    $favs = Load-Favs
    if (@($favs).Count -eq 0) {
        Write-Host '收藏夹为空。用 fav -a 把上一条命令收藏起来吧。' -ForegroundColor Cyan
        return
    }
    $favs = @($favs) | Sort-Object { [int]$_.id }

    function Show-List($list) {
        $pad = ' ' * 44
        Write-Host ''
        Write-Host ('{0,-5} {1,-14} {2,-20} {3}' -f '#', '缩写', '时间', '标题 / 命令') -ForegroundColor DarkGray
        Write-Host ('-' * 88) -ForegroundColor DarkGray
        foreach ($f in $list) {
            $ab = if ($f.abbr) { $f.abbr } else { '' }
            $label = if ($f.title) { $f.title } else { $f.cmd }
            $disp  = if ($label.Length -gt 46) { $label.Substring(0, 43) + '...' } else { $label }
            Write-Host ('{0,-5} {1,-14} {2,-20} {3}' -f "#$($f.id)", $ab, $f.time, $disp)
            if ($f.title) { Write-Host ($pad + $f.cmd) -ForegroundColor DarkGray }
        }
        Write-Host ''
    }

    if ($action -eq 'list') {
        Show-List $favs
        return
    }

    # ---------- 直接执行 fav <编号|缩写> ----------
    if ($action -eq 'run') {
        $target = Find-Target $favs $value
        if (-not $target) {
            Write-Warning "找不到编号或缩写: $value  (用 fav -h 查看帮助)"
            return
        }
        Write-Host "执行 $(Tag $target): $($target.cmd)" -ForegroundColor Cyan
        Invoke-Expression $target.cmd
        return
    }

    # ---------- 浏览并选择执行 ----------
    Show-List $favs
    while ($true) {
        $ans = Read-Host '输入编号/缩写执行 (q 退出)'
        if ($ans -eq 'q' -or $ans -eq 'Q' -or [string]::IsNullOrWhiteSpace($ans)) { return }
        $target = Find-Target $favs $ans
        if ($target) {
            Write-Host "执行 $(Tag $target): $($target.cmd)" -ForegroundColor Cyan
            Invoke-Expression $target.cmd
            return
        } else {
            Write-Warning "找不到编号或缩写: $ans ，请重试(或 q 退出)。"
        }
    }
}

# 当本文件被「直接运行(非 dot-source)」且「带参数」时, 立即执行 fav。
# 这样既支持 .\fav.ps1 -a 直接调用, 又把文件 dot-source 进 $PROFILE 时
# (无参数) 不会误触发浏览模式、卡住每次开 shell。
if ($MyInvocation.InvocationName -ne '.' -and $args.Count -gt 0) {
    fav @args
}
