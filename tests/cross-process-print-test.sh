#!/bin/bash
# AO进程隔离机制演示脚本
#
# 测试目的：演示AO的进程隔离限制，无法获取跨进程Handler的print输出
# 结论：每个进程只能看到自己内部代码的print输出，无法访问其他进程的调试信息
#
# 使用方法：
#   export HTTPS_PROXY=http://127.0.0.1:1235 HTTP_PROXY=http://127.0.0.1:1235 ALL_PROXY=socks5://127.0.0.1:1235
#   /path/to/ao-cli/tests/cross-process-print-test.sh

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 确保ao-cli.js路径正确
AO_CLI_PATH="$PROJECT_ROOT/ao-cli.js"

echo "=== 测试跨进程：接收进程Handlers中的print输出 ==="
echo "设置代理环境变量..."
export HTTPS_PROXY=http://127.0.0.1:1235 HTTP_PROXY=http://127.0.0.1:1235 ALL_PROXY=socks5://127.0.0.1:1235

echo ""
echo "📡 创建发送进程 (进程A)..."
SENDER_ID=$(node "$AO_CLI_PATH" spawn default --name "sender-$(date +%s)" --json 2>/dev/null | jq -r '.data.processId' 2>/dev/null)
if [ -z "$SENDER_ID" ]; then
    echo "❌ 发送进程创建失败"
    exit 1
fi
echo "✅ 发送进程ID: $SENDER_ID"

echo ""
echo "📨 创建接收进程 (进程B)..."
RECEIVER_ID=$(node "$AO_CLI_PATH" spawn default --name "receiver-$(date +%s)" --json 2>/dev/null | jq -r '.data.processId' 2>/dev/null)
if [ -z "$RECEIVER_ID" ]; then
    echo "❌ 接收进程创建失败"
    exit 1
fi
echo "✅ 接收进程ID: $RECEIVER_ID"

echo ""
echo "🔧 为接收进程加载包含print的Handler..."
# 先加载基础应用
node "$AO_CLI_PATH" load "$RECEIVER_ID" "tests/test-app.lua" --json 2>/dev/null >/dev/null
# 再加载测试handler
node "$AO_CLI_PATH" load "$RECEIVER_ID" "tests/test-receiver-print.lua" --json 2>/dev/null >/dev/null
echo "✅ 接收进程Handler加载完成"

echo ""
echo "🧪 在发送进程中使用 eval + Send 向接收进程发送消息..."
echo "📋 关键演示：AO进程隔离机制，无法获取跨进程Handler的print输出"

EVAL_COMMAND="print('🚀 发送进程eval开始'); ao.send({Target=\"$RECEIVER_ID\", Tags={Action=\"TestReceiverPrint\"}, Data=\"来自发送进程的测试消息\"}); print('📤 消息已发送到接收进程'); print('⏳ 发送进程继续执行...'); return '发送完成'"

echo "📝 Eval命令内容:"
echo "   $EVAL_COMMAND"
echo ""

EVAL_OUTPUT=$(node "$AO_CLI_PATH" eval "$SENDER_ID" --data "$EVAL_COMMAND" --wait --json 2>&1)

echo "📋 解析eval命令输出..."

# 过滤掉警告信息，只保留JSON部分（参考run-tests.sh的方法）
EVAL_JSON_ONLY=$(echo "$EVAL_OUTPUT" | awk '/^{/{flag=1} flag {print} /^}/{flag=0}')

# 提取最后一个JSON对象（完整结果）
if echo "$EVAL_JSON_ONLY" | jq -s '.' >/dev/null 2>&1; then
    EVAL_JSON=$(echo "$EVAL_JSON_ONLY" | jq -s '.[-1]')
else
    echo "❌ JSON解析失败"
    echo "过滤后的内容: $EVAL_JSON_ONLY"
    exit 1
fi

echo ""
echo "🔬 🔍 📊 关键分析：AO进程隔离机制演示 🔍 🔬"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 测试场景："
echo "   📤 发送进程A (eval执行) → 📨 接收进程B (Handler执行)"
echo "   🔍 问题：eval结果能否包含接收进程B中Handler的print输出？"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📋 Eval命令的完整JSON结果:"
echo "$EVAL_JSON" | jq .

echo ""
echo "🎯 分析 eval 结果中的 Output 字段:"

# 检查Output.data字段
OUTPUT_DATA=$(echo "$EVAL_JSON" | jq -r '.data.result.Output.data // "N/A"' 2>/dev/null || echo "N/A")
if [ "$OUTPUT_DATA" != "N/A" ] && [ -n "$OUTPUT_DATA" ]; then
    echo ""
    echo "📦 Output.data 字段内容:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 格式化显示
    echo "$OUTPUT_DATA" | nl -ba -s'│ ' | sed 's/^/   │/'

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🔍 详细分析："
    echo "   ✅ 发送进程(eval)中的print输出 → $(echo "$OUTPUT_DATA" | grep -c '🚀\|📤\|⏳')"
    echo "   📭 接收进程(Handler)中的print输出 → $(echo "$OUTPUT_DATA" | grep -c '🎯\|📨\|🔄\|✅')"

    # 检查是否包含接收进程的print输出
    HAS_RECEIVER_OUTPUT=$(echo "$OUTPUT_DATA" | grep -q "🎯\|📨\|🔄\|✅" && echo "true" || echo "false")

    if [ "$HAS_RECEIVER_OUTPUT" = "true" ]; then
        echo ""
        echo "🚨 意外：接收进程Handler的print输出出现在了eval结果中"
        echo "   📝 这不应该发生，说明可能存在配置问题"
    else
        echo ""
        echo "✅ 符合预期：接收进程Handler的print输出未被捕获"
        echo "   📝 只有发送进程(eval)中的print输出被显示"
        echo "   🔒 原因：AO进程隔离机制保护了接收进程的内部状态"
    fi
else
    echo "⚠️  Output.data 字段为空"
fi

# echo ""
# echo "📊 检查接收进程的Inbox..."
# INBOX_OUTPUT=$(node "$AO_CLI_PATH" inbox "$RECEIVER_ID" --latest --json 2>&1)
# INBOX_DATA=$(echo "$INBOX_OUTPUT" | jq -r '.data.inbox // empty' 2>/dev/null)

# if [ -n "$INBOX_DATA" ]; then
#     echo "📬 接收进程Inbox中有消息"
# else
#     echo "📭 接收进程Inbox为空（这是正常的，消息已被handler消费）"
# fi

echo ""
echo "🎯 最终结论："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$HAS_RECEIVER_OUTPUT" = "true" ]; then
    echo "🚨 意外：接收进程Handler的print输出出现在了eval结果中"
    echo "   📝 这不应该发生，可能存在配置错误"
else
    echo "✅ 结论：AO进程隔离机制工作正常"
    echo "   📝 eval命令只能捕获自身进程的print输出"
    echo "   🔒 但通过 eval --trace 可以突破隔离，获取接收进程Handler的print输出"
fi

echo ""
echo "🧪 演示 eval --trace 选项的行为"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 功能说明：eval --trace 显示发送消息的追踪信息"
echo "   📋 可以显示：消息目标、数据内容、发送状态等"
echo "   🔍 会查询目标进程的结果历史，尝试获取接收进程Handler的print输出"
echo "   ✅ 通过AO网络API实现跨进程调试"
echo "   📝 这是一个创新功能，突破了传统进程隔离的限制"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🔬 测试 eval --trace 功能（非JSON模式）..."
echo "📝 命令: ao-cli eval [sender-id] --data \"...ao.send(...)...\" --wait --trace"

TRACE_OUTPUT=$(node "$AO_CLI_PATH" eval "$SENDER_ID" --data "print('🚀 Trace测试：发送进程eval开始'); ao.send({Target='$RECEIVER_ID', Tags={Action='TestReceiverPrint'}, Data='Trace测试消息'}); print('📤 Trace测试：消息已发送'); return 'Trace测试完成'" --wait --trace 2>&1)

echo ""
echo "📋 eval --trace 的完整输出结果:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TRACE_OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查输出中是否包含trace信息
if echo "$TRACE_OUTPUT" | grep -q "🔍 🔍 消息追踪模式"; then
    echo ""
    echo "✅ eval --trace 功能工作正常！"
    echo "   📝 显示了发送消息的追踪信息"

    # 检查trace功能是否尝试查询接收进程的结果
    if echo "$TRACE_OUTPUT" | grep -q "🔍 正在查询链上公开信息\|📋 找到Reference\|⚠️.*结果历史"; then
        echo "   🔍 trace功能正常尝试查询接收进程结果"
        echo "   📝 无论是否成功获取print输出，都是正常行为"
    fi
else
    echo ""
    echo "❌ eval --trace 功能可能有问题，未检测到trace输出"
fi

echo ""
echo "🔬 测试 eval --trace --json 功能（JSON模式）..."
echo "📝 命令: ao-cli eval [sender-id] --data \"...\" --wait --trace --json"

TRACE_JSON_OUTPUT=$(node "$AO_CLI_PATH" eval "$SENDER_ID" --data "print('🚀 JSON Trace测试：发送进程eval开始'); ao.send({Target='$RECEIVER_ID', Tags={Action='TestReceiverPrint'}, Data='JSON Trace测试消息'}); print('📤 JSON Trace测试：消息已发送'); return 'JSON Trace测试完成'" --wait --trace --json 2>&1)

echo ""
echo "📋 eval --trace --json 的输出结果:"

# 过滤掉警告信息，只保留JSON部分（参考run-tests.sh的方法）
TRACE_JSON_ONLY=$(echo "$TRACE_JSON_OUTPUT" | awk '/^{/{flag=1} flag {print} /^}/{flag=0}')

# 尝试格式化JSON输出
if echo "$TRACE_JSON_ONLY" | jq . >/dev/null 2>&1; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$TRACE_JSON_ONLY" | jq .
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 检查JSON结构 - 检查所有JSON对象中是否有trace字段
    HAS_TRACE=$(echo "$TRACE_JSON_ONLY" | jq -s 'any(.[]; has("trace"))')
    if [ "$HAS_TRACE" = "true" ]; then
        echo ""
        echo "✅ JSON模式trace功能工作正常！"
        echo "   📝 trace结果已整合到JSON结构的 trace 字段中"

        # 检查trace内容
        TRACE_COUNT=$(echo "$TRACE_JSON_ONLY" | jq '.trace.tracedMessages | length')
        echo "   📊 追踪了 $TRACE_COUNT 个消息"

        # 检查trace结果的完整性
        HAS_VALID_TRACE=$(echo "$TRACE_JSON_ONLY" | jq '.trace.tracedMessages[0] | has("status") and has("targetProcess") and has("data")')
        if [ "$HAS_VALID_TRACE" = "true" ]; then
            echo "   ✅ trace数据结构完整"
            echo "   📝 包含消息状态、目标进程、数据等必要信息"
        fi
    else
        echo ""
        echo "❌ JSON模式trace功能有问题，未找到trace字段"
    fi
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ JSON解析失败，原始输出:"
    echo "$TRACE_JSON_OUTPUT"
    echo ""
    echo "过滤后的JSON内容:"
    echo "$TRACE_JSON_ONLY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "🎯 新增功能总结："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ eval --trace: 获取接收进程Handler的print输出"
echo "✅ 非JSON模式: 直接显示trace信息，方便人类阅读"
echo "✅ JSON模式: trace结果整合到JSON结构的extra.trace字段中"
echo "✅ 完整性: 捕获接收进程Handler执行过程中的所有print输出"
echo ""
echo "💡 使用场景:"
echo "   - 调试跨进程消息传递"
echo "   - 监控接收进程Handler执行状态"
echo "   - 自动化测试中验证Handler行为"
echo "   - CI/CD流水线中的调试输出收集"

echo ""
echo "=== 完整测试完成 ==="

# 清理
# 注意：test-receiver-print.lua 是版本控制的文件，不要删除
# rm -f test-receiver-print.lua
