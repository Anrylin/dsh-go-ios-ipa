// 输入框下面那一行：本次对话累计的 ↑输入 ↓输出 · 缓存率 · 当前（或最后一次）tok/s。
// 居中显示；没有数据时整行不占位。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../state/run_pulse.dart';
import '../../../state/session_usage.dart';
import '../../../state/token_usage.dart' show formatTokens;
import '../../theme/theme.dart';

class SessionStatsLine extends ConsumerWidget {
  const SessionStatsLine({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pulse = ref.watch(runPulseProvider(sessionId));
    // 整段对话的累计（含翻出来的历史）：主机的 assistant/message 事件里带 usage。
    final usage = ref.watch(sessionUsageProvider(sessionId));
    return ListenableBuilder(
      listenable: pulse,
      builder: (context, _) {
        // 历史里有就用历史的；还没落盘（正在跑第一步）就用本次运行的累计兜着。
        final input = usage.isEmpty ? pulse.sessionInput : usage.input;
        final output = usage.isEmpty ? pulse.sessionOutput : usage.output;
        final cacheRead = usage.isEmpty ? pulse.sessionCacheRead : usage.cacheRead;
        final cacheWrite = usage.isEmpty ? pulse.sessionCacheWrite : usage.cacheWrite;
        final speed = pulse.displayTps;
        // 一点数据都没有：不占位。
        if (input == 0 && output == 0 && speed <= 0) return const SizedBox.shrink();

        // 缓存率：缓存读 / 计费输入（未缓存 + 缓存读 + 缓存写）。
        final billed = input + cacheRead + cacheWrite;
        final hit = billed > 0 ? cacheRead / billed * 100 : 0.0;

        final theme = Theme.of(context);
        final colors = DshColors.of(context);
        final l10n = context.l10n;
        final parts = <String>[
          '↑${formatTokens(input)}',
          '↓${formatTokens(output)}',
          if (billed > 0) '${l10n.statsCache} ${hit.toStringAsFixed(hit >= 10 ? 0 : 1)}%',
          if (speed > 0) '${speed.toStringAsFixed(speed < 10 ? 1 : 0)} tok/s',
        ];
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Center(
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppType.tabular(
                theme.textTheme.bodySmall!.copyWith(color: colors.textTertiary),
              ),
            ),
          ),
        );
      },
    );
  }
}
