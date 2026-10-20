import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../download/download_service.dart';
import '../history/history_item.dart';
import '../history/history_store.dart';
import '../parser/parse_controller.dart';
import '../parser/parse_result.dart';
import '../platform/media_store.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/platform_item.dart';
import '../widgets/primary_button.dart';

class ParseScreen extends StatefulWidget {
  const ParseScreen({super.key});

  @override
  State<ParseScreen> createState() => _ParseScreenState();
}

class _ParseScreenState extends State<ParseScreen> {
  final TextEditingController _linkController = TextEditingController();
  final ParseController _parse = ParseController();
  bool _downloading = false;
  double _progress = 0;
  String? _lastRecordedId;

  @override
  void initState() {
    super.initState();
    _parse.addListener(_onParseChanged);
  }

  void _onParseChanged() {
    if (!mounted) return;
    setState(() {});
    final error = _parse.error;
    if (error != null && _parse.stage == ParseStage.error) {
      _toast(error);
    }
    final result = _parse.result;
    if (result != null &&
        _parse.stage == ParseStage.done &&
        _lastRecordedId != result.awemeId) {
      _lastRecordedId = result.awemeId;
      HistoryStore.instance.add(
        HistoryItem(
          awemeId: result.awemeId,
          platform: result.platform,
          title: result.title,
          author: result.author,
          coverUrl: result.coverUrl,
          videoUrl: result.videoUrls.first,
          durationMs: result.durationMs,
          savedAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _parse.removeListener(_onParseChanged);
    _parse.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('剪贴板里没有可用的文本');
      return;
    }
    _linkController.text = text;
    _linkController.selection = TextSelection.collapsed(offset: text.length);
    _toast('已粘贴分享链接');
  }

  Future<void> _startParse() async {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      _toast('先粘贴一条分享链接');
      return;
    }
    FocusScope.of(context).unfocus();
    await _parse.parse(text);
  }

  Future<void> _download() async {
    final result = _parse.result;
    if (result == null || result.videoUrls.isEmpty) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final file = await DownloadService.download(
        result.videoUrls.first,
        result.fileName,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          final p = received / total;
          if ((p - _progress).abs() >= 0.01) {
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted) return;
      final saved = await MediaStore.saveVideo(file, result.fileName);
      if (!mounted) return;
      if (saved != null) {
        await HistoryStore.instance.markDownloaded(
          result.awemeId,
          'Movies/VideoSaver/${result.fileName}',
        );
        _toast('已保存到相册：Movies/VideoSaver');
        try {
          await file.delete();
        } catch (_) {}
      } else {
        _toast('已保存到：${file.path}');
      }
    } catch (e) {
      if (mounted) _toast('下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      children: [
        _TopGlow(color: p.accent),
        SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              _buildHeader(p),
              const SizedBox(height: 28),
              Text('解析抖音视频\n保存无水印原片', style: AppText.hero(context)),
              const SizedBox(height: 10),
              Text('粘贴分享链接，自动解析原始视频地址', style: AppText.sub(context)),
              const SizedBox(height: 24),
              _buildInputCard(context),
              if (_parse.stage == ParseStage.done && _parse.result != null) ...[
                const SizedBox(height: 16),
                _buildResultCard(context, _parse.result!),
              ],
              const SizedBox(height: 28),
              _buildPlatforms(context),
              const SizedBox(height: 28),
              _buildRecent(context),
            ],
          ),
        ),
        // 隐藏 WebView：放在屏幕外，保持正常尺寸以便页面 JS 正常执行
        Positioned(
          left: -1200,
          top: -1200,
          child: SizedBox(
            width: 420,
            height: 900,
            child: WebViewWidget(controller: _parse.web),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AppPalette p) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [p.accent, p.accent2]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          '视频嗅探',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
        ),
      ],
    );
  }

  Widget _buildInputCard(BuildContext context) {
    final p = context.palette;
    final busy = _parse.busy;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        children: [
          TextField(
            controller: _linkController,
            minLines: 1,
            maxLines: 3,
            style: AppText.body(context),
            cursorColor: p.accent,
            cursorWidth: 2,
            enabled: !busy,
            decoration: InputDecoration(
              hintText: '粘贴抖音分享链接…',
              hintStyle: TextStyle(fontSize: 13.5, color: p.faint),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _PasteButton(onTap: busy ? null : _paste),
              const Spacer(),
              PrimaryButton(
                label: _stageLabel(),
                icon: Icons.bolt_rounded,
                height: 40,
                loading: busy,
                onPressed: busy ? null : _startParse,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _stageLabel() {
    switch (_parse.stage) {
      case ParseStage.resolving:
        return '识别中';
      case ParseStage.loading:
        return '加载中';
      case ParseStage.parsing:
        return '解析中';
      default:
        return '开始解析';
    }
  }

  Widget _buildResultCard(BuildContext context, ParseResult result) {
    final p = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                result.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: p.cardAlt,
                  child: Icon(Icons.movie_outlined, color: p.faint, size: 36),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.author.isEmpty ? '抖音' : '@${result.author}',
                        style: AppText.label(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(result.durationText, style: AppText.label(context)),
                  ],
                ),
                const SizedBox(height: 14),
                if (_downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 6,
                      backgroundColor: p.cardAlt,
                      valueColor: AlwaysStoppedAnimation(p.accent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('下载中 ${(_progress * 100).toStringAsFixed(0)}%', style: AppText.label(context)),
                ] else
                  PrimaryButton(
                    label: '下载无水印视频',
                    icon: Icons.download_rounded,
                    height: 42,
                    expand: true,
                    onPressed: _download,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatforms(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('支持平台', style: AppText.section(context)),
            const Spacer(),
            Text('抖音已接入', style: AppText.label(context)),
          ],
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(
              child: PlatformItem(
                name: '抖音',
                icon: Icons.music_note_rounded,
                active: true,
                badge: 'NEW',
              ),
            ),
            Expanded(child: PlatformItem(name: '快手', icon: Icons.videocam_rounded)),
            Expanded(child: PlatformItem(name: '小红书', icon: Icons.bookmark_rounded)),
            Expanded(child: PlatformItem(name: 'B 站', icon: Icons.live_tv_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _buildRecent(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('最近解析', style: AppText.section(context)),
            const Spacer(),
            Text('查看全部', style: AppText.label(context)),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: p.cardAlt,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.movie_outlined, size: 18, color: p.faint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _parse.stage == ParseStage.done ? '本次解析结果已生成' : '还没有解析记录',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('先粘贴一条链接试试', style: AppText.label(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.cardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_paste_rounded, size: 14, color: p.dim),
            const SizedBox(width: 6),
            Text('粘贴', style: TextStyle(fontSize: 12.5, color: p.dim)),
          ],
        ),
      ),
    );
  }
}

/// 顶部单点光晕：径向渐变自然淡出，不铺满整屏
class _TopGlow extends StatelessWidget {
  const _TopGlow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -120,
      left: -70,
      child: IgnorePointer(
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withOpacity(0.18),
                color.withOpacity(0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}