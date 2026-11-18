import 'package:hyperlens/src/markdown/links.dart';

import 'package:flutter_test/flutter_test.dart';

/// 用例取自 CPF-Flutter 文档索引（`cpf-docs/README.md`）里真实出现的链接形态 ——
/// 这类表格型索引每个单元格都是一个文档链接，全仓库共上百条。
void main() {
  MarkdownLinkAction resolve(String href, {String from = 'README.md'}) =>
      resolveMarkdownLink(fromRelPath: from, href: href);

  group('仓内相对路径', () {
    test('./ 前缀：索引里的主流写法', () {
      expect(
        resolve('./getting-started/overview.md'),
        isA<OpenRepoFile>().having((OpenRepoFile a) => a.relPath, 'relPath',
            'getting-started/overview.md'),
      );
      expect(
        resolve('./troubleshooting/dfx/README.md'),
        isA<OpenRepoFile>().having((OpenRepoFile a) => a.relPath, 'relPath',
            'troubleshooting/dfx/README.md'),
      );
    });

    test('不带 ./ 也一样', () {
      expect(
        resolve('app-development/flutter-oh-core-objects.md'),
        isA<OpenRepoFile>()
            .having((OpenRepoFile a) => a.relPath, 'relPath',
                'app-development/flutter-oh-core-objects.md'),
      );
    });

    test('../ 相对当前文件所在目录', () {
      expect(
        resolve('../app-development/flutter-oh-app-lifecycle.md',
            from: 'getting-started/README.md'),
        isA<OpenRepoFile>().having((OpenRepoFile a) => a.relPath, 'relPath',
            'app-development/flutter-oh-app-lifecycle.md'),
      );
    });

    test('/ 开头 = 相对仓库根', () {
      expect(
        resolve('/docs/version/flutter-oh-upgrade-guide.md',
            from: 'a/b/c.md'),
        isA<OpenRepoFile>().having((OpenRepoFile a) => a.relPath, 'relPath',
            'docs/version/flutter-oh-upgrade-guide.md'),
      );
    });

    test('带锚点 / 查询串：只取路径', () {
      expect(
        resolve('./app-development/x.md#生命周期'),
        isA<OpenRepoFile>()
            .having((OpenRepoFile a) => a.relPath, 'relPath', 'app-development/x.md'),
      );
      expect(
        resolve('./app-development/x.md?plain=1'),
        isA<OpenRepoFile>()
            .having((OpenRepoFile a) => a.relPath, 'relPath', 'app-development/x.md'),
      );
    });

    test('%20 与中文链接要还原', () {
      expect(
        resolve('./media/sliding/use%20case.md'),
        isA<OpenRepoFile>().having(
            (OpenRepoFile a) => a.relPath, 'relPath', 'media/sliding/use case.md'),
      );
    });

    test('目录链接保留尾斜杠（上层据此进目录）', () {
      expect(
        resolve('./hybrid-development/'),
        isA<OpenRepoFile>().having((OpenRepoFile a) => a.relPath, 'relPath',
            'hybrid-development/'),
      );
    });
  });

  group('外部链接', () {
    test('http/https 原样交给系统浏览器', () {
      const String url =
          'https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md#1openharmony';
      expect(
        resolve(url),
        isA<OpenExternal>().having((OpenExternal a) => a.url, 'url', url),
      );
    });

    test('协议相对 //host/path 补成 https', () {
      expect(
        resolve('//example.com/a.md'),
        isA<OpenExternal>()
            .having((OpenExternal a) => a.url, 'url', 'https://example.com/a.md'),
      );
    });

    test('mailto 也交出去', () {
      expect(
        resolve('mailto:a@b.c'),
        isA<OpenExternal>()
            .having((OpenExternal a) => a.url, 'url', 'mailto:a@b.c'),
      );
    });

    test('<url> 包裹写法', () {
      expect(
        resolve('<https://example.com/a>'),
        isA<OpenExternal>()
            .having((OpenExternal a) => a.url, 'url', 'https://example.com/a'),
      );
    });
  });

  group('不处理的情况', () {
    test('页内锚点交给 WebView 自己滚', () {
      expect(resolve('#快速入门'), isA<IgnoreLink>());
    });

    test('空链接', () {
      expect(resolve(''), isA<IgnoreLink>());
      expect(resolve('   '), isA<IgnoreLink>());
    });

    test('越出仓库根一律不跳（防 `../../../etc/passwd` 这类写法）', () {
      expect(resolve('../../outside.md', from: 'a/b.md'), isA<IgnoreLink>());
      expect(resolve('./..'), isA<IgnoreLink>());
      expect(resolve('..'), isA<IgnoreLink>());
    });

    test('不认识的协议不跳', () {
      expect(resolve('file:///etc/passwd'), isA<IgnoreLink>());
      expect(resolve('javascript:alert(1)'), isA<IgnoreLink>());
      expect(resolve('ohos://x'), isA<IgnoreLink>());
    });
  });

  test('指向自身也照常解析（重复打开同一文件，无害）', () {
    expect(
      resolve('./README.md'),
      isA<OpenRepoFile>()
          .having((OpenRepoFile a) => a.relPath, 'relPath', 'README.md'),
    );
  });
}
