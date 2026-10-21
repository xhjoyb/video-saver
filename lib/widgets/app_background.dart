import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_events.dart';
import '../state/app_settings.dart';
import '../theme/app_palette.dart';

/// 全局背景层：渐变底 → 图片/视频 → 可读性遮罩 → 页面内容
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final p = context.palette;
    final path = settings.bgPath;
    final hasCustom = settings.bgType != BackgroundType.none && path != null;

    return ValueListenableBuilder<bool>(
      valueListenable: AppEvents.hideBackground,
      builder: (context, hidden, _) {
        final showCustom = hasCustom && !hidden;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.bgTop, p.bgBottom],
                ),
              ),
            ),
            if (showCustom && settings.bgType == BackgroundType.image)
              Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (showCustom && settings.bgType == BackgroundType.video)
              _VideoBackground(path: path),
            if (showCustom) ColoredBox(color: p.scrim),
            child,
          ],
        );
      },
    );
  }
}

class _VideoBackground extends StatefulWidget {
  const _VideoBackground({required this.path});

  final String path;

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final controller = VideoPlayerController.file(File(widget.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _controller = null;
      _initController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return ColoredBox(color: context.palette.bgTop);
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}