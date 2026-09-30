#Requires -Version 5.1
<#
.SYNOPSIS
    把构建好的 APK 发布到 GitHub Releases，并标注版本号与更新内容。

.DESCRIPTION
    用 GitHub REST API 直接完成，不依赖 gh CLI（本机没装）。

    令牌从 git 凭据管理器读取（`git credential fill`），
    不写在脚本里、也不出现在命令行参数中，避免泄露到进程列表或历史记录。

    流程：
      1. 确定 tag 与版本号（默认从 pubspec.yaml 读，可用 -Tag 覆盖）
      2. 创建 release（已存在同名 tag 时报错退出，不会覆盖已有的）
      3. 上传 APK 作为附件
      4. 校验线上附件大小与本地一致

.EXAMPLE
    # 版本号与说明都由脚本参数给出
    .\tools\release_to_github.ps1 -ApkPath ..\build\app\outputs\flutter-apk\app-release.apk `
        -Notes "1. 新增赞助名单`n2. 修复导入"

.EXAMPLE
    # 只建 release 不传真机包（用于先挂个说明）
    .\tools\release_to_github.ps1 -Tag v1.0.25 -NoAsset -Notes "占位说明"
#>
param(
    # tag 名；不传则按 pubspec.yaml 的版本号生成 vX.Y.Z
    [string]$Tag = '',

    # 要上传的安装包路径
    [string]$ApkPath = '',

    # 更新说明；\n 会被转成换行
    [string]$Notes = '',

    # 目标仓库
    [string]$Repo = 'Wangxiaolu0716/class-schedule',

    # 附件在 release 里的文件名；不传则沿用本地文件名。
    # Flutter 的产物统一叫 app-release.apk，直接传上去看不出是哪个版本，
    # 所以发版时建议显式指定，如 nbcc_schedule-1.0.24.apk
    [string]$AssetName = '',

    # release 标题；不传则与 tag 相同
    [string]$Title = '',

    # 标记为预发布
    [switch]$Prerelease,

    # 只建 release，不上传附件
    [switch]$NoAsset,

    # 跳过发布前确认
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Write-Step($text) { Write-Host "`n>>> $text" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 取令牌

function Get-GitHubToken {
    # git credential fill 从标准输入读「要找哪个 host 的凭据」，
    # 再把用户名密码打回标准输出。这里只要 password，且绝不打印出来。
    $probe = "protocol=https`nhost=github.com`n`n"
    $lines = $probe | & git credential fill 2>$null
    if ($LASTEXITCODE -ne 0) { throw '调用 git credential fill 失败' }

    foreach ($line in $lines) {
        if ($line -like 'password=*') {
            $token = $line.Substring('password='.Length).Trim()
            if ($token) { return $token }
        }
    }
    throw 'git 凭据管理器里没有 github.com 的令牌，请先执行一次 git push 让 Git 记住凭据'
}

# ---------------------------------------------------------------- 版本号

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $projectRoot 'pubspec.yaml'

if (-not $Tag) {
    if (-not (Test-Path $pubspec)) { throw "没传 -Tag，又找不到 pubspec.yaml：$pubspec" }
    $line = Select-String -Path $pubspec -Pattern '^version:\s*([0-9][0-9.]*)\+' | Select-Object -First 1
    if (-not $line) { throw 'pubspec.yaml 里读不到版本号，请显式传 -Tag' }
    $version = $line.Matches[0].Groups[1].Value
    $Tag = "v$version"
    Write-Ok "从 pubspec.yaml 读到版本 $version"
}

if (-not $Title) { $Title = $Tag }
$Notes = $Notes -replace '\\n', "`n"
if (-not $Notes) { $Notes = '问题修复与体验优化' }

# ---------------------------------------------------------------- 附件检查

$apk = $null
if (-not $NoAsset) {
    if (-not $ApkPath) { throw '没传 -ApkPath；只想建 release 请加 -NoAsset' }
    $apk = (Resolve-Path -LiteralPath $ApkPath -ErrorAction Stop).Path
    if (-not (Test-Path $apk)) { throw "找不到安装包：$ApkPath" }
    if (-not $apk.ToLower().EndsWith('.apk')) { throw '附件必须是 .apk 文件' }
}

# ---------------------------------------------------------------- 确认

Write-Step '发布计划'
Write-Host "    仓库    : $Repo"
Write-Host "    Tag     : $Tag"
Write-Host "    标题    : $Title"
Write-Host "    预发布  : $(if ($Prerelease) { '是' } else { '否' })"
Write-Host "    说明    : $(($Notes -split "`n") -join ' / ')"
if ($apk) {
    $sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 2)
    Write-Host "    附件    : $apk  ($sizeMb MB)"
} else {
    Write-Host '    附件    : 无（-NoAsset）'
}

if (-not $Yes) {
    $answer = Read-Host '确认发布到 GitHub Releases？(y/N)'
    if ($answer -ne 'y' -and $answer -ne 'Y') { Write-Warn '已取消'; return }
}

$token = Get-GitHubToken
$headers = @{
    Authorization          = "Bearer $token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

# ---------------------------------------------------------------- 建 release

Write-Step '创建 release'
$payload = @{
    tag_name   = $Tag
    name       = $Title
    body       = $Notes
    draft      = $false
    prerelease = [bool]$Prerelease
} | ConvertTo-Json -Depth 4

# 必须显式转成 UTF-8 字节再发。
# PowerShell 5.1 的 Invoke-RestMethod 在 -Body 传字符串时按 Windows-1252 编码，
# 中文会被替换成「?」，GitHub 端再按 UTF-8 解码就变成一串问号。
$payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)

try {
    $release = Invoke-RestMethod -Method Post `
        -Uri "https://api.github.com/repos/$Repo/releases" `
        -Headers $headers -ContentType 'application/json; charset=utf-8' `
        -Body $payloadBytes
} catch {
    $detail = $_.ErrorDetails.Message
    if ($detail -match 'already_exists') {
        throw "tag $Tag 已存在，GitHub 不允许覆盖已有 release。请换个版本号，或先去网页上删掉那条 release"
    }
    throw "创建 release 失败：$detail"
}
Write-Ok "release 已创建：$($release.html_url)"
$releaseId = $release.id

# ---------------------------------------------------------------- 上传附件

if ($apk) {
    Write-Step '上传安装包'
    # 优先用显式指定的名字；没指定就沿用本地文件名
    $fileName = if ($AssetName) { $AssetName } else { [IO.Path]::GetFileName($apk) }
    if (-not $fileName.ToLower().EndsWith('.apk')) { $fileName = "$fileName.apk" }
    $item = Get-Item $apk
    # 名字里带版本号，下载的人一眼能看出拿到的是哪一版
    if ($fileName -notmatch [regex]::Escape($Tag.TrimStart('v'))) {
        Write-Warn "附件名「$fileName」里没有版本号，建议用 -AssetName 指定"
    }
    try {
        $asset = Invoke-RestMethod -Method Post `
            -Uri "https://uploads.github.com/repos/$Repo/releases/$releaseId/assets?name=$fileName" `
            -Headers $headers -ContentType 'application/vnd.android.package-archive' `
            -InFile $apk -TimeoutSec 900
    } catch {
        throw "上传失败（release 已建好，可稍后重跑并换 -Tag，或手动拖拽上传）：$($_.ErrorDetails.Message)"
    }
    Write-Ok "已上传 $($asset.name)  ($([math]::Round($asset.size / 1MB, 2)) MB)"

    # ------------------------------------------------------------ 校验

    Write-Step '校验线上附件'
    if ($asset.size -ne $item.Length) {
        throw "线上附件大小 $($asset.size) 与本地 $($item.Length) 不一致"
    }
    Write-Ok '大小一致'
}

Write-Host ''
Write-Host '发布完成。' -ForegroundColor Green
Write-Host "  版本  $Tag"
Write-Host "  页面  https://github.com/$Repo/releases/tag/$Tag"