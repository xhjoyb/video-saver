import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path_provider/path_provider.dart';

import '../platform/bilibili_session.dart';
import 'douyin_parser.dart';
import 'parse_result.dart';

/// B 站解析：Web wbi 签名路线（不走 App 的 gRPC）
///
/// 已验证：
/// - `x/web-interface/view` 免签名
/// - `x/player/wbi/playurl` 需 wbi 签名
/// - **`fnval=1`（durl 单文件 mp4）通道即使登录也被服务端卡在 720P**：
///   带 SESSDATA 请求 qn=80 仍返回 `quality=64 / accept=[64,16]`
/// - **1080P 只在 DASH（`fnval=4048`）通道下发**：`quality=80`、
///   `accept=[120,116,80,64,32,16]`，但视频流无音轨，必须与 audio 流合流
/// - 直链下载必须带 `Referer: https://www.bilibili.com/`
class BilibiliParser {
  BilibiliParser._();

  static const String userAgent = DouyinParser.userAgent;
  static const String referer = 'https://www.bilibili.com/';

  /// DASH：音视频分离，1080P 起只有这个通道
  static const int _dashFnval = 4048;

  /// durl：单个 mp4（含音轨），最高 720P，下载即用无需合流
  static const int _durlFnval = 1;

  static final RegExp _bvidRe = RegExp(r'BV[0-9A-Za-z]{10}');
  static final RegExp _urlRe = RegExp(r'https?://[^\s\u4e00-\u9fa5]+');
  static final RegExp _b23Re = RegExp(r'https?://b23\.tv/[A-Za-z0-9]+');

  /// 从分享文本里取出可用的 URL：
  /// 抖音/B 站分享文本常把中文、全角标点紧贴在 URL 后面，必须切干净
  static String? extractShareUrl(String text) {
    final short = _b23Re.firstMatch(text)?.group(0);
    if (short != null) return short;

    var url = _urlRe.firstMatch(text)?.group(0);
    if (url == null) return null;
    url = url.replaceAll(
      RegExp(r'''[)\]}>.,;:!?"'，。；：！？、）】」』]+$'''),
      '',
    );
    return url;
  }

  static const List<int> _mixinTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  static bool looksLike(String text) {
    if (_bvidRe.hasMatch(text)) return true;
    final lower = text.toLowerCase();
    return lower.contains('bilibili.com') || lower.contains('b23.tv');
  }

  static String? extractBvid(String text) {
    final match = _bvidRe.firstMatch(text);
    if (match != null) return match.group(0);
    final param = RegExp(r'[?&]bvid=(BV[0-9A-Za-z]{10})').firstMatch(text);
    return param?.group(1);
  }

  /// 支持纯 BV 号 / 完整链接 / b23.tv 短链（跟随最多 3 跳）
  static Future<String?> resolveBvid(String input) async {
    final direct = extractBvid(input);
    if (direct != null) return direct;

    final url = extractShareUrl(input);
    if (url == null) return null;

    final location = await _followRedirects(url);
    if (location != null) {
      final bvid = extractBvid(location);
      if (bvid != null) return bvid;
    }

    // 兜底：个别短链不返回 302，而是在 HTML 里放跳转链接
    final html = await _getText(url);
    if (html == null) return null;
    return extractBvid(html);
  }

  static Future<String?> _getText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.refererHeader, referer);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode == 200 ? body : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _followRedirects(String url) async {
    var current = url;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      for (var hop = 0; hop < 3; hop++) {
        final request = await client.getUrl(Uri.parse(current));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) return null;
          current = location;
          continue;
        }
        return current;
      }
      return current;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.refererHeader, referer);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // 有登录态就带上，1080P / 受限视频才拿得到
      final cookie = await BilibiliSession.cookie();
      if (cookie != null && cookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('接口返回格式异常');
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  /// playurl 统一入口：wbi 签名 + 固定平台参数
  static Future<Map<String, dynamic>> _playUrl({
    required String bvid,
    required String cid,
    required int qn,
    required int fnval,
    required String mixin,
  }) {
    final query = signQuery(
      {
        'bvid': bvid,
        'cid': cid,
        'qn': '$qn',
        'fnval': '$fnval',
        'fnver': '0',
        'fourk': '1',
      },
      mixin,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    return _getJson('https://api.bilibili.com/x/player/wbi/playurl?$query');
  }

  static String _short(Object error) {
    final text = error.toString();
    return text.length > 60 ? text.substring(0, 60) : text;
  }

  /// 从 dash 节点挑出每个清晰度档位的最佳编码
  ///
  /// 同一档位 B 站会同时下发 avc1 与 hevc 两条流（清晰度 id 相同），
  /// 这里优先保留 avc1（兼容性最好），同编码再按码率取高者；
  /// 音轨统一取码率最高的一条（DASH 的音轨与清晰度无关）。
  static List<DashQuality> pickDashQualities(
    List<dynamic> videos,
    List<dynamic> audios,
  ) {
    final best = <int, _DashVideo>{};
    for (final raw in videos) {
      if (raw is! Map) continue;
      final id = int.tryParse('${raw['id']}') ?? 0;
      if (id <= 0) continue;
      final url = '${raw['baseUrl'] ?? raw['base_url'] ?? ''}';
      if (url.isEmpty) continue;
      final codecs = '${raw['codecs'] ?? ''}';
      final candidate = _DashVideo(
        url: url,
        bandwidth: int.tryParse('${raw['bandwidth']}') ?? 0,
        avc: codecs.startsWith('avc'),
      );
      final current = best[id];
      if (current == null ||
          (candidate.avc && !current.avc) ||
          (candidate.avc == current.avc &&
              candidate.bandwidth > current.bandwidth)) {
        best[id] = candidate;
      }
    }

    var audioUrl = '';
    var audioBandwidth = -1;
    for (final raw in audios) {
      if (raw is! Map) continue;
      final url = '${raw['baseUrl'] ?? raw['base_url'] ?? ''}';
      if (url.isEmpty) continue;
      final bandwidth = int.tryParse('${raw['bandwidth']}') ?? 0;
      if (bandwidth > audioBandwidth) {
        audioBandwidth = bandwidth;
        audioUrl = url;
      }
    }

    final ids = best.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final id in ids)
        DashQuality(
          id: id,
          videoUrl: best[id]!.url,
          audioUrl: audioUrl,
          bandwidth: best[id]!.bandwidth,
        ),
    ];
  }

  static String mixinKey(String imgKey, String subKey) {
    final source = imgKey + subKey;
    final buffer = StringBuffer();
    for (final index in _mixinTab) {
      if (index < source.length) buffer.write(source[index]);
      if (buffer.length >= 32) break;
    }
    final result = buffer.toString();
    return result.length > 32 ? result.substring(0, 32) : result;
  }

  /// 生成带 w_rid 的 query；[wts] 由调用方传入，便于单测固定时间
  static String signQuery(Map<String, String> params, String mixin, int wts) {
    final merged = Map<String, String>.from(params)..['wts'] = '$wts';
    final keys = merged.keys.toList()..sort();
    final pairs = <String>[];
    for (final key in keys) {
      final value = merged[key]!.replaceAll(RegExp(r"[!'()*]"), '');
      pairs.add('${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}');
    }
    final query = pairs.join('&');
    final rid = crypto.md5.convert(utf8.encode(query + mixin)).toString();
    return '$query&w_rid=$rid';
  }

  static String? _cachedMixin;
  static DateTime? _cachedAt;

  static Future<String> _wbiMixin() async {
    // nav 下发的 img_key/sub_key 有效期约 1 小时，缓存避免每档 qn 都多打一次
    final cachedAt = _cachedAt;
    final cached = _cachedMixin;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt).inMinutes < 60) {
      return cached;
    }
    final nav = await _getJson('https://api.bilibili.com/x/web-interface/nav');
    final data = nav['data'];
    final wbi = data is Map ? data['wbi_img'] : null;
    final imgUrl = '${wbi is Map ? wbi['img_url'] ?? '' : ''}';
    final subUrl = '${wbi is Map ? wbi['sub_url'] ?? '' : ''}';
    if (imgUrl.isEmpty || subUrl.isEmpty) {
      throw const FormatException('没有拿到 wbi 密钥');
    }
    final imgKey = imgUrl.split('/').last.split('.').first;
    final subKey = subUrl.split('/').last.split('.').first;
    final mixin = mixinKey(imgKey, subKey);
    _cachedMixin = mixin;
    _cachedAt = DateTime.now();
    return mixin;
  }

  static Future<ParseResult> parse(String input) async {
    final bvid = await resolveBvid(input);
    if (bvid == null) {
      throw const FormatException('没有识别到 B 站视频链接');
    }

    final view = await _getJson(
      'https://api.bilibili.com/x/web-interface/view?bvid=$bvid',
    );
    if ('${view['code']}' != '0') {
      throw FormatException('${view['message'] ?? '视频信息获取失败'}');
    }
    final info = view['data'] as Map<String, dynamic>?;
    if (info == null) throw const FormatException('视频信息为空');
    final cid = info['cid'];
    if (cid == null) throw const FormatException('没有拿到 cid');

    final mixin = await _wbiMixin();
    final urls = <String>[];
    final labels = <String>[];
    final audios = <String>[];
    final diag = <String>[];
    final cookie = await BilibiliSession.cookie();
    diag.add(
      'bvid=$bvid login=${cookie != null} cookieLen=${cookie?.length ?? 0}',
    );

    var authExpired = false;
    final seenQuality = <String>{};

    // 1080P 只在 DASH 通道下发：`fnval=1`（durl 单文件）即使登录也被服务端卡在 720P，
    // 所以最高档走 dash（视频流 + 音轨，下载后由原生 MediaMuxer 合流），
    // 720P / 360P 仍走 durl 单文件，省一次合流、下载更快。
    var dashPicks = <DashQuality>[];
    try {
      final res = await _playUrl(
        bvid: bvid,
        cid: '$cid',
        qn: 120,
        fnval: _dashFnval,
        mixin: mixin,
      );
      final code = '${res['code']}';
      if (code != '0') {
        diag.add('dash code=$code');
        if (code == '-101') authExpired = true;
      } else {
        final data = res['data'];
        final dash = data is Map ? data['dash'] : null;
        if (dash is Map) {
          dashPicks = pickDashQualities(
            (dash['video'] as List?) ?? const [],
            (dash['audio'] as List?) ?? const [],
          );
          diag.add(
            'dash ids=${dashPicks.map((e) => e.id).join('/')} '
            'audio=${dashPicks.isNotEmpty && dashPicks.first.audioUrl.isNotEmpty} '
            'accept=${data['accept_quality']}',
          );
        } else {
          diag.add('dash empty');
        }
      }
    } catch (e) {
      diag.add('dash err=${_short(e)}');
    }

    // 只取最高一档 dash（1080P 及以上）；低于 720P 交给 durl 单文件
    for (final pick in dashPicks) {
      if (pick.id < 80 || pick.audioUrl.isEmpty) continue;
      final key = '${pick.id}';
      if (!seenQuality.add(key)) break;
      urls.add(pick.videoUrl);
      labels.add(_qualityLabel(key));
      audios.add(pick.audioUrl);
      break;
    }

    for (final qn in [64, 16]) {
      try {
        final res = await _playUrl(
          bvid: bvid,
          cid: '$cid',
          qn: qn,
          fnval: _durlFnval,
          mixin: mixin,
        );
        final code = '${res['code']}';
        if (code != '0') {
          diag.add('qn$qn code=$code');
          if (code == '-101') authExpired = true;
          continue;
        }
        final data = res['data'];
        if (data is! Map) {
          diag.add('qn$qn no-data');
          continue;
        }
        final durl = (data['durl'] as List?) ?? const [];
        if (durl.isEmpty) {
          diag.add('qn$qn durl-empty');
          continue;
        }
        final first = durl.first;
        final quality = '${data['quality'] ?? qn}';
        diag.add('qn$qn->q$quality accept=${data['accept_quality']}');
        // 按码率档位去重：不同 qn 请求同一档时，返回的直链签名参数不同，
        // 只比 URL 字符串会重复出两个「720P」
        if (!seenQuality.add(quality)) continue;
        final url = first is Map ? '${first['url'] ?? ''}' : '';
        if (url.isEmpty || urls.contains(url)) continue;
        urls.add(url);
        labels.add(_qualityLabel(quality));
        audios.add('');
      } catch (e) {
        diag.add('qn$qn err=${_short(e)}');
      }
    }

    // durl 完全拿不到（部分受限视频只有 dash）时兜底：把 dash 的档位全放出来
    if (urls.isEmpty) {
      for (final pick in dashPicks) {
        final key = '${pick.id}';
        if (!seenQuality.add(key)) continue;
        urls.add(pick.videoUrl);
        labels.add(_qualityLabel(key));
        audios.add(pick.audioUrl);
      }
    }

    await _writeDiag(diag);

    if (urls.isEmpty && authExpired) {
      throw const FormatException('B 站登录已过期，请到「设置 → B 站登录」重新登录');
    }
    if (urls.isEmpty) {
      throw const FormatException('没有拿到播放地址（可能需要登录或视频受限）');
    }

    final owner = info['owner'];
    return ParseResult(
      platform: 'bilibili',
      awemeId: bvid,
      title: '${info['title'] ?? ''}',
      author: '${owner is Map ? owner['name'] ?? '' : ''}',
      coverUrl: '${info['pic'] ?? ''}',
      durationMs: (int.tryParse('${info['duration'] ?? 0}') ?? 0) * 1000,
      videoUrls: urls,
      audioUrls: audios,
      qualityNames: labels,
    );
  }

  /// 把每次请求的服务端返回写入 app 目录（bili_diag.log），
  /// 用于排查「登录了仍拿不到 1080P」是 cookie 未生效还是服务端只给 720P
  static Future<void> _writeDiag(List<String> lines) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final stamp = DateTime.now().toIso8601String();
      await File('${dir.path}/bili_diag.log').writeAsString(
        '$stamp\n${lines.join('\n')}\n\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static String _qualityLabel(String quality) {
    switch (quality) {
      case '120':
        return '4K';
      case '116':
        return '1080P60';
      case '112':
        return '1080P+';
      case '80':
        return '1080P';
      case '64':
        return '720P';
      case '32':
        return '480P';
      case '16':
        return '360P';
      default:
        return '原画';
    }
  }
}

/// DASH 通道里的一档视频流。
///
/// 视频流本身**不含音轨**，下载后必须与 [audioUrl] 合流才能得到可播放的成片
/// （B 站 1080P 起只走 DASH；720P 及以下仍有 durl 单文件）。
class DashQuality {
  const DashQuality({
    required this.id,
    required this.videoUrl,
    required this.audioUrl,
    required this.bandwidth,
  });

  /// 清晰度 id：120=4K / 116=1080P60 / 112=1080P+ / 80=1080P / 64=720P / 32=480P / 16=360P
  final int id;
  final String videoUrl;
  final String audioUrl;
  final int bandwidth;
}

class _DashVideo {
  const _DashVideo({
    required this.url,
    required this.bandwidth,
    required this.avc,
  });

  final String url;
  final int bandwidth;
  final bool avc;
}