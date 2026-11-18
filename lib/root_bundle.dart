/// Flutter 环境的资产读取实现。
///
/// **本文件是包里唯一 import `flutter/services` 的地方**（主入口
/// `package:hyperlens/hyperlens.dart` 保持零 flutter）。要用它就必须在 Flutter
/// 工程里；纯 Dart 场景请自己实现 `HyperlensAssetLoader`。
library;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import 'src/asset/asset_loader.dart';

/// 用 `rootBundle` 读随包资产。
///
/// `path` 直接传 `HyperlensAssets` 的常量即可 —— 前缀里已带 `packages/hyperlens/`，
/// `rootBundle` 认的就是这个形态。
class RootBundleAssetLoader implements HyperlensAssetLoader {
  const RootBundleAssetLoader();

  @override
  Future<String> loadString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } on FlutterError catch (error) {
      // 资产没打进包（pubspec 漏了 `flutter: assets:` 或发布产物不全）时
      // rootBundle 抛的是 FlutterError —— 换成自己的类型，调用方好分级处理。
      throw HyperlensAssetException(path, error);
    }
  }
}
