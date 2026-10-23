# 健康自检：端口 + 进程 + 日志尾巴
$ErrorActionPreference = "SilentlyContinue"
$root = "__INSTALL_DIR__"

$services = @(
  @{ Name = "DSH Web";      Port = 3080 },
  @{ Name = "SnowLuma WebUI"; Port = 5099 },
  @{ Name = "OneBot HTTP";  Port = 3000 },
  @{ Name = "OneBot WS";    Port = 3001 },
  @{ Name = "QQ Bridge";    Port = 3100 }
)

Write-Host "=== 端口 ===" -ForegroundColor Cyan
foreach ($s in $services) {
  $c = Get-NetTCPConnection -State Listen -LocalPort $s.Port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) {
    $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
    Write-Host ("  {0,-14} :{1}  OK   pid={2} ({3})" -f $s.Name, $s.Port, $c.OwningProcess, $p.ProcessName) -ForegroundColor Green
  } else {
    Write-Host ("  {0,-14} :{1}  --   未监听" -f $s.Name, $s.Port) -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "=== 进程 ===" -ForegroundColor Cyan
Get-Process QQ, node -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, StartTime | Format-Table -AutoSize

$log = Join-Path $root "qq-bridge\state\bridge.log"
if (Test-Path $log) {
  Write-Host "=== 桥接日志（最后 15 行）===" -ForegroundColor Cyan
  Get-Content $log -Tail 15
}
