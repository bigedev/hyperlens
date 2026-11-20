/// 示例用的两份文档：一份 Markdown、一份 HTML。真实宿主这里换成读文件。
///
/// 两份都写成**两段**：第一段英文、第二段中文，方便对照排版差异。
library;

import 'package:hyperlens/hyperlens.dart';

/// Markdown 那份：还带公式（KaTeX）与图表（Mermaid）—— 这两样由包里按内容
/// 自动门控（`detectMarkdownExtras`），调用方没有开关。
const String demoMarkdown = r'''
# hyperlens demo

Part 1 — English

## One address, two documents

- A Markdown address is a **source line**; the page reports the line the reader settled on.
- An HTML address is a **DOM path** such as `body>article>h2:nth(2)`.

Both live in the same `PreviewPosition`, so "jump to a section" and "come back to where
I was reading" are one code path.

## Math

Inline math works: $a^2 + b^2 = c^2$, and so does a block:

$$
\int_{0}^{1} x^2\,\mathrm{d}x = \frac{1}{3}
$$

## Diagram

```mermaid
flowchart LR
  src[source] --> render[render payload]
  render --> view[your WebView]
  view -->|receipts| host[your app]
```

## Receipts

| receipt | payload |
| --- | --- |
| `render` | the submitted page is alive |
| `position` | reading position + viewport |
| `outline` | section list |
| `ast` | syntax tree (skeleton first) |

```dart
final html = await HyperlensPage.fromText(
  source: text,
  path: 'demo/a.md',
).render(assets: const HyperlensRootBundleAssetLoader());
```

> Link clicks are intercepted as well: try [this section](#receipts) or
> [pub.dev](https://pub.dev/packages/hyperlens).

---

# hyperlens 示例

第二部分 —— 中文

## 一套坐标，两种文档

- Markdown 的地址是**源码行**，滚动停下时页面把行号发回来；
- HTML 的地址是 **DOM 路径**（`body>article>h2:nth(2)`）。

两种地址放在同一个 `PreviewPosition` 里，所以「跳到某一节」与「返回时落回读到的
位置」是同一条代码路径。

## 公式

行内公式：$e^{i\pi} + 1 = 0$；块级公式：

$$
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
$$

## 图表

```mermaid
sequenceDiagram
  页面->>宿主: render ok
  宿主->>页面: mdScrollToLine(12)
  页面->>宿主: position + outline + ast
```

## 回执

| 回执 | 载荷 |
| --- | --- |
| `render` | 这次提交的页面活着 |
| `position` | 阅读位置 + 视口 |
| `outline` | 章节清单 |
| `ast` | 语法树骨架 |

> 侧栏点一条标题试试：那条命令走的是 [HyperlensCommands.forPosition]。

链接也拦下来了：点 [这一段](#回执) 或 [外链](https://pub.dev/packages/hyperlens)。
''';

/// HTML 那份走的是「看别人的页面」：样式、图表、公式都由作者自己带。
///
/// 公式这里用 MathML（浏览器原生支持），因为 HTML 预览**不注入** KaTeX —— 那是
/// Markdown 那份才有的增强；作者要公式就自己带渲染器或 MathML。
const String demoHtml = r'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>hyperlens demo</title>
  <style>
    body { font-family: Georgia, serif; max-width: 40em; margin: 2em auto; padding: 0 1em; }
    h1 { border-bottom: 2px solid currentColor; padding-bottom: .3em; }
    .note { padding: .6em .8em; border-left: 3px solid #888; }
    svg { display: block; margin: 1em 0; }
    math { font-size: 1.15em; }
  </style>
</head>
<body>
  <h1>HTML preview</h1>
  <p>Part 1 — English. Author styles are kept as written: this side is "look at someone
     else's page", not "re-typeset it for them".</p>

  <h2>A chart, drawn by the author</h2>
  <p>Scripts are stripped, so the picture has to be markup — here it is inline SVG:</p>
  <svg width="300" height="110" viewBox="0 0 300 110" role="img" aria-label="bar chart">
    <line x1="10" y1="95" x2="290" y2="95" stroke="#888" stroke-width="1"></line>
    <rect x="30"  y="55" width="40" height="40" fill="#3b6ea5"></rect>
    <rect x="100" y="35" width="40" height="60" fill="#5b8fc4"></rect>
    <rect x="170" y="15" width="40" height="80" fill="#7fb0dd"></rect>
    <rect x="240" y="70" width="40" height="25" fill="#a9cbe8"></rect>
    <text x="50"  y="108" font-size="10" text-anchor="middle" fill="#555">render</text>
    <text x="120" y="108" font-size="10" text-anchor="middle" fill="#555">position</text>
    <text x="190" y="108" font-size="10" text-anchor="middle" fill="#555">outline</text>
    <text x="260" y="108" font-size="10" text-anchor="middle" fill="#555">ast</text>
  </svg>

  <h2>Math, brought by the author</h2>
  <p>No KaTeX is injected into an HTML page — MathML is the built-in way:</p>
  <math display="block">
    <mi>x</mi><mo>=</mo>
    <mfrac>
      <mrow><mo>−</mo><mi>b</mi><mo>±</mo>
        <msqrt><mrow><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></mrow></msqrt>
      </mrow>
      <mrow><mn>2</mn><mi>a</mi></mrow>
    </mfrac>
  </math>

  <h2>Scripts</h2>
  <p class="note">Author scripts are stripped by default: rendering only opens the door for
     our own bridge, so positions and the outline stay in sync.</p>
  <p><a href="https://pub.dev/packages/hyperlens">pub.dev</a></p>

  <hr>

  <h1>HTML 预览</h1>
  <p>第二部分 —— 中文。作者写的样式原样保留 —— 这一档讲的是「看别人的页面」，
     不是替它定排版。</p>

  <h2>只有一条命令</h2>
  <p>章节从 <code>h1~h6</code>（含 ARIA 标题）扫出来，地址是 DOM 路径，
     所以目录点击与 Markdown 走同一个位置类型。</p>

  <h3 id="receipts">回执</h3>
  <ol>
    <li><code>render</code>：这次提交的页面活着；</li>
    <li><code>position</code>：阅读位置 + 视口；</li>
    <li><code>outline</code>：章节清单；</li>
    <li><code>ast</code>：语法树（先来骨架）。</li>
  </ol>

  <h2>表格</h2>
  <table border="0" cellpadding="6" style="border-collapse: collapse;">
    <tr><th align="left">回执</th><th align="left">载荷</th></tr>
    <tr><td><code>render</code></td><td>这次提交的页面活着</td></tr>
    <tr><td><code>position</code></td><td>阅读位置 + 视口</td></tr>
    <tr><td><code>outline</code></td><td>章节清单</td></tr>
  </table>

  <h2 id="links">Links</h2>
  <p>Link handling is split: the package decides <em>what counts as a link</em> and
     <em>what counts as leaving the document</em>, the host resolves the rest.</p>
  <ul>
    <li><a href="demo.html#receipts">demo.html#receipts</a> — same file, section
        “回执”: the host turns the fragment into
        <code>PreviewDomAddress('#receipts')</code> and lands there;</li>
    <li><a href="https://pub.dev/packages/hyperlens">pub.dev</a> — external: handed out.</li>
  </ul>
  <p>链接的判定在包里，解析在宿主 —— 点 <a href="demo.html#receipts">demo.html#receipts</a>
     会落回上面的「回执」；外链交给系统浏览器。</p>
</body>
</html>
''';

/// 按档位取文档正文 —— 提交时只多这一行分支。
String demoDocument(PreviewSourceKind kind) =>
    kind == PreviewSourceKind.markdown ? demoMarkdown : demoHtml;
