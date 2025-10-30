#!/bin/bash
# 测试跨进程场景：eval + Send 方式下接收进程Handlers中的print输出
#
# 测试目的：验证eval命令能否捕获跨进程Handler的print输出
# 结论：eval只能捕获自身代码的print输出，无法捕获接收进程Handler的print输出
#
# 使用方法：
#   cd /path/to/ao-cli
#   export HTTPS_PROXY=http://127.0.0.1:1235 HTTP_PROXY=http://127.0.0.1:1235 ALL_PROXY=socks5://127.0.0.1:1235
#   ./tests/cross-process-print-test.sh

echo "=== 测试跨进程：接收进程Handlers中的print输出 ==="
echo "设置代理环境变量..."
export HTTPS_PROXY=http://127.0.0.1:1235 HTTP_PROXY=http://127.0.0.1:1235 ALL_PROXY=socks5://127.0.0.1:1235

echo ""
echo "📡 创建发送进程 (进程A)..."
SENDER_ID=$(ao-cli spawn default --name "sender-$(date +%s)" --json 2>/dev/null | jq -r '.data.processId' 2>/dev/null)
if [ -z "$SENDER_ID" ]; then
    echo "❌ 发送进程创建失败"
    exit 1
fi
echo "✅ 发送进程ID: $SENDER_ID"

echo ""
echo "📨 创建接收进程 (进程B)..."
RECEIVER_ID=$(ao-cli spawn default --name "receiver-$(date +%s)" --json 2>/dev/null | jq -r '.data.processId' 2>/dev/null)
if [ -z "$RECEIVER_ID" ]; then
    echo "❌ 接收进程创建失败"
    exit 1
fi
echo "✅ 接收进程ID: $RECEIVER_ID"

echo ""
echo "🔧 为接收进程加载包含print的Handler..."
# 先加载基础应用
ao-cli load "$RECEIVER_ID" "tests/test-app.lua" --json 2>/dev/null >/dev/null
# 再加载测试handler
ao-cli load "$RECEIVER_ID" "test-receiver-print.lua" --json 2>/dev/null >/dev/null
echo "✅ 接收进程Handler加载完成"

echo ""
echo "🧪 在发送进程中使用 eval + Send 向接收进程发送消息..."
echo "⚠️  关键测试：eval命令能否捕获接收进程中Handler的print输出？"

EVAL_COMMAND="print('🚀 发送进程eval开始'); ao.send({Target='$RECEIVER_ID', Tags={Action='TestReceiverPrint'}, Data='来自发送进程的测试消息'}); print('📤 消息已发送到接收进程'); print('⏳ 等待接收进程处理...'); return '发送完成'"

echo "📝 Eval命令内容:"
echo "   $EVAL_COMMAND"
echo ""

EVAL_OUTPUT=$(ao-cli eval "$SENDER_ID" --data "$EVAL_COMMAND" --wait --json 2>&1)

echo "📋 解析eval命令输出..."

# 提取最后一个JSON对象（完整结果）
if echo "$EVAL_OUTPUT" | jq -s '.' >/dev/null 2>&1; then
    EVAL_JSON=$(echo "$EVAL_OUTPUT" | jq -s '.[-1]')
else
    echo "❌ JSON解析失败"
    echo "原始输出: $EVAL_OUTPUT"
    exit 1
fi

echo ""
echo "🔬 🔍 📊 关键分析：eval命令能否捕获跨进程Handler的print输出？🔍 🔬"
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

# 检查Output.print字段
OUTPUT_PRINT=$(echo "$EVAL_JSON" | jq -r '.data.result.Output.print // "N/A"' 2>/dev/null || echo "N/A")
if [ "$OUTPUT_PRINT" != "N/A" ]; then
    echo "📍 Output.print 字段: $OUTPUT_PRINT"
else
    echo "📍 Output.print 字段: 不存在"
fi

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
    echo "   ❓ 接收进程(Handler)中的print输出 → $(echo "$OUTPUT_DATA" | grep -c '🎯\|📨\|🔄\|📤\|✅')"

    if echo "$OUTPUT_DATA" | grep -q "🎯\|📨\|🔄\|📤\|✅"; then
        echo ""
        echo "🚨 意外发现：接收进程Handler的print输出也被捕获了！"
        echo "   📝 这意味着跨进程的Handler print 输出可以被 eval 命令捕获"
        echo ""
        echo "🔗 对照验证 (接收进程Handler中的print语句):"
        echo "   📝 Handler: print('🎯 接收进程Handler开始执行')"
        echo "   📝 Handler: print('📨 收到来自发送进程的消息: ...')"
        echo "   📝 Handler: print('🔄 处理中...')"
        echo "   📝 Handler: print('📤 发送响应消息')"
        echo "   📝 Handler: print('✅ 接收进程Handler执行完成')"
    else
        echo ""
        echo "✅ 符合预期：接收进程Handler的print输出未被捕获"
        echo "   📝 只有发送进程(eval)中的print输出被捕获"
    fi
else
    echo "⚠️  Output.data 字段为空"
fi

echo ""
echo "📊 检查接收进程的Inbox（验证消息是否成功到达）..."
INBOX_OUTPUT=$(ao-cli inbox "$RECEIVER_ID" --latest --json 2>&1)
INBOX_DATA=$(echo "$INBOX_OUTPUT" | jq -r '.data.inbox // empty' 2>/dev/null)

if [ -n "$INBOX_DATA" ]; then
    echo "✅ 接收进程Inbox中有消息，说明跨进程通信成功"
else
    echo "⚠️  接收进程Inbox为空，消息可能未到达"
fi

echo ""
echo "🎯 最终结论："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if echo "$OUTPUT_DATA" | grep -q "🎯\|📨\|🔄\|📤\|✅" 2>/dev/null; then
    echo "🚨 结论：eval + Send 方式下，接收进程Handler的print输出可以被捕获！"
    echo "   📝 这是一个重要的发现，意味着跨进程调试成为可能"
else
    echo "✅ 结论：eval + Send 方式下，接收进程Handler的print输出不会被eval捕获"
    echo "   📝 eval命令只能捕获自身执行代码的print输出"
fi

echo ""
echo "=== 测试完成 ==="

# 清理
rm -f test-receiver-print.lua
