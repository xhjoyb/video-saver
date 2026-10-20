import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 下载服务：带 Referer 直链下载（抖音 CDN 防盗链要求）
class DownloadService {
  DownloadService._();

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14; PGT-AN20 Build/HONORPGT-AN20) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static Future<String> detectImageExt(File file) async {
    try {
      final raf = await file.open();
      final head = await raf.read(12);
      await raf.close();
      if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8) return 'jpg';
      if (head.length >= 8 && head[0] == 0x89 && head[1] == 0x50) return 'png';
      if (head.length >= 12 &&
          String.fromCharCodes(head.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(head.sublist(8, 12)) == 'WEBP') {
        return 'webp';
      }
      return 'jpg';
    } catch (_) {
      return 'jpg';
    }
  }

  static Future<File> download(
    String url,
    String fileName, {
    void Function(int received, int total)? onProgress,
    String referer = 'https://www.douyin.com/',
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      request.headers.set(HttpHeaders.refererHeader, referer);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw const FileSystemException('无法获取下载目录');
      final target = File('${dir.path}/$fileName');
      final sink = target.openWrite();
      var received = 0;
      final total = response.contentLength;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      return target;
    } finally {
      client.close(force: true);
    }
  }
}