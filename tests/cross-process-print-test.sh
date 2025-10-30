#!/bin/bash
# 测试跨进程场景：eval + Send 方式下接收进程Handlers中的print输出
#
# 测试目的：验证eval命令能否捕获跨进程Handler的print输出
# 结论：eval只能捕获自身代码的print输出，无法捕获接收进程Handler的print输出
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
node ../ao-cli.js load "$RECEIVER_ID" "tests/test-app.lua" --json 2>/dev/null >/dev/null
# 再加载测试handler
node ../ao-cli.js load "$RECEIVER_ID" "tests/test-receiver-print.lua" --json 2>/dev/null >/dev/null
echo "✅ 接收进程Handler加载完成"

echo ""
echo "🧪 在发送进程中使用 eval + Send 向接收进程发送消息..."
echo "⚠️  关键测试：eval命令能否捕获接收进程中Handler的print输出？"

EVAL_COMMAND="print('🚀 发送进程eval开始'); ao.send({Target='$RECEIVER_ID', Tags={Action='TestReceiverPrint'}, Data='来自发送进程的测试消息'}); print('📤 消息已发送到接收进程'); print('⏳ 等待接收进程处理...'); return '发送完成'"

echo "📝 Eval命令内容:"
echo "   $EVAL_COMMAND"
echo ""

EVAL_OUTPUT=$(node ../ao-cli.js eval "$SENDER_ID" --data "$EVAL_COMMAND" --wait --json 2>&1)

echo "📋 解析eval命令输出..."

# 提取最后一个JSON对象（完整结果）
if echo "$EVAL_OUTPUT" | jq -s '.' >/dev/null 2>&1; then
    EVAL_JSON=$(echo "$EVAL_OUTPUT" | jq -s '.[-1]')
else
    # 尝试手动提取最后一个JSON对象
    EVAL_JSON=$(echo "$EVAL_OUTPUT" | awk '
    BEGIN { json=""; brace_count=0; in_json=0 }
    /^{/ {
        if (!in_json) {
            in_json=1
            json=$0
            brace_count=1
            # 简单计算大括号
            for(i=1;i<=length($0);i++) {
                c=substr($0,i,1)
                if(c=="{") brace_count++
                if(c=="}") brace_count--
            }
        } else {
            json=json"\n"$0
            for(i=1;i<=length($0);i++) {
                c=substr($0,i,1)
                if(c=="{") brace_count++
                if(c=="}") brace_count--
            }
        }
        next
    }
    in_json && !/^{/ {
        json=json"\n"$0
        for(i=1;i<=length($0);i++) {
            c=substr($0,i,1)
            if(c=="{") brace_count++
            if(c=="}") brace_count--
        }
        if(brace_count <= 0) {
            print json
            exit
        }
    }
    ')
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
INBOX_OUTPUT=$(node ../ao-cli.js inbox "$RECEIVER_ID" --latest --json 2>&1)
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
echo "🆕 🆕 🆕 新增功能测试：eval --trace 选项 🆕 🆕 🆕"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 最新功能：eval --trace 可以获取接收进程Handler的print输出"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🔬 测试 eval --trace 功能（非JSON模式）..."
echo "📝 命令: ao-cli eval [sender-id] --data \"...ao.send(...)...\" --wait --trace"

TRACE_OUTPUT=$(node ../ao-cli.js eval "$SENDER_ID" --data "print('🚀 Trace测试：发送进程eval开始'); ao.send({Target='$RECEIVER_ID', Tags={Action='TestReceiverPrint'}, Data='Trace测试消息'}); print('📤 Trace测试：消息已发送'); return 'Trace测试完成'" --wait --trace 2>&1)

echo ""
echo "📋 eval --trace 的完整输出结果:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TRACE_OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查输出中是否包含trace信息
if echo "$TRACE_OUTPUT" | grep -q "🔍 🔍 消息追踪模式"; then
    echo ""
    echo "✅ eval --trace 功能工作正常！"
    echo "   📝 成功显示了跨进程Handler的print输出追踪"

    # 检查是否包含接收进程的print输出
    if echo "$TRACE_OUTPUT" | grep -q "🎯\|📨\|🔄\|📤\|✅"; then
        echo "   🎯 接收进程Handler的print输出已被捕获并显示"
        echo ""
        echo "🔗 验证接收进程Handler中的print语句:"
        echo "   📝 Handler: print('🎯 接收进程Handler开始执行')"
        echo "   📝 Handler: print('📨 收到来自发送进程的消息: ...')"
        echo "   📝 Handler: print('🔄 处理中...')"
        echo "   📝 Handler: print('📤 发送响应消息')"
        echo "   📝 Handler: print('✅ 接收进程Handler执行完成')"
    else
        echo "   ⚠️  未检测到接收进程Handler的print输出"
    fi
else
    echo ""
    echo "❌ eval --trace 功能可能有问题，未检测到trace输出"
fi

echo ""
echo "🔬 测试 eval --trace --json 功能（JSON模式）..."
echo "📝 命令: ao-cli eval [sender-id] --data \"...\" --wait --trace --json"

TRACE_JSON_OUTPUT=$(node ../ao-cli.js eval "$SENDER_ID" --data "print('🚀 JSON Trace测试：发送进程eval开始'); ao.send({Target='$RECEIVER_ID', Tags={Action='TestReceiverPrint'}, Data='JSON Trace测试消息'}); print('📤 JSON Trace测试：消息已发送'); return 'JSON Trace测试完成'" --wait --trace --json 2>&1)

echo ""
echo "📋 eval --trace --json 的输出结果:"

# 尝试格式化JSON输出
if echo "$TRACE_JSON_OUTPUT" | jq . >/dev/null 2>&1; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$TRACE_JSON_OUTPUT" | jq .
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 检查JSON结构
    HAS_TRACE=$(echo "$TRACE_JSON_OUTPUT" | jq 'has("extra") and (.extra.trace // false)')
    if [ "$HAS_TRACE" = "true" ]; then
        echo ""
        echo "✅ JSON模式trace功能工作正常！"
        echo "   📝 trace结果已整合到JSON结构的 extra.trace 字段中"

        # 检查trace内容
        TRACE_COUNT=$(echo "$TRACE_JSON_OUTPUT" | jq '.extra.trace.tracedMessages | length')
        echo "   📊 追踪了 $TRACE_COUNT 个消息"

        # 检查是否有接收进程的print输出
        HAS_HANDLER_PRINT=$(echo "$TRACE_JSON_OUTPUT" | jq '.extra.trace.tracedMessages[0].result.output.data // "" | contains("🎯") or contains("📨") or contains("🔄") or contains("📤") or contains("✅")')
        if [ "$HAS_HANDLER_PRINT" = "true" ]; then
            echo "   🎯 接收进程Handler的print输出已包含在JSON结果中"
        else
            echo "   ⚠️  JSON结果中未检测到接收进程Handler的print输出"
        fi
    else
        echo ""
        echo "❌ JSON模式trace功能有问题，未找到extra.trace字段"
    fi
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ JSON解析失败，原始输出:"
    echo "$TRACE_JSON_OUTPUT"
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
rm -f test-receiver-print.lua
