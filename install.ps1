#Requires -Version 5.1
<#
.SYNOPSIS
  一键部署 DeepSeek Harness + qq-bridge + SnowLuma（Windows x64）。

.DESCRIPTION
  安装目录结构：
    <InstallDir>\
      node\                 Node.js 便携版
      npm-global\           全局 npm 包（dsh）
      qq-bridge\            桥接（含 config.json / state / roles）
      SnowLuma\             网关（官方发行包）
      scripts\              启动、自检、任务注册脚本
      config\               配置模板

.PARAMETER OwnerQQ
  你自己的 QQ 号（白名单，只有它能和机器人对话）。

.PARAMETER GroupQQ
  要放行的群号，多个用逗号分隔。留空则只放行私聊。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -OwnerQQ 2928845553
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "C:\qq-bot",
  [Parameter(Mandatory = $true)][string]$OwnerQQ,
  [string]$GroupQQ = "",
  [string]$NodeVersion = "24.22.1",
  [string]$DshVersion = "0.2.1-rc.2",
  [string]$GithubProxy = "",
  [string]$Profile = "web",
  [switch]$SkipSnowLuma,
  [switch]$SkipTasks
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Log([string]$m) { Write-Host "[deploy] $m" -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host "[deploy] OK  $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "[deploy] WARN $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "[deploy] FAIL $m" -ForegroundColor Red; exit 1 }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Url([string]$url) {
  if ($GithubProxy -and $url -like "https://github.com/*") {
    return $GithubProxy.TrimEnd("/") + "/" + $url
  }
  return $url
}

function Save-File([string]$url, [string]$out) {
  $u = Get-Url $url
  Log "下载 $u"
  Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing -TimeoutSec 600
  if (-not (Test-Path $out)) { Fail "下载失败：$u" }
  Ok ("已保存 " + (Split-Path $out -Leaf) + " (" + [math]::Round((Get-Item $out).Length / 1MB, 1) + " MB)")
}

# 原生命令（npm/node）的 stderr 会被 PowerShell 当成错误记录；临时放宽再收回，避免误杀安装
function Invoke-Native([string]$exe, [string[]]$argList) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $exe @argList
    return $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $old
  }
}

function Expand-Zip([string]$zip, [string]$dest) {
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
}

# 解压后把唯一的顶层目录提到目标位置
function Move-SingleChild([string]$from, [string]$to) {
  $children = @(Get-ChildItem $from)
  if ($children.Count -ne 1 -or -not $children[0].PSIsContainer) { Fail "压缩包结构不符合预期：$from" }
  if (Test-Path $to) { Remove-Item $to -Recurse -Force }
  Move-Item $children[0].FullName $to
}

# ---------------------------------------------------------------- 环境检查

Log "安装目录：$InstallDir"
if (-not [Environment]::Is64BitOperatingSystem) { Fail "只支持 64 位 Windows" }
if (-not (Test-Admin)) { Warn "当前不是管理员权限，注册计划任务可能失败" }

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir "scripts") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir "config") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir "tmp") | Out-Null

# 仓库里的 scripts / config 模板拷进安装目录，并把 __INSTALL_DIR__ 换成真实路径
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($sub in @("scripts", "config")) {
  $src = Join-Path $here $sub
  if (-not (Test-Path $src)) { continue }
  Get-ChildItem $src -File | ForEach-Object {
    $text = (Get-Content $_.FullName -Raw -Encoding UTF8).Replace("__INSTALL_DIR__", $InstallDir)
    $out = Join-Path (Join-Path $InstallDir $sub) $_.Name
    [System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding($false)))
  }
  Ok "脚本已就位：$sub"
}

# ---------------------------------------------------------------- Node.js

$nodeDir = Join-Path $InstallDir "node"
if (-not (Test-Path (Join-Path $nodeDir "node.exe"))) {
  $nodeZip = Join-Path $InstallDir "tmp\node.zip"
  $nodeUrl = "https://registry.npmmirror.com/-/binary/node/v$NodeVersion/node-v$NodeVersion-win-x64.zip"
  Save-File $nodeUrl $nodeZip
  $tmp = Join-Path $InstallDir "tmp\node-x"
  Expand-Zip $nodeZip $tmp
  Move-SingleChild $tmp $nodeDir
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Ok "Node.js $NodeVersion 已装"
} else {
  Ok "Node.js 已存在，跳过"
}

$env:PATH = "$nodeDir;$env:PATH"
$node = Join-Path $nodeDir "node.exe"
$npm = Join-Path $nodeDir "npm.cmd"
if (-not (Test-Path $node)) { Fail "找不到 node.exe" }
& $node --version
if ($LASTEXITCODE -ne 0) { Fail "node 无法运行" }

# npm 全局目录放到安装目录，避免写 C:\Users\...\AppData
$npmGlobal = Join-Path $InstallDir "npm-global"
New-Item -ItemType Directory -Force -Path $npmGlobal | Out-Null
$code = Invoke-Native $npm @("config", "set", "prefix", $npmGlobal, "--global")
if ($code -ne 0) { Warn "npm prefix 设置失败（$code）" }
$null = Invoke-Native $npm @("config", "set", "registry", "https://registry.npmmirror.com")
# npm 11 默认拦截依赖的安装脚本；DSH 的原生依赖（pty/koffi）需要放行
$null = Invoke-Native $npm @("config", "set", "allow-scripts", "@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs", "--location=user")
$env:PATH = "$npmGlobal;$env:PATH"

# ---------------------------------------------------------------- DSH

if (-not (Test-Path (Join-Path $npmGlobal "dsh.cmd"))) {
  Log "安装 @deepseek-ai/dsh@$DshVersion"
  $code = Invoke-Native $npm @("install", "-g", "@deepseek-ai/dsh@$DshVersion", "--no-audit", "--no-fund")
  if ($code -ne 0) { Fail "DSH 安装失败（检查网络/镜像）" }
  Ok "DSH 已装"
} else {
  Ok "DSH 已存在，跳过"
}

# ---------------------------------------------------------------- qq-bridge

$bridgeDir = Join-Path $InstallDir "qq-bridge"
if (-not (Test-Path (Join-Path $bridgeDir "package.json"))) {
  $bridgeZip = Join-Path $InstallDir "tmp\qq-bridge.zip"
  Save-File "https://codeload.github.com/Derpyu520/qq-bridge/zip/refs/heads/main" $bridgeZip
  $tmp = Join-Path $InstallDir "tmp\qq-bridge-x"
  Expand-Zip $bridgeZip $tmp
  Move-SingleChild $tmp $bridgeDir
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Ok "qq-bridge 已下载"
} else {
  Ok "qq-bridge 已存在，跳过"
}

Push-Location $bridgeDir
try {
  Log "安装桥接依赖"
  $code = Invoke-Native $npm @("install", "--no-audit", "--no-fund")
  if ($code -ne 0) { Fail "桥接依赖安装失败" }
  Ok "桥接依赖已装"
} finally { Pop-Location }

# ---------------------------------------------------------------- 配置

$cfgPath = Join-Path $bridgeDir "config.json"
$groups = @()
if ($GroupQQ.Trim()) { $groups = @($GroupQQ -split "[,，\s]+" | Where-Object { $_ }) }

$cfg = [ordered]@{
  dsh = [ordered]@{
    baseUrl         = "http://127.0.0.1:3080"
    provider        = "deepseek-account"
    model           = "deepseek-flash"
    reasoningEffort = "low"
    authToken       = ""
    allowRemote     = $false
  }
  snowluma = [ordered]@{
    wsUrl                     = "ws://127.0.0.1:3001"
    httpUrl                   = "http://127.0.0.1:3000"
    accessToken               = ""
    followDiscoveredEndpoint  = $true
    homeDir                   = (Join-Path $InstallDir "SnowLuma")
    launcherPath              = (Join-Path $InstallDir "SnowLuma\launcher.bat")
  }
  ownerQQ          = [long]$OwnerQQ
  sessionCwd       = $InstallDir
  agentPreset      = "qq-chat"
  workspaceTitle   = "QQ 聊天"
  allow            = [ordered]@{ private = @([string]$OwnerQQ); groups = $groups }
  allowAllWhenEmpty = $false
  consolePort      = 3100
  consoleToken     = ""
}
$json = $cfg | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($cfgPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Ok "config.json 已生成（白名单：$OwnerQQ）"

# DSH 端：preset + MCP（装完必须重启 DSH 才生效）
Log "安装 DSH 端 preset 与 MCP"
Push-Location $bridgeDir
try {
  $code = Invoke-Native $node @("scripts\setup-dsh.mjs", $Profile)
  if ($code -ne 0) { Warn "setup-dsh.mjs 退出码 $code，DSH 启动后若报错请重跑" }
} finally { Pop-Location }

# ---------------------------------------------------------------- SnowLuma

if (-not $SkipSnowLuma) {
  $snowDir = Join-Path $InstallDir "SnowLuma"
  if (-not (Test-Path (Join-Path $snowDir "index.mjs"))) {
    Log "查询 SnowLuma 最新发行版"
    $api = Invoke-RestMethod -Uri "https://api.github.com/repos/TomyJan/SnowLuma/releases/latest" `
      -UseBasicParsing -Headers @{ "User-Agent" = "dsh-qq-deploy" } -TimeoutSec 60
    $asset = $api.assets | Where-Object { $_.name -like "*win-x64.zip" -and $_.name -notlike "*lite*" } | Select-Object -First 1
    if (-not $asset) { Fail "没找到 SnowLuma win-x64 发行包" }
    Log "使用 $($asset.name)"
    $zip = Join-Path $InstallDir "tmp\snowluma.zip"
    Save-File $asset.browser_download_url $zip
    Expand-Zip $zip $snowDir
    Ok "SnowLuma 已解压：$snowDir"
  } else {
    Ok "SnowLuma 已存在，跳过"
  }
}

# ---------------------------------------------------------------- 计划任务

if (-not $SkipTasks) {
  $taskDir = Join-Path $InstallDir "scripts"
  $tasks = @(
    @{ Name = "DSH-Web";   Script = "start-dsh.cmd" },
    @{ Name = "SnowLuma";  Script = "start-snowluma.cmd" },
    @{ Name = "QQ-Bridge"; Script = "start-bridge.cmd" }
  )
  foreach ($t in $tasks) {
    $exe = Join-Path $taskDir $t.Script
    if (-not (Test-Path $exe)) { Warn "缺少 $exe，跳过任务 $($t.Name)"; continue }
    schtasks /Create /TN $t.Name /TR "cmd.exe /c `"$exe`"" /SC ONLOGON /RL HIGHEST /F 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "计划任务已注册：$($t.Name)" }
    else { Warn "计划任务注册失败：$($t.Name)（可能需要管理员权限）" }
  }
}

Remove-Item (Join-Path $InstallDir "tmp") -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 收尾

Write-Host ""
Write-Host "================= 部署完成 =================" -ForegroundColor Green
Write-Host "安装目录 : $InstallDir"
Write-Host "桥接日志 : $bridgeDir\state\bridge.log"
Write-Host ""
Write-Host "接下来三步（必须人工）：" -ForegroundColor Yellow
Write-Host "  1) 复制凭据：把日常电脑的 ~\.dsh\.credentials.yaml 放到本机 %USERPROFILE%\.dsh\"
Write-Host "  2) 登录 QQ ：用机器人小号登录（不要用主号）"
Write-Host "  3) 接 SnowLuma：双击 $InstallDir\scripts\start-snowluma.cmd，"
Write-Host "     浏览器打开 http://127.0.0.1:5099，用窗口里的初始密码登录并接入 QQ 进程"
Write-Host ""
Write-Host "自检：powershell -File $InstallDir\scripts\verify.ps1" -ForegroundColor Cyan

