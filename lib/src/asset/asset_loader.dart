/// 读取包内资产的最小接口。
///
/// `path` 用 `HyperlensAssets` 里的常量（形如 `packages/hyperlens/assets/web/…`）。
/// 只声明「怎么读」不关心「怎么打包」：包内不 import flutter / dart:io，
/// 要现成实现见 `package:hyperlens/root_bundle.dart`（Flutter）与将来的
/// `package:hyperlens/io.dart`（VM）。
///
/// 为什么是接口而不是直接用 `rootBundle`：测试要替身（返回假模板），使用方也可能
/// 从别处取资产（预置缓存、内嵌字节）。把读取方式钉死，等于把这两种场景堵死。
abstract interface class HyperlensAssetLoader {
  /// 读一份文本资产。
  ///
  /// 读不到时抛 [HyperlensAssetException]（核心资产：模板 / marked / purify / 主题
  /// CSS）或由调用方降级（增强资产：KaTeX / Mermaid / mhchem）—— 分级见 README。
  Future<String> loadString(String path);
}

/// 资产缺失或读取失败。
///
/// 单独一个异常类型：使用方要能一眼分清「模板没读到」（必然白屏，该报错）与
/// 「公式库没读到」（可降级，正文照常）。
class HyperlensAssetException implements Exception {
  const HyperlensAssetException(this.path, [this.cause]);

  final String path;
  final Object? cause;

  @override
  String toString() => 'HyperlensAssetException: $path'
      '${cause == null ? '' : ' ($cause)'}';
}
