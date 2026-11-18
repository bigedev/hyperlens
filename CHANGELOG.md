## 0.1.0

Unreleased. First extraction from the preview implementation of an editor app.

- Markdown rendering payload with line/block markers, safe HTML (DOMPurify), and
  KaTeX / mhchem math.
- HTML rendering payload with a DOM-path address for restoring the reading position.
- Receipt protocol: render ready, link tapped, position reported, outline reported,
  focus applied, anchor scrolled, unknown message.
- Source-linked outline and syntax tree built from the same parse.
- Web assets (marked, DOMPurify, KaTeX, mhchem, highlight.js, Mermaid) declared by
  the package; the host stops declaring them.
- Public surface: `MarkdownPage` is the single render entry; `HyperlensAssets`,
  `HyperlensBridge`, `HyperlensTheme`, `HyperlensLogger` and `HyperlensAssetLoader`
  (`RootBundleAssetLoader` for Flutter) are the rest of it.
- The WebView channel name is injected into the template instead of being hard-coded,
  so a host can register its own name.
- Missing enhanced assets (KaTeX, mhchem, Mermaid) degrade to plain text and report
  through `HyperlensLogger` instead of failing the whole page.
