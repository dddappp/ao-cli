# 快速参考：使用 ao-cli --json 编写自动化脚本

## 🚀 3 分钟入门

### 基础模板

```bash
#!/bin/bash
set -e

# 1. 定义辅助函数（关键！隔离日志）
run_ao_cli() {
    ao-cli "$@" 2>/dev/null
}

# 2. 执行命令获取 JSON
JSON=$(run_ao_cli spawn default --name "test" --json)

# 3. 验证成功状态
if ! echo "$JSON" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "❌ 失败: $(echo "$JSON" | jq -r '.error')"
    exit 1
fi

# 4. 提取数据
PROCESS_ID=$(echo "$JSON" | jq -r '.data.processId')
echo "✅ 进程ID: $PROCESS_ID"
```

## ⚙️ 关键检查清单

- [ ] **使用 `2>/dev/null`**：所有 `ao-cli` 调用都要过滤日志
- [ ] **验证 `.success`**：每个命令结果都要用 `jq -e '.success == true'` 检查
- [ ] **错误消息**：用 `jq -r '.error'` 提取错误信息
- [ ] **提取数据**：用 `jq -r '.data.fieldName'` 提取需要的数据

## 📋 常用命令模式

### 创建进程
```bash
JSON=$(run_ao_cli spawn default --name "my-app" --json)
PID=$(echo "$JSON" | jq -r '.data.processId')
```

### 加载代码
```bash
JSON=$(run_ao_cli load "$PID" app.lua --json)
# 检查成功
echo "$JSON" | jq -e '.success == true' >/dev/null 2>&1 || echo "加载失败"
```

### 发送消息
```bash
JSON=$(run_ao_cli message "$PID" Action --data '{"x":1}' --wait --json)
RESULT=$(echo "$JSON" | jq '.data.result')
```

### 执行 Lua 代码
```bash
JSON=$(run_ao_cli eval "$PID" "return State.counter" --wait --json)
OUTPUT=$(echo "$JSON" | jq '.data.result.Output.data')
```

## 🐛 常见错误

| 错误              | 原因              | 解决方案                                     |
| ----------------- | ----------------- | -------------------------------------------- |
| `jq: parse error` | JSON 混入日志     | 使用 `2>/dev/null`                           |
| `null` 值         | 字段不存在        | 用 `jq -r '.data.field // empty'` 提供默认值 |
| 脚本卡住          | `--wait` 等待结果 | 正常行为，耐心等待或设置网络超时             |

## ✨ 最佳实践

```bash
# ✅ 好的做法
JSON=$(ao-cli command --json 2>/dev/null)
SUCCESS=$(echo "$JSON" | jq -e '.success == true')

# ❌ 不好的做法
JSON=$(ao-cli command --json 2>&1)  # 混入日志！
SUCCESS=$(echo "$JSON" | jq '.success')  # 不检查有效性
```

## 🔗 更多信息

详见 [README.md](README.md)
