# 架构与数据流

```
┌──────────────┐   QQ 协议   ┌───────────────────────────┐
│  QQ NT 客户端 │◄──────────►│ 腾讯服务器                  │
│  (机器人小号)  │            └───────────────────────────┘
└──────┬───────┘
       │ 原生 hook（SnowLuma 注入 QQ 进程）
       ▼
┌───────────────────────────┐
│ SnowLuma                  │  OneBot v11
│  WS  :3001（反向服务端）    │  HTTP :3000（动作）
│  WebUI :5099              │
└──────┬────────────────────┘
       │ WebSocket / HTTP
       ▼
┌───────────────────────────┐
│ qq-bridge                 │
│  会话映射 / 白名单 / 人格    │  控制台 :3100
│  安全守卫（工具白名单）       │
└──────┬────────────────────┘
       │ Cookie 鉴权 + /api/<ns>/<method> + /api/remote.mux
       ▼
┌───────────────────────────┐
│ DeepSeek Harness (dsh web) │  127.0.0.1:3080
│  agent preset: qq-chat(-v2)│
│  MCP: snowluma / web-search│
└──────┬────────────────────┘
       │
       ▼
  DeepSeek 模型（账号凭据在 ~/.dsh/.credentials.yaml）
```

## 关键文件

| 路径 | 作用 |
|---|---|
| `qq-bridge/config.json` | 桥接配置：DSH 地址、SnowLuma 端点、白名单、控制台端口 |
| `qq-bridge/state/sessions.json` | QQ 会话 ↔ DSH session 映射（删了会重建） |
| `qq-bridge/state/current-role.json` | 当前人格卡：`{"role":"鱼酱"}` |
| `qq-bridge/roles/*.md` | 人格卡（每条消息热注入） |
| `qq-bridge/state/bridge.log` | 主日志 |
| `SnowLuma/config/onebot_<uin>.json` | OneBot 端口与 token（桥接自动读取） |
| `~/.dsh/profiles/web/cordis.patch.yml` | DSH 侧 MCP 与 preset 注入点 |

## 端口一览

| 端口 | 谁 | 用途 |
|---|---|---|
| 3080 | dsh web | 桥接连它 |
| 5099 | SnowLuma | 管理面板 |
| 3000 | SnowLuma | OneBot HTTP |
| 3001 | SnowLuma | OneBot WS |
| 3100 | qq-bridge | 控制台 |

全部只监听 `127.0.0.1`，不需要开公网端口。远程看面板用 SSH 隧道或远程桌面。

## 启动顺序

```
QQ 登录 → SnowLuma（hook QQ）→ dsh web → qq-bridge
```

桥接启动时会等 3080 就绪（最多 180 秒），SnowLuma 不可用会每 30 秒自动重连并自愈 token。

## 权限边界

- QQ 会话只有 MCP 工具（发消息、看图、查历史），**没有**本地命令、文件读写、插件安装。
- 群友不能改人格/设置；只有 `state/current-role.json` 和白名单（管理员改）有效。
- `allow.private` / `allow.groups` 为空且 `allowAllWhenEmpty: false` 时，桥接不响应任何消息（fail-closed）。
