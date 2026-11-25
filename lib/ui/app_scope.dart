import 'package:flutter/widgets.dart';

import '../core/store.dart';
import '../platform/library.dart';

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.store, required this.library, required super.child});

  final AppStore store;
  final Library library;

  static AppScope of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      store != oldWidget.store || library != oldWidget.library;
}

String formatCount(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String plural(int n, String one, [String? many]) =>
    '${formatCount(n)} ${n == 1 ? one : (many ?? '${one}s')}';

String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
}
