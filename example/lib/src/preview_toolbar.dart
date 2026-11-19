/// 工具栏：两个档位开关 —— 看哪种文档、用哪一档主题。
///
/// 这里只管「读者按了哪个档」，位置定格、重新提交都在宿主侧（见 `main.dart`）：
/// 换档要不要先记下当前位置，是位置语义的一部分，不是控件的事。
library;

import 'package:flutter/material.dart';
import 'package:hyperlens/hyperlens.dart';

/// 演示用的三档主题：颜色与字号都由调用方给，包里只有「不给也能看」的预设。
const List<({String label, HyperlensTheme theme})> demoThemes =
    <({String label, HyperlensTheme theme})>[
  (label: 'Light', theme: HyperlensTheme.light),
  (label: 'Dark', theme: HyperlensTheme.dark),
  (label: 'Ink', theme: HyperlensTheme.ink),
];

/// 文档档位 + 主题档位。
class PreviewToolbar extends StatelessWidget {
  const PreviewToolbar({
    super.key,
    required this.kind,
    required this.themeIndex,
    required this.onKindChanged,
    required this.onThemeChanged,
  });

  /// 当前选中的文档档位（提交时要等渲染回来，但选中态跟手）。
  final PreviewSourceKind kind;

  /// 当前主题在 [demoThemes] 里的下标。
  final int themeIndex;

  final ValueChanged<PreviewSourceKind> onKindChanged;
  final ValueChanged<int> onThemeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SegmentedButton<PreviewSourceKind>(
            segments: const <ButtonSegment<PreviewSourceKind>>[
              ButtonSegment<PreviewSourceKind>(
                value: PreviewSourceKind.markdown,
                label: Text('Markdown'),
              ),
              ButtonSegment<PreviewSourceKind>(
                value: PreviewSourceKind.html,
                label: Text('HTML'),
              ),
            ],
            selected: <PreviewSourceKind>{kind},
            onSelectionChanged: (Set<PreviewSourceKind> value) {
              final PreviewSourceKind next = value.first;
              if (next != kind) {
                onKindChanged(next);
              }
            },
          ),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (int i = 0; i < demoThemes.length; i++)
                ButtonSegment<int>(value: i, label: Text(demoThemes[i].label)),
            ],
            selected: <int>{themeIndex},
            onSelectionChanged: (Set<int> value) => onThemeChanged(value.first),
          ),
        ],
      ),
    );
  }
}
