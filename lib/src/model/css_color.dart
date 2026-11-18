/// 颜色值进 `<style>` 之前的唯一一道校验。
///
/// 主题三色不是「随便一个字符串」：它们被**原样**拼进 CSS（Markdown 模板的三处
/// 占位符、HTML 预览的整段样式表），`#fff}</style><script>…` 足以破出样式块。
/// 文档里那句「一律用 `#rrggbb`」到这里才算契约，而不是注释。
library;

/// `#rgb` / `#rgba` / `#rrggbb` / `#rrggbbaa`。
final RegExp _hexColor = RegExp(
  r'^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);

/// 校验并原样返回一个十六进制颜色，不合法时抛 [ArgumentError]。
///
/// 只认十六进制：`red` / `rgb(…)` 这类写法拼进 CSS 也合法，但校验器没法穷举它们的
/// 语法（嵌套括号、百分比、`var()`），而放行等于放弃这道闸门。自定义配色请先转成
/// 十六进制。
String cssHexColor(String value, String name) {
  if (!_hexColor.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a hex colour: #rgb / #rgba / #rrggbb / #rrggbbaa',
    );
  }
  return value;
}
