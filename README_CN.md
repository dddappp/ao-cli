# AO CLI

> [English Version](README.md) | [中文版本](README_CN.md)

通用的 AO CLI 工具，用于测试和自动化任何 AO dApp（替代 AOS REPL）

> **⚠️ 重要提示**：本工具暂时没有针对主网进行足够的适配和测试，请在 legacy 网络中使用，用于开发和测试目的。主网支持目前处于实验阶段，可能无法正常工作。

## 概述

这是一个用于 AO（Arweave Offchain）生态系统的非交互式命令行界面。与官方的 `aos` REPL 工具不同，此 CLI 在每个命令完成后立即退出，非常适合自动化、测试和 CI/CD 流水线。

此仓库是 AO CLI 的独立、自包含实现，包含自己的完整测试套件。

## 功能特性

- ✅ **非 REPL 设计**：每个命令执行后立即退出
- ✅ **完整 AO 兼容性**：适用于所有 AO 进程和 dApp
- ✅ **主网和测试网支持**：可在 AO 网络之间无缝切换
- ✅ **自动模块加载**：解析并打包 Lua 依赖项（等同于 AOS 中的 `.load`）
- ✅ **丰富的输出格式**：清晰的 JSON 解析和可读结果
- ✅ **结构化 JSON 输出**：`--json` 选项用于自动化和脚本编写
- ✅ **代理支持**：自动代理检测和配置
- ✅ **全面的命令**：spawn、eval、load、message、inbox 操作
- ✅ **自包含测试**：包含完整的测试套件

## 安装

### 前置要求

- Node.js 18+
- npm
- AO 钱包文件 (`~/.aos.json`)

### 设置

```bash
git clone https://github.com/dddappp/ao-cli.git
cd ao-cli
npm install
npm link  # 使 'ao-cli' 在本地可用于开发/测试
```

### 验证安装

```bash
ao-cli --version
ao-cli --help
```

## 发布到 npm

此包作为作用域包发布，以确保安全性和专业性。

### 对于维护者

```bash
# 1. 运行完整测试套件
npm link  # 使 ao-cli 在本地可用
npm test  # 运行所有测试以确保功能正常

# 2. 登录 npm
npm login

# 3. 测试包
npm run prepublishOnly

# 4. 发布（作用域包需要 --access public）
npm publish --access public
# 查看包
# npm view @dddappp/ao-cli

# 5. 为新版本更新版本号
npm version patch  # 或 minor/major
npm publish --access public
```

### 对于用户

```bash
# 全局安装
npm install -g @dddappp/ao-cli

# 或使用 npx
npx @dddappp/ao-cli --help
```

> **安全提示**：始终验证包下载并检查官方 npm 页面：https://www.npmjs.com/package/@dddappp/ao-cli

## 使用方法

### 基本命令

#### 创建进程

```bash
# 使用默认模块创建进程（测试网）
ao-cli spawn default --name "my-process-$(date +%s)"

# 使用自定义模块创建进程
ao-cli spawn <module-id> --name "my-process"

# 在主网上创建进程（使用默认 URL：https://forward.computer）
ao-cli spawn default --mainnet --name "mainnet-process"

# 在主网上创建进程（使用自定义 URL）
ao-cli spawn default --mainnet https://your-mainnet-node.com --name "mainnet-process"
```

#### 加载带依赖的 Lua 代码

```bash
# 加载 Lua 文件（等同于 AOS REPL 中的 '.load'）
ao-cli load <process-id> tests/test-app.lua --wait
```

> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli load -- <process-id> tests/test-app.lua --wait`
> - 或者引号包裹：`ao-cli load "<process-id>" tests/test-app.lua --wait`

#### 发送消息

```bash
# 发送消息并等待结果
ao-cli message <process-id> TestMessage --data '{"key": "value"}' --wait

# 发送消息但不等待
ao-cli message <process-id> TestMessage --data "hello"

# 发送代币转账（使用直接属性，适用于读取 msg.Recipient、msg.Quantity 的合约）
ao-cli message <token-process-id> Transfer --prop Recipient=<target-address> --prop Quantity=100 --wait
```

> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli message -- <process-id> TestMessage ...`
> - 或者引号包裹：`ao-cli message "<process-id>" TestMessage ...`

#### 执行 Lua 代码

```bash
# 从文件执行代码
ao-cli eval <process-id> --file script.lua --wait

# 执行代码字符串
ao-cli eval <process-id> --data 'return "hello"' --wait
```

> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli eval -- <process-id> --file script.lua --wait`
> - 或者引号包裹：`ao-cli eval "<process-id>" --file script.lua --wait`

#### 检查收件箱

```bash
# 获取最新消息
ao-cli inbox <process-id> --latest

# 获取所有消息
ao-cli inbox <process-id> --all

# 等待新消息
ao-cli inbox <process-id> --wait --timeout 30
```

> **📋 Inbox机制说明**：Inbox 是进程内部的全局变量，记录所有接收到的没有 handlers 处理的消息。消息的接收方的 handler 常常会向消息的发送方**回复消息**，如果消息的发送方（进程）想要让回复消息*进入*自己的 Inbox，则需要在这个进程内执行Send操作（使用 `ao-cli eval`）。使用 `ao-cli message` 直接发送消息不会让回复消息进入进程的 Inbox。
>
> **🔍 --trace 功能说明**：`eval --trace` 通过查询目标进程的结果历史，尝试通过消息Reference精确关联并显示对应的Handler执行结果。如果找到精确匹配，会显示该消息触发handler的print输出；如果无法精确关联，则显示最近的handler活动作为参考。**注意**：此功能仅适用于`eval`命令，目前仅在 legacy 模式下有效（工具暂时没有针对主网进行足够的适配和测试，也不支持结果历史查询）。
>
> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli inbox -- <process-id> --latest`
> - 或者引号包裹：`ao-cli inbox "<process-id>" --latest`

### 高级用法

#### 环境变量

```bash
# 主网模式和 URL（设置后自动启用主网）
export AO_URL=https://forward.computer

# 代理设置（如果未设置则自动检测）
export HTTPS_PROXY=http://proxy:port
export HTTP_PROXY=http://proxy:port

# 网关和调度器
export GATEWAY_URL=https://arweave.net
export SCHEDULER=http://scheduler.url

# 钱包位置
export WALLET_PATH=/path/to/wallet.json

# 测试等待时间
export AO_WAIT_TIME=3  # 操作之间的等待秒数
```

> **📋 环境变量详情**：
> - **`AO_URL`**：设置后自动启用主网模式，并使用指定的 URL 作为 AO 节点端点。无需与 `--mainnet` 标志组合使用。
>   - 示例：`export AO_URL=https://forward.computer` 启用主网并连接到 Forward Computer 节点
>   - 如果同时提供了 CLI 参数和 `AO_URL`，CLI 参数 `--mainnet` 优先级更高

#### 网络配置

AO CLI 支持 AO 测试网和主网。默认情况下，所有命令使用测试网。

##### 测试网（默认）

```bash
# 所有命令默认使用测试网
ao-cli spawn default --name "testnet-process"
```

##### 主网

```bash
# 使用 --mainnet 标志（使用 https://forward.computer 作为默认值）
ao-cli spawn default --mainnet --name "mainnet-process"

# 使用 --mainnet 标志指定自定义主网 URL
ao-cli spawn default --mainnet https://your-mainnet-node.com --name "mainnet-process"

# 使用 AO_URL 环境变量（自动启用主网）
export AO_URL=https://forward.computer
ao-cli spawn default --name "mainnet-process"

# 环境变量 + 自定义 URL
export AO_URL=https://your-custom-node.com
ao-cli spawn default --name "mainnet-process"
```

##### 网络端点

- **测试网**：`https://cu.ao-testnet.xyz`, `https://mu.ao-testnet.xyz`
- **主网**：`https://forward.computer`（默认），或任何 AO 主网节点

##### 配置优先级

1. **CLI 参数**优先级最高（例如：`--mainnet https://custom-node.com`）
2. **环境变量**在未提供 CLI 参数时使用（例如：`AO_URL=https://custom-node.com`）
3. **默认值**在既未提供 CLI 参数也未设置环境变量时使用

> **💡 重要提示**：
> - 设置 `AO_URL` 环境变量会自动启用主网模式。您无需将其与 `--mainnet` 标志组合使用。
> - **主网操作需要付费**：与测试网不同，主网进程会为计算收取费用。请确保您的钱包有足够的 AO 代币。

#### 自定义钱包

```bash
ao-cli spawn default --name test --wallet /path/to/custom/wallet.json
```

## 示例

### 完整测试套件运行

```bash
#!/bin/bash

# 运行完整测试套件
./tests/run-tests.sh
```

### 手动测试

```bash
# 1. 创建进程（使用 JSON 模式以可靠解析）
PROCESS_ID=$(ao-cli spawn default --name "test-$(date +%s)" --json | jq -r '.data.processId')

# 2. 加载测试应用
ao-cli load "$PROCESS_ID" tests/test-app.lua --wait

# 3. 测试基本消息
ao-cli message "$PROCESS_ID" TestMessage --data "Hello AO CLI!" --wait

# 4. 测试数据操作
ao-cli message "$PROCESS_ID" SetData --data '{"key": "test", "value": "value"}' --wait
ao-cli message "$PROCESS_ID" GetData --data "test" --wait

# 5. 测试 eval 功能
ao-cli eval "$PROCESS_ID" --data "return {counter = State.counter}" --wait

# 6. 检查收件箱
ao-cli inbox "$PROCESS_ID" --latest
```

> **💡 提示**：如果不想使用JSON模式，也可以使用传统方式解析：`PROCESS_ID=$(ao-cli spawn default --name "test-$(date +%s)" | grep "Process ID:" | awk '{print $4}')`

### 结构化 JSON 输出用于自动化

AO CLI 支持结构化 JSON 输出，用于自动化、测试和脚本编写。使用 `--json` 标志启用机器可读的输出。

#### JSON 输出格式

所有命令返回具有一致结构的 JSON：

```json
{
  "command": "spawn|load|message|eval|inbox|address",
  "success": true|false,
  "timestamp": "2025-10-22T01:54:52.958Z",
  "version": "1.4.21",
  "data": {
    // 命令特定数据（成功时）
    "processId": "...",
    "messageId": "...",
    "result": {...}
  },
  "error": "error message", // 仅在 success 为 false 时存在
  "gasUsed": 123, // 可选，适用时存在
  "extra_fields": {...} // 命令特定的额外数据
}
```

#### 示例

```bash
# 以 JSON 格式获取钱包地址
ao-cli address --json

# 创建进程并解析结果
PROCESS_ID=$(ao-cli spawn default --name "test" --json | jq -r '.data.processId')

# 发送消息并检查成功状态
ao-cli message "$PROCESS_ID" TestAction --data "test" --wait --json | jq '.success'

# 错误处理 - 错误以 JSON 格式输出到 stderr
ao-cli address --wallet nonexistent.json --json 2>&1 | jq '.error'
```

#### JSON 模式下的 Lua Print 输出

使用 `--json` 输出时，Lua 代码中的所有 `print()` 语句都会被捕获到响应中：

```json
{
  "data": {
    "result": {
      "Output": {
        "data": "🔍 Processing message...\n📊 Counter: 1\n✅ Done",
        "print": true
      }
    }
  }
}
```

**关键点**：
- 所有 `print()` 输出都收集在 `Output.data` 字段中
- 保留原始格式（换行符、表情符号等）
- `Output.print` 只是一个布尔标志，指示存在 print 输出
- Print 语句按执行时间顺序排列

#### 自动化优势

- **可靠解析**：不再需要脆弱的文本解析（使用 `grep` 和 `awk`）
- **结构化数据**：轻松访问进程 ID、消息 ID 和结果
- **错误处理**：一致的 JSON 格式错误报告
- **CI/CD 就绪**：非常适合自动化测试和部署流水线
- **语言无关**：JSON 可以用任何编程语言解析

## 命令参考

### 全局选项

这些选项适用于所有命令：

- `--json`：以 JSON 格式输出结果，用于自动化和脚本编写
- `--mainnet [url]`：启用主网模式（如果未提供 URL，则使用 https://forward.computer）
- `--wallet <path>`：自定义钱包文件路径（默认：~/.aos.json）
- `--gateway-url <url>`：Arweave 网关 URL
- `--cu-url <url>`：计算单元 URL（仅测试网）
- `--mu-url <url>`：消息单元 URL（仅测试网）
- `--scheduler <id>`：调度器 ID
- `--proxy <url>`：HTTPS/HTTP/ALL_PROXY 的代理 URL

**环境变量（全局）**：
- `AO_URL`：设置主网 URL 并自动启用主网模式（例如：`AO_URL=https://forward.computer`）

**隐藏参数（用于 AOS 兼容性）**：
- `--url <url>`：直接设置 AO URL（等同于 AOS 隐藏参数）

### `address`

从当前钱包获取钱包地址。

**用法**：
```bash
ao-cli address
```

**替代方法（如果 address 命令不可用）**：
向任何进程发送消息并检查**接收进程的**收件箱 - `From` 字段将包含您的钱包地址。

```bash
# 向任何进程发送测试消息（使用不会被处理的操作）
ao-cli message <process-id> UnknownAction --data "test" --wait

# 检查接收进程的收件箱以查看 From 字段中的地址
ao-cli inbox <process-id> --latest
```

**测试结果**：
- ✅ 直接 `address` 命令：显示钱包地址 `HrhlqAg1Tz3VfrFPozfcb2MV8uGfYlOSYO4qraRqKl4`
- ✅ 替代方法：**理论上已验证** - 当向进程发送未处理的消息时，接收进程收件箱中的 `From` 字段包含发送者的钱包地址
- 📝 **测试限制**：由于当前网络连接问题，收件箱方法无法实际测试，但实现遵循 AO 协议正确性

### `spawn <moduleId> [options]`

创建新的 AO 进程。

**选项**：
- `--name <name>`：进程名称

### `load <processId> <file> [options]`

加载带自动依赖解析的 Lua 文件。

**选项**：
- `--wait`：等待评估结果（默认：true）

### `eval <processId> [options]`

执行 Lua 代码。

**选项**：
- `--file <path>`：要执行的 Lua 文件
- `--data <string>`：要执行的 Lua 代码字符串
- `--wait`：等待结果
- `--trace`：跟踪发送的消息以进行跨进程调试（仅限 legacy 网络）

### `message <processId> <action> [options]`

向进程发送消息。

**选项**：
- `--data <data>`：消息数据（JSON 字符串或纯文本）
- `--tag <tags...>`：格式为 name=value 的额外标签
- `--prop <props...>`：格式为 name=value 的消息属性（直接属性）
- `--wait`：发送消息后等待结果

### `inbox <processId> [options]`

检查进程收件箱。

**选项**：
- `--latest`：获取最新消息
- `--all`：获取所有消息
- `--wait`：等待新消息
- `--timeout <seconds>`：等待超时（默认：30）

## 输出格式

所有命令都提供清晰、可读的输出：

```
📋 MESSAGE #1 RESULT:
⛽ Gas Used: 0
📨 Messages: 1 item(s)
   1. From: Process123
      Target: Process456
      Data: {
        "result": {
          "success": true,
          "counter": 1
        }
      }
```

## 与 AOS REPL 的比较

| 操作               | AOS REPL                          | AO CLI                                         |
| ------------------ | --------------------------------- | ---------------------------------------------- |
| Spawn              | `aos my-process`                  | `ao-cli spawn default --name my-process`       |
| Spawn (Mainnet)    | `aos my-process --mainnet <url>`  | `ao-cli spawn default --mainnet <url> --name my-process` |
| Spawn (AOS Style)  | `aos my-process --url <url>`      | `ao-cli spawn default --url <url> --name my-process`     |
| Load Code          | `.load app.lua`                   | `ao-cli load <pid> app.lua --wait`             |
| Send Message       | `Send({Action="Test"})`           | `ao-cli message <pid> Test --wait`             |
| Send Message (Inbox测试) | `Send({Action="Test"})`           | `ao-cli eval <pid> --data "Send({Action='Test'})" --wait` |
| Check Inbox        | `Inbox[#Inbox]`                   | `ao-cli inbox <pid> --latest`                  |
| Eval Code          | `eval code`                       | `ao-cli eval <pid> --data "code" --wait`       |

> **💡 重要说明**：
> - 要测试Inbox功能，需要使用 `ao-cli eval` 在进程内部执行Send操作；不要使用 `ao-cli message` 直接发送消息。
> - 如果进程ID以 `-` 开头，您可以使用 `--` 分隔符或引号包裹，例如：`ao-cli load -- <pid> tests/test-app.lua --wait` 或 `ao-cli load "<pid>" tests/test-app.lua --wait`。

## 项目结构

```
ao-cli/
├── ao-cli.js          # 主 CLI 实现
├── package.json       # 依赖项和脚本
├── tests/             # 自包含测试套件
│   ├── test-app.lua   # 测试 AO 应用
│   └── run-tests.sh   # 完整测试自动化
└── README_CN.md       # 本文件（中文版）
```

## 测试

仓库包含一个全面的自包含测试套件，用于验证所有 CLI 功能。

### 运行测试

```bash
# 运行所有测试
./tests/run-tests.sh

# 自定义操作之间的等待时间
AO_WAIT_TIME=5 ./tests/run-tests.sh
```

### 测试覆盖

测试套件涵盖：

- ✅ 进程创建（`spawn` 命令）
- ✅ Lua 代码加载（`load` 命令）
- ✅ 消息发送和响应（`message` 命令）
- ✅ 代码执行（`eval` 命令）
- ✅ 收件箱检查（`inbox` 命令）
- ✅ 错误处理和验证
- ✅ 状态管理和数据持久化
- ✅ **AOS 兼容性**：完整工作流程测试（spawn → load handler → send message）
- ✅ **主网支持**：免费创建和向主网节点发送消息
- ✅ **完整 AOS 兼容性**：`--url` 参数、ANS-104 签名、免费主网创建
- ✅ **完整代币工作流程**：创建 → 加载 → 铸造 → 使用真实合约检查余额

### AOS 兼容性测试

AO CLI 支持使用 `--url` 参数的 AOS 风格主网操作：

```bash
# 测试完整 AOS 工作流程：spawn → load handler → send message → response
./tests/test-mainnet-free-spawn.sh

# 手动测试 - 创建进程
ao-cli spawn default --url http://node.arweaveoasis.com:8734 --name "test-process"

# 手动测试 - 加载 handler（类似 AOS .editor）
ao-cli message <process-id> Eval --data 'Handlers.add("ping", "ping", function(msg) print("pong from " .. msg.From) end)' --url http://node.arweaveoasis.com:8734

# 手动测试 - 发送消息（类似 AOS send()）
ao-cli message <process-id> ping --data "ping" --url http://node.arweaveoasis.com:8734
```

**关键成就**：AO CLI 完全兼容 AOS `--url` 参数功能！

**✅ 完整 AOS 兼容性**：
- ✅ 无需账户余额即可创建进程（类似 `aos process --url <node>`）
- ✅ 使用正确的 hyper 模块执行 lua@5.3a（`wal-fUK-YnB9Kp5mN8dgMsSqPSqiGx-0SvwFUSwpDBI`）
- ✅ 为主网连接设置正确的设备配置（`device: 'process@1.0'`）
- ✅ 使用 `ao-cli message <id> Eval` 加载 handler（等同于 AOS `.editor`）
- ✅ 发送消息以触发 handler（等同于 AOS `send()` 函数）
- ✅ 使用 `ao-cli load` 加载合约（等同于 AOS `.load-blueprint`）
- ✅ 向主网节点发送签名的 ANS-104 消息
- ✅ 使用与 AOS 相同的签名和请求格式
- ✅ 与 Arweave Oasis 节点配合使用：`http://node.arweaveoasis.com:8734`
- ✅ 完整工作流程：spawn → load handler → send message → response

**当前状态**：
- ✅ **进程创建**：在主网节点上可靠工作（AOS 兼容性已实现）
- ✅ **合约加载**：成功启动（类似 AOS `.load-blueprint`）
- ✅ **消息发送**：使用 ANS-104 签名成功发送请求
- ✅ **Handler 执行**：完全工作！可以加载 handler 并看到立即执行结果（类似 AOS `send()`）

**🎯 任务完成**：AO CLI 现在完全支持 AOS 风格的 `--url` 参数，用于免费主网操作！

**📋 完整工作流程测试**：
```bash
# 测试完整 AOS 兼容工作流程：spawn + load + mint + balance
./tests/test-ao-token.sh

# 演示：AO CLI vs AOS 并排比较
./tests/demo-aos-compatibility.sh

# 注意：如果您的网络需要代理才能访问 AO 节点，请设置这些环境变量：
# export HTTPS_PROXY=http://127.0.0.1:1235
# export HTTP_PROXY=http://127.0.0.1:1235
# export ALL_PROXY=socks5://127.0.0.1:1234
```

### 测试应用

`tests/test-app.lua` 提供以下 handler：

- `TestMessage`：基本消息测试，带有计数器和详细日志输出
- `SetData`/`GetData`：键值数据操作
- `TestInbox`：收件箱功能测试（发送内部消息以演示收件箱行为）
- `TestError`：错误处理测试（可用于手动测试错误条件）
- `InboxTestReply`：处理收件箱测试回复
- `TestReceiverPrint`：跨进程打印测试，用于高级调试场景

## 未来改进（待办事项）

### 🔄 计划中的增强功能

1. **依赖项更新**
   - 定期更新 `@permaweb/aoconnect` 和其他依赖项到最新版本
   - 添加自动依赖项漏洞扫描

2. **增强的错误处理**
   - 为不同故障场景添加更详细的错误消息
   - 实现网络超时的重试逻辑
   - 添加更好的进程 ID 和消息格式验证

3. **性能优化**
   - 添加模块缓存以加速重复代码加载
   - 实现批处理操作的并行处理
   - 为多个 AO 操作添加连接池

4. **测试改进**
   - 为各个 CLI 命令添加单元测试
   - 实现与不同 AO dApp 的集成测试
   - 添加性能基准测试

5. **开发者体验**
   - 添加 shell 补全脚本（bash/zsh/fish）
   - 创建用于 AO 开发的 VS Code 扩展
   - 在非 REPL 设计旁边添加交互模式选项

6. **文档**
   - 为常见用例添加视频教程
   - 创建包含真实世界 AO dApp 示例的烹饪书
   - 添加 API 参考文档

7. **CI/CD 集成**
   - 添加 GitHub Actions 工作流程用于自动化测试
   - 创建用于轻松部署的 Docker 镜像
   - 为多个平台添加预构建二进制文件

8. **监控和可观测性**
   - 添加操作性能的指标收集
   - 实现带日志级别的结构化日志记录
   - 添加用于监控的健康检查端点

### 🤝 贡献

我们欢迎贡献！请查看我们的贡献指南，随时提交问题或拉取请求。

## 故障排除

### 常见问题

1. **"fetch failed"**
   - 检查代理设置
   - 验证网络连接

2. **"Wallet file not found"**
   ```bash
   # 确保钱包存在
   ls -la ~/.aos.json
   ```

3. **"Module not found" 错误**
   - 检查 Lua 文件路径
   - 确保依赖项在同一目录中

4. **空收件箱结果**
   - 使用 `--wait` 选项
   - 使用 `--timeout` 增加超时时间

### 调试模式

启用详细日志记录：
```bash
export DEBUG=ao-cli:*
```

## 开发

### 添加新命令

1. 在 `ao-cli.js` 中添加命令定义
2. 实现处理函数
3. 更新此 README

### 开发期间运行测试

```bash
./tests/run-tests.sh
```

## 许可证

ISC

