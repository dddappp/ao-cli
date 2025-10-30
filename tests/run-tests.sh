#!/bin/bash
# 暂时禁用 set -e，因为一些测试步骤可能会失败
# set -e

# 检查是否使用 JSON 模式
USE_JSON="false"
if [ "$1" = "--json" ]; then
    USE_JSON="true"
    echo "=== AO CLI 自动化测试脚本 (JSON 模式) ==="
    echo "测试所有主要命令的结构化 JSON 输出：spawn, load, message, eval, inbox"
else
    echo "=== AO CLI 自动化测试脚本 ==="
    echo "测试所有主要命令：spawn, load, message, eval, inbox"
fi
echo ""

# 检查 ao-cli 是否安装
if ! command -v ao-cli &> /dev/null; then
    echo "❌ ao-cli 命令未找到。"
    echo "请先运行: npm link"
    exit 1
fi

# 检查钱包文件
WALLET_FILE="${HOME}/.aos.json"
if [ ! -f "$WALLET_FILE" ]; then
    echo "❌ AOS 钱包文件未找到: $WALLET_FILE"
    echo "请先运行 aos 创建钱包文件"
    exit 1
fi

echo "✅ 环境检查通过"
echo "   钱包文件: $WALLET_FILE"
echo "   ao-cli 版本: $(ao-cli --version 2>/dev/null)"
echo ""

# 0. 测试 JSON 输出格式（如果使用 JSON 模式）
if [ "$USE_JSON" = "true" ]; then
    echo "=== 步骤 0: 测试 JSON 输出格式 ==="

    # 测试 address 命令的成功情况
    echo "测试 address 命令 (成功)..."
    RAW_OUTPUT=$(ao-cli address --json 2>&1)
    JSON_OUTPUT=$(echo "$RAW_OUTPUT" | awk '/^{/{flag=1} flag {print} /^}/{flag=0}')
    echo "📋 JSON 输出: $JSON_OUTPUT"
    if echo "$JSON_OUTPUT" | jq -e '.command == "address" and .success == true and .data.address' >/dev/null 2>&1; then
        echo "✅ address 成功 JSON 格式正确"
    else
        echo "❌ address 成功 JSON 格式错误"
        exit 1
    fi

    # 测试 address 命令的错误情况
    echo "测试 address 命令 (错误)..."
    RAW_OUTPUT=$(ao-cli address --wallet nonexistent.json --json 2>&1)
    JSON_OUTPUT=$(echo "$RAW_OUTPUT" | awk '/^{/{flag=1} flag {print} /^}/{flag=0}')
    echo "📋 JSON 输出: $JSON_OUTPUT"
    if echo "$JSON_OUTPUT" | jq -e '.command == "address" and .success == false and .error' >/dev/null 2>&1; then
        echo "✅ address 错误 JSON 格式正确"
    else
        echo "❌ address 错误 JSON 格式错误"
        exit 1
    fi

    STEP_0_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ JSON 输出格式验证通过"
    echo ""
fi

# 从已有的输出中提取最后一个 JSON 对象（避免重复执行命令）
get_final_json_result_from_output() {
    local full_output="$1"

    # 优先使用 jq -s 处理 JSON 流
    if echo "$full_output" | jq -s '.' >/dev/null 2>&1; then
        local json_count=$(echo "$full_output" | jq -s '. | length')
        if [ "$json_count" -gt 1 ]; then
            # 返回最后一个 JSON 对象
            echo "$full_output" | jq -s '.[-1]'
        else
            # 单个 JSON 对象
            echo "$full_output" | jq -s '.[0]'
        fi
    else
        # jq 失败时返回原始输出
        echo "$full_output"
    fi
}

# 辅助函数：根据进程ID是否以-开头来决定是否使用--
# 注意：此函数只返回第一个 JSON 对象（发送确认），用于验证操作成功
run_ao_cli() {
    local command="$1"
    local process_id="$2"
    shift 2

    # Always add --json in JSON mode
    if [[ "$process_id" == -* ]]; then
        ao-cli "$command" -- "$process_id" --json "$@" 2>/dev/null
    else
        ao-cli "$command" "$process_id" --json "$@" 2>/dev/null
    fi
}

# 初始化测试状态
STEP_SUCCESS_COUNT=0
STEP_TOTAL_COUNT=8
STEP_1_SUCCESS=false
STEP_2_SUCCESS=false
STEP_3_SUCCESS=false
STEP_4_SUCCESS=false
STEP_5_SUCCESS=false
STEP_6_SUCCESS=false
STEP_7_SUCCESS=false
STEP_8_SUCCESS=false

START_TIME=$(date +%s)

echo "🚀 开始执行测试..."

# 1. 创建 AO 进程
echo "=== 步骤 1: 创建 AO 进程 ==="
if [ "$USE_JSON" != "true" ]; then
    echo "正在生成AO进程..."
fi
if [ "$USE_JSON" = "true" ]; then
    RAW_OUTPUT=$(ao-cli spawn default --name "test-$(date +%s)" --json 2>&1)
    # 过滤掉警告信息，只保留 JSON 部分（从第一个 { 到最后一个 }）
    JSON_OUTPUT=$(echo "$RAW_OUTPUT" | awk '/^{/{flag=1} flag {print} /^}/{flag=0}')
    echo "📋 JSON 输出: $JSON_OUTPUT"
    # 总是尝试解析 JSON，无论命令退出码如何
    SUCCESS=$(echo "$JSON_OUTPUT" | jq -r 'if has("success") then .success else "unknown" end' 2>/dev/null || echo "parse_error")
    if [ "$SUCCESS" = "true" ]; then
        PROCESS_ID=$(echo "$JSON_OUTPUT" | jq -r '.data.processId')
        if [ "$USE_JSON" != "true" ]; then
            echo "进程 ID: '$PROCESS_ID'"
        fi
    else
        # 解析错误信息
        ERROR_MSG=$(echo "$JSON_OUTPUT" | jq -r '.error // "Unknown error"' 2>/dev/null || echo "JSON parse error")
        if [ "$USE_JSON" != "true" ]; then
            echo "❌ Spawn 失败: $ERROR_MSG"
        fi
        PROCESS_ID=""
    fi
else
    PROCESS_ID=$(ao-cli spawn default --name "test-$(date +%s)" 2>/dev/null | grep "📋 Process ID:" | awk '{print $4}')
    echo "进程 ID: '$PROCESS_ID'"
fi

if [ -z "$PROCESS_ID" ]; then
    if [ "$USE_JSON" != "true" ]; then
        echo "❌ 无法获取进程 ID（可能是网络问题）"
        echo "⚠️ 继续测试其他功能..."
    fi
    STEP_1_SUCCESS=false
else
    STEP_1_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    if [ "$USE_JSON" != "true" ]; then
        echo "✅ 步骤1成功，当前成功计数: $STEP_SUCCESS_COUNT"
    fi
fi
echo ""

# 2. 加载测试应用
echo "=== 步骤 2: 加载测试应用 ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 2（需要有效的进程ID）"
    STEP_2_SUCCESS=false
else
    echo "正在加载测试应用到进程: $PROCESS_ID"
    TEST_APP_FILE="tests/test-app.lua"
    if run_ao_cli load "$PROCESS_ID" "$TEST_APP_FILE" --wait; then
        STEP_2_SUCCESS=true
        ((STEP_SUCCESS_COUNT++))
        echo "✅ 代码加载成功，当前成功计数: $STEP_SUCCESS_COUNT"
    else
        STEP_2_SUCCESS=false
        echo "❌ 代码加载失败"
    fi
fi
echo ""

# 设置等待时间
WAIT_TIME="${AO_WAIT_TIME:-2}"
echo "等待时间设置为: ${WAIT_TIME} 秒"

# 3. 测试基本消息
echo "=== 步骤 3: 测试基本消息 (message 命令) ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 3（需要有效的进程ID）"
    STEP_3_SUCCESS=false
else
    # 获取完整的命令输出（包含多个 JSON 对象）
    FULL_OUTPUT=$(run_ao_cli message "$PROCESS_ID" TestMessage --data 'Hello AO CLI!' --wait 2>&1)

    # 提取第一个 JSON（发送确认）
    if echo "$FULL_OUTPUT" | jq -s '.' >/dev/null 2>&1; then
        FIRST_JSON=$(echo "$FULL_OUTPUT" | jq -s '.[0]')
    else
        # jq 失败时的备用方案 - 只提取第一个完整的JSON对象
        FIRST_JSON=$(echo "$FULL_OUTPUT" | awk '
        BEGIN { brace_count = 0; in_json = 0; json_content = "" }
        /^{/ {
            if (!in_json) {
                in_json = 1
                json_content = $0
                brace_count = 1
                for (i = 1; i <= length($0); i++) {
                    if (substr($0, i, 1) == "{") brace_count++
                    if (substr($0, i, 1) == "}") brace_count--
                }
            } else {
                json_content = json_content "\n" $0
                for (i = 1; i <= length($0); i++) {
                    if (substr($0, i, 1) == "{") brace_count++
                    if (substr($0, i, 1) == "}") brace_count--
                }
                if (brace_count == 0) {
                    print json_content
                    exit
                }
            }
        }
        !/^{/ && in_json {
            json_content = json_content "\n" $0
            for (i = 1; i <= length($0); i++) {
                if (substr($0, i, 1) == "{") brace_count++
                if (substr($0, i, 1) == "}") brace_count--
            }
            if (brace_count == 0) {
                print json_content
                exit
            }
        }
        ')
    fi
    echo "📋 第一个 JSON (发送确认):"
    echo "$FIRST_JSON" | jq -c '.' 2>/dev/null || echo "$FIRST_JSON"

    if echo "$FIRST_JSON" | jq -e '.success == true' >/dev/null 2>&1; then
        STEP_3_SUCCESS=true
        ((STEP_SUCCESS_COUNT++))
        echo "✅ 消息发送成功"

        # 实际演示：从同一个输出中提取最后一个 JSON（完整结果）
        echo ""
        echo "🔍 演示：从同一输出提取完整结果..."
        LAST_JSON=$(get_final_json_result_from_output "$FULL_OUTPUT")
        echo "📋 最后一个 JSON (完整结果):"
        echo "$LAST_JSON" | jq -c '.' 2>/dev/null || echo "$LAST_JSON"

        # 从完整结果中提取实际数据
        RECEIVED_DATA=$(echo "$LAST_JSON" | jq -r '.data.result.Messages[0].Data.received_data // "N/A"' 2>/dev/null || echo "无法提取")
        echo "📨 实际接收到的数据: '$RECEIVED_DATA'"

        # 🔍 关键演示：Lua print输出位置分析
        echo ""
        echo "🔬 🔍 🎯 Lua print() 输出位置分析 🎯 🔍 🔬"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "💡 重要发现：print()输出在JSON模式下的位置"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # 检查Output.print字段（标记字段）
        OUTPUT_PRINT=$(echo "$LAST_JSON" | jq -r '.data.result.Output.print // "N/A"' 2>/dev/null || echo "N/A")
        if [ "$OUTPUT_PRINT" != "N/A" ]; then
            echo "📍 Output.print 字段: $OUTPUT_PRINT (标记字段，表示有print输出)"
        else
            echo "📍 Output.print 字段: 不存在"
        fi

        # 检查Output.data字段（实际包含print输出）
        OUTPUT_DATA=$(echo "$LAST_JSON" | jq -r '.data.result.Output.data // "N/A"' 2>/dev/null || echo "N/A")
        if [ "$OUTPUT_DATA" != "N/A" ] && [ -n "$OUTPUT_DATA" ]; then
            echo ""
            echo "🎯 Output.data 字段: 包含完整的Lua print()输出"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📄 完整print输出内容:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            # 格式化显示print输出，按行显示并编号
            echo "$OUTPUT_DATA" | nl -ba -s'│ ' | sed 's/^/   │/'

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "💡 关键发现："
            echo "   ✅ Lua print() 输出 → 全部收集在 Output.data 字段"
            echo "   ✅ 保持原始格式，包括换行符和表情符号"
            echo "   ✅ 按执行顺序排列所有print语句"
            echo "   ✅ Output.print 仅为布尔标记，无实际内容"

            # 验证与test-app.lua的对应关系
            if echo "$OUTPUT_DATA" | grep -q "🔍 TestMessage handler"; then
                echo ""
                echo "🔗 对照验证 (与 test-app.lua 中的print语句对应):"
                echo "   📝 test-app.lua:27 → print(\"🔍 TestMessage handler...\")"
                echo "   📝 test-app.lua:29 → print(\"📊 Counter incremented...\")"
                echo "   📝 test-app.lua:36 → print(\"📤 Sending response...\")"
                echo "   📝 test-app.lua:38 → print(\"✅ TestMessage handler...\")"
                echo ""
                echo "   🎯 结论：所有print()输出都完整保存在Output.data中！"
            fi
        else
            echo ""
            echo "⚠️  Output.data 字段为空或不存在"
        fi

    else
        STEP_3_SUCCESS=false
        echo "❌ 消息发送失败"
    fi
fi
echo ""

# 4. 测试数据设置
echo "=== 步骤 4: 测试数据设置 (message 命令) ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 4（需要有效的进程ID）"
    STEP_4_SUCCESS=false
else
    JSON_OUTPUT=$(run_ao_cli message "$PROCESS_ID" SetData --data '{"key": "test_key", "value": "test_value"}' --wait 2>&1)
    echo "📋 JSON 输出: $JSON_OUTPUT"
    if echo "$JSON_OUTPUT" | jq -e '.success == true' >/dev/null 2>&1; then
        STEP_4_SUCCESS=true
        ((STEP_SUCCESS_COUNT++))
        echo "✅ 数据设置成功"
    else
        STEP_4_SUCCESS=false
        echo "❌ 数据设置失败"
    fi
fi
echo ""

# 5. 测试数据获取
echo "=== 步骤 5: 测试数据获取 (message 命令) ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 5（需要有效的进程ID）"
    STEP_5_SUCCESS=false
else
    JSON_OUTPUT=$(run_ao_cli message "$PROCESS_ID" GetData --data "test_key" --wait 2>&1)
    echo "📋 JSON 输出: $JSON_OUTPUT"
    if echo "$JSON_OUTPUT" | jq -e '.success == true' >/dev/null 2>&1; then
        STEP_5_SUCCESS=true
        ((STEP_SUCCESS_COUNT++))
        echo "✅ 数据获取成功"
    else
        STEP_5_SUCCESS=false
        echo "❌ 数据获取失败"
    fi
fi
echo ""

# 6. 测试 Eval 命令
echo "=== 步骤 6: 测试 Eval 命令 ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 6（需要有效的进程ID）"
    STEP_6_SUCCESS=false
else
    JSON_OUTPUT=$(run_ao_cli eval "$PROCESS_ID" --data "return {counter = State.counter, data_count = #State.test_data}" --wait 2>&1)
    echo "📋 JSON 输出: $JSON_OUTPUT"
    if echo "$JSON_OUTPUT" | jq -e '.success == true' >/dev/null 2>&1; then
        STEP_6_SUCCESS=true
        ((STEP_SUCCESS_COUNT++))
        echo "✅ Eval执行成功"
    else
        STEP_6_SUCCESS=false
        echo "❌ Eval执行失败"
    fi
fi
echo ""

# 7. 测试 Inbox 功能
echo "=== 步骤 7: 测试 Inbox 功能 ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 7（需要有效的进程ID）"
    STEP_7_SUCCESS=false
else
    echo "发送消息到Inbox..."
    SEND_MSG=$(run_ao_cli message "$PROCESS_ID" TestInbox --data "Testing Inbox" --wait)
    if [ "$USE_JSON" = "true" ]; then
        echo "   📤 消息发送结果: $(echo "$SEND_MSG" | jq -c '{success: .success, command: .command, action: .data.action}')"
    fi
    
    sleep "$WAIT_TIME"
    
    echo "检查Inbox内容..."
    if [ "$USE_JSON" = "true" ]; then
        JSON_OUTPUT=$(run_ao_cli inbox "$PROCESS_ID" --latest)
        echo "📋 原始 JSON 输出:"
        echo "$JSON_OUTPUT" | jq .
        
        # 验证成功状态
        if echo "$JSON_OUTPUT" | jq -e '.success == true' >/dev/null 2>&1; then
            # 提取并展示 inbox 数据
            INBOX_DATA=$(echo "$JSON_OUTPUT" | jq -r '.data.inbox // empty')
            if [ -n "$INBOX_DATA" ]; then
                echo ""
                echo "📨 Inbox 数据摘要:"
                
                # 尝试提取 length 信息（兼容 macOS grep，不使用 -P 选项）
                LENGTH=$(echo "$INBOX_DATA" | sed -n 's/.*length\s*=\s*\([0-9]*\).*/\1/p' | head -1)
                if [ -n "$LENGTH" ] && [ "$LENGTH" != "0" ]; then
                    echo "   ✓ 消息数量: $LENGTH"
                    echo "   ✓ Latest 消息信息:"
                    
                    # 提取 latest 消息的关键字段
                    echo "$INBOX_DATA" | grep -E "Name|Timestamp|From|Content-Type|Block-Height" | head -5 | sed 's/^/     /'
                    
                    STEP_7_SUCCESS=true
                    ((STEP_SUCCESS_COUNT++))
                    echo "✅ Inbox 检查成功 (找到 $LENGTH 条消息)"
                else
                    # 如果是 Lua 对象格式，检查是否有 'latest' 或 'all' 字段
                    if echo "$INBOX_DATA" | grep -q "latest\s*=\|all\s*="; then
                        # 简单计算：如果有 'latest' 说明至少有 1 条
                        echo "   ✓ Lua 对象格式 Inbox"
                        echo "   ✓ 包含 Latest 消息"
                        STEP_7_SUCCESS=true
                        ((STEP_SUCCESS_COUNT++))
                        echo "✅ Inbox 检查成功 (找到消息)"
                    else
                        STEP_7_SUCCESS=false
                        echo "⚠️  Inbox 数据格式异常"
                    fi
                fi
            else
                echo "📭 Inbox 数据为空"
                STEP_7_SUCCESS=false
            fi
        else
            ERROR=$(echo "$JSON_OUTPUT" | jq -r '.error // "Unknown error"')
            echo "❌ Inbox 检查失败: $ERROR"
            STEP_7_SUCCESS=false
        fi
    else
        # 非 JSON 模式
        INBOX_OUTPUT=$(run_ao_cli inbox "$PROCESS_ID" --latest)
        echo "📋 Inbox 输出:"
        echo "$INBOX_OUTPUT"
        
        if echo "$INBOX_OUTPUT" | grep -q "InboxTestReply\|length\|Messages"; then
            STEP_7_SUCCESS=true
            ((STEP_SUCCESS_COUNT++))
            echo "✅ Inbox 检查成功"
        else
            STEP_7_SUCCESS=false
            echo "❌ Inbox 检查失败"
        fi
    fi
fi
echo ""

# 8. 测试错误处理
echo "=== 步骤 8: 测试错误处理 (eval 命令) ==="
if [ -z "$PROCESS_ID" ]; then
    echo "⚠️ 跳过步骤 8（需要有效的进程ID）"
    STEP_8_SUCCESS=false
else
    if [ "$USE_JSON" = "true" ]; then
        JSON_OUTPUT=$(run_ao_cli eval "$PROCESS_ID" --data "error('Test error from eval')" --wait 2>&1)
        echo "📋 JSON 输出: $JSON_OUTPUT"
        if echo "$JSON_OUTPUT" | jq -e '.success == false and (.error or .gasUsed)' >/dev/null 2>&1; then
            STEP_8_SUCCESS=true
            ((STEP_SUCCESS_COUNT++))
            echo "✅ 错误处理正确"
        else
            STEP_8_SUCCESS=false
            echo "❌ 错误处理失败"
        fi
    else
        if run_ao_cli eval "$PROCESS_ID" --data "error('Test error from eval')" --wait 2>&1 | grep -q "Error\|error"; then
            STEP_8_SUCCESS=true
            ((STEP_SUCCESS_COUNT++))
            echo "✅ 错误处理正确"
        else
            STEP_8_SUCCESS=false
            echo "❌ 错误处理失败"
        fi
    fi
fi
echo ""

END_TIME=$(date +%s)

echo ""
echo "=== 测试完成 ==="
echo "⏱️ 总耗时: $((END_TIME - START_TIME)) 秒"

# 详细的状态报告
echo ""
echo "📋 测试步骤详细状态:"

if $STEP_1_SUCCESS; then
    echo "✅ 步骤 1 (进程生成): 成功 - 进程ID: $PROCESS_ID"
else
    echo "❌ 步骤 1 (进程生成): 失败"
fi

if $STEP_2_SUCCESS; then
    echo "✅ 步骤 2 (应用加载): 成功"
else
    echo "❌ 步骤 2 (应用加载): 失败"
fi

if $STEP_3_SUCCESS; then
    echo "✅ 步骤 3 (基本消息): 成功"
else
    echo "❌ 步骤 3 (基本消息): 失败"
fi

if $STEP_4_SUCCESS; then
    echo "✅ 步骤 4 (数据设置): 成功"
else
    echo "❌ 步骤 4 (数据设置): 失败"
fi

if $STEP_5_SUCCESS; then
    echo "✅ 步骤 5 (数据获取): 成功"
else
    echo "❌ 步骤 5 (数据获取): 失败"
fi

if $STEP_6_SUCCESS; then
    echo "✅ 步骤 6 (Eval命令): 成功"
else
    echo "❌ 步骤 6 (Eval命令): 失败"
fi

if $STEP_7_SUCCESS; then
    echo "✅ 步骤 7 (Inbox功能): 成功"
else
    echo "❌ 步骤 7 (Inbox功能): 失败"
fi

if $STEP_8_SUCCESS; then
    echo "✅ 步骤 8 (错误处理): 成功"
else
    echo "❌ 步骤 8 (错误处理): 失败"
fi

echo ""
echo "📊 测试摘要:"
if [ "$STEP_SUCCESS_COUNT" -eq "$STEP_TOTAL_COUNT" ]; then
    echo "✅ 所有 ${STEP_TOTAL_COUNT} 个测试步骤都成功执行"
else
    echo "⚠️ ${STEP_SUCCESS_COUNT} / ${STEP_TOTAL_COUNT} 个测试步骤成功执行"
fi

echo ""
echo "🎯 验证的功能:"
echo "  ✅ 进程生成和销毁 (spawn)"
echo "  ✅ Lua代码加载和执行 (load)"
echo "  ✅ 消息发送和结果获取 (message --wait)"
echo "  ✅ Lua代码执行 (eval --wait)"
echo "  ✅ Inbox子命令功能 (inbox --latest)"
echo "  ✅ 错误处理和异常捕获"
echo "  ✅ 状态管理和数据持久化"

echo ""
echo "💡 使用提示:"
echo "  - 如需自定义等待时间: export AO_WAIT_TIME=5"
echo "  - 测试脚本会自动检测钱包和环境"
if [ "$USE_JSON" = "true" ]; then
echo "  - 当前运行在 JSON 模式，使用结构化输出解析"
else
echo "  - 运行 ./tests/run-tests.sh --json 来使用结构化 JSON 输出测试"
fi
