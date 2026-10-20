/// 解析结果模型（多平台通用，抖音先落地）
class ParseResult {
  const ParseResult({
    required this.platform,
    required this.awemeId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationMs,
    required this.videoUrls,
    this.imageUrls = const [],
  });

  final String platform;
  final String awemeId;
  final String title;
  final String author;
  final String coverUrl;
  final int durationMs;
  final List<String> videoUrls;
  final List<String> imageUrls;

  bool get isImages => imageUrls.isNotEmpty;
  bool get isVideo => !isImages && videoUrls.isNotEmpty;

  String get durationText {
    final total = (durationMs / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get displayTitle => title.isEmpty ? '无标题' : title;

  String get fileName {
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final base = safe.isEmpty
        ? 'douyin_$awemeId'
        : (safe.length > 40 ? safe.substring(0, 40) : safe);
    return '${base}_$awemeId.mp4';
  }

  factory ParseResult.fromDouyin(Map<String, dynamic> m) {
    final play = (m['play'] as List?) ?? const [];
    final images = (m['images'] as List?) ?? const [];
    return ParseResult(
      platform: 'douyin',
      awemeId: '${m['id'] ?? ''}',
      title: '${m['desc'] ?? ''}',
      author: '${m['author'] ?? ''}',
      coverUrl: '${m['cover'] ?? ''}',
      durationMs: int.tryParse('${m['duration'] ?? 0}') ?? 0,
      videoUrls: play
          .map((e) => e.toString())
          .where((e) => e.startsWith('http'))
          .toList(),
      imageUrls: images.map((e) => e.toString()).toList(),
    );
  }
}