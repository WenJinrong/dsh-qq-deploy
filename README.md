# QQ ↔ DeepSeek Harness 一键部署（Windows）

把 **DeepSeek Harness（无头 Web）+ qq-bridge + SnowLuma** 装在任意一台 Windows 机器上，
让 QQ 机器人 7×24 在线，不依赖你日常用的那台电脑。

> 适用：Windows 10 / 11 / Server 2019+（x64），2 核 4G 起。
> 不支持 Linux：SnowLuma 靠 hook QQ NT 客户端进程工作，QQ 客户端目前只有 Windows 版能稳定 hook。

---

## 它装了什么

```
QQ NT 客户端  ──hook──►  SnowLuma（OneBot v11：WS 3001 / HTTP 3000）
                              │
                              ▼
                        qq-bridge（人格/白名单/会话映射，控制台 3100）
                              │  Cookie 鉴权 + /api/remote.mux
                              ▼
                    DeepSeek Harness（dsh web，127.0.0.1:3080）
```

| 组件 | 来源 | 说明 |
|---|---|---|
| Node.js 24.22.1 | npmmirror 二进制镜像 | 便携版，不污染系统 |
| DSH | npm `@deepseek-ai/dsh` | 无头 web，固定 3080 |
| qq-bridge | GitHub `Derpyu520/qq-bridge` | MIT |
| SnowLuma | GitHub Releases `TomyJan/SnowLuma`（官方镜像） | 源码可见非商业许可，脚本只下载官方发行包，不改不打包 |

---

## 一键部署

在**管理员** PowerShell 里：

```powershell
git clone https://github.com/WenJinrong/dsh-qq-deploy.git C:\deploy
cd C:\deploy
powershell -ExecutionPolicy Bypass -File .\install.ps1 -OwnerQQ 2928845553
```

没有 git 就直接下载 ZIP 解压，然后跑同一条命令。

常用参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `-InstallDir` | `C:\qq-bot` | 安装目录 |
| `-OwnerQQ` | 必填 | 你自己的 QQ（白名单，只放行这个号） |
| `-GroupQQ` | 空 | 要放行的群号（可多个，逗号分隔） |
| `-GithubProxy` | 空 | 国内访问 GitHub 慢时填 `https://ghfast.top/` 之类前缀 |
| `-SkipSnowLuma` | 关 | 只装 DSH + 桥接，SnowLuma 自己装 |
| `-SkipTasks` | 关 | 不注册开机自启任务 |

---

## 装完还要做三件事（都要人工）

### 1. 登录 DSH

`dsh web` 首次启动需要登录 DeepSeek 账号。两种办法：

- **搬凭据（推荐）**：把日常那台电脑的 `C:\Users\<你>\.dsh\.credentials.yaml` 复制到服务器的 `C:\Users\<用户>\.dsh\.credentials.yaml`
- 或者：打开 `http://127.0.0.1:3080`，按页面提示登录（需要浏览器能访问服务器，可用远程桌面里的浏览器）

### 2. 登录机器人 QQ

服务器上打开 QQ，用**机器人小号**登录（主号别用，有风控风险）。扫码或密码都行。

### 3. 接入 SnowLuma

双击 `C:\qq-bot\scripts\start-snowluma.cmd`，窗口里会打印：

```
[WebUI] initial credentials: user=admin password=xxxxxxxx
[WebUI] listening http://127.0.0.1:5099
```

浏览器打开 `http://127.0.0.1:5099`，用初始密码登录 → 同意条款 → 改密码 → **接入 QQ 进程** →
在 OneBot 设置里开启 **WebSocket 服务端 3001** 和 **HTTP API 3000**。

桥接会自动发现端口和 token（`snowluma.followDiscoveredEndpoint`），不用手填。

---

## 开机自启

`install.ps1` 会注册三个「登录时启动」的计划任务：

| 任务 | 作用 |
|---|---|
| `DSH-Web` | `dsh --profile web`（3080） |
| `SnowLuma` | SnowLuma 网关（5099 / 3000 / 3001） |
| `QQ-Bridge` | 桥接（3100），会等 DSH 端口就绪后再启动 |

Windows 的 GUI 程序（QQ）需要有人登录桌面才能跑，所以服务器要开**自动登录**：

```powershell
# 管理员 PowerShell；把用户名密码换成服务器的
netplwiz
# 或在注册表里配置 AutoAdminLogon（更危险，不推荐明文存密码）
```

> 云服务器建议装 Windows Server + 自动登录 + 关闭屏幕保护/睡眠。
> 家用小主机同理。**关机/断网就是离线**，没有例外。

---

## 日常运维

```powershell
# 看状态
powershell -File C:\qq-bot\scripts\verify.ps1

# 手动起停
C:\qq-bot\scripts\start-dsh.cmd
C:\qq-bot\start-snowluma.cmd
C:\qq-bot\start-bridge.cmd

# 桥接控制台（令牌在 qq-bridge\state\console-token）
http://127.0.0.1:3100
```

日志：

- 桥接：`C:\qq-bot\qq-bridge\state\bridge.log`
- SnowLuma：`C:\qq-bot\SnowLuma\logs\snowluma-*.log`
- DSH：`%USERPROFILE%\.dsh\`（会话、配置）

---

## 常见问题

| 现象 | 排查 |
|---|---|
| QQ 发消息没反应 | 看 `bridge.log` 是否有 `SnowLuma 已连接`；没有就查 SnowLuma 是否登录、OneBot 3000/3001 是否监听 |
| 日志里 `model-unavailable` | `config.json` 的 `dsh.provider` 改成 `deepseek-account`，`model` 改成 DSH 设置页里可用的 |
| `unknown prompt variable {{cwd}}` | DSH 版本与 qq-bridge 不匹配，看 qq-bridge README 的版本对照表 |
| GitHub 下载失败 | 加 `-GithubProxy`，或手动下载后解压到 `C:\qq-bot\SnowLuma` |
| 重装/换号 | 删 `qq-bridge\state\sessions.json` 后重启桥接 |

更多见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

---

## 合规提醒

- SnowLuma 是第三方项目，与腾讯/QQ 无隶属关系，使用前读它的 EULA 与《QQ 用户协议》；**用机器人小号，别用主号**。
- qq-bridge 是 MIT；DSH 是 MIT。
- 本仓库只包含部署脚本和配置模板，不包含 SnowLuma 二进制、不包含任何账号凭据。

