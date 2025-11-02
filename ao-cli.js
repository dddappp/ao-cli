#!/usr/bin/env node

// AO CLI - Universal Non-REPL AO Command Line Interface
// A comprehensive tool for interacting with any AO dApp, replacing AOS REPL for automation and testing

// Default AO network endpoints
const DEFAULT_GATEWAY_URL = 'https://arweave.net';
const DEFAULT_ARWEAVE_GRAPHQL_URL = 'https://arweave.net/graphql';
const DEFAULT_ARWEAVE_HOST = 'arweave.net';
const DEFAULT_CU_URL = 'https://cu.ao-testnet.xyz';
const DEFAULT_MU_URL = 'https://mu.ao-testnet.xyz';
const DEFAULT_MAINNET_URL = 'https://forward.computer';
const DEFAULT_SCHEDULER_URL = 'https://scheduler.forward.computer';

// Default AO network identifiers
const DEFAULT_AUTHORITY = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';
// Authority ID for forward.computer mainnet (same as AOS)
const FORWARD_COMPUTER_AUTHORITY = 'QWg43UIcJhkdZq6ourr1VbnkwcP762Lppd569bKWYKY';
const DEFAULT_SCHEDULER_ID = '_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA';
const DEFAULT_AOS_MODULE = 'wal-fUK-YnB9Kp5mN8dgMsSqPSqiGx-0SvwFUSwpDBI';

// Setup environment BEFORE importing aoconnect - mimic AOS behavior
process.env.GATEWAY_URL = process.env.GATEWAY_URL || DEFAULT_GATEWAY_URL;
process.env.CU_URL = process.env.CU_URL || DEFAULT_CU_URL;
process.env.MU_URL = process.env.MU_URL || DEFAULT_MU_URL;

process.env.ARWEAVE_GRAPHQL = process.env.ARWEAVE_GRAPHQL || DEFAULT_ARWEAVE_GRAPHQL_URL;
// Don't set AO_URL default - only set when explicitly requested
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
process.env.AUTHORITY = process.env.AUTHORITY || DEFAULT_AUTHORITY;

process.env.DEBUG = 'false';
process.env.NODE_ENV = 'development';
process.env.TZ = 'UTC';

// Fix for AO_URL being set to string "undefined"
if (process.env.AO_URL === 'undefined') {
  delete process.env.AO_URL;
}

// Setup proxy agent BEFORE importing aoconnect (same as AOS)
try {
  const { ProxyAgent } = require('undici');
  if (process.env.HTTPS_PROXY) {
    const proxyAgent = new ProxyAgent(process.env.HTTPS_PROXY);
    const originalFetch = globalThis.fetch;
    globalThis.fetch = function (url, options = {}) {
      const finalOptions = { ...options, dispatcher: proxyAgent };
      return originalFetch(url, finalOptions);
    };
    console.error('🔧 ProxyAgent enabled: all fetch requests go through', process.env.HTTPS_PROXY);
  }
} catch (proxyError) {
  console.error('⚠️ Failed to enable undici ProxyAgent:', proxyError.message);
}

// Module loading functions (ported from AOS)
function createProjectStructure(mainFile) {
  const sorted = [];
  const cwd = path.dirname(mainFile);

  // checks if the sorted module list already includes a node
  const isSorted = (node) => sorted.find(
    (sortedNode) => sortedNode.path === node.path
  );

  // recursive dfs algorithm
  function dfs(currentNode) {
    const unvisitedChildNodes = exploreNodes(currentNode, cwd).filter(
      (node) => !isSorted(node)
    );

    for (let i = 0; i < unvisitedChildNodes.length; i++) {
      dfs(unvisitedChildNodes[i]);
    }

    if (!isSorted(currentNode)) {
      sorted.push(currentNode);
    }
  }

  // run DFS from the main file
  dfs({ path: mainFile });

  return sorted.filter(
    // modules that were not read don't exist locally
    // aos assumes that these modules have already been
    // loaded into the process, or they're default modules
    (mod) => mod.content !== undefined
  );
}

function createExecutableFromProject(project) {
  const getModFnName = (name) => name.replace(/\.|-/g, '_').replace(/^_/, '');
  const contents = [];

  // filter out repeated modules with different import names
  // and construct the executable Lua code
  // (the main file content is handled separately)
  for (let i = 0; i < project.length - 1; i++) {
    const mod = project[i];

    const existing = contents.find((m) => m.path === mod.path);
    const moduleContent = (!existing && `-- module: "${mod.name}"\nlocal function _loaded_mod_${getModFnName(mod.name)}()\n${mod.content}\nend\n`) || '';
    const requireMapper = `\n_G.package.loaded["${mod.name}"] = _loaded_mod_${getModFnName(existing?.name || mod.name)}()`;

    contents.push({
      ...mod,
      content: moduleContent + requireMapper
    });
  }

  // finally, add the main file
  contents.push(project[project.length - 1]);

  return [
    contents.reduce((acc, con) => acc + '\n\n' + con.content, ''),
    contents
  ];
}

// Find child nodes for a node (a module)
function exploreNodes(node, cwd) {
  if (!fs.existsSync(node.path)) return [];

  // set content
  node.content = fs.readFileSync(node.path, 'utf-8');

  // Don't include requires that are commented (start with --)
  const requirePattern = /(?<!^.*--.*)(?<=(require( *)(\n*)(\()?( *)("|'))).*(?=("|'))/gm;
  const requiredModules = node.content.match(requirePattern)?.map(
    (mod) => {
      return {
        name: mod,
        path: path.join(cwd, mod.replace(/\./g, '/') + '.lua'),
        content: undefined
      };
    }
  ) || [];

  return requiredModules;
}


async function evalLuaCode(processId, code, wait, wallet) {
  const messageId = await sendMessage({
    wallet,
    processId,
    action: 'Eval',
    data: code,
    tags: []
  });

  if (!program.opts().json) {
    console.log('📨 Eval message sent successfully!');
    console.log('📋 Message ID:', messageId);
  }

  if (wait) {
    if (!program.opts().json) {
      console.log('⏳ Waiting for eval result...');
    }
    const result = await getResult({
      wallet,
      processId,
      messageId
    });

    if (program.opts().json) {
      const formattedResult = formatResult(result);
      const extra = {};
      if (formattedResult.GasUsed) extra.gasUsed = formattedResult.GasUsed;
      if (formattedResult.Error) extra.error = formattedResult.Error;
      console.log(createJsonOutput('load', !formattedResult.Error, {
        messageId,
        processId,
        result: formattedResult
      }, formattedResult.Error, extra));
    } else {
      printFormattedResult(result, 'eval', 0);
    }
  } else {
    if (program.opts().json) {
      console.log(createJsonOutput('load', true, { messageId, processId }, null, { wait: false }));
    }
  }
}

// Now import aoconnect AFTER environment and proxy are set
const fs = require('fs');
const path = require('path');
const { Command } = require('commander');
const { connect, createDataItemSigner } = require('@permaweb/aoconnect');
const Arweave = require('arweave');

// Initialize Arweave
const arweave = Arweave.init({
  host: DEFAULT_ARWEAVE_HOST,
  port: 443,
  protocol: 'https'
});

// Get version dynamically to avoid hardcoding
let version = '1.0.0'; // fallback version
try {
  // Try to read from generated version.js file first (for published packages)
  version = require('./version.js');
} catch (e) {
  try {
    // Fallback to package.json (for development)
    const packageJson = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8'));
    version = packageJson.version;
  } catch (e2) {
    // Keep fallback version
    console.error('⚠️ Could not read version, using fallback:', version);
  }
}

// Utility functions for better output formatting
function createJsonOutput(command, success, data = {}, error = null, extra = {}) {
  const output = {
    command,
    success,
    timestamp: new Date().toISOString(),
    version,
    ...extra
  };

  if (success && data) {
    output.data = data;
  }

  if (error) {
    output.error = error;
  }

  return JSON.stringify(output, null, 2);
}

function formatResult(result) {
  if (!result) return result;

  const formatted = JSON.parse(JSON.stringify(result));

  // Format Messages array - preserve original data and provide formatted versions
  if (formatted.Messages && Array.isArray(formatted.Messages)) {
    formatted.Messages = formatted.Messages.map(msg => {
      const formattedMsg = { ...msg };

      // Preserve original Data
      if (typeof msg.Data === 'string') {
        formattedMsg._RawData = msg.Data; // Keep original raw data

        try {
          formattedMsg.Data = JSON.parse(msg.Data);
          formattedMsg._DataType = 'parsed_json';
        } catch (e) {
          try {
            const decoded = Buffer.from(msg.Data, 'base64').toString('utf8');
            if (decoded !== msg.Data) {
              formattedMsg.Data = decoded;
              formattedMsg._DataType = 'base64_decoded';
            } else {
              formattedMsg._DataType = 'string';
            }
          } catch (e2) {
            formattedMsg._DataType = 'string';
          }
        }
      }

      // Preserve original Tags and provide formatted versions
      if (formattedMsg.Tags && Array.isArray(formattedMsg.Tags)) {
        formattedMsg._RawTags = [...formattedMsg.Tags]; // Keep original tags array
        formattedMsg.Tags = formattedMsg.Tags.map(tag =>
          typeof tag === 'object' && tag.name && tag.value ? `${tag.name}=${tag.value}` : tag
        );
      }

      return formattedMsg;
    });
  }

  // Format Output.data - preserve original and provide formatted versions
  if (formatted.Output && typeof formatted.Output.data === 'string') {
    formatted.Output._RawData = formatted.Output.data; // Keep original raw data

    let cleanData = formatted.Output.data.replace(/\u001b\[[0-9;]*[mG]/g, '');
    if (cleanData.startsWith('{') || cleanData.startsWith('[')) {
      try {
        formatted.Output.data = JSON.parse(cleanData);
        formatted.Output._DataType = 'parsed_json';
      } catch (e) {
        formatted.Output.data = cleanData;
        formatted.Output._DataType = 'string';
      }
    } else {
      formatted.Output.data = cleanData;
      formatted.Output._DataType = 'string';
    }
  }

  return formatted;
}

function printFormattedResult(result, operationType, operationIndex) {
  console.log(`\n📋 ${operationType.toUpperCase()} #${operationIndex + 1} RESULT:`);

  if (operationType === 'spawn') {
    console.log(`🚀 Process ID: ${result}`);
    return;
  }

  const formatted = formatResult(result);

  if (formatted.GasUsed !== undefined) {
    console.log(`⛽ Gas Used: ${formatted.GasUsed}`);
  }

  if (formatted.Error) {
    console.log(`❌ Error: ${formatted.Error}`);
  }

  const hasContent = (formatted.Messages && formatted.Messages.length > 0) ||
    (formatted.Assignments && formatted.Assignments.length > 0) ||
    (formatted.Spawns && formatted.Spawns.length > 0) ||
    (formatted.Output && (formatted.Output.data || formatted.Output.prompt));

  if (!hasContent && !formatted.Error) {
    console.log(`✅ Operation completed successfully`);
  }

  if (formatted.Messages && formatted.Messages.length > 0) {
    console.log(`📨 Messages: ${formatted.Messages.length} item(s)`);
    formatted.Messages.forEach((msg, idx) => {
      console.log(`   ${idx + 1}. From: ${msg.From || 'Unknown'}`);
      console.log(`      Target: ${msg.Target || 'N/A'}`);
      console.log(`      Tags: [${msg.Tags ? msg.Tags.join(', ') : 'none'}]`);
      if (msg.Data) {
        if (msg._DataType === 'parsed_json') {
          console.log(`      Data: ${JSON.stringify(msg.Data, null, 2).replace(/\n/g, '\n           ')}`);
        } else {
          console.log(`      Data: "${msg.Data}"`);
        }
      }
    });
  }

  if (formatted.Assignments && formatted.Assignments.length > 0) {
    console.log(`📝 Assignments: ${formatted.Assignments.length} item(s)`);
    formatted.Assignments.forEach((assignment, idx) => {
      console.log(`   ${idx + 1}. Process: ${assignment.Process || 'Unknown'}`);
    });
  }

  if (formatted.Spawns && formatted.Spawns.length > 0) {
    console.log(`🚀 Spawns: ${formatted.Spawns.length} item(s)`);
    formatted.Spawns.forEach((spawn, idx) => {
      console.log(`   ${idx + 1}. Process: ${spawn || 'Unknown'}`);
    });
  }

  if (formatted.Output) {
    console.log(`📤 Output:`);
    if (formatted.Output.data) {
      if (formatted.Output._DataType === 'parsed_json') {
        console.log(`   Data: ${JSON.stringify(formatted.Output.data, null, 2).replace(/\n/g, '\n         ')}`);
      } else if (typeof formatted.Output.data === 'object') {
        console.log(`   Data: ${JSON.stringify(formatted.Output.data, null, 2).replace(/\n/g, '\n         ')}`);
      } else {
        console.log(`   Data: "${formatted.Output.data}"`);
      }
    }
    if (formatted.Output.prompt) {
      console.log(`   Prompt: ${formatted.Output.prompt.replace(/\u001b\[[0-9;]*[mG]/g, '')}`);
    }
  }
}

function loadWallet(walletPath) {
  const defaultWalletPath = path.join(require('os').homedir(), '.aos.json');

  if (!walletPath) {
    walletPath = defaultWalletPath;
  }

  if (!fs.existsSync(walletPath)) {
    throw new Error(`Wallet file not found: ${walletPath}`);
  }

  const walletData = fs.readFileSync(walletPath, 'utf8');
  return JSON.parse(walletData);
}

async function spawnProcess({ wallet, moduleId, tags, data, scheduler }) {
  const connectionInfo = getConnectionInfo();
  const isMainnet = connectionInfo.MODE === 'mainnet';

  if (isMainnet) {
    // Mainnet mode - use createSigner instead of createDataItemSigner
    const { createSigner } = require('@permaweb/aoconnect');
    const signer = createSigner(wallet);

    // Add version tag
    tags = tags.concat([{ name: 'aos-version', value: version }]);

    // Auto-detect scheduler for mainnet
    let scheduler = process.env.SCHEDULER;
    if (!scheduler) {
      let schedulerUrl = connectionInfo.URL;
      if (schedulerUrl === DEFAULT_MAINNET_URL) {
        schedulerUrl = DEFAULT_SCHEDULER_URL;
      }
      try {
        const response = await fetch(schedulerUrl + '/~meta@1.0/info/address');
        scheduler = await response.text();
        // Don't output in JSON mode
      } catch (e) {
        console.error('⚠️ Failed to auto-detect scheduler, using default');
        scheduler = DEFAULT_SCHEDULER_ID;
      }
    }

    // Auto-detect authority for mainnet
    let authority = process.env.AUTHORITY;
    if (!authority) {
      try {
        if (connectionInfo.URL === DEFAULT_MAINNET_URL) {
          authority = FORWARD_COMPUTER_AUTHORITY;
        } else {
          const response = await fetch(connectionInfo.URL + '/~meta@1.0/info/address');
          authority = await response.text();
        }
        authority = authority + ',' + DEFAULT_AUTHORITY;
        // Don't output in JSON mode
      } catch (e) {
        console.error('⚠️ Failed to auto-detect authority, using default');
        authority = DEFAULT_AUTHORITY;
      }
    }

    // Determine the correct module based on execution device (like AOS)
    const executionDevice = 'lua@5.3a';
    let finalModule = moduleId;
    if (executionDevice === 'lua@5.3a') {
      // Use hyper module for lua@5.3a execution device (like AOS)
      finalModule = process.env.AOS_MODULE || DEFAULT_AOS_MODULE;
    }

    const spawnParams = {
      device: 'process@1.0',
      'scheduler-device': 'scheduler@1.0',
      'push-device': 'push@1.0',
      'execution-device': executionDevice,
      'data-protocol': 'ao',
      variant: 'ao.TN.1',
      module: finalModule,
      scheduler: scheduler,
      authority: authority,
      ...tags.reduce((a, t) => ({ ...a, [t.name.toLowerCase()]: t.value }), {}),
      'signing-format': 'ANS-104',
      data: data || ''
    };

    // In JSON mode, don't output progress information

    const { request } = connect({ ...connectionInfo, signer });
    const response = await request({
      path: '/push',
      method: 'POST',
      type: 'Process',
      ...spawnParams
    });

    const result = response.process;
    if (!program.opts().json) {
      console.log('✅ Process spawned:', result);
    }

    // Small delay to ensure process is ready
    await new Promise(resolve => setTimeout(resolve, 500));
    return result;

  } else {
    // Legacy/Testnet mode - original implementation
    const signer = createDataItemSigner(wallet);

    // Add AOS version tag
    tags = tags.concat([{ name: 'aos-Version', value: version }]);

    const spawnParams = {
      module: moduleId,
      scheduler: scheduler || process.env.SCHEDULER || DEFAULT_SCHEDULER_ID,
      signer,
      tags,
      data: data || ''
    };

    // In JSON mode, don't output progress information

    const result = await connect({
      GATEWAY_URL: connectionInfo.GATEWAY_URL,
      CU_URL: connectionInfo.CU_URL,
      MU_URL: connectionInfo.MU_URL
    }).spawn(spawnParams);

    // Small delay to ensure process is ready
    await new Promise(resolve => setTimeout(resolve, 500));

    return result;
  }
}

async function sendMessage({ wallet, processId, action, data, tags = [], props = [] }) {
  const connectionInfo = getConnectionInfo();
  const isMainnet = connectionInfo.MODE === 'mainnet';

  if (isMainnet) {
    // Mainnet mode - use same approach as AOS
    const { createSigner } = require('@permaweb/aoconnect');

    // Combine tags and props for HTTP request
    // Props are treated as additional tags to maintain original case
    const allTags = [
      { name: 'Action', value: action },
      ...tags,
      ...props
    ];

    const messageParams = {
      type: 'Message',
      path: `/${processId}/push`,
      method: 'POST',
      target: processId,
      'data-protocol': 'ao',
      'signing-format': 'ANS-104',
      accept: 'application/json',
      action: action,
      // All tags (including props) are converted to lowercase properties for HTTP request
      ...allTags.reduce((a, t) => ({ ...a, [t.name.toLowerCase()]: t.value }), {}),
      data: data || ''
    };

    // In JSON mode, don't output progress information

    const { request } = connect({
      MODE: 'mainnet',
      device: 'process@1.0',
      signer: createSigner(wallet),
      GATEWAY_URL: connectionInfo.GATEWAY_URL,
      URL: connectionInfo.URL
    });

    const result = await request(messageParams);
    let messageId = undefined;

    try {
      // Try to parse the response body - handle ReadableStream
      if (result.body) {
        let text;
        if (typeof result.body === 'string') {
          text = result.body;
        } else if (result.body instanceof ReadableStream) {
          const reader = result.body.getReader();
          const chunks = [];
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            chunks.push(value);
          }
          text = new TextDecoder().decode(new Uint8Array(chunks.flat()));
        } else if (typeof result.body.text === 'function') {
          text = await result.body.text();
        }

        if (text && text.trim()) {
          const parsedResult = JSON.parse(text);

          // Check if the response contains immediate output (like AOS)
          if (parsedResult.output && parsedResult.output.data) {
            if (!program.opts().json) {
              console.log('📨 Message sent and processed successfully!');
              console.log('📋 IMMEDIATE RESULT:');
              console.log('📤 Output:', parsedResult.output.data);
            }

            // For immediate results, we don't need to wait for getResult
            messageId = 'immediate_result_processed';
          } else {
            // Try to get message ID for later result fetching
            messageId = parsedResult.id || parsedResult.messageId;
          }
        }
      }
    } catch (e) {
      // If parsing fails, try to get message ID from response headers or other sources
      console.error('⚠️ Could not parse response body for message ID:', e.message);
    }

    return messageId;

  } else {
    // Legacy/Testnet mode - use aoconnect message function
    const signer = createDataItemSigner(wallet);

    // Combine tags and props for aoconnect message function
    // Props are treated as additional tags to maintain original case
    const allTags = [
      { name: 'Action', value: action },
      ...tags,
      ...props
    ];

    const messageParams = {
      process: processId,
      data: data || '',
      tags: allTags,
      signer
    };

    // In JSON mode, don't output progress information

    const result = await connect(connectionInfo).message(messageParams);
    return result;
  }
}

async function getResult({ wallet, processId, messageId }) {
  const connectionInfo = getConnectionInfo();
  const isMainnet = connectionInfo.MODE === 'mainnet';

  // In JSON mode, don't output progress information

  if (isMainnet) {
    // Mainnet mode - different result retrieval
    const { createSigner } = require('@permaweb/aoconnect');
    const signer = createSigner(wallet);
    const { request } = connect({ ...connectionInfo, signer });
    const result = await request({
      path: `/${processId}/compute/${messageId}`,
      method: 'GET',
      accept: 'application/json',
      'accept-bundle': 'true'
    });

    // Parse the mainnet result format
    const body = JSON.parse(result.body || '{}');
    const results = body.results || [];
    if (results.length > 0) {
      return results[0]; // Return the first result
    } else {
      return { Error: 'No results found' };
    }

  } else {
    // Legacy/Testnet mode - original implementation
    const result = await connect(connectionInfo).result({
      process: processId,
      message: messageId
    });
    return result;
  }
}

// Main CLI setup
const program = new Command();

program
  .name('ao-cli')
  .description('Universal AO CLI tool for testing and automating any AO dApp (replaces AOS REPL)')
  .version(version);

program
  .option('--wallet <path>', 'Path to wallet file (default: ~/.aos.json)')
  .option('--gateway-url <url>', 'Arweave gateway URL')
  .option('--cu-url <url>', 'Compute Unit URL')
  .option('--mu-url <url>', 'Messenger Unit URL')
  .option('--scheduler <id>', 'Scheduler ID')
  .option('--proxy <url>', 'Proxy URL for HTTPS/HTTP/ALL_PROXY')
  .option('--mainnet [url]', `Enable mainnet mode (uses ${DEFAULT_MAINNET_URL} if no URL provided)`)
  .option('--url <url>', 'Set AO URL (hidden parameter for AOS compatibility)')
  .option('--json', 'Output results in JSON format for automation and scripting');

program
  .command('address')
  .description('Get the wallet address from current wallet')
  .action(async () => {
    try {
      const wallet = loadWallet(program.opts().wallet);
      const address = await arweave.wallets.jwkToAddress(wallet);
      if (program.opts().json) {
        console.log(createJsonOutput('address', true, { address }));
      } else {
        console.log('💰 Wallet Address:', address);
      }
    } catch (error) {
      if (program.opts().json) {
        console.error(createJsonOutput('address', false, null, error.message));
      } else {
        console.error('❌ Error getting wallet address:', error.message);
      }
      process.exit(1);
    }
  });

program
  .command('spawn')
  .description('Spawn a new AO process')
  .argument('<moduleId>', 'Module ID to use')
  .option('-n, --name <name>', 'Process name')
  .option('-t, --tag <tags...>', 'Tags in format name=value')
  .option('-d, --data <data>', 'Initial data for the process')
  .option('-l, --load <file>', 'Load Lua file and set as initial data')
  .option('--hyper', 'Use hyper module instead of legacy')
  .action(async (moduleId, options) => {
    try {
      // Force fix AO_URL issue
      if (process.env.AO_URL === 'undefined') {
        delete process.env.AO_URL;
      }

      // Override environment with CLI options
      if (program.opts().gatewayUrl) process.env.GATEWAY_URL = program.opts().gatewayUrl;
      if (program.opts().cuUrl) process.env.CU_URL = program.opts().cuUrl;
      if (program.opts().muUrl) process.env.MU_URL = program.opts().muUrl;
      if (program.opts().scheduler) process.env.SCHEDULER = program.opts().scheduler;
      if (program.opts().proxy) {
        process.env.HTTPS_PROXY = program.opts().proxy;
        process.env.HTTP_PROXY = program.opts().proxy;
        process.env.ALL_PROXY = program.opts().proxy;
      }

      const wallet = loadWallet(program.opts().wallet);

      // Default module IDs (same as AOS)
      const LEGACY_MODULE_ID = 'ISShJH1ij-hPPt9St5UFFr_8Ys3Kj5cyg7zrMGt7H9s';
      const HYPER_MODULE_ID = DEFAULT_AOS_MODULE;

      const actualModuleId = options.hyper ? HYPER_MODULE_ID : (moduleId === 'default' ? LEGACY_MODULE_ID : moduleId);

      const tags = [];
      if (options.name) {
        tags.push({ name: 'Name', value: options.name });
      }

      // Parse custom tags
      if (options.tag) {
        options.tag.forEach(tagStr => {
          const [name, value] = tagStr.split('=');
          if (name && value) {
            tags.push({ name, value });
          }
        });
      }

      // Add default tags
      const appName = process.env.AO_URL ? "hyper-aos" : "aos";
      tags.push({ name: 'App-Name', value: appName });
      tags.push({ name: 'Authority', value: process.env.AUTHORITY });

      // Handle --load option
      let initialData = options.data;
      if (options.load) {
        if (!fs.existsSync(options.load)) {
          throw new Error(`Lua file not found: ${options.load}`);
        }
        // In JSON mode, don't output progress information
        initialData = fs.readFileSync(options.load, 'utf8');
      }

      const processId = await spawnProcess({
        wallet,
        moduleId: actualModuleId,
        tags,
        data: initialData
      });

      if (program.opts().json) {
        console.log(createJsonOutput('spawn', true, { processId }));
      } else {
        console.log('🎉 Process spawned successfully!');
        console.log('📋 Process ID:', processId);
      }

    } catch (error) {
      if (program.opts().json) {
        console.error(createJsonOutput('spawn', false, null, error.message));
      } else {
        console.error('❌ Error:', error.message);
      }
      process.exit(1);
    }
  });

program
  .command('eval')
  .description('Send an Eval message to execute Lua code in an AO process')
  .argument('<processId>', 'Target process ID')
  .option('-f, --file <file>', 'Lua file to load and execute')
  .option('-d, --data <data>', 'Lua code to execute')
  .option('-t, --tag <tags...>', 'Additional tags in format name=value')
  .option('-w, --wait', 'Wait for result after sending message')
  .option('--trace', 'Trace sent messages for cross-process debugging')
  .action(async (processId, options) => {
    try {

      // Override environment with CLI options
      if (program.opts().gatewayUrl) process.env.GATEWAY_URL = program.opts().gatewayUrl;
      if (program.opts().cuUrl) process.env.CU_URL = program.opts().cuUrl;
      if (program.opts().muUrl) process.env.MU_URL = program.opts().muUrl;
      if (program.opts().scheduler) process.env.SCHEDULER = program.opts().scheduler;
      if (program.opts().proxy) {
        process.env.HTTPS_PROXY = program.opts().proxy;
        process.env.HTTP_PROXY = program.opts().proxy;
        process.env.ALL_PROXY = program.opts().proxy;
      }

      const wallet = loadWallet(program.opts().wallet);

      const tags = [];
      if (options.tag) {
        options.tag.forEach(tagStr => {
          const [name, value] = tagStr.split('=');
          if (name && value) {
            tags.push({ name, value });
          }
        });
      }

      // Handle --file option
      let evalData = options.data;
      if (options.file) {
        if (!fs.existsSync(options.file)) {
          throw new Error(`Lua file not found: ${options.file}`);
        }
        // In JSON mode, don't output progress information
        evalData = fs.readFileSync(options.file, 'utf8');
      }

      // 如果启用了trace，暂时不支持，需要等待所有消息处理完成
      if (options.trace && !program.opts().json) {
        console.error('🔧 Trace模式：将等待消息处理完成后查询结果');
      }


      const messageId = await sendMessage({
        wallet,
        processId,
        action: 'Eval',
        data: evalData,
        tags
      });

      if (program.opts().json) {
        console.log(createJsonOutput('eval', true, { messageId, processId }, null, { wait: options.wait }));
      } else {
        console.log('📨 Eval message sent successfully!');
        console.log('📋 Message ID:', messageId);
      }

      if (options.wait) {
        if (!program.opts().json) {
          console.log('⏳ Waiting for eval result...');
        }
        const result = await getResult({
          wallet,
          processId,
          messageId
        });

        if (program.opts().json) {
          const formattedResult = formatResult(result);
          const extra = {};
          if (formattedResult.GasUsed) extra.gasUsed = formattedResult.GasUsed;
          if (formattedResult.Error) extra.error = formattedResult.Error;

          // 如果启用了trace，在JSON模式下获取trace结果
          if (options.trace) {
            const traceResult = await traceSentMessages(result, wallet, true);
            if (traceResult) {
              extra.trace = traceResult;
            }
          }

          console.log(createJsonOutput('eval', !formattedResult.Error, {
            messageId,
            processId,
            result: formattedResult
          }, formattedResult.Error, extra));
        } else {
          printFormattedResult(result, 'eval', 0);

          // 如果启用了trace，显示发送消息的处理结果
          if (options.trace) {
            await traceSentMessages(result, wallet, false);
          }
        }
      }

    } catch (error) {
      if (program.opts().json) {
        console.error(createJsonOutput('eval', false, null, error.message));
      } else {
        console.error('❌ Error:', error.message);
      }
      process.exit(1);
    }
  });

program
  .command('message')
  .description('Send a message to an AO process (equivalent to AOS REPL Send command)')
  .argument('<processId>', 'Target process ID')
  .argument('<action>', 'Action to perform')
  .option('-d, --data <data>', 'Message data (JSON string or plain text)')
  .option('-t, --tag <tags...>', 'Additional tags in format name=value')
  .option('-p, --prop <props...>', 'Message properties (direct attributes) in format name=value')
  .option('-w, --wait', 'Wait for result after sending message')
  .action(async (processId, action, options) => {
    try {
      // Override environment with CLI options
      if (program.opts().gatewayUrl) process.env.GATEWAY_URL = program.opts().gatewayUrl;
      if (program.opts().cuUrl) process.env.CU_URL = program.opts().cuUrl;
      if (program.opts().muUrl) process.env.MU_URL = program.opts().muUrl;
      if (program.opts().scheduler) process.env.SCHEDULER = program.opts().scheduler;
      if (program.opts().proxy) {
        process.env.HTTPS_PROXY = program.opts().proxy;
        process.env.HTTP_PROXY = program.opts().proxy;
        process.env.ALL_PROXY = program.opts().proxy;
      }

      const wallet = loadWallet(program.opts().wallet);

      const tags = [];
      if (options.tag) {
        options.tag.forEach(tagStr => {
          const [name, value] = tagStr.split('=');
          if (name && value) {
            tags.push({ name, value });
          }
        });
      }

      const props = [];
      if (options.prop) {
        options.prop.forEach(propStr => {
          const [name, value] = propStr.split('=');
          if (name && value) {
            props.push({ name, value });
          }
        });
      }

      const messageId = await sendMessage({
        wallet,
        processId,
        action,
        data: options.data,
        tags,
        props
      });

      // Check if result was processed immediately (like AOS)
      if (messageId === 'immediate_result_processed') {
        if (program.opts().json) {
          console.log(createJsonOutput('message', true, {
            processId,
            action,
            immediate: true
          }));
        } else {
          console.log('✅ Message processed immediately (like AOS)!');
          console.log('🎉 Handler executed successfully!');
        }
        return; // Don't wait for additional results
      }

      if (program.opts().json) {
        console.log(createJsonOutput('message', true, { messageId, processId, action }, null, { wait: options.wait }));
      } else {
        console.log('📨 Message sent successfully!');
        console.log('📋 Message ID:', messageId);
      }


      if (options.wait) {
        if (!program.opts().json) {
          console.log('⏳ Waiting for result...');
        }
        const result = await getResult({
          wallet,
          processId,
          messageId
        });

        if (program.opts().json) {
          const formattedResult = formatResult(result);
          const extra = {};
          if (formattedResult.GasUsed) extra.gasUsed = formattedResult.GasUsed;
          if (formattedResult.Error) extra.error = formattedResult.Error;
          console.log(createJsonOutput('message', !formattedResult.Error, {
            messageId,
            processId,
            action,
            result: formattedResult
          }, formattedResult.Error, extra));
        } else {
          printFormattedResult(result, 'message', 0);
        }
      }

    } catch (error) {
      if (program.opts().json) {
        console.error(createJsonOutput('message', false, { processId, action }, error.message));
      } else {
        console.error('❌ Error:', error.message);
      }
      process.exit(1);
    }
  });

program
  .command('inbox')
  .description('Check inbox of an AO process (equivalent to Inbox[#Inbox] in AOS REPL)')
  .argument('<processId>', 'Process ID to check inbox')
  .option('-l, --latest', 'Get the latest message from inbox')
  .option('-a, --all', 'Get all messages from inbox')
  .option('-w, --wait', 'Wait for new messages if inbox is empty')
  .action(async (processId, options) => {
    try {
      // Override environment with CLI options
      if (program.opts().gatewayUrl) process.env.GATEWAY_URL = program.opts().gatewayUrl;
      if (program.opts().cuUrl) process.env.CU_URL = program.opts().cuUrl;
      if (program.opts().muUrl) process.env.MU_URL = program.opts().muUrl;
      if (program.opts().scheduler) process.env.SCHEDULER = program.opts().scheduler;
      if (program.opts().proxy) {
        process.env.HTTPS_PROXY = program.opts().proxy;
        process.env.HTTP_PROXY = program.opts().proxy;
        process.env.ALL_PROXY = program.opts().proxy;
      }

      const wallet = loadWallet(program.opts().wallet);

      // In JSON mode, don't output progress information

      if (options.wait) {
        // In JSON mode, don't output progress information

        const timeoutMs = parseInt(options.timeout) * 1000;
        const startTime = Date.now();

        while (Date.now() - startTime < timeoutMs) {
          try {
            // Read the actual inbox content by evaluating Inbox variable
            const result = await sendMessage({
              wallet,
              processId,
              action: 'Eval',
              data: 'return {latest = Inbox[#Inbox], all = Inbox, length = #Inbox}',
              tags: []
            });
            const inboxResult = await getResult({
              wallet,
              processId,
              messageId: result
            });
            printFormattedResult(inboxResult, 'inbox', 0);

            // If we got some data, we found messages
            if (inboxResult.Output && inboxResult.Output.data) {
              if (!program.opts().json) {
                console.log('✅ Found messages in inbox!');
              }
              break;
            }

          } catch (error) {
            // Ignore errors and continue waiting
          }

          // Wait 1 second before checking again
          await new Promise(resolve => setTimeout(resolve, 1000));
        }

        if (!program.opts().json) {
          console.log('⏰ Timeout reached or messages found');
        }

      } else {
        // Read the actual inbox content by evaluating Inbox variable
        const result = await sendMessage({
          wallet,
          processId,
          action: 'Eval',
          data: options.latest ? 'return {latest = Inbox[#Inbox], length = #Inbox}' : 'return {all = Inbox, length = #Inbox}',
          tags: []
        });

        const inboxResult = await getResult({
          wallet,
          processId,
          messageId: result
        });

        if (program.opts().json) {
          const formattedResult = formatResult(inboxResult);
          const extra = {};
          if (formattedResult.GasUsed) extra.gasUsed = formattedResult.GasUsed;
          if (formattedResult.Error) extra.error = formattedResult.Error;
          console.log(createJsonOutput('inbox', !formattedResult.Error, {
            processId,
            inbox: formattedResult.Output?.data || formattedResult
          }, formattedResult.Error, extra));
        } else {
          printFormattedResult(inboxResult, 'inbox', 0);
        }
      }

    } catch (error) {
      if (program.opts().json) {
        console.error(createJsonOutput('inbox', false, { processId }, error.message));
      } else {
        console.error('❌ Error:', error.message);
      }
      process.exit(1);
    }
  });

program
  .command('load')
  .description('Load Lua file with dependencies (equivalent to .load in AOS REPL)')
  .argument('<processId>', 'Process ID to load code into')
  .argument('<file>', 'Lua file to load')
  .option('-w, --wait', 'Wait for eval result', true)
  .action(async (processId, filePath, options) => {
    try {
      // Override environment with CLI options
      if (program.opts().gatewayUrl) process.env.GATEWAY_URL = program.opts().gatewayUrl;
      if (program.opts().cuUrl) process.env.CU_URL = program.opts().cuUrl;
      if (program.opts().muUrl) process.env.MU_URL = program.opts().muUrl;
      if (program.opts().scheduler) process.env.SCHEDULER = program.opts().scheduler;
      if (program.opts().proxy) {
        process.env.HTTPS_PROXY = program.opts().proxy;
        process.env.HTTP_PROXY = program.opts().proxy;
        process.env.ALL_PROXY = program.opts().proxy;
      }

      const wallet = loadWallet(program.opts().wallet);

      // In JSON mode, don't output progress information

      // Read the main file
      if (!fs.existsSync(filePath)) {
        throw new Error(`File not found: ${filePath}`);
      }

      // Use the same project structure creation logic as AOS
      const project = createProjectStructure(filePath);
      const [executable] = createExecutableFromProject(project);

      await evalLuaCode(processId, executable, options.wait, wallet);
    } catch (error) {
      if (program.opts().json) {
        console.error(createJsonOutput('load', false, { processId, file: filePath }, error.message));
      } else {
        console.error('❌ Error:', error.message);
      }
      process.exit(1);
    }
  });

// 新的trace函数：使用捕获的发送消息信息

// 追踪发送消息的处理结果，用于显示接收进程Handler中的print输出
async function traceSentMessages(evalResult, wallet, isJsonMode = false, evalMessageId = null) {
  if (!evalResult || !evalResult.Messages || evalResult.Messages.length === 0) {
    if (!isJsonMode) {
      console.log('ℹ️  Eval执行没有发送任何消息，无需追踪');
    }
    return { tracedMessages: [], summary: 'No messages sent' };
  }

  const tracedMessages = [];

  if (!isJsonMode) {
    console.log('');
    console.log('🔍 🔍 消息追踪模式 🔍 🔍');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('🔍 正在查询目标进程的结果历史，尝试通过Reference精确关联消息处理结果...');
    console.log('📝 Reference是AO消息系统的唯一标识符，可以用来关联发送消息和处理结果');
    console.log('📝 如果找到精确匹配，将显示该消息触发的handler print输出');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  for (let i = 0; i < evalResult.Messages.length; i++) {
    const message = evalResult.Messages[i];
    const targetProcess = message.Target;
    let messageResult = null;
    let hasPrintOutput = false;

    if (!isJsonMode) {
      console.log(`\n📤 追踪消息 ${i + 1}/${evalResult.Messages.length}:`);
      console.log(`   🎯 目标进程: ${targetProcess}`);
    }

    // 检查是否支持results查询（mainnet模式不支持）
    const connectionInfo = getConnectionInfo();
    if (connectionInfo.MODE === 'mainnet') {
      if (!isJsonMode) {
        console.log(`   ⚠️ 主网模式不支持结果历史查询，跳过追踪`);
      }
      continue;
    }

    // 从消息Tags中提取Reference
    let messageReference = null;
    if (message.Tags && Array.isArray(message.Tags)) {
      const referenceTag = message.Tags.find(tag => tag.name === 'Reference');
      if (referenceTag) {
        messageReference = referenceTag.value;
      }
    }

    if (!messageReference) {
      if (!isJsonMode) {
        console.log(`   ⚠️ 无法从消息中提取Reference，无法追踪`);
      }
      continue;
    }

    if (!isJsonMode) {
      console.log(`   🔗 消息Reference: ${messageReference}`);
    }

    // 尝试通过Reference精确关联消息处理结果
    const maxRetries = 12;
    const retryDelay = 1500;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (!isJsonMode && attempt === 1) {
          console.log(`   🔄 查询目标进程结果历史，尝试通过Reference=${messageReference}关联处理结果 (最多尝试 ${maxRetries} 次)...`);
        }

        const resultsResponse = await queryProcessResults(wallet, targetProcess, 50); // 查询更多结果

        if (resultsResponse && resultsResponse.edges && resultsResponse.edges.length > 0) {
          // 判断是否为系统输出（发送操作的结果或调试信息）
          const isSystemOutput = (outputData) => {
            if (!outputData || typeof outputData !== 'string') return false;

            // 纯系统输出：只有简单的确认信息
            if (outputData.trim() === 'Message added to outbox') return true;

            // 系统计算函数
            if (outputData.trim() === 'compute(base, req, opts)') return true;

            // AOS内部调试信息格式（Lua表格式，包含函数引用）
            // 这种格式通常是：{ onReply = function: 0x..., receive = function: 0x..., output = "..." }
            if (outputData.includes('onReply') &&
                outputData.includes('receive') &&
                outputData.includes('function: 0x')) {
              return true;
            }

            // 其他包含函数引用的输出（可能是系统调试信息）
            if (outputData.includes('function: 0x') && outputData.includes('output =')) {
              return true;
            }

            return false;
          };

          // 判断是否为Handler处理结果（优先级最高）
          const isHandlerResult = (outputData) => {
            return !isSystemOutput(outputData) && outputData.trim().length > 0;
          };

          // 判断是否为发送操作结果（中等优先级）
          const isSendOperation = (outputData) => {
            return isSystemOutput(outputData) && outputData.includes('Message added to outbox');
          };

          // 尝试通过Reference精确关联 - 在一次遍历中找到最佳和次佳匹配
          let bestMatch = null; // Handler处理结果（最高优先级）
          let fallbackMatch = null; // 发送操作结果（中等优先级）
          let foundHandlerResult = false;

          for (const edge of resultsResponse.edges) {
            if (edge.node && edge.node.Messages && Array.isArray(edge.node.Messages)) {
              const hasMatchingReference = edge.node.Messages.some(msg =>
                msg.Tags && msg.Tags.some(tag =>
                  tag.name === 'Reference' && tag.value === messageReference
                )
              );

              if (hasMatchingReference) {
                const outputData = edge.node.Output?.data || '';

                if (!isJsonMode) {
                  console.log(`   🔍 检查结果: isHandler=${isHandlerResult(outputData)}, isSendOp=${isSendOperation(outputData)}, data=${outputData.substring(0, 50)}${outputData.length > 50 ? '...' : ''}`);
                }

                // 优先检查Handler处理结果（最高优先级）
                if (isHandlerResult(outputData)) {
                  bestMatch = edge.node;
                  foundHandlerResult = true;
                  if (!isJsonMode) {
                    console.log(`   ✅ 发现Reference=${messageReference}的Handler处理结果（最高优先级，立即选择）`);
                  }
                  break; // 找到Handler结果就退出循环，这是最佳匹配
                }

                // 检查发送操作结果（中等优先级）
                // 注意：只有当这个结果明确是"Message added to outbox"时才作为备选
                if (isSendOperation(outputData) && !foundHandlerResult) {
                  if (!fallbackMatch) {
                    fallbackMatch = edge.node;
                    if (!isJsonMode) {
                      console.log(`   📝 找到Reference=${messageReference}的发送操作结果（备选，继续寻找Handler结果）`);
                    }
                  }
                  // 继续遍历，不要退出，看是否有更好的Handler结果
                }
              }
            }
          }

          // 选择最佳匹配
          if (bestMatch) {
            matchedResult = bestMatch;
            if (!isJsonMode) {
              console.log(`   ✅ 第${attempt}次尝试成功！选择最佳匹配：Handler处理结果`);
              console.log(`   🔍 结果类型：Handler处理结果（来自接收进程，最高优先级）`);
            }
          } else if (fallbackMatch) {
            matchedResult = fallbackMatch;
            if (!isJsonMode) {
              console.log(`   ✅ 第${attempt}次尝试成功！选择备选匹配：发送操作结果`);
              console.log(`   🔍 结果类型：发送操作结果（来自发送进程，中等优先级）`);
            }
          }

          // 策略2: 如果没有找到精确匹配，则查找最近的有意义输出（后备策略）
          if (!matchedResult) {
            for (const edge of resultsResponse.edges.slice(0, 10)) {
              const outputData = edge.node?.Output?.data;
              if (outputData && (isHandlerResult(outputData) || isSendOperation(outputData))) {
                matchedResult = edge.node;
                if (!isJsonMode) {
                  console.log(`   ✅ 第${attempt}次尝试成功！找到目标进程的最近handler执行记录 (Reference关联失败，使用最近活动)`);
                  console.log(`   📝 注意：由于无法精确关联，使用最近的handler活动作为参考`);
                }
                break;
              }
            }
          }

          if (matchedResult) {
            messageResult = matchedResult;
          }
        }

        if (messageResult) {
          break;
        } else if (attempt < maxRetries) {
          if (!isJsonMode) {
            console.log(`   ⏳ 第${attempt}次尝试未找到Reference=${messageReference}的关联结果，等待 ${retryDelay}ms 后重试...`);
          }
          await new Promise(resolve => setTimeout(resolve, retryDelay));
        } else {
          if (!isJsonMode) {
            console.log(`   📭 经过 ${maxRetries} 次尝试，未找到与Reference=${messageReference}关联的处理结果`);
            console.log(`   💡 可能原因：消息尚未被处理、处理结果尚未记录到链上、或CU API限制`);
          }
        }
      } catch (error) {
        if (attempt === maxRetries) {
          if (!isJsonMode) {
            console.log(`   📡 所有查询尝试都失败: ${error.message}`);
          }
        } else {
          if (!isJsonMode) {
            console.log(`   ⚠️ 第${attempt}次查询失败，等待重试...`);
          }
          await new Promise(resolve => setTimeout(resolve, retryDelay));
        }
      }
    }

    // 检查结果中是否有print输出
    if (messageResult && messageResult.Output) {
      if (!isJsonMode) {
        console.log('   ✅ 获取到处理结果:');
      }

      if (messageResult.Output.data && typeof messageResult.Output.data === 'string') {
        const printLines = messageResult.Output.data.split('\n').filter(line => line.trim());
        if (printLines.length > 0) {
          hasPrintOutput = true;
          if (!isJsonMode) {
            console.log('   📝 发现Handler中的print输出:');
            console.log('   ┌─────────────────────────────────────────────────────────────┐');
            printLines.forEach((line, idx) => {
              console.log(`   │ ${line}`);
            });
            console.log('   └─────────────────────────────────────────────────────────────┘');
          }
        }
      }
    }

    const tracedMessage = {
      index: i + 1,
      status: messageResult ? (hasPrintOutput ? 'success_with_print' : 'success_no_print') : 'no_result',
      targetProcess,
      hasPrintOutput
    };

    if (messageResult) {
      tracedMessage.result = {
        output: messageResult.Output,
        error: messageResult.Error
      };
    }

    tracedMessages.push(tracedMessage);

    if (!isJsonMode) {
      if (hasPrintOutput) {
        console.log(`   🎉 成功获取接收进程Handler的print输出！`);
      } else if (messageResult) {
        console.log(`   ✅ 消息已处理，但Handler没有print输出`);
      } else {
        console.log(`   📭 无法获取处理结果`);
      }
    }
  }

  if (!isJsonMode) {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    const successCount = tracedMessages.filter(m => m.hasPrintOutput).length;
    if (successCount > 0) {
      console.log(`✅ 消息追踪完成！成功获取了 ${successCount} 个接收进程Handler的print输出`);
    } else {
      console.log('✅ 消息追踪完成（未发现接收进程Handler的print输出）');
    }
  }

  return {
    tracedMessages,
    summary: `Traced ${tracedMessages.length} messages, ${tracedMessages.filter(m => m.hasPrintOutput).length} with print output`
  };
}


// Parse CLI arguments
program.parse();

// Create AO connect instance based on connection info
function getConnect(connectionInfo) {
  if (connectionInfo.MODE === 'mainnet') {
    const { createSigner } = require('@permaweb/aoconnect');
    // For mainnet, we need wallet context, but this function is called without wallet
    // So we return a function that creates the connection when called with wallet
    return (wallet) => {
      const signer = createSigner(wallet);
      return connect({ ...connectionInfo, signer });
    };
  } else {
    // Legacy mode
    return connect({
      GATEWAY_URL: connectionInfo.GATEWAY_URL,
      CU_URL: connectionInfo.CU_URL,
      MU_URL: connectionInfo.MU_URL
    });
  }
}

// Get request function for mainnet
function getRequest(connectionInfo) {
  const { createSigner } = require('@permaweb/aoconnect');
  // This also needs wallet context
  return (wallet) => {
    const signer = createSigner(wallet);
    const { request } = connect({ ...connectionInfo, signer });
    return request;
  };
}

// Generic function to get message result
async function getMessageResult(wallet, messageId, targetProcess) {
  const connectionInfo = getConnectionInfo();

  if (connectionInfo.MODE === 'mainnet') {
    const request = getRequest(connectionInfo)(wallet);
    const result = await request({
      method: 'GET',
      url: `${connectionInfo.URL}/result/${messageId}?process-id=${targetProcess}`
    });
    const body = JSON.parse(result.body || '{}');
    const results = body.results || [];
    return results.length > 0 ? results[0] : { Error: 'No results found' };
  } else {
    const connectInstance = getConnect(connectionInfo);
    return await connectInstance.result({
      process: targetProcess,
      message: messageId
    });
  }
}

async function queryProcessResults(wallet, processId, limit = 10) {
  const connectionInfo = getConnectionInfo();

  if (connectionInfo.MODE === 'mainnet') {
    // Mainnet mode doesn't support results query API
    // Return null to indicate no results available
    return null;
  } else {
    // 直接使用fetch调用CU API，因为aoconnect的results可能有问题
    const cuUrl = connectionInfo.CU_URL;
    const url = `${cuUrl}/results/${processId}?limit=${limit}&sort=DESC`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      },
      redirect: 'follow'
    });

    if (!response.ok) {
      throw new Error(`CU API request failed: ${response.status}`);
    }

    return await response.json();
  }
}


// Now we can check both CLI options and environment variables
function getConnectionInfo() {
  // Check for mainnet mode (CLI param takes priority over env var)
  const cliMainnet = program.opts().mainnet;
  const cliUrl = program.opts().url;
  const envAoUrl = process.env.AO_URL;

  // Handle --url parameter (AOS compatibility)
  if (cliUrl) {
    process.env.AO_URL = cliUrl;
    console.error('🌐 Using AO URL from --url parameter:', cliUrl);
    return {
      MODE: 'mainnet',
      URL: cliUrl,
      GATEWAY_URL: process.env.GATEWAY_URL
    };
  }

  // Only use mainnet if user explicitly requested it via CLI
  const isUserRequestedMainnet = cliMainnet || cliUrl;

  if (isUserRequestedMainnet) {
    // Mainnet mode - determine URL from CLI param or env var
    let finalUrl = cliMainnet || (envAoUrl && envAoUrl !== 'undefined' ? envAoUrl : null);

    // If --mainnet is provided without URL (true), use default mainnet URL
    if (cliMainnet === true) {
      finalUrl = DEFAULT_MAINNET_URL;
    }

    console.error('🌐 Using Mainnet mode with AO URL:', finalUrl);
    process.env.AO_URL = finalUrl;

    // Mainnet will auto-detect scheduler and authority
    return {
      MODE: 'mainnet',
      URL: finalUrl,
      GATEWAY_URL: process.env.GATEWAY_URL
    };
  } else {
    // Testnet/Legacy mode - default configuration
    return {
      MODE: 'legacy',
      GATEWAY_URL: process.env.GATEWAY_URL,
      CU_URL: process.env.CU_URL || DEFAULT_CU_URL,
      MU_URL: process.env.MU_URL || DEFAULT_MU_URL
    };
  }
}
