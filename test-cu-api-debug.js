#!/usr/bin/env node

// CU API Debug Script - 详细检查进程结果历史
// 用于诊断为什么trace功能只能找到系统输出而找不到Handler print输出

const fs = require('fs');
const path = require('path');

// 默认配置（从ao-cli.js复制）
const DEFAULT_CU_URL = 'https://cu6.ao-testnet.xyz';

// 读取版本
let version = '1.0.0';
try {
  const packageJson = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8'));
  version = packageJson.version;
} catch (e) {
  console.error('⚠️ Could not read version:', version);
}

// 解析命令行参数
const args = process.argv.slice(2);
if (args.length < 1) {
  console.log('用法: node test-cu-api-debug.js <processId> [limit]');
  console.log('示例: node test-cu-api-debug.js G8XryOcdv-AcyPMJa7wQ1IHbEvfmhGEDENnI6qe8U_U 20');
  process.exit(1);
}

const processId = args[0];
const limit = parseInt(args[1]) || 50;

console.log(`🔍 CU API 调试脚本 v${version}`);
console.log(`🎯 目标进程: ${processId}`);
console.log(`📊 查询限制: ${limit} 条记录`);
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

async function queryProcessResults(processId, limit = 10) {
  const cuUrl = process.env.CU_URL || DEFAULT_CU_URL;
  const url = `${cuUrl}/results/${processId}?limit=${limit}&sort=DESC`;

  console.log(`🌐 CU API URL: ${url}`);
  console.log(`⏳ 正在查询...\n`);

  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      },
      redirect: 'follow'
    });

    if (!response.ok) {
      throw new Error(`CU API request failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    return data;
  } catch (error) {
    console.error(`❌ 查询失败: ${error.message}`);
    return null;
  }
}

function analyzeResult(result, index) {
  console.log(`📋 结果 #${index + 1}:`);
  console.log(`   🆔 消息ID: ${result.id || 'N/A'}`);
  console.log(`   📅 时间戳: ${new Date(result.timestamp || 0).toISOString()}`);
  console.log(`   ⛽ Gas消耗: ${result.gasUsed || 'N/A'}`);

  // 分析Messages (注意：实际API返回的是大写的 Messages)
  if (result.Messages && Array.isArray(result.Messages) && result.Messages.length > 0) {
    console.log(`   📨 消息数量: ${result.Messages.length}`);
    result.Messages.forEach((msg, msgIdx) => {
      console.log(`      ${msgIdx + 1}. 目标: ${msg.Target || 'N/A'}`);
      if (msg.Tags && Array.isArray(msg.Tags)) {
        // 检查所有标签，特别是X-Reference
        const referenceTag = msg.Tags.find(tag => tag.name === 'Reference');
        const xReferenceTag = msg.Tags.find(tag => tag.name === 'X-Reference');
        const actionTag = msg.Tags.find(tag => tag.name === 'Action');

        if (referenceTag) {
          console.log(`         🔗 Reference: ${referenceTag.value}`);
        }
        if (xReferenceTag) {
          console.log(`         🔗 X-Reference: ${xReferenceTag.value}`);
        }
        if (actionTag) {
          console.log(`         🎬 Action: ${actionTag.value}`);
        }

        // 如果有其他相关标签也显示出来
        const otherTags = msg.Tags.filter(tag =>
          !['Reference', 'X-Reference', 'Action', 'Data-Protocol', 'Variant', 'Type'].includes(tag.name)
        );
        if (otherTags.length > 0) {
          console.log(`         📋 其他标签:`);
          otherTags.forEach(tag => {
            console.log(`            ${tag.name}: ${tag.value}`);
          });
        }
      }
    });
  } else {
    console.log(`   📨 消息数量: 0`);
  }

  // 分析Output (注意：实际API返回的是大写的 Output)
  if (result.Output) {
    console.log(`   📤 Output存在: 是`);
    if (result.Output.data) {
      console.log(`   📄 Output.data类型: ${typeof result.Output.data}`);
      console.log(`   📏 Output.data长度: ${result.Output.data.length} 字符`);

      // 详细分析data内容
      let dataContent = result.Output.data;
      if (typeof dataContent === 'string') {
        console.log(`   📝 Output.data内容 (前500字符):`);
        console.log(`   ┌─────────────────────────────────────────────────────────────┐`);
        const lines = dataContent.substring(0, 500).split('\n');
        lines.forEach((line, idx) => {
          const displayLine = line.length > 80 ? line.substring(0, 80) + '...' : line;
          console.log(`   │ ${displayLine}`);
        });
        if (dataContent.length > 500) {
          console.log(`   │ ... (${dataContent.length - 500} 更多字符)`);
        }
        console.log(`   └─────────────────────────────────────────────────────────────┘`);

        // 分析内容特征
        console.log(`   🔍 内容特征分析:`);
        console.log(`      • 包含 "function: 0x": ${dataContent.includes('function: 0x')}`);
        console.log(`      • 包含 "output": ${dataContent.includes('output')}`);
        console.log(`      • 包含 "Message added to outbox": ${dataContent.includes('Message added to outbox')}`);
        console.log(`      • 包含 "🎯": ${dataContent.includes('🎯')}`);
        console.log(`      • 包含 "📨": ${dataContent.includes('📨')}`);
        console.log(`      • 包含 "Trace测试消息": ${dataContent.includes('Trace测试消息')}`);
        console.log(`      • 包含 "接收进程": ${dataContent.includes('接收进程')}`);
        console.log(`      • 包含 "Handler": ${dataContent.includes('Handler') || dataContent.includes('handler')}`);

        // 清理ANSI代码后重新分析
        const cleanData = dataContent.replace(/\u001b\[[0-9;]*m/g, '');
        if (cleanData !== dataContent) {
          console.log(`   🎨 检测到ANSI颜色代码，已清理`);
          console.log(`   🔍 清理后特征:`);
          console.log(`      • 包含 "function: 0x": ${cleanData.includes('function: 0x')}`);
          console.log(`      • 包含 "output": ${cleanData.includes('output')}`);
          console.log(`      • 包含 "Message added to outbox": ${cleanData.includes('Message added to outbox')}`);
        }
      } else {
        console.log(`   📄 Output.data内容: ${JSON.stringify(dataContent, null, 2)}`);
      }
    } else {
      console.log(`   📄 Output.data: 空`);
    }

    if (result.Output.prompt) {
      console.log(`   💬 Output.prompt: ${result.Output.prompt}`);
    }
  } else {
    console.log(`   📤 Output存在: 否`);
  }

  // 分析Error
  if (result.Error) {
    console.log(`   ❌ Error: ${result.Error}`);
  }

  console.log('');
}

async function main() {
  console.log(`🔍 开始调试进程 ${processId} 的CU API结果...\n`);

  const results = await queryProcessResults(processId, limit);

  if (!results) {
    console.log('❌ 无法获取结果数据');
    return;
  }

  console.log(`📊 查询成功！返回数据结构:`);
  console.log(`   • 类型: ${typeof results}`);
  console.log(`   • 有edges字段: ${results.edges ? '是' : '否'}`);
  console.log(`   • edges长度: ${results.edges ? results.edges.length : 'N/A'}`);
  console.log(`   🔍 原始JSON响应 (前1000字符):`);
  console.log(JSON.stringify(results, null, 2).substring(0, 1000) + (JSON.stringify(results, null, 2).length > 1000 ? '\n... (truncated)' : ''));
  console.log('');

  if (!results.edges || !Array.isArray(results.edges) || results.edges.length === 0) {
    console.log('⚠️ 没有找到任何结果记录');
    return;
  }

  console.log(`📈 详细分析 ${results.edges.length} 条结果记录:\n`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  results.edges.forEach((edge, index) => {
    if (edge && edge.node) {
      analyzeResult(edge.node, index);
    } else {
      console.log(`❌ 结果 #${index + 1}: 数据结构异常`);
      console.log(`   原始数据: ${JSON.stringify(edge, null, 2)}\n`);
    }
  });

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🎯 调试完成！');
  console.log('');
  console.log('💡 分析要点:');
  console.log('   • 检查是否有非系统输出的结果（包含实际业务内容的print）');
  console.log('   • 注意Reference标签是否与trace查询匹配');
  console.log('   • 观察Output.data是否包含预期的Handler输出');
  console.log('   • 确认是否有ANSI颜色代码影响内容识别');
}

main().catch(error => {
  console.error('💥 脚本执行失败:', error);
  process.exit(1);
});
