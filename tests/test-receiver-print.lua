-- 测试接收进程Handlers中的print输出
-- 这个文件会被加载到接收进程中，用于验证跨进程Handler的print输出是否可以被捕获

Handlers.add(
    "TestReceiverPrint",
    Handlers.utils.hasMatchingTag("Action", "TestReceiverPrint"),
    function(msg)
        print('🎯 接收进程Handler开始执行')
        print('📨 收到来自发送进程的消息: ' .. msg.Data)
        print('🔄 处理中...')
        print('📤 发送响应消息')
        print('✅ 接收进程Handler执行完成')

        ao.send({
            Target = msg.From,  -- 回复给发送者
            Tags = { Action = "ReceiverResponse" },
            Data = "处理完成: " .. msg.Data
        })

        return "处理完成"
    end
)
