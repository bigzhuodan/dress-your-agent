#requires -Version 5.1
# ============================================================
#  给你喜爱的 agent 更换衣服 —— 一键安装
#  流程: 备份 -> 解包 asar -> 打补丁 -> 重打包 -> 同步 exe 内嵌哈希 -> ion-dist 注入 -> 部署
# ============================================================
param(
    [string]$WallpaperPath = (Join-Path $PSScriptRoot "wallpaper.jpg"),
    [double]$OverlayAlpha  = 0.45,
    [bool]$ForceDark       = $true
)

$ErrorActionPreference = "Stop"

# ---- 自动提权（写入 WindowsApps 需要）----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args2 = @("-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
               "-WallpaperPath", $WallpaperPath, "-OverlayAlpha", $OverlayAlpha, "-ForceDark", $ForceDark)
    Start-Process powershell -Verb RunAs -Wait -ArgumentList $args2
    exit
}

# ---- 配置 ----
$ImgName     = "bg-custom.jpg"
$WorkDir     = Join-Path $env:TEMP ("dress-your-agent-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$AsarMarker  = 'app.asar","alg":"SHA256","value":"'

# ---- 0. 前置检查 ----
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "未找到 node，请先安装 Node.js >= 18: https://nodejs.org" }
$pkg = Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pkg) { throw "未找到 Claude 桌面版（Get-AppxPackage Claude 为空）" }
$res  = Join-Path $pkg.InstallLocation "app\resources"
$app  = Join-Path $pkg.InstallLocation "app"
Write-Host ("[1/9] Claude " + $pkg.Version + " @ " + $pkg.InstallLocation)

if (-not (Test-Path $WallpaperPath)) { throw "未找到壁纸: $WallpaperPath （请在项目根目录放一张 wallpaper.jpg）" }

# ---- 1. 备份（仅首次）----
$bak = Join-Path $res "_dressup-backup"
New-Item $bak -ItemType Directory -Force | Out-Null
foreach ($f in @((Join-Path $res "app.asar"), (Join-Path $app "claude.exe"))) {
    $d = Join-Path $bak (Split-Path $f -Leaf)
    if (-not (Test-Path $d)) { Copy-Item $f $d -Force; Write-Host ("[2/9] 备份 " + (Split-Path $f -Leaf)) }
}
$ionCss = Join-Path $res "ion-dist\assets\v1"
# 找到被 index.html 引用的 shared-styles 样式表（文件名带哈希，随版本变化）
$sharedCss = Get-ChildItem $ionCss -Filter "shared-styles-*.css" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sharedCss) { throw "未在 ion-dist 中找到 shared-styles-*.css，包结构可能已变化" }
$bakIon = Join-Path $bak "shared-styles.css.orig"
if (-not (Test-Path $bakIon)) { Copy-Item $sharedCss.FullName $bakIon -Force }
$bakIonHtml = Join-Path $bak "ion-index.html.orig"
if (-not (Test-Path $bakIonHtml)) { Copy-Item (Join-Path $res "ion-dist\index.html") $bakIonHtml -Force }

# ---- 2. 解包 asar ----
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
npx --yes "@electron/asar" extract (Join-Path $res "app.asar") $WorkDir
Write-Host "[3/9] asar 已解包"

# ---- 3. asar 内容补丁（node）----
& node (Join-Path $PSScriptRoot "scripts\asar-patch.js") $WorkDir $ImgName $ForceDark
if ($LASTEXITCODE -ne 0) { throw "asar-patch.js 失败" }
# 壁纸进主窗口资源
Copy-Item $WallpaperPath (Join-Path $WorkDir ".vite\renderer\main_window\assets\$ImgName") -Force
Write-Host "[4/9] asar 内容补丁完成"

# ---- 4. 重打包 ----
$newAsar = Join-Path $WorkDir "app.asar.new"
npx --yes "@electron/asar" pack $WorkDir $newAsar --unpack="{**/*.node,**/*.exe,**/*.dll}"
Write-Host "[5/9] asar 重打包完成"

# ---- 5. 计算 asar 头部哈希 ----
function Get-AsarHeaderHash([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    try {
        $b = New-Object byte[] 16
        [void]$fs.Read($b, 0, 16)
        $jsize = [BitConverter]::ToUInt32($b, 12)
        $js = New-Object byte[] $jsize
        [void]$fs.Read($js, 0, $jsize)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return (([System.BitConverter]::ToString($sha.ComputeHash($js))) -replace "-", "").ToLowerInvariant()
    } finally { $fs.Dispose() }
}
$newHash = Get-AsarHeaderHash $newAsar

# ---- 6. 等长改写 exe 内嵌哈希 ----
$exeSrc = Join-Path $app "claude.exe"
$exeNew = Join-Path $WorkDir "claude.exe.new"
Copy-Item $exeSrc $exeNew -Force
$bytes = [IO.File]::ReadAllBytes($exeNew)
$text  = [Text.Encoding]::ASCII.GetString($bytes)
$idx   = $text.IndexOf($AsarMarker, [StringComparison]::Ordinal)
if ($idx -lt 0) { throw "exe 中未找到 asar 完整性标记，包结构可能已变化" }
if ($text.IndexOf($AsarMarker, $idx + 1) -ge 0) { throw "完整性标记不唯一，中止" }
$off   = $idx + $AsarMarker.Length
$old   = [Text.Encoding]::ASCII.GetString($bytes, $off, 64)
if ($old -notmatch '^[0-9a-fA-F]{64}$') { throw "内嵌哈希格式异常: $old" }
[Array]::Copy([Text.Encoding]::ASCII.GetBytes($newHash), 0, $bytes, $off, 64)
[IO.File]::WriteAllBytes($exeNew, $bytes)
Write-Host ("[6/9] exe 内嵌哈希已更新: " + $old.Substring(0,12) + "... -> " + $newHash.Substring(0,12) + "...")

# ---- 7. ion-dist 注入（壁纸 + 透明化 + 浮层修复）----
$ion = Join-Path $res "ion-dist"
takeown /f $ion /r /d y | Out-Null
icacls $ion /grant "${env:USERNAME}:(OI)(CI)F" /t /c | Out-Null
Copy-Item $WallpaperPath (Join-Path $ion "assets\v1\$ImgName") -Force
# 部署前移除旧补丁段，保证幂等
$css = Get-Content $sharedCss.FullName -Raw
$css = ($css -split "`n" | Where-Object { $_ -notmatch 'dress-your-agent|custom bg patch' }) -join "`n"
$tokens = @"
/* ====== dress-your-agent: wallpaper theme ====== */
@media (prefers-color-scheme: dark) {
  html {
    --cds-surface-0: transparent !important;
    --cds-surface-1: transparent !important;
    --cds-surface-2: transparent !important;
    --cds-page-bg: transparent !important;
    --background-color-page: transparent !important;
    --epitaxy-transcript-surface: transparent !important;
    --panel-card-surface: transparent !important;
    --df-sidebar-bg: transparent !important;
    --df-web-sidebar-bg: transparent !important;
  }
  html[data-mode="dark"] body, html.dark body {
    background: linear-gradient(rgba(10,12,18,$OverlayAlpha), rgba(10,12,18,$OverlayAlpha)),
                url("/assets/v1/$ImgName") center/cover no-repeat fixed !important;
  }
  html[data-mode="dark"] .bg-surface-1,
  html[data-mode="dark"] .bg-surface-2,
  html[data-mode="dark"] .dframe-sidebar,
  html[data-mode="dark"] .rounded-card { background-color: transparent !important; }
  html[data-mode="dark"] [role="menu"], html[data-mode="dark"] [role="dialog"],
  html[data-mode="dark"] [role="listbox"], html[data-mode="dark"] [role="tooltip"],
  html[data-mode="dark"] [data-radix-popper-content-wrapper] > *,
  html[data-mode="dark"] .shadow-panel, html[data-mode="dark"] .shadow-panel-sm,
  html[data-mode="dark"] .shadow-lg, html[data-mode="dark"] .shadow-md {
    background-color: rgba(22,22,25,.96) !important;
    background-image: none !important;
    backdrop-filter: blur(8px) !important;
  }
  html[data-mode="dark"] .scroll-fade-strip-top, html[data-mode="dark"] .scroll-fade-strip-bottom,
  html[data-mode="dark"] .scroll-fade-strip-left, html[data-mode="dark"] .scroll-fade-strip-right {
    display: none !important; background: none !important;
  }
}
"@
$css = $css + "`n" + ($tokens -replace "`n", "`n/* dress-your-agent */`n")
Set-Content -Path $sharedCss.FullName -Value $css -Encoding UTF8
Write-Host "[7/9] ion-dist 主题样式已注入"

# ---- 8. 部署 asar + exe ----
icacls (Join-Path $res "app.asar") /grant "*S-1-5-32-544:F" | Out-Null
takeown /f $exeSrc | Out-Null
icacls $exeSrc /grant "*S-1-5-32-544:F" | Out-Null
Copy-Item $newAsar (Join-Path $res "app.asar") -Force
Copy-Item $exeNew $exeSrc -Force
Write-Host "[8/9] asar + exe 已部署"

# ---- 9. 完成 ----
Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "[9/9] 全部完成！关闭并重新打开 Claude 即可看到新衣服。"
Write-Host      "恢复原状: powershell -File restore.ps1"
