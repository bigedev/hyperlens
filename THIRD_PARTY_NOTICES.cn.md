# 第三方许可说明

[English](THIRD_PARTY_NOTICES.md) | 简体中文

hyperlens 随包带了少量第三方**前端资源**，都放在 [`assets/web/`](assets/web/) —— 它们是
预览 WebView 真正执行的东西：Markdown 解析器、清洗器、图表与公式渲染器，以及各自的样式表。
它们的许可正文**逐字**收录在 [`assets/licenses/`](assets/licenses/) 下，一个组件一份；
下面的表格是「包里到底装了哪些文件」与「该看哪份正文」的对照。

版本号取自随包文件内部的声明（bundle 里的 banner 或 `version:"…"` 字段），不是取自某个清单 ——
压缩过的资源本身不带包元数据。

| 组件 | 版本 | 许可 | 随包文件 | 正文 |
|---|---|---|---|---|
| [DOMPurify](https://github.com/cure53/DOMPurify) | 3.2.6 | Apache-2.0（与 MPL-2.0 双许可，本项目按 Apache-2.0 使用） | `assets/web/purify.min.js` | [`assets/licenses/dompurify.txt`](assets/licenses/dompurify.txt) |
| [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) | —（上游 CSS 不带版本号） | MIT | `assets/web/md-light.css`、`md-dark.css`、`md-ink.css`、`md-ink-dark.css` | [`assets/licenses/github-markdown-css.txt`](assets/licenses/github-markdown-css.txt) |
| [highlight.js](https://github.com/highlightjs/highlight.js) | 11.9.0 | BSD-3-Clause | `assets/web/highlight.min.js`、`highlight-dart.min.js`、`hljs-light.css`、`hljs-dark.css`、`hljs-ink.css`、`hljs-ink-dark.css` | [`assets/licenses/highlight.js.txt`](assets/licenses/highlight.js.txt) |
| [KaTeX](https://github.com/KaTeX/KaTeX) | 0.19.1 | MIT | `assets/web/katex.min.js`、`katex.min.css`、`mhchem.min.js` | [`assets/licenses/katex.txt`](assets/licenses/katex.txt) |
| [marked](https://github.com/markedjs/marked) | 14.1.3 | MIT | `assets/web/marked.min.js` | [`assets/licenses/marked.txt`](assets/licenses/marked.txt) |
| [Mermaid](https://github.com/mermaid-js/mermaid) | 11.17.2 | MIT（产物里另有 53 个依赖，按 MIT / ISC / BSD-3-Clause / MPL-2.0 或 Apache-2.0 分发） | `assets/web/mermaid.min.js` | [`assets/licenses/mermaid.txt`](assets/licenses/mermaid.txt)（mermaid + KaTeX）· [`assets/licenses/mermaid-bundle.txt`](assets/licenses/mermaid-bundle.txt)（全部 55 个包） |

## 文件与许可的对应关系

- **`md-*.css` 是 github-markdown-css 的修改版**：只改颜色变量，另有一处结构性改动 ——
  删掉 `prefers-color-scheme` 分支，深浅色改由宿主应用指定，而不是跟随系统（系统深色
  + 应用浅色时会出现白底浅字）。MIT 允许修改，上游版权声明保留在
  `assets/licenses/github-markdown-css.txt` 里；`-ink*` 两档是同一份文件换成墨色系配色。
- **`mhchem.min.js` 是 KaTeX 包内自带的 contrib 构建**（同版本、同一条 MIT，提供
  `\ce{}` / `\pu{}`），所以由 `assets/licenses/katex.txt` 一并覆盖，不单列一份。
- **`mermaid.min.js` 是本项目自建的 bundle** —— mermaid + KaTeX + mhchem，另外还有 mermaid
  自己的 53 个依赖（d3 系 30 个、cytoscape 系、dagre-d3-es、dompurify、marked、lodash-es 等），
  一共 55 个包打成一个 IIFE。两份正文分工：
  - `assets/licenses/mermaid.txt` 收两个**主作品**（mermaid、KaTeX，含 contrib/mhchem）的 MIT 全文；
  - `assets/licenses/mermaid-bundle.txt` 收**完整清单** —— 每个包的版权行，加上四种许可的逐字全文。
  同一份清单与正文也内联在产物末尾（`mermaid.min.js` 的尾注释），所以副本走到哪，声明跟到哪。
- **产物里还另有一份 dompurify 3.4.18**：那是 mermaid 自带的，被打进了 bundle；与这里独立分发的
  `purify.min.js`（3.2.6）不是同一份代码。两者同属 Apache-2.0，共用 `assets/licenses/dompurify.txt`。
- **`assets/licenses/marked.txt` 是上游 LICENSE 原文**，实际含两份文本：marked 自身的
  MIT，以及它派生自 Markdown 语法的那份 BSD 风格声明（John Gruber, 2004）。
- **`assets/web/markdown_view.html` 是本项目自有文件** —— 这是本包生成并注入的页面模板，
  不涉及第三方许可。

## Dart 依赖

从 pub 拉取的包**不在**此列，它们的 LICENSE 也没有复制到本目录。Flutter 在构建时会把
所有依赖的 `LICENSE` 汇总进 `NOTICES` 并注册到 `LicenseRegistry`，宿主应用自己的许可页
会自动展示，hyperlens 不需要重复一份。本文件只覆盖上面这些**不走那套机制**的非 Dart 资源。

## hyperlens 自身

MIT —— 见 [LICENSE](LICENSE)。
