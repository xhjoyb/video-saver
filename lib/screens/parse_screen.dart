import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/platform_chip.dart';

class ParseScreen extends StatefulWidget {
  const ParseScreen({super.key});

  @override
  State<ParseScreen> createState() => _ParseScreenState();
}

class _ParseScreenState extends State<ParseScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _linkController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _halo;
  bool _parsing = false;

  @override
  void initState() {
    super.initState();
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _halo.dispose();
    _focusNode.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('剪贴板里没有可用的文本');
      return;
    }
    setState(() {
      _linkController.text = text;
      _linkController.selection = TextSelection.collapsed(offset: text.length);
    });
    _toast('已从剪贴板粘贴');
  }

  Future<void> _parse() async {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      _toast('先粘贴一条分享链接');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _parsing = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _parsing = false);
    _toast('解析引擎接入中，下一步将真正返回无水印直链');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _HaloBackground(animation: _halo),
        SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 28),
                _buildHero(),
                const SizedBox(height: 22),
                _buildInputCard(),
                const SizedBox(height: 22),
                _buildPlatforms(),
                const SizedBox(height: 28),
                _buildRecent(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: AppGradients.brand,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '视频嗅探',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'VIDEO SAVER',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
                color: AppColors.textFaint.withOpacity(0.9),
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'v0.2.0 · 开发版',
                style: TextStyle(fontSize: 10.5, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('粘贴链接，\n一键去水印', style: TextStyle(
          fontSize: 30,
          height: 1.26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: AppColors.text,
        )),
        const SizedBox(height: 12),
        Text(
          '解析抖音短视频原始地址，保存到相册，不留下平台水印。',
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.textDim.withOpacity(0.95),
          ),
        ),
      ],
    );
  }

  Widget _buildInputCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 12),
      child: Column(
        children: [
          TextField(
            controller: _linkController,
            focusNode: _focusNode,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(fontSize: 14, color: AppColors.text, height: 1.5),
            cursorColor: AppColors.accent,
            cursorWidth: 2,
            decoration: InputDecoration(
              hintText: '粘贴抖音分享链接，例如 https://v.douyin.com/…',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textFaint),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _MiniAction(
                icon: Icons.content_paste_rounded,
                label: '粘贴',
                onTap: _pasteFromClipboard,
              ),
              const SizedBox(width: 8),
              _MiniAction(
                icon: Icons.center_focus_strong_rounded,
                label: '识别',
                onTap: () => _toast('图片/二维码识别开发中'),
              ),
              const Spacer(),
              GradientButton(
                label: '解析',
                icon: Icons.bolt_rounded,
                height: 42,
                loading: _parsing,
                onPressed: _parse,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlatforms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('支持平台', style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            )),
            const SizedBox(width: 8),
            Text('1 / 4 已接入', style: TextStyle(
              fontSize: 11,
              color: AppColors.textFaint.withOpacity(0.9),
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(child: PlatformChip(name: '抖音', icon: Icons.music_note_rounded, active: true, badge: 'NEW')),
            SizedBox(width: 9),
            Expanded(child: PlatformChip(name: '快手', icon: Icons.videocam_rounded)),
            SizedBox(width: 9),
            Expanded(child: PlatformChip(name: '小红书', icon: Icons.bookmark_rounded)),
            SizedBox(width: 9),
            Expanded(child: PlatformChip(name: 'B 站', icon: Icons.live_tv_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _buildRecent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('最近解析', style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            )),
            const Spacer(),
            Text('查看全部', style: TextStyle(
              fontSize: 11.5,
              color: AppColors.cyan.withOpacity(0.85),
            )),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.035),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: const Icon(Icons.movie_filter_rounded, color: AppColors.textFaint, size: 26),
              ),
              const SizedBox(height: 14),
              const Text('还没有解析记录', style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              )),
              const SizedBox(height: 6),
              const Text('粘贴一条抖音分享链接，试试第一解析', style: TextStyle(
                fontSize: 12,
                color: AppColors.textFaint,
              )),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textDim),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }
}

class _HaloBackground extends StatelessWidget {
  const _HaloBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                top: -140 - 24 * t,
                left: -90,
                child: _Glow(color: AppColors.accent.withOpacity(0.28), size: 330),
              ),
              Positioned(
                top: -40 + 34 * t,
                right: -120,
                child: _Glow(color: AppColors.cyan.withOpacity(0.16), size: 310),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.bg.withOpacity(0.55),
                        AppColors.bg,
                      ],
                      stops: const [0.32, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}