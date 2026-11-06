// 一段对话的累计用量：输入 / 输出 / 缓存读 / 缓存写。
//
// 数据来源是**已经加载进内存的会话事件**——主机的 `assistant/message` 事件里带
// `data.usage`（`AssistantMessageEvent.usage`），网页版「性能与用量」看的就是这些。
// 所以不需要额外请求：翻到哪、算到哪，live 回合也会随事件进来。

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_state.dart';

@immutable
class SessionUsage {
  const SessionUsage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.turns = 0,
  });

  /// 未命中缓存的输入。
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  /// 有 usage 的助手消息条数，用来判断"到底有没有数据"。
  final int turns;

  bool get isEmpty => input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0;

  /// 计费输入 = 未缓存 + 缓存读 + 缓存写。
  int get billedInput => input + cacheRead + cacheWrite;

  /// 缓存命中率（0–100）。没有输入时算 0。
  double get cacheHit => billedInput == 0 ? 0 : cacheRead / billedInput * 100;
}

/// 从会话事件里累加 usage。事件变多（翻到更早的、或新回合到达）就自动重算。
final sessionUsageProvider = Provider.autoDispose.family<SessionUsage, String>((ref, sessionId) {
  // 事件保存在 controller 上（ChatState 不直接暴露），所以监听状态变化，
  // 再由 controller 取一遍事件——新回合、翻历史都会改变状态。
  ref.watch(chatProvider(sessionId));
  final events = ref.read(chatProvider(sessionId).notifier).events;
  var input = 0, output = 0, cacheRead = 0, cacheWrite = 0, turns = 0;
  for (final event in events) {
    if (event is! AssistantMessageEvent) continue;
    final usage = event.usage;
    if (usage == null) continue;
    input += usage.inputTokens.toInt();
    output += usage.outputTokens.toInt();
    cacheRead += (usage.cacheReadTokens ?? 0).toInt();
    cacheWrite += (usage.cacheWriteTokens ?? 0).toInt();
    turns++;
  }
  return SessionUsage(
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    turns: turns,
  );
});
