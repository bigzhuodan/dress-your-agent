#requires -Version 5.1
# ============================================================
#  dress-your-agent — 轻量模式：仅注入 ion-dist 主题（推荐）
#
#  不修改 app.asar / claude.exe，工作区(Cowork)、PPT 解析等
#  全部功能不受影响。主题在 Windows 深色模式下自动生效。
#
#  用法: 右键"使用 PowerShell 运行"，UAC 点一次"是"
# ============================================================
param(
    [string]$WallpaperPath = (Join-Path $PSScriptRoot "..\wallpaper.jpg"),
    [double]$OverlayAlpha  = 0.45
)
$ErrorActionPreference = "Stop"
$ImgName = "bg-custom.jpg"

# 自动提权
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
        "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
        "-WallpaperPath", $WallpaperPath, "-OverlayAlpha", $OverlayAlpha)
    exit
}

if (-not (Test-Path $WallpaperPath)) { throw "未找到壁纸: $WallpaperPath （请放一张 wallpaper.jpg 在项目根目录）" }
$pkg = Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pkg) { throw "未找到 Claude 桌面版" }
$ion = Join-Path $pkg.InstallLocation "app\resources\ion-dist"
if (-not (Test-Path $ion)) { throw "未找到 ion-dist，包结构可能已变化" }

# 备份（仅首次）
$v1 = Join-Path $ion "assets\v1"
$bak = Join-Path $env:TEMP "dress-your-agent-ion-backup"
New-Item $bak -ItemType Directory -Force | Out-Null
$cssFile = Get-ChildItem $v1 -Filter "shared-styles-*.css" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $cssFile) { throw "未找到 shared-styles-*.css，包结构可能已变化" }
$bakCss = Join-Path $bak ("shared-styles-" + $pkg.Version + ".css.orig")
if (-not (Test-Path $bakCss)) { Copy-Item $cssFile.FullName $bakCss -Force }

# 写权限 + 注入
takeown /f $ion /r /d y | Out-Null
icacls $ion /grant "${env:USERNAME}:(OI)(CI)F" /t /c | Out-Null
Copy-Item $WallpaperPath (Join-Path $v1 $ImgName) -Force

$css = Get-Content $cssFile.FullName -Raw
if ($css -notmatch 'dress-your-agent') {
    $block = Get-Content (Join-Path $PSScriptRoot "theme-ion.css") -Raw
    $block = $block.Replace("rgba(10,12,18,.45)", "rgba(10,12,18,$OverlayAlpha)")
    $block = $block.Replace("/assets/v1/bg-custom.jpg", "/assets/v1/$ImgName")
    Add-Content -Path $cssFile.FullName -Value $block -Encoding UTF8
} else {
    Write-Host "样式已存在，跳过（如需更新遮罩浓度请先还原再注入）"
}

Write-Host "完成！重启 Claude 后，Windows 深色模式下即可看到壁纸。"
Write-Host ("样式表备份: " + $bakCss)
