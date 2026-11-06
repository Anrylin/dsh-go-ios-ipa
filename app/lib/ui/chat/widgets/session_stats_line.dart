// 输入框下面那一行：本次对话累计的 ↑输入 ↓输出 · 缓存率 · 当前（或最后一次）tok/s。
// 居中显示；没有数据时整行不占位。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../state/run_pulse.dart';
import '../../../state/usage_state.dart';
import '../../../state/token_usage.dart' show formatTokens;
import '../../theme/theme.dart';

class SessionStatsLine extends ConsumerWidget {
  const SessionStatsLine({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pulse = ref.watch(runPulseProvider(sessionId));
    // 整段对话的累计：用主机的 DSH 投影（`tokenUsage`）——用量面板显示的就是它，
    // 所以两处数字一致。自己累加事件只会算到"已加载的部分"，对不上。
    final usage = ref.watch(sessionUsageProvider(sessionId));
    return ListenableBuilder(
      listenable: pulse,
      builder: (context, _) {
        // 输入按"计费输入"算：未缓存 + 缓存读 + 缓存写，和用量面板一致。
        final billed = usage.uncachedInput + usage.cacheRead + usage.cacheWrite;
        final output = usage.output;
        final cacheRead = usage.cacheRead;
        final speed = pulse.displayTps;
        // 投影还没到（刚打开）时用本次运行的累计兜着。
        final input = billed > 0 ? billed : pulse.sessionInput;
        final out = output > 0 ? output : pulse.sessionOutput;
        if (input == 0 && out == 0 && speed <= 0) return const SizedBox.shrink();

        // 缓存率：缓存读 / 计费输入。
        final hit = input > 0 ? cacheRead / input * 100 : 0.0;

        final theme = Theme.of(context);
        final colors = DshColors.of(context);
        final l10n = context.l10n;
        final parts = <String>[
          '↑${formatTokens(input)}',
          '↓${formatTokens(out)}',
          if (input > 0) '${l10n.statsCache} ${hit.toStringAsFixed(hit >= 10 ? 0 : 1)}%',
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
