import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlens/src/model/preview_syntax.dart';

/// 语法树模型（`preview_syntax.dart`）。
///
/// 这一层只有「解析 + 闸门 + 序列化」，没有解析器：树由页面侧收集
/// （方案 §4.5 / §4.6），Dart 侧只负责把一条回执变成可用的结构。
void main() {
  group('解析骨架载荷', () {
    test('数组载荷（模板最早发的形态）：Markdown 顶层块 + 行范围', () {
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<Object?>[
        <String, Object?>{'type': 'heading', 'line': 1, 'level': 1, 'text': '标题'},
        <String, Object?>{
          'type': 'code',
          'line': 3,
          'endLine': 8,
          'lang': 'dart',
          'text': 'void main() {}',
        },
      ]);

      expect(tree.kind, PreviewSourceKind.markdown);
      expect(tree.version, PreviewSyntaxTree.currentVersion);
      expect(tree.truncated, isFalse);
      expect(tree.nodes, hasLength(2));
      expect(tree.nodes.first.isHeading, isTrue);
      expect(tree.nodes.first.level, 1);
      expect(tree.nodes.last.lang, 'dart');
      expect(tree.nodes.last.endLine, 8);
      expect(tree.count, 2);
    });

    test('对象载荷：带 kind 的 HTML 树，用 path 不用行号', () {
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<String, Object?>{
        'kind': 'html',
        'version': 1,
        'nodeCount': 42,
        'truncated': true,
        'nodes': <Object?>[
          <String, Object?>{
            'type': 'h2',
            'path': 'body>main>h2:nth(2)',
            'level': 2,
            'text': '第二节',
          },
        ],
      });

      expect(tree.kind, PreviewSourceKind.html);
      expect(tree.truncated, isTrue);
      expect(tree.nodeCount, 42, reason: '载荷给了 nodeCount 就用它（未截断前的真实值）');
      expect(tree.count, 42);
      expect(tree.nodes.single.path, 'body>main>h2:nth(2)');
      expect(tree.nodes.single.line, isNull, reason: 'HTML 没有可换算的行号');
    });

    test('认不出的载荷：空树，不抛（这条路径挨着「是否渲染成功」）', () {
      expect(PreviewSyntaxTree.parse('{不是 json').isEmpty, isTrue);
      expect(PreviewSyntaxTree.parse(42).isEmpty, isTrue);
      expect(PreviewSyntaxTree.parse(null).isEmpty, isTrue);
    });

    test('单条坏节点丢掉那一条，不影响整棵树', () {
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<Object?>[
        <String, Object?>{'type': 'paragraph', 'text': '好的一条'},
        <String, Object?>{'text': '没有 type'},
        'not a map',
        <String, Object?>{'type': 'hr', 'line': 9},
      ]);

      expect(tree.nodes, hasLength(2));
      expect(tree.nodes.last.type, 'hr');
    });
  });

  group('闸门', () {
    test('文本超过上限就截断并补省略号', () {
      final String long = '字' * (PreviewSyntaxLimits.maxTextLength + 40);
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<Object?>[
        <String, Object?>{'type': 'paragraph', 'text': long},
      ]);

      final String text = tree.nodes.single.text;
      expect(text.length, PreviewSyntaxLimits.maxTextLength + 1);
      expect(text.endsWith('…'), isTrue);
    });

    test('深度超过上限：停止下钻，整棵树标记为截断', () {
      // 9 层：第 8 层之后不再下钻（列表套列表的极端情况）
      Map<String, Object?> node = <String, Object?>{'type': 'leaf', 'text': '最深'};
      for (int i = 0; i < 10; i++) {
        node = <String, Object?>{
          'type': 'list',
          'children': <Object?>[node],
        };
      }
      final PreviewSyntaxTree tree =
          PreviewSyntaxTree.parse(<Object?>[node]);

      expect(tree.truncated, isTrue);
      // 数一下实际下钻了几层：不超过 maxDepth
      int depth = 0;
      PreviewSyntaxNode cursor = tree.nodes.single;
      while (cursor.children.isNotEmpty) {
        cursor = cursor.children.single;
        depth += 1;
      }
      expect(depth, lessThan(PreviewSyntaxLimits.maxDepth));
    });

    test('节点数超过上限：停止收集并标记截断', () {
      final List<Object?> many = List<Object?>.generate(
        PreviewSyntaxLimits.maxNodes + 10,
        (int i) => <String, Object?>{'type': 'p'},
      );
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(many);

      expect(tree.truncated, isTrue);
      expect(tree.nodes.length, lessThanOrEqualTo(PreviewSyntaxLimits.maxNodes));
    });
  });

  group('问题清单', () {
    test('页面声明的问题在前，解析侧补的在后', () {
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<String, Object?>{
        'kind': 'markdown',
        'issues': <Object?>[
          <String, Object?>{
            'kind': 'unclosedFence',
            'line': 12,
            'detail': '围栏 ``` 没闭合',
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'type': 'futureBlock', 'line': 3},
        ],
      });

      expect(tree.issues, hasLength(2));
      expect(tree.issues.first.kind, PreviewSyntaxIssueKind.unclosedFence);
      expect(tree.issues.first.detail, '围栏 ``` 没闭合',
          reason: '页面侧的细节是它那边才有的，不能被解析侧覆盖');
      expect(tree.issues.last.kind, PreviewSyntaxIssueKind.unknownNodeType);
      expect(tree.issues.last.line, 3);
      expect(tree.issues.last.detail, 'futureBlock');
    });

    test('认不出种类的问题丢掉那一条，不影响别的', () {
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<String, Object?>{
        'kind': 'markdown',
        'issues': <Object?>[
          <String, Object?>{'kind': '还没发明的种类', 'line': 1},
          <String, Object?>{'kind': 'tableColumnMismatch', 'line': 4},
          'not a map',
        ],
        'nodes': <Object?>[<String, Object?>{'type': 'hr', 'line': 1}],
      });

      expect(tree.issues, hasLength(1));
      expect(tree.issues.single.kind, PreviewSyntaxIssueKind.tableColumnMismatch);
      expect(tree.issues.single.line, 4);
    });

    test('未知类型按类型去重：同一个 type 报一次就够', () {
      final PreviewSyntaxTree tree =
          PreviewSyntaxTree.parse(<Object?>[
        <String, Object?>{'type': 'futureBlock', 'line': 2},
        <String, Object?>{'type': 'futureBlock', 'line': 9},
        <String, Object?>{'type': 'anotherFuture', 'line': 10},
      ]);

      expect(tree.issues, hasLength(2));
      expect(tree.issues.first.line, 2, reason: '落在第一次出现的地方');
      expect(tree.issues.last.detail, 'anotherFuture');
    });

    test('HTML 不查 Markdown 白名单（标签名本来就不在表里）', () {
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(<String, Object?>{
        'kind': 'html',
        'nodes': <Object?>[
          <String, Object?>{'type': 'h2', 'path': 'body>h2:nth(1)'},
          <String, Object?>{'type': 'my-widget', 'path': 'body>my-widget'},
        ],
      });

      expect(tree.issues, isEmpty);
    });

    test('问题条数有上限：被改坏的载荷不该让面板滚三屏', () {
      final List<Object?> many = List<Object?>.generate(
        80,
        (int i) => <String, Object?>{'type': 'future$i', 'line': i + 1},
      );
      final PreviewSyntaxTree tree = PreviewSyntaxTree.parse(many);

      expect(tree.issues, hasLength(50));
    });

    test('mergeIssues：同一处同一个问题不重复，其余追加', () {
      const PreviewSyntaxTree tree = PreviewSyntaxTree(
        kind: PreviewSourceKind.html,
        issues: <PreviewSyntaxIssue>[
          PreviewSyntaxIssue(
            kind: PreviewSyntaxIssueKind.unclosedTag,
            line: 3,
            detail: '<span> 没有闭合',
          ),
        ],
      );

      final PreviewSyntaxTree merged = tree.mergeIssues(
        <PreviewSyntaxIssue>[
          const PreviewSyntaxIssue(
            kind: PreviewSyntaxIssueKind.unclosedTag,
            line: 3,
            detail: '重复的一条',
          ),
          const PreviewSyntaxIssue(
            kind: PreviewSyntaxIssueKind.unclosedTag,
            line: 7,
          ),
        ],
      );

      expect(merged.issues, hasLength(2));
      expect(merged.issues.first.detail, '<span> 没有闭合');
      expect(merged.issues.last.line, 7);
    });
  });

  group('序列化', () {
    test('空值省略：1000 个节点不该每个都带 null 字段', () {
      const PreviewSyntaxNode node = PreviewSyntaxNode(type: 'hr');
      expect(node.toJson(), <String, Object?>{'type': 'hr'});
    });

    test('往返一致：toJson 之后再 parse，结构与层级不丢', () {
      const PreviewSyntaxTree original = PreviewSyntaxTree(
        kind: PreviewSourceKind.markdown,
        nodes: <PreviewSyntaxNode>[
          PreviewSyntaxNode(
            type: 'list',
            line: 2,
            children: <PreviewSyntaxNode>[
              PreviewSyntaxNode(type: 'list_item', line: 3, text: '一条'),
            ],
          ),
        ],
      );

      final PreviewSyntaxTree parsed =
          PreviewSyntaxTree.parse(original.toJson());

      expect(parsed.kind, original.kind);
      expect(parsed.nodes.single.type, 'list');
      expect(parsed.nodes.single.children.single.text, '一条');
      expect(parsed.count, 2);
    });
  });
}
