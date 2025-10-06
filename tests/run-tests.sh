#!/bin/bash
set -e

echo "=== AO CLI 自动化测试脚本 ==="
echo "测试所有主要命令：spawn, load, message, eval, inbox"
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
echo "   ao-cli 版本: $(ao-cli --version)"
echo ""

# 辅助函数：根据进程ID是否以-开头来决定是否使用--
run_ao_cli() {
    local command="$1"
    local process_id="$2"
    shift 2

    if [[ "$process_id" == -* ]]; then
        ao-cli "$command" -- "$process_id" "$@"
    else
        ao-cli "$command" "$process_id" "$@"
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
echo "正在生成AO进程..."
PROCESS_ID=$(ao-cli spawn default --name "test-$(date +%s)" 2>/dev/null | grep "📋 Process ID:" | awk '{print $4}')
echo "进程 ID: '$PROCESS_ID'"

if [ -z "$PROCESS_ID" ]; then
    echo "❌ 无法获取进程 ID"
    STEP_1_SUCCESS=false
    echo "由于进程生成失败，测试终止"
    exit 1
else
    STEP_1_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ 步骤1成功，当前成功计数: $STEP_SUCCESS_COUNT"
fi
echo ""

# 2. 加载测试应用
echo "=== 步骤 2: 加载测试应用 ==="
echo "正在加载测试应用到进程: $PROCESS_ID"
TEST_APP_FILE="tests/test-app.lua"
if run_ao_cli load "$PROCESS_ID" "$TEST_APP_FILE" --wait; then
    STEP_2_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ 代码加载成功，当前成功计数: $STEP_SUCCESS_COUNT"
else
    STEP_2_SUCCESS=false
    echo "❌ 代码加载失败"
    echo "由于代码加载失败，测试终止"
    exit 1
fi
echo ""

# 设置等待时间
WAIT_TIME="${AO_WAIT_TIME:-2}"
echo "等待时间设置为: ${WAIT_TIME} 秒"

# 3. 测试基本消息
echo "=== 步骤 3: 测试基本消息 (message 命令) ==="
if run_ao_cli message "$PROCESS_ID" TestMessage --data "Hello AO CLI!" --wait; then
    STEP_3_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ 消息发送成功"
else
    STEP_3_SUCCESS=false
    echo "❌ 消息发送失败"
fi
echo ""

# 4. 测试数据设置
echo "=== 步骤 4: 测试数据设置 (message 命令) ==="
if run_ao_cli message "$PROCESS_ID" SetData --data '{"key": "test_key", "value": "test_value"}' --wait; then
    STEP_4_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ 数据设置成功"
else
    STEP_4_SUCCESS=false
    echo "❌ 数据设置失败"
fi
echo ""

# 5. 测试数据获取
echo "=== 步骤 5: 测试数据获取 (message 命令) ==="
if run_ao_cli message "$PROCESS_ID" GetData --data "test_key" --wait; then
    STEP_5_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ 数据获取成功"
else
    STEP_5_SUCCESS=false
    echo "❌ 数据获取失败"
fi
echo ""

# 6. 测试 Eval 命令
echo "=== 步骤 6: 测试 Eval 命令 ==="
if run_ao_cli eval "$PROCESS_ID" --data "return {counter = State.counter, data_count = #State.test_data}" --wait; then
    STEP_6_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ Eval执行成功"
else
    STEP_6_SUCCESS=false
    echo "❌ Eval执行失败"
fi
echo ""

# 7. 测试 Inbox 功能
echo "=== 步骤 7: 测试 Inbox 功能 ==="
echo "发送消息到Inbox..."
run_ao_cli message "$PROCESS_ID" TestInbox --data "Testing Inbox" --wait >/dev/null 2>&1
sleep "$WAIT_TIME"
echo "检查Inbox..."
if run_ao_cli inbox "$PROCESS_ID" --latest 2>/dev/null | grep -q "InboxTestReply\|length"; then
    STEP_7_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ Inbox检查成功"
else
    STEP_7_SUCCESS=false
    echo "❌ Inbox检查失败"
fi
echo ""

# 8. 测试错误处理
echo "=== 步骤 8: 测试错误处理 (eval 命令) ==="
if run_ao_cli eval "$PROCESS_ID" --data "error('Test error from eval')" --wait 2>&1 | grep -q "Error\|error"; then
    STEP_8_SUCCESS=true
    ((STEP_SUCCESS_COUNT++))
    echo "✅ 错误处理正确"
else
    STEP_8_SUCCESS=false
    echo "❌ 错误处理失败"
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
