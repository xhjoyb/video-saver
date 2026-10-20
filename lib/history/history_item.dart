import 'dart:convert';

/// 一条解析历史（解析成功即记录，下载后补充保存路径）
class HistoryItem {
  const HistoryItem({
    required this.awemeId,
    required this.platform,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.videoUrl,
    required this.durationMs,
    required this.savedAt,
    this.filePath,
  });

  final String awemeId;
  final String platform;
  final String title;
  final String author;
  final String coverUrl;
  final String videoUrl;
  final int durationMs;
  final DateTime savedAt;
  final String? filePath;

  bool get downloaded => (filePath ?? '').isNotEmpty;

  String get displayTitle => title.isEmpty ? '无标题' : title;

  String get timeText {
    final t = savedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  String get durationText {
    final total = (durationMs / 1000).round();
    if (total <= 0) return '';
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  HistoryItem copyWith({String? filePath}) => HistoryItem(
        awemeId: awemeId,
        platform: platform,
        title: title,
        author: author,
        coverUrl: coverUrl,
        videoUrl: videoUrl,
        durationMs: durationMs,
        savedAt: savedAt,
        filePath: filePath ?? this.filePath,
      );

  Map<String, dynamic> toJson() => {
        'awemeId': awemeId,
        'platform': platform,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'videoUrl': videoUrl,
        'durationMs': durationMs,
        'savedAt': savedAt.toIso8601String(),
        'filePath': filePath,
      };

  static HistoryItem? tryParse(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = '${m['awemeId'] ?? ''}';
      if (id.isEmpty) return null;
      return HistoryItem(
        awemeId: id,
        platform: '${m['platform'] ?? 'douyin'}',
        title: '${m['title'] ?? ''}',
        author: '${m['author'] ?? ''}',
        coverUrl: '${m['coverUrl'] ?? ''}',
        videoUrl: '${m['videoUrl'] ?? ''}',
        durationMs: int.tryParse('${m['durationMs'] ?? 0}') ?? 0,
        savedAt: DateTime.tryParse('${m['savedAt'] ?? ''}') ?? DateTime.now(),
        filePath: (m['filePath'] as String?)?.trim().isEmpty ?? true
            ? null
            : m['filePath'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}