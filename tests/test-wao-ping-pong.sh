#!/bin/bash
# WAO 本地测试网络 Ping/Pong 验证脚本
# 使用 ao-cli 验证 WAO 本地环境下的进程间通信功能

# 设置脚本错误退出
set -e

# 参数解析：支持 --json 与 --local [port]
USE_JSON="false"
LOCAL_MODE=true  # 默认启用本地模式
LOCAL_PORT=""
WAO_BASE_PORT="${LOCAL_PORT:-4000}"

# 显示使用说明
show_usage() {
    echo "WAO 本地测试网络 Ping/Pong 验证脚本"
    echo ""
    echo "使用 ao-cli 验证 WAO 本地环境下的进程间通信功能"
    echo ""
    echo "用法:"
    echo "  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --local [端口]    指定 WAO 本地网络基准端口 (默认: 4000)"
    echo "  --port 端口       同 --local"
    echo "  --json            使用 JSON 输出模式"
    echo ""
    echo "环境变量:"
    echo "  AO_CLI_USE_SOURCE=true  使用本地源码而不是全局安装的 ao-cli"
    echo ""
    echo "前提条件:"
    echo "  1. WAO 服务已启动: npx wao --port 4000"
    echo "  2. 钱包文件存在: ~/.aos.json"
    echo "  3. ao-cli 已安装并可用"
    echo ""
    echo "示例:"
    echo "  # 使用默认端口 (4000)"
    echo "  $0"
    echo ""
    echo "  # 指定自定义端口"
    echo "  $0 --local 5000"
    echo "  $0 --port 5000"
}

# 检查帮助参数
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            USE_JSON="true"
            ;;
        --local)
            LOCAL_MODE=true
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                LOCAL_PORT="$2"
                WAO_BASE_PORT="$2"
                shift
            fi
            ;;
        --local=*)
            LOCAL_MODE=true
            LOCAL_PORT="${1#--local=}"
            WAO_BASE_PORT="$LOCAL_PORT"
            ;;
        --port)
            WAO_BASE_PORT="$2"
            shift
            ;;
        *)
            echo "⚠️ 未知参数: $1 (已忽略)"
            ;;
    esac
    shift
done

# WAO 服务端点配置
WAO_GATEWAY="http://localhost:${WAO_BASE_PORT}"
WAO_MU="http://localhost:$((WAO_BASE_PORT + 2))"
WAO_CU="http://localhost:$((WAO_BASE_PORT + 4))"
WAO_SU="http://localhost:$((WAO_BASE_PORT + 3))"

# AO CLI 目标选项
AO_TARGET_OPTS=(--local "$WAO_BASE_PORT" --gateway-url "$WAO_GATEWAY")

echo "=== WAO 本地测试网络 Ping/Pong 验证脚本 ==="
echo "WAO 基准端口: $WAO_BASE_PORT"
echo "网关: $WAO_GATEWAY"
echo "消息单元: $WAO_MU"
echo "计算单元: $WAO_CU"
echo "调度单元: $WAO_SU"
echo ""

# 选择使用的 ao-cli 命令
if [ "${AO_CLI_USE_SOURCE:-false}" = "true" ]; then
    AO_CLI_CMD="node ./ao-cli.js"
    echo "🔧 使用本地源码 ao-cli: $AO_CLI_CMD"
else
    if ! command -v ao-cli &> /dev/null; then
        echo "❌ ao-cli 命令未找到。"
        echo "请先运行: npm link 或设置 AO_CLI_USE_SOURCE=true"
        exit 1
    fi
    AO_CLI_CMD="ao-cli"
fi

# 检查钱包文件
WALLET_FILE="${HOME}/.aos.json"
if [ ! -f "$WALLET_FILE" ]; then
    echo "❌ 钱包文件未找到: $WALLET_FILE"
    echo "请先创建钱包文件"
    exit 1
fi

# 辅助函数：运行 ao-cli 命令
run_ao_cli() {
    local command="$1"
    local process_id="$2"

    # Handle commands without process_id (like address)
    if [ "$command" = "address" ]; then
        $AO_CLI_CMD address "${AO_TARGET_OPTS[@]}" --json
        return
    fi

    shift 2

    # Always add --json in JSON mode
    if [[ "$process_id" == -* ]]; then
        $AO_CLI_CMD "$command" -- "$process_id" "${AO_TARGET_OPTS[@]}" --json "$@"
    else
        $AO_CLI_CMD "$command" "$process_id" "${AO_TARGET_OPTS[@]}" --json "$@"
    fi
}

# 获取钱包地址
WALLET_ADDRESS=$(run_ao_cli address 2>/dev/null | jq -r '.data.address // empty' 2>/dev/null || echo "")
if [ -z "$WALLET_ADDRESS" ] || [ "$WALLET_ADDRESS" = "empty" ]; then
    echo "❌ 无法获取钱包地址"
    exit 1
fi
echo "✅ 钱包地址: $WALLET_ADDRESS"

# 检查 WAO 服务状态
check_wao_services() {
    echo "🔍 检查 WAO 服务状态..."

    local services=(
        "Gateway:$WAO_GATEWAY"
        "MU:$WAO_MU"
        "CU:$WAO_CU"
        "SU:$WAO_SU"
    )

    for service in "${services[@]}"; do
        local name="${service%%:*}"
        local url="${service#*:}"

        if curl -fs --max-time 2 "$url" >/dev/null 2>&1; then
            echo "✅ $name ($url) - 运行中"
        else
            echo "❌ $name ($url) - 未响应"
            return 1
        fi
    done

    echo "✅ 所有 WAO 服务运行正常"
    return 0
}

# 创建 Ping 进程的 Lua 代码
create_ping_process_lua() {
    cat << 'EOF'
-- Ping 进程：发送 Ping 消息并等待 Pong 回复
State = State or {}
State.pings_sent = State.pings_sent or 0
State.pongs_received = State.pongs_received or 0

-- 初始化 authorities（如果不存在）
if not ao.authorities then
    ao.authorities = {}
end

-- 添加消息处理器
Handlers.add(
    "ReceivePong",
    Handlers.utils.hasMatchingTag("Action", "Pong"),
    function(msg)
        State.pongs_received = State.pongs_received + 1
        print("📥 收到 Pong 回复 #" .. State.pongs_received .. " 来自: " .. msg.From)
        print("📄 回复内容: " .. (msg.Data or "无内容"))
        return "Pong received from " .. msg.From
    end
)

-- Ping 函数
function SendPing(target_process_id)
    State.pings_sent = State.pings_sent + 1
    print("📤 发送 Ping #" .. State.pings_sent .. " 到: " .. target_process_id)

    Send({
        Target = target_process_id,
        Action = "Ping",
        Data = "Ping #" .. State.pings_sent .. " from " .. ao.id
    })

    return "Ping sent to " .. target_process_id
end

-- 返回进程状态
function GetStatus()
    return {
        id = ao.id,
        pings_sent = State.pings_sent,
        pongs_received = State.pongs_received,
        authorities = ao.authorities
    }
end
EOF
}

# 创建 Pong 进程的 Lua 代码
create_pong_process_lua() {
    cat << 'EOF'
-- Pong 进程：接收 Ping 消息并回复 Pong
State = State or {}
State.pings_received = State.pings_received or 0
State.pongs_sent = State.pongs_sent or 0

-- 初始化 authorities（如果不存在）
if not ao.authorities then
    ao.authorities = {}
end

-- 添加消息处理器
Handlers.add(
    "ReceivePing",
    Handlers.utils.hasMatchingTag("Action", "Ping"),
    function(msg)
        State.pings_received = State.pings_received + 1
        print("🏓 收到 Ping #" .. State.pings_received .. " 来自: " .. msg.From)
        print("📄 Ping 内容: " .. (msg.Data or "无内容"))

        -- 回复 Pong
        State.pongs_sent = State.pongs_sent + 1
        Send({
            Target = msg.From,
            Action = "Pong",
            Data = "Pong #" .. State.pongs_sent .. " from " .. ao.id .. " (reply to ping #" .. State.pings_received .. ")"
        })

        print("📤 已回复 Pong #" .. State.pongs_sent)
        return "Ping processed and Pong sent"
    end
)

-- 返回进程状态
function GetStatus()
    return {
        id = ao.id,
        pings_received = State.pings_received,
        pongs_sent = State.pongs_sent,
        authorities = ao.authorities
    }
end
EOF
}

# 主测试流程
main() {
    echo "🚀 开始 WAO Ping/Pong 测试..."
    echo ""

    # 步骤 1: 检查 WAO 服务
    if ! check_wao_services; then
        echo "❌ WAO 服务未运行，请先启动 WAO 服务："
        echo "   npx wao --port $WAO_BASE_PORT"
        exit 1
    fi
    echo ""

    # 步骤 2: 创建 Ping 进程
    echo "=== 步骤 1: 创建 Ping 进程 ==="
    PING_PROCESS_ID=$($AO_CLI_CMD spawn default "${AO_TARGET_OPTS[@]}" --name "ping-process-$(date +%s)" --json 2>&1 | awk '/^{/{flag=1} flag {print} /^}/{flag=0}' | jq -r '.data.processId // empty' 2>/dev/null || echo "")

    if [ -z "$PING_PROCESS_ID" ] || [ "$PING_PROCESS_ID" = "empty" ]; then
        echo "❌ 无法创建 Ping 进程"
        exit 1
    fi
    echo "✅ Ping 进程创建成功: $PING_PROCESS_ID"

    # 加载 Ping 进程代码
    echo "📝 加载 Ping 进程代码..."
    PING_LUA=$(create_ping_process_lua)
    if run_ao_cli load "$PING_PROCESS_ID" <(echo "$PING_LUA") --wait >/dev/null 2>&1; then
        echo "✅ Ping 进程代码加载成功"
    else
        echo "❌ Ping 进程代码加载失败"
        exit 1
    fi

    # 配置 Ping 进程的 authorities
    echo "🔐 配置 Ping 进程 authorities..."
    if run_ao_cli eval "$PING_PROCESS_ID" --data "if not ao.authorities then ao.authorities = {} end; table.insert(ao.authorities, '$WALLET_ADDRESS'); return 'Authorities configured'" --wait >/dev/null 2>&1; then
        echo "✅ Ping 进程 authorities 配置成功"
    else
        echo "⚠️ Ping 进程 authorities 配置失败（可能不影响测试）"
    fi
    echo ""

    # 步骤 3: 创建 Pong 进程
    echo "=== 步骤 2: 创建 Pong 进程 ==="
    PONG_PROCESS_ID=$($AO_CLI_CMD spawn default "${AO_TARGET_OPTS[@]}" --name "pong-process-$(date +%s)" --json 2>&1 | awk '/^{/{flag=1} flag {print} /^}/{flag=0}' | jq -r '.data.processId // empty' 2>/dev/null || echo "")

    if [ -z "$PONG_PROCESS_ID" ] || [ "$PONG_PROCESS_ID" = "empty" ]; then
        echo "❌ 无法创建 Pong 进程"
        exit 1
    fi
    echo "✅ Pong 进程创建成功: $PONG_PROCESS_ID"

    # 加载 Pong 进程代码
    echo "📝 加载 Pong 进程代码..."
    PONG_LUA=$(create_pong_process_lua)
    if run_ao_cli load "$PONG_PROCESS_ID" <(echo "$PONG_LUA") --wait >/dev/null 2>&1; then
        echo "✅ Pong 进程代码加载成功"
    else
        echo "❌ Pong 进程代码加载失败"
        exit 1
    fi

    # 配置 Pong 进程的 authorities
    echo "🔐 配置 Pong 进程 authorities..."
    if run_ao_cli eval "$PONG_PROCESS_ID" --data "if not ao.authorities then ao.authorities = {} end; table.insert(ao.authorities, '$WALLET_ADDRESS'); return 'Authorities configured'" --wait >/dev/null 2>&1; then
        echo "✅ Pong 进程 authorities 配置成功"
    else
        echo "⚠️ Pong 进程 authorities 配置失败（可能不影响测试）"
    fi

    # 让两个进程相互信任
    echo "🔗 配置进程间信任关系..."
    run_ao_cli eval "$PING_PROCESS_ID" --data "table.insert(ao.authorities, '$PONG_PROCESS_ID'); return 'Added pong process'" --wait >/dev/null 2>&1
    run_ao_cli eval "$PONG_PROCESS_ID" --data "table.insert(ao.authorities, '$PING_PROCESS_ID'); return 'Added ping process'" --wait >/dev/null 2>&1
    echo "✅ 进程间信任关系配置完成"
    echo ""

    # 步骤 4: 执行 Ping/Pong 测试
    echo "=== 步骤 3: 执行 Ping/Pong 测试 ==="

    # 发送第一个 Ping
    echo "🏓 发送第一个 Ping..."
    if run_ao_cli eval "$PING_PROCESS_ID" --data "SendPing('$PONG_PROCESS_ID')" --wait >/dev/null 2>&1; then
        echo "✅ Ping 发送成功"
    else
        echo "❌ Ping 发送失败"
        exit 1
    fi

    # 等待 Pong 回复
    echo "⏳ 等待 Pong 回复..."
    sleep 3

    # 检查 Ping 进程状态
    echo "📊 检查 Ping 进程状态..."
    PING_STATUS=$(run_ao_cli eval "$PING_PROCESS_ID" --data "return GetStatus()" --wait 2>&1)
    PINGS_SENT=$(echo "$PING_STATUS" | jq -r '.data.result.pings_sent // 0' 2>/dev/null || echo "0")
    PONGS_RECEIVED=$(echo "$PING_STATUS" | jq -r '.data.result.pongs_received // 0' 2>/dev/null || echo "0")

    # 检查 Pong 进程状态
    echo "📊 检查 Pong 进程状态..."
    PONG_STATUS=$(run_ao_cli eval "$PONG_PROCESS_ID" --data "return GetStatus()" --wait 2>&1)
    PINGS_RECEIVED=$(echo "$PONG_STATUS" | jq -r '.data.result.pings_received // 0' 2>/dev/null || echo "0")
    PONGS_SENT=$(echo "$PONG_STATUS" | jq -r '.data.result.pongs_sent // 0' 2>/dev/null || echo "0")

    echo ""
    echo "📈 测试结果统计:"
    echo "   Ping 进程 ($PING_PROCESS_ID):"
    echo "     📤 发送的 Ping: $PINGS_SENT"
    echo "     📥 收到的 Pong: $PONGS_RECEIVED"
    echo "   Pong 进程 ($PONG_PROCESS_ID):"
    echo "     📥 收到的 Ping: $PINGS_RECEIVED"
    echo "     📤 发送的 Pong: $PONGS_SENT"

    # 验证测试结果
    if [ "$PINGS_SENT" -eq 1 ] && [ "$PONGS_RECEIVED" -eq 1 ] && [ "$PINGS_RECEIVED" -eq 1 ] && [ "$PONGS_SENT" -eq 1 ]; then
        echo ""
        echo "🎉 WAO Ping/Pong 测试成功！"
        echo "✅ 进程间通信正常工作"
        echo "✅ 消息传递和处理正常"
        echo "✅ Authorities 配置正确"
        echo ""
        echo "💡 测试验证了以下功能："
        echo "   • WAO 本地网络进程间通信"
        echo "   • 动态配置 ao.authorities"
        echo "   • 消息发送和接收"
        echo "   • Handler 处理机制"
        echo "   • 跨进程状态同步"
        exit 0
    else
        echo ""
        echo "❌ WAO Ping/Pong 测试失败"
        echo "⚠️ 可能的原因："
        echo "   • 进程间通信未正确配置"
        echo "   • Authorities 未正确设置"
        echo "   • WAO 服务响应延迟"
        echo "   • 消息处理失败"
        echo ""
        echo "🔧 调试建议："
        echo "   1. 检查进程的 Inbox: ao-cli inbox <process-id> --local --latest"
        echo "   2. 查看进程状态: ao-cli eval <process-id> --local --data 'return GetStatus()' --wait"
        echo "   3. 检查 authorities: ao-cli eval <process-id> --local --data 'return ao.authorities' --wait"
        exit 1
    fi
}

# 调用主函数
main "$@"
