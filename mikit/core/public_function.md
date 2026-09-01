# 🛠️ Mikit 框架核心 API 工具函数文档

本文档详细说明 Mikit 框架中提供的日志记录、数据库（UCI）读写以及定时任务（Crontab）统一管理接口的使用方法。

---

## 1. 🪵 日志工具 (log)
仅作为后台任务日志记录，日志文件 /tmp/messages

语法：`log <level> [-s|-t] <message>`

### 参数说明
* **level**：日志级别，支持 `INFO` | `WARN` | `ERROR`
* **-s**：Silent 模式（仅写入 Syslog，不输出控制台）
* **-t**：Terminal 模式（仅输出控制台，不写入 Syslog）
* **快捷函数**：`loginfo` / `logwarn` / `logerr`

### 代码示例
```sh
# 快捷调用示例
loginfo "服务启动成功，监听端口: 8080"
logwarn "配置文件不存在，已自动重置"
logerr -s "后台守护进程异常退出 (PID: 1234)"
```

---

## 2. 🗄️ 数据库统一接口 (mikit_db)

语法：`mikit_db [action] <key/target> [value]`

### 支持的操作 (Action)
* **get** (默认)：读取指定 Key 的值 (`mikit_db get "port"`)
* **set**：设置指定 Key 的值 (`mikit_db set "port" "8080"`)
* **add**：给列表 List 追加项 (`mikit_db add "nodes" "hk01.com"`)
* **rmlist**：从列表 List 中移除指定项 (`mikit_db rmlist "nodes" "hk01.com"`)
* **del** / **clean**：删除指定 Key / Option (`mikit_db del "port"`)
* **del_sec** / **rmsec**：删除整个 Section 节点 (`mikit_db del_sec "mihomo"`)

### 路径规则说明
传入普通 Key（如 `"port"`）时会自动补全为 `$APP_ID.port`；传入带点的路径（如 `"system.hostname"`）时会自动定位到指定 Section。

### 代码示例
```sh
# 读写与删除示例
mikit_db set "enable" "1"
local port=$(mikit_db get "port")
mikit_db del "port"
```

---

## 3. ⏰ 定时任务接口 (cron)

语法：`cron <action> [args...]`

### 常用指令说明
* **cron set <task_id> <tag> <enabled> <expr> <cmd> [remark]**：添加或更新定时任务
* **cron get <task_id>**：获取指定任务详情
* **cron get_tag <tag_name>**：获取指定 Tag 标签下的所有任务
* **cron del <task_id>**：删除指定 ID 的任务
* **cron del_tag <tag_name>**：按 Tag 批量删除任务

### 代码示例
```sh
# 定时任务设置与同步示例
cron set "check_mihomo" "guard" "1" "*/5 * * * *" "/apps/mihomo/check.sh" "心跳检查"
```