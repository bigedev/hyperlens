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
