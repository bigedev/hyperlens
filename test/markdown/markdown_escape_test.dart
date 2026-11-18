import 'package:hyperlens/src/markdown/escape.dart';
import 'package:flutter_test/flutter_test.dart';

/// 转义美元符保护（`markdown_escape.dart`）。
///
/// 这条链路的失败形态很隐蔽：`\$x\$` 在 marked 解析后就是裸 `$x$`，模板那边
/// 分不清「作者要字面量」还是「作者要公式」，于是会被渲染成公式（2026-11-17
/// 真机走查发现）。所以这里钉三件事：正文要换、代码里不换、行数不能变。
void main() {
  test('正文里的 \$ 换成占位字符', () {
    expect(
      protectEscapedDollars(r'转义写法 \$x\$ 应原样显示。'),
      '转义写法 ${kEscapedDollarSentinel}x$kEscapedDollarSentinel 应原样显示。',
    );
  });

  test('没有 \$ 的文档原样返回（同一份内容，不做无谓改写）', () {
    const String md = '# 标题\n\n普通正文 \$ 只有一个美元符也没关系。';
    expect(protectEscapedDollars(md), md);
  });

  test('围栏代码块里保持原样', () {
    const String md = '```bash\necho "\\\$HOME"\n```\n';
    expect(protectEscapedDollars(md), md);
  });

  test('波浪线围栏同样保持原样', () {
    const String md = '~~~\n\\\$x\\\$\n~~~\n';
    expect(protectEscapedDollars(md), md);
  });

  test('行内代码里保持原样', () {
    const String md = '写作 `\\\$x\\\$` 即可。';
    expect(protectEscapedDollars(md), md);
  });

  test('双反引号包住的行内代码也保持原样', () {
    const String md = '写作 ``\\\$x\\\$`` 即可。';
    expect(protectEscapedDollars(md), md);
    expect(protectEscapedDollars(md).contains(kEscapedDollarSentinel), isFalse);
  });

  test('\\\$ 是「转义的反斜杠 + 美元」，不算被转义的美元符', () {
    const String md = r'a \\$ b';
    expect(protectEscapedDollars(md).contains(kEscapedDollarSentinel), isFalse);
  });

  test('行数必须保持不变（块 ↔ 源码行的表靠它）', () {
    const String md = '一行 \\\$a\\\$\n\n```\n\\\$b\\\$\n```\n\n末行 \\\$c\\\$';
    expect(
      protectEscapedDollars(md).split('\n').length,
      md.split('\n').length,
    );
  });

  test('围栏开头那一行不参与替换（info string 里可能有 \$）', () {
    const String md = '```\$lang\ncode\n```\n';
    expect(protectEscapedDollars(md).contains(kEscapedDollarSentinel), isFalse);
  });
}
