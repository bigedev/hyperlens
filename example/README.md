# hyperlens example

One screen, and the whole path a host has to walk in one file (`lib/main.dart`):
**render → route receipts → jump from the outline → remember the reading position.**
The rest is chrome — sample documents, toolbar, drawer, status bar, syntax sheet —
kept in `lib/src/` so the entry file stays readable.

English | [简体中文](https://github.com/bigedev/hyperlens/blob/main/example/README.cn.md)

## Run

```sh
cd example
flutter pub get
flutter run          # android / ios / macos
```

The package itself has no platform code — what you see here is the *host* half: a
`WebViewWidget`, a JavaScript channel and a couple of buttons.

## Files

| File | What it does |
| --- | --- |
| `lib/main.dart` | entry + render pipeline: commit, receipt routing, position semantics |
| `lib/src/demo_documents.dart` | the two sample documents (Markdown / HTML) |
| `lib/src/preview_toolbar.dart` | document kind and theme switches |
| `lib/src/outline_drawer.dart` | outline drawer |
| `lib/src/status_bar.dart` | the two footer lines — *live* and *last read* |
| `lib/src/syntax_sheet.dart` | syntax tree sheet |
| `lib/src/platform_fallback.dart` | which platforms have a WebView, and the payload view for the rest |

## What to look at

| Step | Where |
| --- | --- |
| Render | `main.dart` → `_render()`: `HyperlensPage.fromText(...).render(assets: ...)` — Markdown needs assets, HTML does not |
| Receipts | `main.dart` → `_onMessage()`: `HyperlensBridge.channelName` + `PreviewEvent.parse` (one parser for both document kinds) |
| Outline | `src/outline_drawer.dart` for the list; a tap lands in `main.dart` → `_jumpTo()` and runs `HyperlensCommands.forPosition` |
| Position | `main.dart`: two separate fields, *live* (`_live`, `PreviewPositionReported`, every scroll) and *last read* (`_bookmark`) — the latter is frozen only when the reader leaves (back to top / outline jump / switching document), and that frozen one is what goes back in as `restore:` |
| Stale receipts | `main.dart` → `_fromLivePage()`: every commit gets a `token:`; receipts carrying another one are dropped, so a slow page cannot write into the next one |
| Syntax tree | skeleton from `PreviewSyntaxReported` first; `main.dart` → `_showSyntax()` requests the full tree with `HyperlensCommands.requestSyntaxAst()`, `src/syntax_sheet.dart` renders it |
| Theme | `src/preview_toolbar.dart` → `demoThemes`: `HyperlensTheme.light / dark / ink`, colours and font size come from the caller |

The bottom bar shows two lines — the latest receipt and the frozen *last position* — so every
step is visible without a debugger. The theme switch repaints the **document** only; the app
chrome stays Material on purpose, because the host owns it.

Both sample documents are written in two parts — English first, Chinese second. The
Markdown one also carries **math** (`$…$`, `$$…$$` → KaTeX) and a **diagram**
(a `mermaid` fence). Both are gated by the package on content: no math, no diagram, no
inlined bundle. Expect a multi-MB payload when a document does use them — that is
Mermaid, not the library being wasteful.

The HTML sample shows the other side of that coin: an HTML page gets **no** injected
KaTeX/Mermaid (author page stays the author's), so its chart is inline SVG and its
formula is MathML.

## Platforms

`webview_flutter` officially implements **android / ios / macos**. On **windows / linux**
this example still builds and runs: it shows the payload that `render()` produced instead
of displaying it. Swap in your own WebView there and the rest of the code is unchanged.
