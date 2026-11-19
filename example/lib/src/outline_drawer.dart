/// 目录抽屉：`outline` 回执给的那份清单。
///
/// 层级只影响缩进 —— 清单本身不折叠，折叠是宿主的 UI 选择。点击只把条目交回去，
/// 「先定格当前位置再跳」那一步在宿主侧（见 `main.dart` 的 `_jumpTo`）。
library;

import 'package:flutter/material.dart';
import 'package:hyperlens/hyperlens.dart';

class OutlineDrawer extends StatelessWidget {
  const OutlineDrawer({super.key, required this.outline, required this.onTap});

  final PreviewOutline outline;

  final ValueChanged<PreviewOutlineEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: outline.isEmpty
            ? const Center(child: Text('No outline yet'))
            : ListView(
                children: <Widget>[
                  for (final PreviewOutlineEntry entry in outline.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(
                        left: 16 + (entry.level - 1) * 16.0,
                        right: 16,
                      ),
                      title: Text(
                        entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${entry.address}'),
                      onTap: () => onTap(entry),
                    ),
                ],
              ),
      ),
    );
  }
}
