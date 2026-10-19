import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _parsing = false;

  @override
  void dispose() {
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

  Future<void> _parse() async {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      _toast('先粘贴一条分享链接');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _parsing = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _parsing = false);
    _toast('解析能力接入中，下一步将返回无水印直链');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _TopGlow(),
        SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              const Text('解析抖音视频\n保存无水印原片', style: AppText.hero),
              const SizedBox(height: 10),
              const Text('粘贴分享链接，自动解析原始视频地址', style: AppText.sub),
              const SizedBox(height: 24),
              _buildInputCard(),
              const SizedBox(height: 28),
              _buildPlatforms(),
              const SizedBox(height: 28),
              _buildRecent(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppGradients.brand,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        const Text(
          '视频嗅探',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => _toast('设置页在下方导航'),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.settings_outlined, size: 20, color: AppColors.faint),
          ),
        ),
      ],
    );
  }

  Widget _buildInputCard() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        children: [
          TextField(
            controller: _linkController,
            minLines: 1,
            maxLines: 3,
            style: AppText.body,
            cursorColor: AppColors.accent,
            cursorWidth: 2,
            decoration: const InputDecoration(
              hintText: '粘贴抖音分享链接…',
              hintStyle: TextStyle(fontSize: 13.5, color: AppColors.faint),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _PasteButton(onTap: _paste),
              const Spacer(),
              PrimaryButton(
                label: '开始解析',
                icon: Icons.bolt_rounded,
                height: 40,
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
          children: const [
            Text('支持平台', style: AppText.section),
            Spacer(),
            Text('抖音已接入', style: AppText.label),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: const [
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

  Widget _buildRecent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Text('最近解析', style: AppText.section),
            Spacer(),
            Text('查看全部', style: AppText.label),
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
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.movie_outlined, size: 18, color: AppColors.faint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('还没有解析记录', style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    )),
                    SizedBox(height: 3),
                    Text('先粘贴一条链接试试', style: AppText.label),
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

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.content_paste_rounded, size: 14, color: AppColors.dim),
            SizedBox(width: 6),
            Text('粘贴', style: TextStyle(fontSize: 12.5, color: AppColors.dim)),
          ],
        ),
      ),
    );
  }
}

/// 顶部单点光晕：径向渐变自然淡出，不铺满整屏，避免背景显脏
class _TopGlow extends StatelessWidget {
  const _TopGlow();

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
                AppColors.accent.withOpacity(0.16),
                AppColors.accent.withOpacity(0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}