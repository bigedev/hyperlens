import 'package:hyperlens/src/html/html_anchor.dart';
import 'package:hyperlens/src/protocol/link_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// 链接点击协议（`lib/src/protocol/link_intent.dart`）。
///
/// 钉住三件事：**信封长什么样**、**外链表是哪一张**、**注入脚本用的前缀与 Dart 侧
/// 拼的一致**。前两件是「改一处漏一处不报错」的典型 —— 外链漏一个协议，表现只是
/// 「点电话号码没反应」；信封差一格，表现是「点了没反应」且日志里什么都没有。
void main() {
  group('信封', () {
    test('带地址空间：space + 编码后的 context + 编码后的 href', () {
      expect(
        linkReceipt(
          space: PreviewLinkSpace.repo,
          context: 'docs/chap2.html',
          href: 'a b.html#sec2',
        ),
        'link repo docs%2Fchap2.html a%20b.html%23sec2',
      );
      expect(
        linkReceipt(
          space: PreviewLinkSpace.book,
          context: '3',
          href: '../Text/chap5.xhtml',
        ),
        'link book 3 ..%2FText%2Fchap5.xhtml',
      );
    });

    test('不带地址空间：只剩前缀（旧式回执，Markdown 模板就是这个形状）', () {
      expect(linkReceiptPrefix(), 'link ');
    });

    test('context 里的空格与 # 都编码（不然拆包会把信封切歪）', () {
      expect(
        linkReceiptPrefix(space: PreviewLinkSpace.book, context: 'a b#c'),
        'link book a%20b%23c ',
      );
    });
  });

  group('LinkSpace：回执里的写法', () {
    test('两个空间各有稳定名字，且能还原', () {
      expect(PreviewLinkSpace.repo.wireName, 'repo');
      expect(PreviewLinkSpace.book.wireName, 'book');
      expect(PreviewLinkSpace.fromWire('book'), PreviewLinkSpace.book);
      expect(PreviewLinkSpace.fromWire('Repo'), isNull,
          reason: '大小写敏感：拼错就是认不出');
      expect(PreviewLinkSpace.fromWire('book '), isNull);
    });
  });

  group('解析', () {
    test('带地址空间：往返一致', () {
      final ({PreviewLinkSpace? space, String? context, String href})? click =
          parseLinkReceipt('repo docs%2Fchap2.html a%2Fb.html%23sec2');
      expect(click?.space, PreviewLinkSpace.repo);
      expect(click?.context, 'docs/chap2.html');
      expect(click?.href, 'a/b.html#sec2');
    });

    test('旧式：space / context 为 null，整段解成 href', () {
      final ({PreviewLinkSpace? space, String? context, String href})? click =
          parseLinkReceipt('%E6%96%87%E6%A1%A3%2Fa.md');
      expect(click?.space, isNull);
      expect(click?.href, '文档/a.md');
    });

    test('空载荷 / 空 href：认不出，返回 null', () {
      expect(parseLinkReceipt(''), isNull);
      expect(parseLinkReceipt('repo docs%2Fa.md '), isNull);
    });

    test('段数不对或 space 认不出：null，不退回「整段当 href」', () {
      // 编码后的 href 不含空格，所以 2 段 / 4 段都不是旧式回执
      expect(parseLinkReceipt('repo a%2Fb.html'), isNull, reason: '缺 href 段');
      expect(parseLinkReceipt('repo x a%2Fb.html extra'), isNull, reason: '多一段');
      expect(parseLinkReceipt('repo2 docs%2Fa.md a%2Fb.html'), isNull,
          reason: 'space 名字拼错：不能把整句当成链接交出去');
    });

    test('转义坏掉不抛：按原样留着，别让一条乱码回执打断通道', () {
      // `%zz` / 结尾单个 `%` 抛 ArgumentError；`%FF` 抛 FormatException
      expect(parseLinkReceipt('%zz')?.href, '%zz');
      expect(parseLinkReceipt('repo docs%2Fa.md a%2Fb%'), isNotNull);
      expect(parseLinkReceipt('repo docs%2Fa.md %FF')?.href, '%FF');
    });
  });

  group('外链表', () {
    test('http / https / mailto / tel 都算「离开文档」', () {
      for (final String href in <String>[
        'http://a.b',
        'HTTPS://a.b',
        'mailto:a@b.c',
        'tel:10086',
      ]) {
        expect(isExternalPreviewLink(href), isTrue, reason: href);
      }
    });

    test('仓内相对路径、file:、javascript:、无协议头都不算', () {
      for (final String href in <String>[
        'a/b.md',
        '#sec2',
        'file:///etc/passwd',
        'javascript:void(0)',
        'C:/tmp/a.txt',
      ]) {
        expect(isExternalPreviewLink(href), isFalse, reason: href);
      }
    });

    test('表里就这四个（少一个的表现是「点了没反应」，不会报错）', () {
      expect(
        kPreviewExternalSchemes,
        <String>{'http', 'https', 'mailto', 'tel'},
      );
    });
  });

  group('注入脚本', () {
    test('不带地址空间：链接回执仍是旧式前缀', () {
      final String js = htmlAnchorScript(null);
      expect(js, contains('hyperLensAnchorWatchLinks("link ");'));
    });

    test('带地址空间：前缀里有 space 与编码后的 context', () {
      final String js = htmlAnchorScript(
        null,
        linkSpace: PreviewLinkSpace.book,
        linkContext: '3',
      );
      expect(js, contains('hyperLensAnchorWatchLinks("link book 3 ");'));
    });

    test('前缀与 Dart 侧拼的逐字一致（页面与解析不能各写一份）', () {
      final String prefix = linkReceiptPrefix(
        space: PreviewLinkSpace.repo,
        context: 'docs/a b.md',
      );
      expect(
        htmlAnchorScript(null,
            linkSpace: PreviewLinkSpace.repo, linkContext: 'docs/a b.md'),
        contains('hyperLensAnchorWatchLinks("$prefix");'),
      );
    });

    test('位置监听比链接监听先注册（回退栈要「离开那一刻」的位置）', () {
      final String js = htmlAnchorScript(null);
      // 比的是**注册**那一条（函数定义在脚本正文里，位置更靠前，不能拿来比）
      expect(
        js.indexOf(
          "document.addEventListener('click', function () { hyperLensAnchorReport(); }, true);",
        ),
        lessThan(js.indexOf('hyperLensAnchorWatchLinks("link ");')),
      );
    });
  });
}
