/// 包内要往外说话时用的最小日志接口。
///
/// 为什么不是直接用宿主的日志：日志标签属于宿主排障体系（真机上按标签过滤），
/// 包不该知道那套约定；而包自己 print 又没人收。用接口把「说一句」和「写去哪」
/// 分开，宿主接自己的 `log.w`，三方接 `print`，测试接记录器。
///
/// 只在**降级路径**上调用：增强资产（KaTeX / Mermaid / mhchem）读不到时正文照常
/// 渲染，但要让调用方知道「公式这次没渲染」。渲染成功这是静默的 —— 别拿它当
/// 进度条。
abstract interface class HyperlensLogger {
  /// 可降级的异常：功能少了一块，页面还能看。
  void warn(String tag, String message);

  /// 不该发生、但已经兜住的情况（例如回执格式认不出来）。
  void error(String tag, String message, [Object? cause]);
}

/// 默认实现：什么都不做。
///
/// 有它，`MarkdownPage.render` 才能把 `logger` 定义成可选；否则每个调用点都要写
/// `logger: null` 判断。
final class NoopHyperlensLogger implements HyperlensLogger {
  const NoopHyperlensLogger();

  @override
  void warn(String tag, String message) {}

  @override
  void error(String tag, String message, [Object? cause]) {}
}
