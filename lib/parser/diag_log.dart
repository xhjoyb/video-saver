import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 解析诊断日志
///
/// 写到 App 外部目录（`Android/data/<包名>/files/`），不出网、不含 cookie 值，
/// 只记录尝试次数、UA、耗时和结果摘要，方便线上复现后直接看日志定位。
class DiagLog {
  DiagLog._();

  static Future<void> write(String fileName, List<String> lines) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final stamp = DateTime.now().toIso8601String();
      await File('${dir.path}/$fileName').writeAsString(
        '$stamp\n${lines.join('\n')}\n\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 诊断日志失败不影响解析
    }
  }
}
