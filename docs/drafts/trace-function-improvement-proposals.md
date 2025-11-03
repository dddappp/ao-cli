# AO CLI Trace功能改进方案

## 现状分析

### 🎯 核心发现：通信模式决定Reference分配策略

基于重新分析，我们发现了Trace功能的关键问题：**Reference分配策略取决于通信模式**！

#### Reference重用策略差异
**双进程通信**（我们的成功测试）：
- 发送消息：获得Reference=N
- 响应消息：**重用Reference=N**（碰巧相等）
- Trace查询Reference=N：直接获得Handler输出 ✅

**单进程通信**（用户的失败用例）：
- 发送消息：获得Reference=N
- 响应消息：获得Reference=N+1（递增）
- Trace查询Reference=N：获得系统输出，需要扩展查找Reference=N+1 ❌

#### 技术问题
CU API记录了完整的消息处理历史，但Trace的查找逻辑没有考虑通信模式的差异：

- **查找策略单一**：只查找原始Reference，没有根据通信模式调整
- **双进程场景简单**：接收进程直接获得业务Reference
- **单进程场景复杂**：需要查找递增的Reference序列

## 问题根因

### 当前实现
```javascript
const hasMatchingReference = edge.node.Messages.some(msg =>
  msg.Tags && msg.Tags.some(tag =>
    tag.name === 'Reference' && tag.value === messageReference
  )
);
```

### 实际消息链
- 发送消息：`Reference: 8` (系统记录)
- Handler处理：`Reference: 9` (业务记录)
- 响应消息：可能有更多Reference

## 改进方案

### Scheme 1: 扩展Reference范围匹配

#### 实现思路
查找发送Reference及其相关Reference范围内的消息。

#### 代码实现
```javascript
function findRelatedMessages(messageReference, edges) {
  const baseRef = parseInt(messageReference);
  const relatedRefs = [
    baseRef,        // 原始Reference
    baseRef + 1,    // 下一个Reference (常见于Handler处理)
    baseRef - 1,    // 上一个Reference (边界情况)
    baseRef + 2,    // 更远的关联
  ];

  return edges.filter(edge => {
    if (!edge.node?.Messages) return false;

    return edge.node.Messages.some(msg => {
      const refTag = msg.Tags?.find(tag => tag.name === 'Reference');
      if (!refTag) return false;

      const msgRef = parseInt(refTag.value);
      return relatedRefs.includes(msgRef);
    });
  });
}
```

#### 优势
- 覆盖常见的Reference递增模式
- 实现简单，逻辑清晰
- 向后兼容现有功能

#### 劣势
- 可能匹配到不相关的消息
- Reference递增不保证业务关联

### Scheme 2: 时间窗口关联

#### 实现思路
基于时间戳关联发送消息前后一段时间内的所有相关消息。

#### 代码实现
```javascript
function findTimeRelatedMessages(evalTimestamp, edges, windowMs = 120000) {
  return edges.filter(edge => {
    // 提取记录的时间戳 (从cursor或Output中解析)
    const recordTimestamp = extractTimestampFromEdge(edge);
    const timeDiff = Math.abs(recordTimestamp - evalTimestamp);

    return timeDiff <= windowMs;
  }).filter(edge => {
    // 进一步筛选：包含Handler相关输出的记录
    const outputData = edge.node?.Output?.data || '';
    return isLikelyHandlerOutput(outputData);
  });
}

function extractTimestampFromEdge(edge) {
  // 从cursor中提取时间戳
  // cursor格式: "eyJ0aW1lc3RhbXAiOjE3NjIxNDExMTIxNDAs...
  try {
    const decoded = JSON.parse(Buffer.from(edge.cursor, 'base64').toString());
    return decoded.timestamp;
  } catch (e) {
    return 0;
  }
}

function isLikelyHandlerOutput(outputData) {
  if (!outputData || typeof outputData !== 'string') return false;

  // 清理ANSI代码
  const cleanData = outputData.replace(/\u001b\[[0-9;]*m/g, '');

  // 排除已知的系统输出模式
  if (cleanData.includes('function: 0x') &&
      cleanData.includes('Message added to outbox')) {
    return false; // 明确是系统输出
  }

  // 检查业务输出特征（通用特征，避免硬编码特定应用内容）
  const hasBusinessFeatures = cleanData.length > 30 || // 内容较长
                              cleanData.split('\n').length > 1 || // 多行输出
                              /[\u{1F600}-\u{1F64F}]/u.test(cleanData) || // 包含emoji
                              /\p{Script=Han}/u.test(cleanData) || // 包含中文
                              cleanData.includes('Handler') || // 通用Handler标识
                              cleanData.includes('处理') || // 处理相关
                              /^\d+$/.test(cleanData) === false; // 不是纯数字（Inbox计数）

  return hasBusinessFeatures;
}
```

#### 优势
- 时间关联更准确
- 自动适应不同的Reference分配模式
- 能过滤掉明显不相关的记录

#### 劣势
- 时间窗口选择困难
- 需要解析时间戳，复杂度增加
- 可能受到时钟同步问题影响

### Scheme 3: 内容优先级排序

#### 实现思路
不依赖Reference匹配，而是对所有候选记录进行内容分析，按优先级排序。

#### 代码实现
```javascript
function rankAndSelectBestMatch(messageReference, edges, evalTimestamp) {
  const candidates = edges.map(edge => ({
    edge,
    score: calculateMatchScore(edge, messageReference, evalTimestamp)
  }));

  // 按分数排序
  candidates.sort((a, b) => b.score - a.score);

  return candidates[0]?.edge;
}

function calculateMatchScore(edge, messageReference, evalTimestamp) {
  let score = 0;
  const node = edge.node;
  if (!node?.Output?.data) return 0;

  const outputData = node.Output.data;
  const cleanData = outputData.replace(/\u001b\[[0-9;]*m/g, '');

  // Reference匹配度 (最高优先级)
  const refMatches = node.Messages?.filter(msg => {
    const refTag = msg.Tags?.find(tag => tag.name === 'Reference');
    return refTag && refTag.value === messageReference;
  }) || [];

  if (refMatches.length > 0) score += 100;

  // 时间接近度
  const recordTime = extractTimestampFromEdge(edge);
  const timeDiff = Math.abs(recordTime - evalTimestamp);
  if (timeDiff < 30000) score += 50;      // 30秒内
  else if (timeDiff < 120000) score += 30; // 2分钟内
  else if (timeDiff < 300000) score += 10; // 5分钟内

  // 内容质量评分
  if (cleanData.includes('Handler called')) score += 40;
  if (cleanData.includes('SET-NFT-TRANSFERABLE')) score += 35;
  if (cleanData.includes('MINT-NFT')) score += 35;
  if (cleanData.includes('Transfer completed')) score += 35;
  if (cleanData.includes('🎯') && cleanData.includes('✅')) score += 30;
  if (cleanData.length > 100) score += 20; // 详细输出
  if (!cleanData.includes('function: 0x')) score += 15; // 非系统输出
  if (!cleanData.includes('Message added to outbox')) score += 10;

  // 消息数量
  const msgCount = node.Messages?.length || 0;
  score += Math.min(msgCount * 5, 25);

  return score;
}
```

#### 优势
- 最智能的匹配方式
- 不依赖单一特征
- 能适应各种边缘情况

#### 劣势
- 实现复杂度高
- 评分算法需要调优
- 可能选错最优匹配

## 推荐实施方案

### Phase 1: 快速修复 (Scheme 1)
```javascript
// 在traceSentMessages函数中修改Reference匹配逻辑
const relatedRefs = [messageReference, (parseInt(messageReference) + 1).toString()];

// 查找所有相关Reference的记录
const matchingEdges = edges.filter(edge => {
  return edge.node?.Messages?.some(msg => {
    const refTag = msg.Tags?.find(tag => tag.name === 'Reference');
    return refTag && relatedRefs.includes(refTag.value);
  });
});

// 然后按内容质量排序选择最佳匹配
```

### Phase 2: 长期优化 (Scheme 3)
实现完整的评分系统，提供最准确的匹配结果。

## 测试策略

### 单元测试
```javascript
describe('Trace Message Matching', () => {
  test('should find related Reference messages', () => {
    // 测试Reference +1的匹配
  });

  test('should prefer Handler output over system output', () => {
    // 测试内容优先级
  });

  test('should handle time window filtering', () => {
    // 测试时间关联
  });
});
```

### 集成测试
- 使用已知结果的进程进行回归测试
- 测试不同类型的Handler输出
- 验证边界情况处理

## 改进策略

### 增强Reference关联查找

实现支持多种Reference关联关系的查找逻辑：

```javascript
function findTraceResults(baseReference, records) {
  const results = [];

  records.forEach(record => {
    const messages = record.node.Messages || [];

    messages.forEach(message => {
      const tags = message.Tags || [];
      let matchType = null;
      let matchScore = 0;

      // 1. 直接Reference匹配（最高优先级）
      const refTag = tags.find(t => t.name === 'Reference' && t.value === baseReference);
      if (refTag) {
        matchType = 'direct_reference';
        matchScore = 100;
      }

      // 2. X-Reference关联匹配（高优先级）
      const xRefTag = tags.find(t => t.name === 'X-Reference' && t.value === baseReference);
      if (xRefTag && !matchType) {
        matchType = 'x_reference';
        matchScore = 90;
      }

      // 3. 递增Reference匹配（中等优先级）
      const refTag2 = tags.find(t => t.name === 'Reference');
      if (refTag2 && !matchType) {
        const refNum = parseInt(refTag2.value);
        const baseNum = parseInt(baseReference);
        if (refNum > baseNum && refNum <= baseNum + 5) {
          matchType = 'incremental_reference';
          matchScore = 50 + (baseNum + 5 - refNum) * 5; // 越接近越优先
        }
      }

      if (matchType) {
        results.push({
          record,
          message,
          matchType,
          matchScore,
          output: record.node.Output?.data || ''
        });
      }
    });
  });

  // 按匹配分数排序
  return results.sort((a, b) => b.matchScore - a.matchScore);
}
```

### 输出质量评估和选择

对找到的记录进行质量排序，优先选择Handler输出：

```javascript
function selectBestTraceResult(records) {
  const scoredResults = records.map(record => ({
    record,
    score: rankOutputQuality(record)
  }));

  // 按质量分数排序（Handler > System > Other > Empty）
  scoredResults.sort((a, b) => b.score - a.score);

  return scoredResults[0]?.record;
}

function rankOutputQuality(record) {
  const output = record.node.Output?.data || '';

  // Handler业务输出（最高优先级）
  if (typeof output === 'string' && output.length > 50 &&
      !output.includes('function: 0x') &&
      !output.includes('Message added to outbox')) {
    return 100; // Handler output
  }

  // 系统输出（中等优先级）
  if (output.includes('Message added to outbox')) {
    return 50; // System output
  }

  // 其他输出（低优先级）
  if (typeof output === 'string' && output.trim()) {
    return 10; // Other content
  }

  // 空输出（最低优先级）
  return 0; // Empty
}
```

## 部署计划

1. **Phase 1**: 实现增强Reference关联查找（支持Reference、X-Reference、递增Reference）
2. **Phase 2**: 实现匹配结果评分和排序（Handler > System > Other优先级）
3. **Phase 3**: 优化时序处理（确保Handler处理完成后进行查询）
4. **测试验证**: 在各种通信模式和Reference关联场景下验证改进效果
5. **Phase 4**: 实现通信模式自适应（根据场景选择最优查找策略）
6. **性能优化**: 确保查询效率不受影响
7. **文档更新**: 更新Trace功能的使用说明和技术细节

---

*此方案基于实际调试数据制定，旨在解决CU API数据关联的核心问题。*
