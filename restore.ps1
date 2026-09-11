#requires -Version 5.1
# dress-your-agent: 一键还原（使用首次安装时的备份）
$ErrorActionPreference = "Stop"

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList "-ExecutionPolicy","Bypass","-File",$PSCommandPath
    exit
}

$pkg = Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pkg) { throw "未找到 Claude 桌面版" }
$res = Join-Path $pkg.InstallLocation "app\resources"
$app = Join-Path $pkg.InstallLocation "app"
$bak = Join-Path $res "_dressup-backup"
if (-not (Test-Path $bak)) { throw "未找到备份目录 $bak —— 本机未用本脚本安装过，或备份已被删除" }

foreach ($pair in @(
    @{ src = Join-Path $bak "app.asar";          dst = Join-Path $res "app.asar" },
    @{ src = Join-Path $bak "claude.exe";        dst = Join-Path $app "claude.exe" },
    @{ src = Join-Path $bak "shared-styles.css.orig"; dst = $null },
    @{ src = Join-Path $bak "ion-index.html.orig";    dst = $null }
)) {
    if (Test-Path $pair.src) {
        if ($pair.dst) {
            icacls $pair.dst /grant "*S-1-5-32-544:F" | Out-Null
            Copy-Item $pair.src $pair.dst -Force
            Write-Host ("已还原 " + (Split-Path $pair.dst -Leaf))
        } else {
            $name = Split-Path $pair.src -Leaf
            if ($name -eq "shared-styles.css.orig") {
                $css = Get-ChildItem (Join-Path $res "ion-dist\assets\v1") -Filter "shared-styles-*.css" | Select-Object -First 1
                if ($css) { Copy-Item $pair.src $css.FullName -Force; Write-Host ("已还原 " + $css.Name) }
            } elseif ($name -eq "ion-index.html.orig") {
                Copy-Item $pair.src (Join-Path $res "ion-dist\index.html") -Force
                Write-Host "已还原 ion-dist\index.html"
            }
        }
    }
}

# 移除注入的壁纸文件（app.asar.unpacked 目录为官方原生模块，保留不动）
Remove-Item (Join-Path $res "ion-dist\assets\v1\bg-custom.jpg") -Force -ErrorAction SilentlyContinue

Write-Host "还原完成。关闭并重新打开 Claude 即可。"
Write-Host "注意: claude.exe 的数字签名在备份时即已是官方状态, 还原后应显示 Valid。"
