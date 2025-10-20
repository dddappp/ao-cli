# AOS 研究备忘录

## 项目目标

**AO CLI** 的目标是打造 **AOS 的非REPL版本**，作为 AOS 的替代品，主要用于：
- 🔧 **自动化测试** - 提供命令行接口进行批量测试
- 🚀 **CI/CD集成** - 支持脚本化部署和测试流程
- 📊 **程序化交互** - 通过编程方式与AO网络交互
- 🎯 **兼容性保证** - 完全兼容AOS的核心功能和行为

## AOS Computing 过程深入分析

### Computing过程真相大白！

#### 根本原因：AOS连接时自动执行初始化代码

当你新spawn一个进程并进入AOS时，**马上出现的Computing过程并非你输入的命令**，而是AOS**自动执行的初始化代码**：

```javascript
// AOS连接函数中的关键代码 (src/index.js:610)
promptResult = await evaluate("require('.process')._version", id, jwk, { sendMessage, readResult }, spinner, true)
```

#### 初始化代码的作用

AOS执行 `require('.process')._version` 来：

1. **检查进程是否正常运行** 🏥
2. **获取进程版本信息** 📋 (`process._version = "2.0.4"`)
3. **获取命令行提示符** 💻

#### Prompt的构成

Prompt字符串由以下部分组成（在process.lua的Prompt()函数中）：

```lua
function Prompt()
  return Colors.green .. Name .. Colors.gray
      .. "@" .. Colors.blue .. "aos-" .. process._version .. Colors.gray
      .. "[Inbox:" .. Colors.red .. tostring(#Inbox) .. Colors.gray
      .. "]" .. Colors.reset .. "> "
end
```

**显示效果**：`hyper~aos@dev[1]>` 或 `aos@aos-2.0.4[Inbox:0]>`

#### 关键变量说明

- **`Name`**：进程名称，默认为`'aos'`（第314-321行）
- **`Inbox`**：消息队列，存储接收到的消息（第302行）
- **`process._version`**：进程版本，当前是`"2.0.4"`

#### 完整执行流程

```javascript
// evaluate.js 中的完整流程
export async function evaluate(line, processId, wallet, services, spinner) {
  return of({ processId, wallet, tags: [{ name: 'Action', value: 'Eval' }], data: line })
    .map(tStart('Send'))          // ⏰ 开始计时 - 发送阶段
    .chain(pushMessage)           // 📤 发送消息到AO网络
    .map(tEnd('Send'))            // ⏰ 结束计时 - 发送阶段
    .map(changeSpinner)           // 🔄 显示: [Computing messageId...]
    .map(tStart('Read'))          // ⏰ 开始计时 - 读取阶段
    .chain(readResult)            // 📥 等待并读取计算结果
    .map(tEnd('Read'))            // ⏰ 结束计时 - 读取阶段
    .toPromise()
}
```

### AO CLI 的改进建议

#### 需要模仿的行为
- ✅ **进程连接验证** - 确保进程正常运行
- ✅ **版本检查** - 显示当前进程状态

#### 可以优化的地方
- 🔄 **更友好的连接提示**：`🔗 连接到进程...` 而不是 `Computing...`
- ⚡ **异步初始化**：连接和初始化可以并行，减少等待时间
- 📊 **更详细的状态反馈**：显示进程ID、版本、消息队列状态等
- ⏰ **可配置的超时**：避免无限等待

## AOS 消息通知机制深入分析

### "New Message From" 显示机制

#### 消息通知的触发时机

当进程接收到消息时，AOS会立即显示类似这样的通知：
```
New Message From njuP4JuzVEpcfJWa63pDFhjg3suidx7uwbsEXCBN4Mo: Action = XXX
```

这个机制**并非实时推送**，而是通过以下流程实现的：

#### 核心实现原理

**1. 默认处理器注册**
在每次消息处理时（hyper/src/process.lua），AOS会注册一个特殊的`_default`处理器：

```lua
Handlers.add("_default",
  function () return true end,  -- 总是匹配所有消息
  default(state.insertInbox)    -- 使用default处理器函数
)
```

**2. 默认处理器实现** (process/default.lua)
```lua
return function (insertInbox)
  return function (msg)
    -- Add Message to Inbox
    insertInbox(msg)

    local txt = Colors.gray .. "New Message From " .. Colors.green ..
    (msg.From and (msg.From:sub(1,3) .. "..." .. msg.From:sub(-3)) or "unknown") .. Colors.gray .. ": "
    if msg.Action then
      txt = txt .. Colors.gray .. (msg.Action and ("Action = " .. Colors.blue .. msg.Action:sub(1,20)) or "") .. Colors.reset
    else
      local data = msg.Data
      if type(data) == 'table' then
        data = require('json').encode(data)
      end
      txt = txt .. Colors.gray .. "Data = " .. Colors.blue .. (data and data:sub(1,20) or "") .. Colors.reset
    end
    -- Print to Output
    print(txt)
  end
end
```

**3. 消息格式化规则**
- **发送者ID**：显示前3个字符 + "..." + 后3个字符（例如：`nju...4Mo`）
- **Action消息**：显示 `Action = [Action值]`（截取前20个字符）
- **Data消息**：显示 `Data = [Data值]`（截取前20个字符，支持JSON格式化）

**4. 实时监听机制** (src/services/connect.js)
当用户执行`.live`命令时，启动定时任务（每2秒执行一次）：

```javascript
// 检查新的消息结果
const checkLive = async () => {
  const results = await connect(getInfo()).results(params)
  // 过滤出带有 print=true 的消息
  let edges = uniqBy(prop('cursor'))(results.edges.filter(function (e) {
    return e.node?.Output?.print === true
  }))
  // ... 处理消息并存储到 globalThis.alerts
}

// 显示消息到控制台
export function printLive() {
  keys(globalThis.alerts).map(k => {
    if (globalThis.alerts[k].print) {
      globalThis.alerts[k].print = false
      process.stdout.write("\u001b[0G" + globalThis.alerts[k].data)
    }
  })
}
```

#### 处理器执行流程

1. **消息到达**：其他进程发送消息到当前进程
2. **处理器匹配**：handlers.evaluate函数遍历所有处理器
3. **默认处理器执行**：如果没有其他处理器匹配，执行`_default`处理器
4. **消息入队**：insertInbox(msg) 将消息添加到Inbox
5. **通知显示**：print() 函数输出"New Message From..."消息
6. **实时同步**：.live命令启动的定时任务将消息同步到控制台

#### AO CLI 的实现建议

**需要模仿的**：
- ✅ **消息入队机制** - 维护Inbox队列
- ✅ **消息格式化** - 统一的ID和内容显示格式
- ✅ **实时监听** - 类似.live的定时检查功能

**可以优化的**：
- 🔄 **更丰富的通知类型** - 支持不同类型的消息分类显示
- ⚡ **真实时推送** - 如果AO网络支持WebSocket，可以考虑实时推送
- 📊 **消息过滤** - 允许用户过滤显示某些类型的消息

## 待研究的其他AOS特性

### 1. AOS 消息处理机制
- [ ] Handler注册和执行流程
- [ ] 消息队列(Inbox)管理
- [ ] 异步消息处理

### 2. AOS 模块系统
- [ ] `.load` 命令的工作原理
- [ ] 模块依赖解析
- [ ] 热重载机制

### 3. AOS 网络交互
- [ ] 与AO节点的连接建立
- [ ] 消息签名和验证
- [ ] 结果轮询策略

### 4. AOS 内置命令
- [ ] `.monitor` 和 `.unmonitor`
- [ ] `.live` 实时消息监听
- [ ] `.dryrun` 模式

### 5. AOS 错误处理
- [ ] 超时机制
- [ ] 网络异常处理
- [ ] Lua执行错误处理

## 研究方法和工具

### 代码分析
- AOS源码位置：`/PATH/TO/permaweb/aos`
- 重点文件：
  - `src/evaluate.js` - 表达式执行逻辑
  - `src/index.js` - 主入口和REPL逻辑
  - `process/process.lua` - AO进程运行时

### 测试验证
- 使用现有的测试脚本验证功能
- 对比AOS和AO CLI的行为差异
- 性能测试和压力测试

### 文档记录
- 定期更新此文档
- 记录关键发现和决策
- 维护功能对比矩阵
