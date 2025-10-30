# AO CLI 测试脚本索引

本目录包含 AO CLI 的测试脚本和示例。这些脚本演示了如何正确使用 `ao-cli` 进行自动化测试和脚本编写。

## 📁 文件清单

### 主要测试脚本

| 文件                        | 描述                        |
| --------------------------- | --------------------------- |
| **run-tests.sh** | 完整的综合测试脚本，验证所有主要命令（spawn, load, message, eval, inbox）。支持 JSON 模式用于自动化测试。 |
| test-address-alternative.sh | 测试 address 命令的备选实现 |
| test-ao-token.sh            | AO token 相关的测试         |
| **cross-process-print-test.sh** | 测试跨进程场景和eval --trace功能的完整演示 |

### Lua 应用示例

| 文件             | 描述                                           |
| ---------------- | ---------------------------------------------- |
| **test-app.lua** | 一个简单的测试应用，演示如何处理消息和状态管理 |
| **test-receiver-print.lua** | 跨进程Handler测试应用，演示接收进程中的print输出 |
| token-test.lua   | Token 相关的 Lua 代码示例                      |

---

## 🚀 快速开始

### 运行完整的测试套件

```bash
# 标准模式（人可读的输出）
./tests/run-tests.sh

# JSON 模式（用于自动化和脚本）
./tests/run-tests.sh --json
```

### 设置自定义参数

```bash
# 自定义等待时间
export AO_WAIT_TIME=5
./tests/run-tests.sh --json

# 使用自定义钱包
./tests/run-tests.sh --wallet /path/to/wallet.json

# 使用代理
export HTTPS_PROXY=http://127.0.0.1:1235
./tests/run-tests.sh --json
```

---

## 📚 使用 `--json` 选项的最佳实践

### 1️⃣ 关键原则：输出流的正确使用

**最重要的一点**：`ao-cli --json` 的所有 JSON 输出都在 **stdout**，调试/进度日志都在 **stderr**。

```bash
# ✅ 正确：只捕获 JSON（stdout）
JSON_OUTPUT=$(ao-cli command args --json 2>/dev/null)

# ❌ 错误：混入日志信息（stderr）
JSON_OUTPUT=$(ao-cli command args --json 2>&1)  # 这样会混入日志！
```

**关键改动**：
- 所有 `console.log()` 的信息性日志 → 改为 `console.error()`
- 所有 `console.warn()` → 改为 `console.error()`
- 只有 JSON 对象和命令输出才使用 `console.log()`

### 2️⃣ 脚本中的 JSON 解析

#### 捕获和验证 JSON

```bash
#!/bin/bash

# 方法 1: 基本捕获
JSON=$(ao-cli spawn default --name "test" --json 2>/dev/null)

# 方法 2: 验证 JSON 有效性并提供默认值
JSON=$(ao-cli message "$PROCESS_ID" Action --json 2>/dev/null | jq . 2>/dev/null || echo '{"success":false,"error":"invalid_json"}')

# 方法 3: 使用 jq 提取特定字段
PROCESS_ID=$(echo "$JSON" | jq -r '.data.processId // empty')
MESSAGE_ID=$(echo "$JSON" | jq -r '.data.messageId // empty')

# 方法 4: 验证成功状态
if echo "$JSON" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "✅ 命令执行成功"
else
    echo "❌ 命令执行失败"
    echo "$JSON" | jq -r '.error // "Unknown error"'
fi
```

#### JSON 结构说明

所有 `--json` 输出都遵循这个结构：

```json
{
  "command": "spawn|load|message|eval|inbox|address",
  "success": true|false,
  "timestamp": "2025-10-22T07:27:35.383Z",
  "version": "1.0.3",
  "data": {
    // 命令特定的数据
  },
  "error": "error message (if success is false)",
  // 可选字段: gasUsed, wait 等
}
```

### 3️⃣ 常见 JSON 输出示例

#### Spawn 命令
```bash
ao-cli spawn default --name "test-process" --json 2>/dev/null | jq .
```
```json
{
  "command": "spawn",
  "success": true,
  "timestamp": "2025-10-22T07:27:35.383Z",
  "version": "1.0.3",
  "data": {
    "processId": "3FcfRiaTFqzKYQs702xm1INNyHt7PHaHl93yK_SR4h4"
  }
}
```

#### Message 命令（带 --wait）
```bash
ao-cli message "$PROCESS_ID" TestAction --data '{"key":"value"}' --wait --json 2>/dev/null | jq .
```
```json
{
  "command": "message",
  "success": true,
  "timestamp": "2025-10-22T07:23:01.830Z",
  "version": "1.0.3",
  "data": {
    "messageId": "8yQbpjfGs5Q_C4UWXqduY0fari9gP4kKiWOFEoz5-Qg",
    "processId": "3FcfRiaTFqzKYQs702xm1INNyHt7PHaHl93yK_SR4h4",
    "action": "TestAction",
    "result": {
      "Messages": [],
      "Assignments": [],
      "Spawns": [],
      "Output": {
        "data": "{...}",
        "_RawData": "{...}",  // 原始未解析的数据
        "_DataType": "parsed_json"  // 数据类型标记
      },
      "GasUsed": 0
    }
  }
}
```

### 4️⃣ 原始数据保留机制

为了保证数据完整性，所有格式化的数据都保留了原始版本：

```bash
# 获取消息结果
JSON=$(ao-cli message "$PID" Action --wait --json 2>/dev/null)

# 原始数据字段
ORIGINAL_DATA=$(echo "$JSON" | jq -r '.data.result.Messages[0]._RawData')
ORIGINAL_TAGS=$(echo "$JSON" | jq '.data.result.Messages[0]._RawTags')

# 格式化后的数据字段
PARSED_DATA=$(echo "$JSON" | jq '.data.result.Messages[0].Data')
FORMATTED_TAGS=$(echo "$JSON" | jq -r '.data.result.Messages[0].Tags[]')
```

**关键字段**：
- `_RawData`：原始未解析的数据内容
- `_RawTags`：原始 Tag 对象数组
- `_DataType`：数据类型标记（`parsed_json`, `base64_decoded`, `string`）
- `Data`：格式化后的数据（如果是 JSON 会被解析）
- `Tags`：格式化后的 Tag 数组（`"name=value"` 格式）

### 5️⃣ 错误处理

```bash
# 完整的错误处理示例
#!/bin/bash
set -e  # 任何命令失败就退出

trap 'echo "❌ 测试失败"; exit 1' ERR

# 执行命令
JSON=$(ao-cli spawn default --json 2>/dev/null || echo '{}')

# 检查 JSON 有效性
if ! echo "$JSON" | jq empty 2>/dev/null; then
    echo "❌ 无效的 JSON 输出"
    exit 1
fi

# 检查命令成功
if ! echo "$JSON" | jq -e '.success == true' >/dev/null 2>&1; then
    ERROR=$(echo "$JSON" | jq -r '.error // "Unknown error"')
    echo "❌ 命令失败: $ERROR"
    exit 1
fi

echo "✅ 命令执行成功"
```

### 6️⃣ 日志隔离最佳实践

为了在脚本中正确使用 JSON，需要对所有命令调用进行日志隔离：

```bash
# 创建一个辅助函数来完全隔离日志
run_ao_cli() {
    local command="$1"
    shift
    # 所有 stderr 输出被丢弃，只返回 stdout（JSON）
    ao-cli "$command" "$@" 2>/dev/null
}

# 使用方式
JSON=$(run_ao_cli spawn default --name "test" --json)
PROCESS_ID=$(echo "$JSON" | jq -r '.data.processId')

# 非 JSON 模式下仍然可以看到完整输出
run_ao_cli spawn default --name "test"  # stderr 和 stdout 都显示
```

### 7️⃣ 命令特定的 JSON 使用

#### 检查进程是否创建成功
```bash
JSON=$(ao-cli spawn default --json 2>/dev/null)
if echo "$JSON" | jq -e '.data.processId | length > 0' >/dev/null 2>&1; then
    PID=$(echo "$JSON" | jq -r '.data.processId')
    echo "✅ 进程已创建: $PID"
fi
```

#### 验证消息发送
```bash
JSON=$(ao-cli message "$PID" MyAction --data '{"x":1}' --wait --json 2>/dev/null)
if echo "$JSON" | jq -e '.success == true and .data.result' >/dev/null 2>&1; then
    RESULT=$(echo "$JSON" | jq '.data.result')
    echo "✅ 消息已发送，结果: $RESULT"
fi
```

#### 加载代码
```bash
JSON=$(ao-cli load "$PID" my-script.lua --json 2>/dev/null)
if echo "$JSON" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "✅ 代码已加载"
fi
```

### 8️⃣ 处理不同的数据类型

```bash
# 获取消息并检查数据类型
JSON=$(ao-cli message "$PID" GetData --wait --json 2>/dev/null)

# 检查数据类型
DATA_TYPE=$(echo "$JSON" | jq -r '.data.result.Messages[0]._DataType')

case "$DATA_TYPE" in
    "parsed_json")
        # 数据已被解析为 JSON 对象
        PARSED=$(echo "$JSON" | jq '.data.result.Messages[0].Data')
        echo "JSON 数据: $PARSED"
        ;;
    "base64_decoded")
        # 数据是 base64 解码的字符串
        DECODED=$(echo "$JSON" | jq -r '.data.result.Messages[0].Data')
        echo "解码数据: $DECODED"
        ;;
    "string")
        # 纯字符串数据
        STRING=$(echo "$JSON" | jq -r '.data.result.Messages[0].Data')
        echo "字符串: $STRING"
        ;;
esac

# 如果需要原始数据
ORIGINAL=$(echo "$JSON" | jq -r '.data.result.Messages[0]._RawData')
echo "原始数据: $ORIGINAL"
```

### 9️⃣ 处理多个 JSON 对象输出

某些命令（如 `message --wait`）可能返回多个 JSON 对象：
- **第一个 JSON**：发送确认
- **第二个 JSON**：包含执行结果

#### 获取最后一个 JSON 对象（推荐）
```bash
# 获取包含结果的最后一个 JSON
RESULT_JSON=$(ao-cli message "$PID" Action --wait --json 2>/dev/null | jq -s '.[-1]')

# 现在可以安全地访问结果
SUCCESS=$(echo "$RESULT_JSON" | jq '.success')
RESULT=$(echo "$RESULT_JSON" | jq '.data.result')
```

#### 获取所有 JSON 对象
```bash
# 将所有 JSON 对象解析为数组
ALL_JSON=$(ao-cli message "$PID" Action --wait --json 2>/dev/null | jq -s '.')

# 获取数组长度
COUNT=$(echo "$ALL_JSON" | jq 'length')
echo "共 $COUNT 个 JSON 对象"

# 分别访问
SEND_CONFIRM=$(echo "$ALL_JSON" | jq '.[0]')
EXEC_RESULT=$(echo "$ALL_JSON" | jq '.[1]')
```

#### 智能处理函数
```bash
#!/bin/bash

# 智能处理多个 JSON 对象的函数
get_final_result() {
    local output=$(ao-cli "$@" 2>/dev/null)

    # 检查是否为多个 JSON 对象
    if echo "$output" | jq -s '.' >/dev/null 2>&1; then
        local json_array=$(echo "$output" | jq -s '.')
        local count=$(echo "$json_array" | jq 'length')

        if [ "$count" -gt 1 ]; then
            # 返回最后一个 JSON 对象
            echo "$json_array" | jq '.[-1]'
        else
            # 单个 JSON 对象
            echo "$json_array" | jq '.[0]'
        fi
    else
        # 解析失败，返回原始输出
        echo "$output"
    fi
}

# 使用示例
RESULT=$(get_final_result message "$PID" Action --wait --json)
echo "最终结果: $RESULT"
```

### 🔟 性能优化建议

```bash
# ❌ 不要这样做（多次调用 jq，浪费资源）
SUCCESS=$(echo "$JSON" | jq '.success')
ERROR=$(echo "$JSON" | jq '.error')
DATA=$(echo "$JSON" | jq '.data')

# ✅ 应该这样做（一次调用 jq 提取所需字段）
FIELDS=$(echo "$JSON" | jq '{success, error, data}')
SUCCESS=$(echo "$FIELDS" | jq '.success')
ERROR=$(echo "$FIELDS" | jq '.error')
DATA=$(echo "$FIELDS" | jq '.data')

# 或者直接提取所需值
SUCCESS=$(echo "$JSON" | jq -r '.success')
ERROR=$(echo "$JSON" | jq -r '.error // empty')
```

### 1️⃣1️⃣ 完整脚本示例

```bash
#!/bin/bash
set -e

# 配置
PROCESS_NAME="test-$(date +%s)"
WAIT_TIME=2

# 辅助函数
run_ao_cli() {
    local cmd="$1"; shift
    ao-cli "$cmd" "$@" 2>/dev/null
}

log_info() { echo "ℹ️  $1"; }
log_success() { echo "✅ $1"; }
log_error() { echo "❌ $1"; exit 1; }

# 1. 创建进程
log_info "创建进程..."
SPAWN_JSON=$(run_ao_cli spawn default --name "$PROCESS_NAME" --json)
if ! echo "$SPAWN_JSON" | jq -e '.success == true' >/dev/null 2>&1; then
    log_error "进程创建失败"
fi
PROCESS_ID=$(echo "$SPAWN_JSON" | jq -r '.data.processId')
log_success "进程已创建: $PROCESS_ID"

# 2. 发送消息
log_info "发送测试消息..."
MSG_JSON=$(run_ao_cli message "$PROCESS_ID" TestMessage --data '{"test":true}' --wait --json)
if ! echo "$MSG_JSON" | jq -e '.success == true' >/dev/null 2>&1; then
    ERROR=$(echo "$MSG_JSON" | jq -r '.error // "Unknown error"')
    log_error "消息发送失败: $ERROR"
fi
log_success "消息已发送"

# 3. 解析结果
RESULT=$(echo "$MSG_JSON" | jq '.data.result')
log_success "收到结果: $(echo "$RESULT" | jq -c .)"

echo ""
log_success "所有测试通过！"
```

---

## 🎯 关键要点总结

| 要点                 | 说明                                                                            |
| -------------------- | ------------------------------------------------------------------------------- |
| **stdout vs stderr** | JSON 输出在 stdout，日志在 stderr。使用 `2>/dev/null` 隔离。                    |
| **JSON 结构**        | 所有输出都有统一的 `{command, success, timestamp, version, data, error}` 结构。 |
| **原始数据保留**     | `_RawData`, `_RawTags`, `_DataType` 字段保留原始数据，确保数据完整性。          |
| **多 JSON 处理**     | 使用 `jq -s '.[-1]'` 获取最后一个 JSON 对象（包含结果）。                      |
| **错误处理**         | 使用 `jq -e '.success == true'` 检查成功状态。                                  |
| **向后兼容**         | 所有 `--wait` 命令都保持原来的"无限期等待"行为。                                |
| **性能**             | 减少 jq 调用次数，合并字段提取。                                                |
| **日志隔离**         | 创建辅助函数统一处理日志隔离。                                                  |

---

## 🔍 跨进程 Print 输出测试

### 测试文件
- `cross-process-print-test.sh` - 跨进程 print 输出测试脚本
- `test-receiver-print.lua` - 接收进程测试应用

### 测试目的
验证 `eval + Send` 方式下，接收进程 Handlers 中的 `print()` 输出是否可以被捕获。

### 重要发现
**结论：接收进程 Handlers 中的 print 输出可以被捕获！通过查询目标进程的结果历史实现跨进程调试！**

#### 技术实现
1. **结果历史查询**：通过AO网络API查询目标进程的最近结果历史
2. **Reference匹配**：根据eval输出中的Reference编号匹配对应的处理结果
3. **输出捕获**：提取处理结果中的print输出，实现跨进程调试

#### 测试结果示例
```bash
# eval 命令只能捕获自身代码的输出
✅ "🚀 发送进程eval开始"
✅ "📤 消息已发送到接收进程"
✅ "⏳ 等待接收进程处理..."

# 接收进程 Handler 的输出不会出现在 eval 结果中
❌ "🎯 接收进程Handler开始执行"  (未被捕获)
❌ "📨 收到来自发送进程的消息"    (未被捕获)
❌ "🔄 处理中..."                 (未被捕获)
```

#### 调试建议
```bash
# 传统方式：分别调试发送和接收进程
# 调试发送进程（eval中的代码）
ao-cli eval <sender-id> --data "print('debug'); ao.send(...)" --json

# 调试接收进程（Handler中的代码）
ao-cli message <receiver-id> <action> --data "test" --json

# 新方式：使用eval --trace一次性调试跨进程场景
ao-cli eval <sender-id> --data "print('发送'); ao.send({Target:'<receiver>', ...}); print('完成')" --wait --trace
```

## 🎯 Eval --trace 功能详解

### 功能概述

`eval --trace` 显示从eval中发送的消息追踪信息。由于AO进程隔离机制的限制，目前无法获取接收进程Handler中的print输出。

### 核心特性

- **📋 消息追踪**：显示从eval中发送的消息信息（目标进程、数据、标签等）
- **🔍 发送状态确认**：确认消息是否成功发送
- **⚠️ 隔离限制说明**：明确说明无法突破AO系统的进程隔离机制
- **📊 双模式支持**：支持人类可读的文本模式和结构化的JSON模式

### 使用方法

#### 基本用法
```bash
# 非JSON模式：直接显示调试信息
ao-cli eval <process-id> --data "ao.send({...})" --wait --trace

# JSON模式：调试信息整合到JSON结构中
ao-cli eval <process-id> --data "ao.send({...})" --wait --trace --json
```

#### 实际示例
```bash
# 创建接收进程并加载Handler
ao-cli load <receiver-id> tests/test-receiver-print.lua

# 使用trace功能发送消息并追踪Handler执行
ao-cli eval <sender-id> \
  --data "print('🚀 开始发送'); ao.send({Target='<receiver-id>', Tags={Action='TestReceiverPrint'}, Data='测试消息'}); print('✅ 发送完成')" \
  --wait --trace
```

### 输出格式

#### 非JSON模式输出
```
🔍 🔍 消息追踪模式：显示接收进程Handler的print输出 🔍 🔍
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📤 追踪消息 1/1:
   📋 消息ID: [message-id]
   🎯 目标进程: [receiver-process-id]
   📄 数据: 测试消息
   ✅ 接收进程处理结果:
   📝 Handler中的print输出:
   ┌─────────────────────────────────────────────────────────────┐
   │ 🎯 接收进程Handler开始执行
   │ 📨 收到来自发送进程的消息: 测试消息
   │ 🔄 处理中...
   │ 📤 发送响应消息
   │ ✅ 接收进程Handler执行完成
   └─────────────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 消息追踪完成
```

#### JSON模式输出
```json
{
  "command": "eval",
  "success": true,
  "timestamp": "2025-10-30T09:30:00.000Z",
  "version": "1.1.1",
  "data": {
    "messageId": "...",
    "processId": "...",
    "result": { ... }
  },
  "extra": {
    "trace": {
      "summary": "Traced 1 messages",
      "tracedMessages": [
        {
          "index": 1,
          "status": "success",
          "messageId": "...",
          "targetProcess": "...",
          "data": "测试消息",
          "result": {
            "output": {
              "data": "🎯 接收进程Handler开始执行\n📨 收到来自发送进程的消息: 测试消息\n🔄 处理中...\n📤 发送响应消息\n✅ 接收进程Handler执行完成"
            }
          }
        }
      ]
    }
  }
}
```

### 技术实现

#### 工作原理

1. **消息发送**：eval执行代码，发送消息到目标进程
2. **消息追踪**：记录发送出去的消息ID和目标进程
3. **结果查询**：使用AO connect的`result` API查询消息处理结果
4. **输出整合**：将接收进程的print输出整合到最终结果中

#### 架构优势

- **🔗 网络原生**：基于AO网络的result API，无需额外协议
- **📦 向后兼容**：不影响现有功能，新功能通过选项启用
- **🔧 统一接口**：JSON和文本模式使用相同的数据结构
- **⚡ 高性能**：直接查询AO节点，响应快速

### 测试和验证

#### 运行测试
```bash
# 运行完整的跨进程测试（包括trace功能）
cd /path/to/ao-cli
export HTTPS_PROXY=http://127.0.0.1:1235
./tests/cross-process-print-test.sh
```

#### 测试覆盖
- ✅ 基本跨进程消息传递
- ✅ eval --trace 非JSON模式
- ✅ eval --trace --json模式
- ✅ 接收进程Handler print输出捕获
- ✅ 错误处理和边界情况

### 应用场景

#### 开发调试
```bash
# 调试复杂的跨进程交互
ao-cli eval $PROCESS_A --data "
  print('发起交易请求')
  ao.send({
    Target='$PROCESS_B',
    Tags={Action='ProcessTrade'},
    Data=json.encode({amount=100, symbol='BTC'})
  })
  print('等待处理结果')
" --wait --trace
```

#### 自动化测试
```bash
# 在CI/CD中验证跨进程功能
TRACE_RESULT=$(ao-cli eval $TEST_PROCESS --data "ao.send({...})" --wait --trace --json)
HAS_HANDLER_OUTPUT=$(echo "$TRACE_RESULT" | jq '.extra.trace.tracedMessages[0].result.output.data // "" | length > 0')
```

#### 监控和诊断
```bash
# 生产环境中监控消息处理状态
ao-cli eval $MONITOR_PROCESS --data "
  ao.send({Target='$SERVICE_PROCESS', Tags={Action='HealthCheck'}})
" --wait --trace
```

### 注意事项

- **网络延迟**：trace功能需要等待消息在AO网络中传播和处理
- **权限控制**：只能追踪发送到目标进程的消息结果
- **性能影响**：启用trace会增加额外的网络请求
- **进程隔离**：**无法获取接收进程Handler中的print输出**，这是AO系统的设计限制
- **功能限制**：trace主要用于显示消息发送状态，无法突破进程隔离获取跨进程调试信息

### 相关文件

- `tests/cross-process-print-test.sh` - 完整的功能测试脚本
- `tests/test-receiver-print.lua` - 测试用的接收进程Handler
- `ao-cli.js` - trace功能的实现代码

---

## 📖 相关文档

- [主 README](../README.md) - AO CLI 主文档
- [ao-cli.js](../ao-cli.js) - 命令行工具源代码
- [run-tests.sh](./run-tests.sh) - 完整测试脚本示例

---

## 💡 常见问题

### Q: 为什么 `2>&1` 会破坏 JSON？
A: 因为 `2>&1` 会将 stderr（日志）混入 stdout（JSON），导致 JSON 解析器收到混有日志的输出，无法正确解析。

### Q: `_RawData` 和 `Data` 有什么区别？
A: `_RawData` 是原始内容，`Data` 是格式化后的内容。如果原始是 JSON 字符串，`Data` 会被解析为对象。

### Q: --wait 会一直等待吗？
A: 是的，所有 `--wait` 命令都会无限期等待结果返回，不会超时。

### Q: 如何使用自定义等待时间？
A: 在脚本中导出 `export AO_WAIT_TIME=5`，或使用环境变量控制。

---

**最后更新**: 2025-10-22
**版本**: 1.0.3
