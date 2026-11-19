/// 语法树弹层：节点按层级摊平，一行一个。
///
/// 绑的是 [ValueNotifier]：点开弹层时才发出「要完整树」的命令，回执往往在弹层
/// 已经建好之后才到 —— 用 [ValueListenableBuilder] 才能就地刷新。
library;

import 'package:flutter/material.dart';
import 'package:hyperlens/hyperlens.dart';

class SyntaxSheet extends StatelessWidget {
  const SyntaxSheet({super.key, required this.syntax});

  final ValueNotifier<PreviewSyntaxTree?> syntax;

  /// 一次最多列这么多行：完整树可以有几千个节点，弹层不是给「逐条读完」用的。
  static const int _maxRows = 300;

  /// 最多缩进这么多层：再深的嵌套靠「地址里的路径」表达，不靠空白。
  static const int _maxIndent = 8;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<PreviewSyntaxTree?>(
      valueListenable: syntax,
      builder: (BuildContext context, PreviewSyntaxTree? tree, Widget? _) {
        final List<(int, PreviewSyntaxNode)> rows =
            _flatten(tree?.nodes ?? const <PreviewSyntaxNode>[]);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tree == null
                      ? "No syntax tree yet: it arrives with the page's ast receipt"
                      : '${tree.kind.wireName}: ${tree.count} nodes'
                          '${tree.truncated ? ' (truncated)' : ''}'
                          '${tree.issues.isEmpty ? '' : ', ${tree.issues.length} issue${tree.issues.length == 1 ? '' : 's'}'}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'The first one is the skeleton; this is the full tree pulled by '
                  'HyperlensCommands.requestSyntaxAst().',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No nodes')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount:
                              rows.length > _maxRows ? _maxRows : rows.length,
                          itemBuilder: (BuildContext context, int index) {
                            final (int depth, PreviewSyntaxNode node) =
                                rows[index];
                            return _row(theme, depth, node);
                          },
                        ),
                ),
                if (rows.length > _maxRows)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      // 行数不写「of N」：摊平有上限（见 _flatten），那个 N 是截断后的
                      // 行数，说成总数会让人以为树被吃掉了 —— 真值在标题的节点数里。
                      '(showing first $_maxRows rows — the tree has ${tree?.count ?? 0} nodes)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 一行一个节点：地址在前（等宽、次要色），文本在后。
  ///
  /// 两段塞进**同一个** `Text` 而不是 Row 的两个子项：地址一栏在 HTML 里是
  /// `body>math>:nth(1)>mfrac>:nth(1)>…` 这种长 DOM 路径，占固定比例会把文本栏压窄，
  /// 不占比例又会直接撑破整行（就是那条黄黑条纹）。合成一段后省略发生在行尾，
  /// 短地址也不会白占宽度。
  Widget _row(ThemeData theme, int depth, PreviewSyntaxNode node) {
    final String where = node.line == null
        ? (node.path ?? '')
        : (node.endLine == null || node.endLine == node.line
            ? 'L${node.line}'
            : 'L${node.line}-${node.endLine}');
    final String label = <String>[
      node.type,
      if (node.level > 0) 'h${node.level}',
      if (node.lang != null) node.lang!,
      if (where.isNotEmpty) _tail(where),
    ].join('  ');
    final TextStyle? body = theme.textTheme.bodySmall;
    return Padding(
      // 缩进按层数无限长的话，MathML 那种十几层嵌套会让整行没有可用宽度。
      padding: EdgeInsets.only(
        left: (depth > _maxIndent ? _maxIndent : depth) * 10.0,
        top: 1,
        bottom: 1,
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label  ',
              style: body?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: node.text, style: body),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 长地址只留尾巴（`…>mrow:nth(1)>mi:nth(1)`）。
  ///
  /// HTML 的地址是 DOM 路径，深层节点前半段几十行完全一样；原样显示会把这一行的
  /// 节点文本挤成省略号 —— 树的意义正好丢在最深的那几层。Markdown 的 `L42` 够短，
  /// 原样返回。
  static String _tail(String address) {
    // 放得下就原样（`body>svg:nth(1)>line:nth(1)` 这类浅层地址不该被动），
    // 放不下才收到尾巴，把宽度留给节点文本。
    const int full = 28;
    const int keep = 20;
    if (address.length <= full) {
      return address;
    }
    String tail = address.substring(address.length - keep);
    // 从中间截会切在 `>` 上：往后挪到下一段开头，别留半截标签名。
    final int cut = tail.indexOf('>');
    if (cut >= 0 && cut + 1 < tail.length) {
      tail = tail.substring(cut + 1);
    }
    return '…>$tail';
  }

  /// 深度优先摊平：(层级, 节点)。
  static List<(int, PreviewSyntaxNode)> _flatten(
    List<PreviewSyntaxNode> nodes, [
    int depth = 0,
  ]) {
    final List<(int, PreviewSyntaxNode)> out = <(int, PreviewSyntaxNode)>[];
    for (final PreviewSyntaxNode node in nodes) {
      out.add((depth, node));
      if (node.children.isNotEmpty) {
        // 超过 _maxRows 就不再往下走：完整树可能有几千个节点，摊完只为显示 300 行不值。
        if (out.length >= _maxRows * 4) {
          return out;
        }
        out.addAll(_flatten(node.children, depth + 1));
      }
    }
    return out;
  }
}
