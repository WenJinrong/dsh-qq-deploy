# 同 install.ps1 里的自动注册，单独跑一次即可（管理员）。
param([string]$InstallDir = "C:\qq-bot")

$ErrorActionPreference = "Stop"
$scripts = Join-Path $InstallDir "scripts"
$tasks = @(
  @{ Name = "DSH-Web";   Script = "start-dsh.cmd" },
  @{ Name = "SnowLuma";  Script = "start-snowluma.cmd" },
  @{ Name = "QQ-Bridge"; Script = "start-bridge.cmd" }
)

foreach ($t in $tasks) {
  $exe = Join-Path $scripts $t.Script
  if (-not (Test-Path $exe)) { Write-Host "skip $($t.Name): $exe 不存在" -ForegroundColor Yellow; continue }
  schtasks /Create /TN $t.Name /TR "cmd.exe /c `"$exe`"" /SC ONLOGON /RL HIGHEST /F 2>$null 1>$null
  if ($LASTEXITCODE -eq 0) { Write-Host "registered: $($t.Name)" -ForegroundColor Green }
  else { Write-Host "failed: $($t.Name)（需要管理员）" -ForegroundColor Red }
}

Write-Host ""
Write-Host "查看：schtasks /Query /TN DSH-Web /V /FO LIST" -ForegroundColor Cyan
Write-Host "删除：schtasks /Delete /TN DSH-Web /F" -ForegroundColor Cyan
