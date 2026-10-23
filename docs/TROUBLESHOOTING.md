# 排障手册

## 先看哪里

```powershell
powershell -File C:\qq-bot\scripts\verify.ps1
```

正常应看到五个端口都在监听：3080 / 5099 / 3000 / 3001 / 3100。

---

## 症状 → 原因 → 处理

### 1. QQ 发消息完全没反应

依次查：

1. `bridge.log` 有没有 `SnowLuma 已连接：ws://127.0.0.1:3001`
   - 没有 → SnowLuma 没起或没登录，见第 2 条
2. 有没有 `会话 ... 已挂载 preset qq-chat-v2`
   - 报 `preset` 相关错误 → `node scripts/setup-dsh.mjs web` 没成功，或 DSH 没重启过
3. 有没有 `模型` 相关错误
   - `session/model-unavailable` → 改 `config.json`：`dsh.provider = "deepseek-account"`，
     `dsh.model` 换成 DSH 设置页里真实可用的模型
4. 有没有 `未知提示词变量 {{cwd}}`
   - qq-bridge 与 DSH 版本不匹配，按 qq-bridge README 的版本对照表换 tag

### 2. SnowLuma 起不来 / 5099 打不开

- 先看窗口输出或 `SnowLuma\logs\snowluma-*.log`
- `ERR_CONNECTION_REFUSED` 多半是进程退了；常见原因：
  - Node 版本不满足（SnowLuma 2.x 要 `^24.22.1 || >=26.12.1`）——发行包自带 `node.exe`，别用系统的旧 node
  - 端口 5099 被占：`netstat -ano | findstr 5099`
- 初始密码只打印一次；忘了就删 `SnowLuma\config\webui.json` 重启，会生成新密码

### 3. 连上了但收不到 QQ 消息

SnowLuma 的 `[Hook]` 退化了。看 `SnowLuma\logs\`：

```
WARN [Hook] receive path stale: PID=… silentFor=…ms; reporting good=false
```

处理：重启 QQ（保持小号登录）→ 重启 SnowLuma → 重新接入 QQ 进程。

### 4. QQ 登录掉线

- 小号被风控：换回手机 QQ 扫码登录一次
- Windows 重启后 QQ 没自动登录：需要配置自动登录，且 QQ 设置里勾选「自动登录」

### 5. DSH 连不上（bridge 日志 `DSH 不可用`）

- 3080 没监听：`dsh --profile web` 启动失败，看窗口报错
- 凭据缺失：`%USERPROFILE%\.dsh\.credentials.yaml` 不存在 → 从日常电脑复制，或浏览器登录一次

### 6. GitHub 下载慢/失败

- 加参数：`-GithubProxy https://ghfast.top/`
- 或手动下 SnowLuma 发行包解压到 `C:\qq-bot\SnowLuma`，再跑 install.ps1（会跳过已存在项）

### 7. 想换机器人号 / 重置会话

```powershell
# 停桥接，删会话映射，重启
Remove-Item C:\qq-bot\qq-bridge\state\sessions.json -Force
```

### 8. 想换人格

编辑 `C:\qq-bot\qq-bridge\roles\*.md`，然后写 `state\current-role.json`：

```json
{ "role": "鱼酱" }
```

桥接每条消息热读，无需重启 DSH。
