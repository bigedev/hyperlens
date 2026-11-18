# hyperlens

Source-linked preview for Markdown and HTML.

The rendered page, the outline and the syntax tree share **one coordinate system** —
the source line for Markdown, the DOM path for HTML — so an editor can move between
source and preview without guessing.

English | [简体中文](README.cn.md)

> **Status: 0.1.0 in progress.** Nothing has been published yet.

## What it does

- **Render** a Markdown or HTML document into the payload the caller shows in its own
  WebView — no widget of its own, no opinion about the caller's layout.
- **Map both ways**: report the source line the reader has scrolled to, and scroll
  the preview back to a remembered line (or DOM path) after a restart.
- **Outline and syntax tree** derived from the same parse, so any outline view of it
  agrees with the preview.
- **Search hits** scroll into view and stay highlighted; the receipt says whether
  the anchor was found.

## What it does not do

- No page widgets, no routing, no theming system — the caller keeps its own shell.
- No encoding detection: bytes are the caller's business.
- No network access: assets ship inside the package.

## Install

```yaml
dependencies:
  hyperlens: ^0.1.0
```

The caller's WebView must be able to load package assets through
`packages/hyperlens/...`; the asset paths are exposed as constants so nothing in the
caller hard-codes them.

The name passed to `addJavaScriptChannel` must match what the render entry uses:
`HyperlensPage.fromText(channelName:)`, defaulting to `HyperlensBridge.channelName`. **A mismatch fails silently** — the
guard in the injected script simply posts nothing, so reading positions and the outline
stop updating with no error anywhere in the logs.

## Quick start

```dart
import 'package:hyperlens/hyperlens.dart';

// 1. One document in, one payload out. The type comes from the path suffix
//    (.md / .markdown / .html / .htm); HTML pages need no assets.
final HyperlensPage page = HyperlensPage.fromText(
  source: text,
  path: entry.path,
  theme: theme,
);
final String html = await page.render(assets: const HyperlensRootBundleAssetLoader());

// 2. Hand it to your own WebView. The channel name must match on both sides,
//    otherwise positions and the outline stop updating without any error.
await controller.loadHtmlString(html);
controller.addJavaScriptChannel(
  HyperlensBridge.channelName,
  onMessageReceived: (message) {
    switch (PreviewEvent.parse(message.message)) {
      case PreviewRenderReady(:final result):
        onReady(result);          // ok（…）/ empty / exception: …
      case PreviewPositionReported(:final position):
        remember(position);       // restore it next time
      case PreviewOutlineReported(:final outline):
        renderOutline(outline);   // shared by Markdown and HTML
      default:
        break;                    // syntax tree, focus, links as needed
    }
  },
);

// 3. Outline tap: run a command (line for Markdown, DOM path for HTML)
await controller.runJavaScript(
  HyperlensCommands.forPosition(entry.address, kind: page.kind),
);
```

Reach for `package:hyperlens/advanced.dart` only when you compose pages
yourself or need diagnostics (HTML injection order, tag scanning, Markdown
link resolution). The main entry keeps just what "using this package" needs.

## License

MIT — see [LICENSE](LICENSE).
