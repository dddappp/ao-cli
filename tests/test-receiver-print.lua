-- 测试接收进程Handlers中的print输出
-- 这个文件会被加载到接收进程中，用于验证跨进程Handler的print输出是否可以被捕获
--
-- 测试场景：eval + Send 方式下，接收进程Handler中的print语句
-- 预期结果：这些print输出不会出现在eval命令的结果中

Handlers.add(
    "TestReceiverPrint",
    Handlers.utils.hasMatchingTag("Action", "TestReceiverPrint"),
    function(msg)
        print("🎯 接收进程Handler开始执行")
        print("📨 收到来自发送进程的消息: " .. msg.Data)
        print("🔄 处理中...")

        -- 模拟一些处理逻辑
        local response = {
            received = msg.Data,
            processed_at = os.time(),
            from_process = msg.From
        }

        print("📤 发送响应消息")
        print("✅ 接收进程Handler执行完成")

        ao.send({
            Target = msg.From,  -- 回复给发送者
            Tags = { Action = "ReceiverResponse" },
            Data = json.encode(response)
        })

        return "处理完成"
    end
)
