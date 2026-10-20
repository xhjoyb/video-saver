/// 一档清晰度（按 br 码率区分）
class VideoQuality {
  const VideoQuality({required this.label, required this.url, required this.br});

  final String label;
  final String url;
  final int br;
}

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

  /// 按 URL 里的 br（码率）分档，供清晰度选择使用
  List<VideoQuality> get qualities {
    final parsed = <VideoQuality>[];
    final seen = <int>{};
    for (final url in videoUrls) {
      final m = RegExp(r'[?&]br=(\d+)').firstMatch(url);
      final br = int.tryParse(m?.group(1) ?? '') ?? 0;
      if (!seen.add(br)) continue;
      parsed.add(VideoQuality(label: '', url: url, br: br));
    }
    parsed.sort((a, b) => b.br.compareTo(a.br));
    final labels = <String>['原画', '高清', '标清'];
    return [
      for (var i = 0; i < parsed.length; i++)
        VideoQuality(
          label: parsed.length == 1
              ? '原画'
              : (i < labels.length ? labels[i] : '标清'),
          url: parsed[i].url,
          br: parsed[i].br,
        ),
    ];
  }

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