import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/app_events.dart';
import '../download/download_queue.dart';
import '../download/download_service.dart';
import '../history/history_item.dart';
import '../history/history_store.dart';
import '../parser/bilibili_parser.dart';
import '../parser/douyin_parser.dart';
import '../parser/kuaishou_parser.dart';
import '../parser/xiaohongshu_parser.dart';
import '../parser/parse_controller.dart';
import '../parser/parse_result.dart';
import '../platform/media_store.dart';
import '../state/app_settings.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/brand_logo.dart';
import '../widgets/platform_item.dart';
import '../widgets/primary_button.dart';

class ParseScreen extends StatefulWidget {
  const ParseScreen({super.key});

  @override
  State<ParseScreen> createState() => _ParseScreenState();
}

class _ParseScreenState extends State<ParseScreen> with WidgetsBindingObserver {
  final TextEditingController _linkController = TextEditingController();
  final ParseController _parse = ParseController();
  bool _downloading = false;
  double _progress = 0;
  String? _lastRecordedId;
  final Set<int> _selectedImages = <int>{};
  int _qualityIndex = 0;
  String? _lastClipboardText;
  bool _seenFirstResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parse.addListener(_onParseChanged);
    AppEvents.pendingParse.addListener(_onPendingParse);
    // 预热 WebView，缩短首次解析等待并提前拿到 cookie
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _parse.warmUp();
    });
  }

  void _onPendingParse() {
    final value = AppEvents.pendingParse.value;
    if (value == null || value.isEmpty) return;
    AppEvents.pendingParse.value = null;
    _linkController.text = value;
    _startParse();
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
      _qualityIndex = 0;
      _selectedImages
        ..clear()
        ..addAll(List<int>.generate(result.imageUrls.length, (i) => i));
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
    WidgetsBinding.instance.removeObserver(this);
    _parse.removeListener(_onParseChanged);
    AppEvents.pendingParse.removeListener(_onPendingParse);
    _parse.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 保存成功提示：带「去相册看看」，点击用系统查看器打开该文件
  void _toastSaved(String message, String? uri) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: uri == null
            ? null
            : SnackBarAction(
                label: '去相册看看',
                onPressed: () async {
                  final ok = await MediaStore.openMedia(uri);
                  if (!ok && mounted) _toast('没有找到能打开该文件的相册或播放器');
                },
              ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _maybeFillFromClipboard();
  }

  /// 从后台切回前台时读剪贴板：只识别抖音链接/纯 ID，且不覆盖已有输入
  Future<void> _maybeFillFromClipboard() async {
    // 冷启动首次进入不抢占剪贴板
    if (!_seenFirstResume) {
      _seenFirstResume = true;
      return;
    }
    final settings = AppSettingsScope.of(context);
    if (!settings.autoClipboard || _parse.busy) return;
    if (_linkController.text.trim().isNotEmpty) return;

    String text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = (data?.text ?? '').trim();
    } catch (_) {
      return;
    }
    if (text.isEmpty || text == _lastClipboardText) return;

    final hasLink = DouyinParser.extractUrl(text) != null;
    final isPureId = RegExp(r'^\d{15,20}$').hasMatch(text);
    if (!hasLink && !isPureId) return;

    _lastClipboardText = text;
    if (!mounted) return;
    setState(() {
      _linkController.text = text;
      _linkController.selection = TextSelection.collapsed(offset: text.length);
    });
    _toast('已从剪贴板识别到链接，点「开始解析」即可');
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
    final qualities = result.qualities;
    final quality = qualities[_qualityIndex.clamp(0, qualities.length - 1)];
    DownloadQueue.instance.enqueue(
      title: result.displayTitle,
      fileName: result.fileName,
      url: quality.url,
      platform: result.platform,
      referer: switch (result.platform) {
        'bilibili' => 'https://www.bilibili.com/',
        'kuaishou' => KuaishouParser.referer,
        'xiaohongshu' => XiaohongshuParser.referer,
        _ => 'https://www.douyin.com/',
      },
      userAgent: switch (result.platform) {
        'bilibili' => BilibiliParser.userAgent,
        'kuaishou' => KuaishouParser.userAgent,
        'xiaohongshu' => XiaohongshuParser.userAgent,
        _ => null,
      },
      awemeId: result.awemeId,
    );
    _toast('已加入下载队列');
  }

  Future<void> _downloadImages() async {
    final result = _parse.result;
    if (result == null || result.imageUrls.isEmpty) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    final indices = _selectedImages.toList()..sort();
    var done = 0;
    String? firstUri;
    try {
      for (final i in indices) {
        final url = result.imageUrls[i];
        final index = (i + 1).toString().padLeft(2, '0');
        final file = await DownloadService.download(url, '${result.awemeId}_$index.tmp');
        final ext = await DownloadService.detectImageExt(file);
        final name = '${result.awemeId}_$index.$ext';
        final mime = ext == 'png'
            ? 'image/png'
            : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final saved = await MediaStore.saveImage(file, name, mime: mime);
        if (saved == null) {
          throw StateError('第 ${i + 1} 张写入相册失败');
        }
        firstUri ??= saved;
        try {
          await file.delete();
        } catch (_) {}
        done++;
        if (mounted) {
          setState(() => _progress = done / indices.length);
        }
      }
      if (!mounted) return;
      await HistoryStore.instance.markDownloaded(
        result.awemeId,
        'Pictures/VideoSaver（${indices.length} 张）',
      );
      _toastSaved('已保存 ${indices.length} 张图片到相册', firstUri);
    } catch (e) {
      if (mounted) _toast('图片下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _buildImageGrid(BuildContext context, ParseResult result) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: result.imageUrls.length,
        itemBuilder: (context, i) {
          final selected = _selectedImages.contains(i);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedImages.remove(i);
                } else {
                  _selectedImages.add(i);
                }
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    result.imageUrls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: p.cardAlt),
                  ),
                ),
                if (selected)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.accent, width: 2),
                      color: p.accent.withOpacity(0.16),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: selected ? p.accent : Colors.white70,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
              Text('解析视频\n保存无水印原片', style: AppText.hero(context)),
              const SizedBox(height: 10),
              Text('粘贴分享链接，自动解析原始视频地址', style: AppText.sub(context)),
              const SizedBox(height: 24),
              _buildInputCard(context),
              if (_parse.stage == ParseStage.done && _parse.result != null) ...[
                const SizedBox(height: 16),
                _buildResultCard(context, _parse.result!),
              ],
              _buildQueueCard(),
              const SizedBox(height: 28),
              _buildPlatforms(context),
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
        const BrandLogo(size: 32),
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
              hintText: '粘贴视频分享链接…',
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
          if (result.isImages)
            _buildImageGrid(context, result)
          else
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
                        result.author.isEmpty ? '未知作者' : '@${result.author}',
                        style: AppText.label(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                        result.isVideo ? result.durationText : '图集 · ${result.imageUrls.length} 张',
                        style: AppText.label(context),
                      ),
                  ],
                ),
                if (result.isVideo && result.qualities.length > 1) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < result.qualities.length; i++)
                        GestureDetector(
                          onTap: () => setState(() => _qualityIndex = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: i == _qualityIndex
                                  ? p.accent.withOpacity(0.16)
                                  : p.cardAlt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: i == _qualityIndex ? p.accent : p.border,
                              ),
                            ),
                            child: Text(
                              result.qualities[i].label,
                              style: TextStyle(
                                fontSize: 11,
                                color: i == _qualityIndex ? p.accent : p.dim,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (result.isImages) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '已选 ${_selectedImages.length}/${result.imageUrls.length}',
                        style: AppText.label(context),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_selectedImages.length == result.imageUrls.length) {
                              _selectedImages.clear();
                            } else {
                              _selectedImages
                                ..clear()
                                ..addAll(List<int>.generate(
                                  result.imageUrls.length,
                                  (i) => i,
                                ));
                            }
                          });
                        },
                        child: Text(
                          _selectedImages.length == result.imageUrls.length ? '清空' : '全选',
                          style: TextStyle(fontSize: 11.5, color: p.accent),
                        ),
                      ),
                    ],
                  ),
                ],
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
                ] else if (result.isVideo)
                  PrimaryButton(
                    label: '加入下载队列',
                    icon: Icons.download_rounded,
                    height: 42,
                    expand: true,
                    onPressed: _download,
                  )
                else
                  PrimaryButton(
                    label: '保存选中（${_selectedImages.length}）',
                    icon: Icons.photo_library_rounded,
                    height: 42,
                    expand: true,
                    onPressed: _selectedImages.isEmpty ? null : _downloadImages,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 下载队列卡片：展示排队/进行中/已完成任务，可直接打开或取消
  Widget _buildQueueCard() {
    final queue = DownloadQueue.instance;
    return AnimatedBuilder(
      animation: queue,
      builder: (context, _) {
        final tasks = queue.tasks;
        if (tasks.isEmpty) return const SizedBox.shrink();
        final p = context.palette;
        final hasFinished = tasks.any((t) => t.finished);
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('下载队列', style: AppText.section(context)),
                    const Spacer(),
                    Text(
                      '运行 ${queue.runningCount} · 等待 ${queue.queuedCount}',
                      style: AppText.label(context),
                    ),
                  ],
                ),
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(context),
                              ),
                              const SizedBox(height: 4),
                              if (task.status == DownloadStatus.running)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: task.progress,
                                    minHeight: 3,
                                    backgroundColor: p.cardAlt,
                                    valueColor:
                                        AlwaysStoppedAnimation(p.accent),
                                  ),
                                )
                              else
                                Text(
                                  task.statusText,
                                  style: AppText.label(context),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (task.status == DownloadStatus.success &&
                            task.savedUri != null)
                          GestureDetector(
                            onTap: () => MediaStore.openMedia(task.savedUri!),
                            child: Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                              color: p.accent,
                            ),
                          )
                        else if (task.status == DownloadStatus.queued)
                          GestureDetector(
                            onTap: () => queue.cancel(task.id),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: p.faint,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (hasFinished) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: queue.removeFinished,
                      child: Text(
                        '清除已完成',
                        style: TextStyle(fontSize: 11.5, color: p.accent),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
            Text('已接入 3 个平台', style: AppText.label(context)),
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
              ),
            ),
            Expanded(
              child: PlatformItem(
                name: '快手',
                icon: Icons.videocam_rounded,
                active: true,
              ),
            ),
            Expanded(
              child: PlatformItem(
                name: '小红书',
                icon: Icons.bookmark_rounded,
              ),
            ),
            Expanded(
              child: PlatformItem(
                name: 'B 站',
                icon: Icons.live_tv_rounded,
                active: true,
              ),
            ),
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