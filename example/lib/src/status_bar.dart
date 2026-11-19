/// 页脚两行：上面是「此刻在哪」（最新一条回执），下面是「上次读到哪」（定格值）。
///
/// 两个值并排摆，读者滚来滚去只会让上面那行变，下面那行只在**离开阅读处**那一刻
/// 定格 —— 一眼就能看出这两个值不是一回事。
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:hyperlens/hyperlens.dart';

class PreviewStatusBar extends StatelessWidget {
  const PreviewStatusBar({
    super.key,
    required this.status,
    required this.bookmark,
  });

  /// 最新一条回执的文字。
  ///
  /// 用 [ValueListenable] 而不是整页 `setState`：位置回执**每滚停一次**就来一条，
  /// 重建整页没有意义。
  final ValueListenable<String> status;

  /// 这份文档定格的「上次位置」，没离开过就是 `null`。
  final PreviewPosition? bookmark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (BuildContext context, String value, Widget? _) => Text(
              value,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Last position: ${bookmark ?? 'none (never left)'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
