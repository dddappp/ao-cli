#!/usr/bin/env node

// AO CLI - Universal Non-REPL AO Command Line Interface
// A comprehensive tool for interacting with any AO dApp, replacing AOS REPL for automation and testing

// Setup environment BEFORE importing aoconnect - mimic AOS behavior
process.env.GATEWAY_URL = process.env.GATEWAY_URL || 'https://arweave.net';

process.env.ARWEAVE_GRAPHQL = process.env.ARWEAVE_GRAPHQL || 'https://arweave.net/graphql';
process.env.AO_URL = process.env.AO_URL || 'https://arweave.net';
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
process.env.AUTHORITY = process.env.AUTHORITY || 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';

process.env.DEBUG = 'false';
process.env.NODE_ENV = 'development';
process.env.TZ = 'UTC';

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
    console.log('🔧 ProxyAgent enabled: all fetch requests go through', process.env.HTTPS_PROXY);
  }
} catch (proxyError) {
  console.warn('⚠️ Failed to enable undici ProxyAgent:', proxyError.message);
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

  console.log('📨 Eval message sent successfully!');
  console.log('📋 Message ID:', messageId);

  if (wait) {
    console.log('⏳ Waiting for eval result...');
    const result = await getResult({
      wallet,
      processId,
      messageId
    });

    printFormattedResult(result, 'eval', 0);
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
  host: 'arweave.net',
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
    console.warn('⚠️ Could not read version, using fallback:', version);
  }
}

// Utility functions for better output formatting
function formatResult(result) {
  if (!result) return result;

  const formatted = JSON.parse(JSON.stringify(result));

  // Format Messages array
  if (formatted.Messages && Array.isArray(formatted.Messages)) {
    formatted.Messages = formatted.Messages.map(msg => {
      const formattedMsg = { ...msg };
      if (typeof msg.Data === 'string') {
        try {
          formattedMsg.Data = JSON.parse(msg.Data);
          formattedMsg._DataType = 'parsed_json';
        } catch (e) {
          try {
            const decoded = Buffer.from(msg.Data, 'base64').toString('utf8');
            if (decoded !== msg.Data) {
              formattedMsg.Data = decoded;
              formattedMsg._DataType = 'base64_decoded';
            }
          } catch (e2) {
            formattedMsg._DataType = 'string';
          }
        }
      }
      if (formattedMsg.Tags && Array.isArray(formattedMsg.Tags)) {
        formattedMsg.Tags = formattedMsg.Tags.map(tag =>
          typeof tag === 'object' && tag.name && tag.value ? `${tag.name}=${tag.value}` : tag
        );
      }
      return formattedMsg;
    });
  }

  // Format Output.data - clean ANSI codes and format
  if (formatted.Output && typeof formatted.Output.data === 'string') {
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
      if (schedulerUrl === 'https://forward.computer') {
        schedulerUrl = 'https://scheduler.forward.computer';
      }
      try {
        const response = await fetch(schedulerUrl + '/~meta@1.0/info/address');
        scheduler = await response.text();
        console.log('📅 Auto-detected scheduler:', scheduler);
      } catch (e) {
        console.warn('⚠️ Failed to auto-detect scheduler, using default');
        scheduler = '_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA';
      }
    }

    // Auto-detect authority for mainnet
    let authority = process.env.AUTHORITY;
    if (!authority) {
      try {
        if (connectionInfo.URL === 'https://forward.computer') {
          authority = "QWg43UIcJhkdZq6ourr1VbnkwcP762Lppd569bKWYKY";
        } else {
          const response = await fetch(connectionInfo.URL + '/~meta@1.0/info/address');
          authority = await response.text();
        }
        authority = authority + ',fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';
        console.log('🏛️ Auto-detected authority:', authority);
      } catch (e) {
        console.warn('⚠️ Failed to auto-detect authority, using default');
        authority = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';
      }
    }

    const spawnParams = {
      device: 'process@1.0',
      'scheduler-device': 'scheduler@1.0',
      'push-device': 'push@1.0',
      'execution-device': 'lua@5.3a',
      'data-protocol': 'ao',
      variant: 'ao.N.1',
      module: moduleId,
      scheduler: scheduler,
      authority: authority,
      ...tags.reduce((a, t) => ({ ...a, [t.name.toLowerCase()]: t.value }), {}),
      'signing-format': 'ANS-104',
      data: data || ''
    };

    console.log('🚀 Spawning AO process on Mainnet...');
    console.log('   Module:', spawnParams.module);
    console.log('   AO URL:', connectionInfo.URL);
    console.log('   Tags:', Object.keys(spawnParams).filter(k => k.startsWith('aos-') || k === 'name').map(k => `${k}=${spawnParams[k]}`).join(', '));

    const { request } = connect({ ...connectionInfo, signer });
    const response = await request({
      path: '/push',
      method: 'POST',
      type: 'Process',
      ...spawnParams
    });

    const result = response.process;
    console.log('✅ Process spawned:', result);

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
      scheduler: scheduler || process.env.SCHEDULER || '_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA',
      signer,
      tags,
      data: data || ''
    };

    console.log('🚀 Spawning AO process...');
    console.log('   Module:', spawnParams.module);
    console.log('   Scheduler:', spawnParams.scheduler);
    console.log('   Tags:', spawnParams.tags.map(t => `${t.name}=${t.value}`).join(', '));

    const result = await connect(connectionInfo).spawn(spawnParams);

    // Small delay to ensure process is ready
    await new Promise(resolve => setTimeout(resolve, 500));

    return result;
  }
}

async function sendMessage({ wallet, processId, action, data, tags = [] }) {
  const connectionInfo = getConnectionInfo();
  const isMainnet = connectionInfo.MODE === 'mainnet';

  if (isMainnet) {
    // Mainnet mode - use different message format
    const { createSigner } = require('@permaweb/aoconnect');
    const signer = createSigner(wallet);

    const messageParams = {
      type: 'Message',
      path: `/${processId}/push`,
      method: 'POST',
      target: processId,
      'data-protocol': 'ao',
      'signing-format': 'ANS-104',
      action: action,
      ...tags.reduce((a, t) => ({ ...a, [t.name.toLowerCase()]: t.value }), {}),
      data: data || ''
    };

    console.log('📨 Sending message to Mainnet...');
    console.log('   Process:', processId);
    console.log('   Action:', action);
    console.log('   AO URL:', connectionInfo.URL);

    const { request } = connect({ ...connectionInfo, signer });
    const result = await request(messageParams);
    return result.id || result.messageId;

  } else {
    // Legacy/Testnet mode - original implementation
    const signer = createDataItemSigner(wallet);

    const messageParams = {
      process: processId,
      signer,
      tags: [
        { name: 'Action', value: action },
        ...tags
      ],
      data: data || ''
    };

    console.log('📨 Sending message...');
    console.log('   Process:', processId);
    console.log('   Action:', action);
    console.log('   Data:', data ? data.substring(0, 100) + (data.length > 100 ? '...' : '') : 'none');

    const result = await connect(connectionInfo).message(messageParams);
    return result;
  }
}

async function getResult({ wallet, processId, messageId }) {
  const connectionInfo = getConnectionInfo();
  const isMainnet = connectionInfo.MODE === 'mainnet';

  console.log('📥 Getting result...');
  console.log('   Process:', processId);
  console.log('   Message:', messageId);
  if (isMainnet) {
    console.log('   AO URL:', connectionInfo.URL);
  }

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
  .option('--mainnet [url]', 'Enable mainnet mode (uses https://forward.computer if no URL provided)')
  .option('--url <url>', 'Set AO URL (hidden parameter for AOS compatibility)');

program
  .command('address')
  .description('Get the wallet address from current wallet')
  .action(async () => {
    try {
      const wallet = loadWallet(program.opts().wallet);
      const address = await arweave.wallets.jwkToAddress(wallet);
      console.log('💰 Wallet Address:', address);
    } catch (error) {
      console.error('❌ Error getting wallet address:', error.message);
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
      const HYPER_MODULE_ID = 'wal-fUK-YnB9Kp5mN8dgMsSqPSqiGx-0SvwFUSwpDBI';

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
        console.log('📄 Loading Lua file:', options.load);
        initialData = fs.readFileSync(options.load, 'utf8');
        console.log('📊 File size:', initialData.length, 'characters');
      }

      const processId = await spawnProcess({
        wallet,
        moduleId: actualModuleId,
        tags,
        data: initialData
      });

      console.log('🎉 Process spawned successfully!');
      console.log('📋 Process ID:', processId);

    } catch (error) {
      console.error('❌ Error:', error.message);
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
        console.log('📄 Loading Lua file:', options.file);
        evalData = fs.readFileSync(options.file, 'utf8');
        console.log('📊 File size:', evalData.length, 'characters');
      }

      const messageId = await sendMessage({
        wallet,
        processId,
        action: 'Eval',
        data: evalData,
        tags
      });

      console.log('📨 Eval message sent successfully!');
      console.log('📋 Message ID:', messageId);

      if (options.wait) {
        console.log('⏳ Waiting for eval result...');
        const result = await getResult({
          wallet,
          processId,
          messageId
        });
        printFormattedResult(result, 'eval', 0);
      }

    } catch (error) {
      console.error('❌ Error:', error.message);
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

      const messageId = await sendMessage({
        wallet,
        processId,
        action,
        data: options.data,
        tags
      });

      console.log('📨 Message sent successfully!');
      console.log('📋 Message ID:', messageId);

      if (options.wait) {
        console.log('⏳ Waiting for result...');
        const result = await getResult({
          wallet,
          processId,
          messageId
        });

        printFormattedResult(result, 'message', 0);
      }

    } catch (error) {
      console.error('❌ Error:', error.message);
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
  .option('--timeout <seconds>', 'Timeout for waiting (default: 30)', '30')
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

      console.log('📬 Checking inbox for process:', processId);

      if (options.wait) {
        console.log(`⏳ Waiting for messages (timeout: ${options.timeout}s)...`);

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
              console.log('✅ Found messages in inbox!');
              break;
            }

          } catch (error) {
            // Ignore errors and continue waiting
          }

          // Wait 1 second before checking again
          await new Promise(resolve => setTimeout(resolve, 1000));
        }

        console.log('⏰ Timeout reached or messages found');

      } else {
        // Read the actual inbox content by evaluating Inbox variable
        const result = await sendMessage({
          wallet,
          processId,
          action: 'Eval',
          data: options.latest ? 'return {latest = Inbox[#Inbox], all = Inbox, length = #Inbox}' : 'return {all = Inbox, length = #Inbox}',
          tags: []
        });

        const inboxResult = await getResult({
          wallet,
          processId,
          messageId: result
        });

        printFormattedResult(inboxResult, 'inbox', 0);
      }

    } catch (error) {
      console.error('❌ Error:', error.message);
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

      console.log('📄 Loading Lua file:', filePath);

      // Read the main file
      if (!fs.existsSync(filePath)) {
        throw new Error(`File not found: ${filePath}`);
      }

      const fileSize = fs.statSync(filePath).size;
      console.log('📊 File size:', fileSize, 'characters');

      // Use the same project structure creation logic as AOS
      const project = createProjectStructure(filePath);
      const [executable] = createExecutableFromProject(project);

      console.log('📦 Project structure:', project.length, 'modules');

      await evalLuaCode(processId, executable, options.wait, wallet);
    } catch (error) {
      console.error('❌ Error:', error.message);
      process.exit(1);
    }
  });

// Parse CLI arguments
program.parse();

// Now we can check both CLI options and environment variables
function getConnectionInfo() {
  // Check for mainnet mode (CLI param takes priority over env var)
  const cliMainnet = program.opts().mainnet;
  const cliUrl = program.opts().url;
  const envAoUrl = process.env.AO_URL;

  // Handle --url parameter (AOS compatibility)
  if (cliUrl) {
    process.env.AO_URL = cliUrl;
    console.log('🌐 Using AO URL from --url parameter:', cliUrl);
    return {
      MODE: 'mainnet',
      URL: cliUrl,
      GATEWAY_URL: process.env.GATEWAY_URL
    };
  }

  const mainnetUrl = cliMainnet || envAoUrl;

  if (mainnetUrl) {
    // Mainnet mode - determine URL from CLI param or env var
    let finalUrl = mainnetUrl;

    // If --mainnet is provided without URL (true), use default mainnet URL
    if (cliMainnet === true) {
      finalUrl = 'https://forward.computer';
    }

    console.log('🌐 Using Mainnet mode with AO URL:', finalUrl);
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
      CU_URL: process.env.CU_URL || 'https://cu.ao-testnet.xyz',
      MU_URL: process.env.MU_URL || 'https://mu.ao-testnet.xyz'
    };
  }
}
