/// 数据类的列表字段怎么比。
///
/// 不用 `package:flutter/foundation.dart` 的 `listEquals`：主入口不许 import
/// `flutter/*`（方案 §8.2 的 R5），而为了一个函数去加 `package:collection` 不值当。
library;

/// 两个列表是否同序同值。
bool sameValues<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// 列表的哈希：与 [sameValues] 配套，元素哈希按顺序混进去。
int valuesHash<T>(List<T> values) => Object.hashAll(values);
