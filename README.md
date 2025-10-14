# AO CLI

Universal AO CLI tool for testing and automating any AO dApp (replaces AOS REPL)

## Overview

This is a non-interactive command-line interface for the AO (Arweave Offchain) ecosystem. Unlike the official `aos` REPL tool, this CLI exits after each command completes, making it perfect for automation, testing, and CI/CD pipelines.

This repository is a standalone, self-contained implementation of the AO CLI with its own comprehensive test suite.

## Features

- ✅ **Non-REPL Design**: Each command executes and exits immediately
- ✅ **Full AO Compatibility**: Works with all AO processes and dApps
- ✅ **Mainnet & Testnet Support**: Seamlessly switch between AO networks
- ✅ **Automatic Module Loading**: Resolves and bundles Lua dependencies (equivalent to `.load` in AOS)
- ✅ **Rich Output Formatting**: Clean JSON parsing and readable results
- ✅ **Proxy Support**: Automatic proxy detection and configuration
- ✅ **Comprehensive Commands**: spawn, eval, load, message, inbox operations
- ✅ **Self-Contained Testing**: Complete test suite included

## Installation

### Prerequisites

- Node.js 18+
- npm
- AO wallet file (`~/.aos.json`)

### Setup

```bash
git clone https://github.com/dddappp/ao-cli.git
cd ao-cli
npm install
npm link  # Makes 'ao-cli' available globally
```

### Verify Installation

```bash
ao-cli --version
ao-cli --help
```

## Publishing to npm

This package is published as a scoped package for security and professionalism.

### For Maintainers

```bash
# 1. Run complete test suite
npm link  # Make ao-cli available locally
npm test  # Run all tests to ensure functionality

# 2. Login to npm
npm login

# 3. Test package
npm run prepublishOnly

# 4. Publish (scoped package requires --access public)
npm publish --access public
# View the package
# npm view @dddappp/ao-cli

# 5. Update version for new releases
npm version patch  # or minor/major
npm publish --access public
```

### For Users

```bash
# Install globally
npm install -g @dddappp/ao-cli

# Or use with npx
npx @dddappp/ao-cli --help
```

> **Security Note**: Always verify package downloads and check the official npm page at https://www.npmjs.com/package/@dddappp/ao-cli

## Usage

### Basic Commands

#### Spawn a Process
```bash
# Spawn with default module (testnet)
ao-cli spawn default --name "my-process-$(date +%s)"

# Spawn with custom module
ao-cli spawn <module-id> --name "my-process"

# Spawn on mainnet with default URL (https://forward.computer)
ao-cli spawn default --mainnet --name "mainnet-process"

# Spawn on mainnet with custom URL
ao-cli spawn default --mainnet https://your-mainnet-node.com --name "mainnet-process"
```

#### Load Lua Code with Dependencies
```bash
# Load a Lua file (equivalent to '.load' in AOS REPL)
ao-cli load <process-id> tests/test-app.lua --wait
```

> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli load -- <process-id> tests/test-app.lua --wait`
> - 或者引号包裹：`ao-cli load "<process-id>" tests/test-app.lua --wait`

#### Send Messages
```bash
# Send a message and wait for result
ao-cli message <process-id> TestMessage --data '{"key": "value"}' --wait

# Send without waiting
ao-cli message <process-id> TestMessage --data "hello"
```

> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli message -- <process-id> TestMessage ...`
> - 或者引号包裹：`ao-cli message "<process-id>" TestMessage ...`

#### Evaluate Lua Code
```bash
# Evaluate code from file
ao-cli eval <process-id> --file script.lua --wait

# Evaluate code string
ao-cli eval <process-id> --data 'return "hello"' --wait
```

> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli eval -- <process-id> --file script.lua --wait`
> - 或者引号包裹：`ao-cli eval "<process-id>" --file script.lua --wait`

#### Check Inbox
```bash
# Get latest message
ao-cli inbox <process-id> --latest

# Get all messages
ao-cli inbox <process-id> --all

# Wait for new messages
ao-cli inbox <process-id> --wait --timeout 30
```

> **📋 Inbox机制说明**：Inbox是进程内部的全局变量，记录所有接收到的消息。要让消息进入Inbox，需要在进程内部执行Send操作（使用`ao-cli eval`），外部API调用不会让消息进入Inbox。
>
> **注意**：如果进程ID以 `-` 开头，您可以使用以下任一种方法：
> - 使用 `--` 分隔符：`ao-cli inbox -- <process-id> --latest`
> - 或者引号包裹：`ao-cli inbox "<process-id>" --latest`

### Advanced Usage

#### Environment Variables

```bash
# Mainnet mode and URL (automatically enables mainnet when set)
export AO_URL=https://forward.computer

# Proxy settings (auto-detected if not set)
export HTTPS_PROXY=http://proxy:port
export HTTP_PROXY=http://proxy:port

# Gateway and scheduler
export GATEWAY_URL=https://arweave.net
export SCHEDULER=http://scheduler.url

# Wallet location
export WALLET_PATH=/path/to/wallet.json

# Test wait time
export AO_WAIT_TIME=3  # seconds to wait between operations
```

> **📋 Environment Variable Details:**
> - **`AO_URL`**: When set, automatically enables mainnet mode and uses the specified URL as the AO node endpoint. No need to combine with `--mainnet` flag.
>   - Example: `export AO_URL=https://forward.computer` enables mainnet with Forward Computer node
>   - The CLI parameter `--mainnet` takes priority over `AO_URL` if both are provided

#### Network Configuration

AO CLI supports both AO testnet and mainnet. By default, all commands use testnet.

##### Testnet (Default)
```bash
# All commands default to testnet
ao-cli spawn default --name "testnet-process"
```

##### Mainnet
```bash
# Use --mainnet flag (uses https://forward.computer as default)
ao-cli spawn default --mainnet --name "mainnet-process"

# Specify custom mainnet URL with --mainnet flag
ao-cli spawn default --mainnet https://your-mainnet-node.com --name "mainnet-process"

# Use AO_URL environment variable (automatically enables mainnet)
export AO_URL=https://forward.computer
ao-cli spawn default --name "mainnet-process"

# Environment variable + custom URL
export AO_URL=https://your-custom-node.com
ao-cli spawn default --name "mainnet-process"
```

##### Network Endpoints
- **Testnet**: `https://cu.ao-testnet.xyz`, `https://mu.ao-testnet.xyz`
- **Mainnet**: `https://forward.computer` (default), or any AO mainnet node

##### Configuration Priority
1. **CLI parameters** take highest priority (e.g., `--mainnet https://custom-node.com`)
2. **Environment variables** are used when CLI parameters are not provided (e.g., `AO_URL=https://custom-node.com`)
3. **Defaults** are used when neither CLI nor environment variables are set

> **💡 Important**:
> - Setting `AO_URL` environment variable automatically enables mainnet mode. You don't need to combine it with `--mainnet` flag.
> - **Mainnet operations require payment**: Unlike testnet, mainnet processes charge fees for computation. Ensure your wallet has sufficient AO tokens.

#### Custom Wallet

```bash
ao-cli spawn default --name test --wallet /path/to/custom/wallet.json
```

## Examples

### Complete Test Suite Run

```bash
#!/bin/bash

# Run the complete test suite
./tests/run-tests.sh
```

### Manual Testing

```bash
# 1. Spawn process
PROCESS_ID=$(ao-cli spawn default --name "test-$(date +%s)" | grep "Process ID:" | awk '{print $4}')

# 2. Load test application
ao-cli load "$PROCESS_ID" tests/test-app.lua --wait

# 3. Test basic messaging
ao-cli message "$PROCESS_ID" TestMessage --data "Hello AO CLI!" --wait

# 4. Test data operations
ao-cli message "$PROCESS_ID" SetData --data '{"key": "test", "value": "value"}' --wait
ao-cli message "$PROCESS_ID" GetData --data "test" --wait

# 5. Test eval functionality
ao-cli eval "$PROCESS_ID" --data "return {counter = State.counter}" --wait

# 6. Check inbox
ao-cli inbox "$PROCESS_ID" --latest
```

## Command Reference

### Global Options

These options work with all commands:

- `--mainnet [url]`: Enable mainnet mode (uses https://forward.computer if no URL provided)
- `--wallet <path>`: Custom wallet file path (default: ~/.aos.json)
- `--gateway-url <url>`: Arweave gateway URL
- `--cu-url <url>`: Compute Unit URL (testnet only)
- `--mu-url <url>`: Messenger Unit URL (testnet only)
- `--scheduler <id>`: Scheduler ID
- `--proxy <url>`: Proxy URL for HTTPS/HTTP/ALL_PROXY

**Environment Variables (Global):**
- `AO_URL`: Set mainnet URL and automatically enable mainnet mode (e.g., `AO_URL=https://forward.computer`)

**Hidden Parameters (for AOS compatibility):**
- `--url <url>`: Set AO URL directly (equivalent to AOS hidden parameter)

### `address`

Get the wallet address from the current wallet.

**Usage:**
```bash
ao-cli address
```

**Alternative Method (if address command is not available):**
Send a message to any process and check the **receiving process's** inbox - the `From` field will contain your wallet address.

```bash
# Send a test message to any process (use an action that won't be handled)
ao-cli message <process-id> UnknownAction --data "test" --wait

# Check the RECEIVING process's inbox to see your address in the From field
ao-cli inbox <process-id> --latest
```

**Test Results:**
- ✅ Direct `address` command: Shows wallet address `HrhlqAg1Tz3VfrFPozfcb2MV8uGfYlOSYO4qraRqKl4`
- ✅ Alternative method: Messages in inbox show `From` field containing the sender's wallet address

### `spawn <moduleId> [options]`

Spawn a new AO process.

**Options:**
- `--name <name>`: Process name

### `load <processId> <file> [options]`

Load Lua file with automatic dependency resolution.

**Options:**
- `--wait`: Wait for evaluation result

### `eval <processId> [options]`

Evaluate Lua code.

**Options:**
- `--file <path>`: Lua file to evaluate
- `--data <string>`: Lua code string
- `--wait`: Wait for result

### `message <processId> <action> [options]`

Send a message to a process.

**Options:**
- `--data <json>`: Message data
- `--tags <json>`: Additional tags
- `--wait`: Wait for result

### `inbox <processId> [options]`

Check process inbox.

**Options:**
- `--latest`: Get latest message
- `--all`: Get all messages
- `--wait`: Wait for new messages
- `--timeout <seconds>`: Wait timeout (default: 30)

## Output Format

All commands provide clean, readable output:

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

## Comparison with AOS REPL

| Operation               | AOS REPL                          | AO CLI                                         |
| ------------------------ | --------------------------------- | ---------------------------------------------- |
| Spawn                    | `aos my-process`                  | `ao-cli spawn default --name my-process`       |
| Spawn (Mainnet)          | `aos my-process --mainnet <url>`  | `ao-cli spawn default --mainnet <url> --name my-process` |
| Load Code                | `.load app.lua`                   | `ao-cli load <pid> app.lua --wait`             |
| Send Message             | `Send({Action="Test"})`           | `ao-cli message <pid> Test --wait`             |
| Send Message (Inbox测试) | `Send({Action="Test"})`           | `ao-cli eval <pid> --data "Send({Action='Test'})" --wait` |
| Check Inbox              | `Inbox[#Inbox]`                   | `ao-cli inbox <pid> --latest`                  |
| Eval Code                | `eval code`                       | `ao-cli eval <pid> --data "code" --wait`       |

> **💡 重要说明**：
> - 要测试Inbox功能，必须使用`ao-cli eval`在进程内部执行Send操作。直接使用`ao-cli message`不会让回复消息进入Inbox，因为那是外部API调用。
> - 如果进程ID以 `-` 开头，您可以使用 `--` 分隔符或引号包裹，例如：`ao-cli load -- <pid> tests/test-app.lua --wait` 或 `ao-cli load "<pid>" tests/test-app.lua --wait`。

## Project Structure

```
ao-cli/
├── ao-cli.js          # Main CLI implementation
├── package.json       # Dependencies and scripts
├── tests/             # Self-contained test suite
│   ├── test-app.lua   # Test AO application
│   └── run-tests.sh   # Complete test automation
└── README.md          # This file
```

## Testing

The repository includes a comprehensive self-contained test suite that verifies all CLI functionality.

### Running Tests

```bash
# Run all tests
./tests/run-tests.sh

# Custom wait time between operations
AO_WAIT_TIME=5 ./tests/run-tests.sh
```

### Test Coverage

The test suite covers:

- ✅ Process spawning (`spawn` command)
- ✅ Lua code loading (`load` command)
- ✅ Message sending and responses (`message` command)
- ✅ Code evaluation (`eval` command)
- ✅ Inbox checking (`inbox` command)
- ✅ Error handling and validation
- ✅ State management and data persistence

### Test Application

The `tests/test-app.lua` provides handlers for:

- `TestMessage`: Basic message testing with counter
- `SetData`/`GetData`: Key-value data operations
- `TestInbox`: Inbox functionality testing
- `TestError`: Error handling testing

## Future Improvements (TODOs)

### 🔄 Planned Enhancements

1. **Dependency Updates**
   - Regularly update `@permaweb/aoconnect` and other dependencies to latest versions
   - Add automated dependency vulnerability scanning

2. **Enhanced Error Handling**
   - Add more granular error messages for different failure scenarios
   - Implement retry logic for network timeouts
   - Add better validation for process IDs and message formats

3. **Performance Optimizations**
   - Add module caching to speed up repeated code loading
   - Implement parallel processing for batch operations
   - Add connection pooling for multiple AO operations

4. **Testing Improvements**
   - Add unit tests for individual CLI commands
   - Implement integration tests with different AO dApps
   - Add performance benchmarking tests

5. **Developer Experience**
   - Add shell completion scripts (bash/zsh/fish)
   - Create VS Code extension for AO development
   - Add interactive mode option alongside non-REPL design

6. **Documentation**
   - Add video tutorials for common use cases
   - Create cookbook with real-world AO dApp examples
   - Add API reference documentation

7. **CI/CD Integration**
   - Add GitHub Actions workflows for automated testing
   - Create Docker images for easy deployment
   - Add pre-built binaries for multiple platforms

8. **Monitoring & Observability**
   - Add metrics collection for operation performance
   - Implement structured logging with log levels
   - Add health check endpoints for monitoring

### 🤝 Contributing

We welcome contributions! Please see our contribution guidelines and feel free to submit issues or pull requests.

## Troubleshooting

### Common Issues

1. **"fetch failed"**
   - Check proxy settings
   - Verify network connectivity

2. **"Wallet file not found"**
   ```bash
   # Ensure wallet exists
   ls -la ~/.aos.json
   ```

3. **"Module not found" errors**
   - Check Lua file paths
   - Ensure dependencies are in the same directory

4. **Empty inbox results**
   - Use `--wait` option
   - Increase timeout with `--timeout`

### Debug Mode

Enable verbose logging:
```bash
export DEBUG=ao-cli:*
```

## Development

### Adding New Commands

1. Add command definition in `ao-cli.js`
2. Implement handler function
3. Update this README

### Running Tests During Development

```bash
./tests/run-tests.sh
```

## License

ISC