/// 一档清晰度（按 br 码率区分）
class VideoQuality {
  const VideoQuality({
    required this.label,
    required this.url,
    required this.br,
    this.audioUrl,
  });

  final String label;
  final String url;
  final int br;

  /// DASH 音轨地址：非空表示这条视频是「无音轨的视频流」，
  /// 下载后需要与音轨合流才能得到可播放的成片（B 站 1080P 起只有 DASH）
  final String? audioUrl;
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
    this.audioUrls = const [],
    this.imageUrls = const [],
    this.qualityNames = const [],
  });

  final String platform;
  final String awemeId;
  final String title;
  final String author;
  final String coverUrl;
  final int durationMs;
  final List<String> videoUrls;

  /// 与 [videoUrls] 并行：非空元素表示该档需要与音轨合流（B 站 DASH 1080P）
  final List<String> audioUrls;
  final List<String> imageUrls;

  /// 可选：与 [videoUrls] 一一对应的清晰度名称（如 B 站 720P/360P）。
  /// 非空时 [qualities] 会直接使用这些标签，不再按 URL 里的 br 推断。
  final List<String> qualityNames;

  bool get isImages => imageUrls.isNotEmpty;
  bool get isVideo => !isImages && videoUrls.isNotEmpty;

  /// 按 URL 里的 br（码率）分档，供清晰度选择使用
  List<VideoQuality> get qualities {
    // 平台直接给了清晰度名称（如 B 站 720P / 360P）时，按给定顺序展示
    if (qualityNames.isNotEmpty && qualityNames.length == videoUrls.length) {
      return [
        for (var i = 0; i < videoUrls.length; i++)
          VideoQuality(
            label: qualityNames[i],
            url: videoUrls[i],
            br: videoUrls.length - i,
            audioUrl: _audioAt(i),
          ),
      ];
    }
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

  /// 取第 [i] 档对应的音轨地址（没有则为 null）
  String? _audioAt(int i) {
    if (i < 0 || i >= audioUrls.length) return null;
    final audio = audioUrls[i].trim();
    return audio.isEmpty ? null : audio;
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
    // 空标题只保留平台前缀，避免拼成 douyin_<id>_<id>.mp4
    final base = safe.isEmpty
        ? platform
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