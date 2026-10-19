import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev/parse_probe_screen.dart';
import 'screens/history_screen.dart';
import 'screens/parse_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_settings.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';
import 'widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(prefs);
  runApp(VideoSaverApp(settings: settings));
}

class VideoSaverApp extends StatelessWidget {
  const VideoSaverApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: settings,
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return MaterialApp(
            title: '视频嗅探',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(AppPalette.light),
            darkTheme: buildAppTheme(AppPalette.dark),
            themeMode: settings.themeMode,
            initialRoute:
                WidgetsBinding.instance.platformDispatcher.defaultRouteName,
            onGenerateRoute: (routeSettings) {
              if (routeSettings.name == '/probe') {
                return MaterialPageRoute(
                  builder: (_) => const ParseProbeScreen(),
                );
              }
              return MaterialPageRoute(builder: (_) => const ParseProbeScreen());
            },
            builder: (context, child) {
              return AppBackground(child: child ?? const SizedBox.shrink());
            },
          );
        },
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _pages = <Widget>[
    ParseScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  static const _items = <_NavMeta>[
    _NavMeta(icon: Icons.auto_awesome_rounded, label: '解析'),
    _NavMeta(icon: Icons.history_rounded, label: '记录'),
    _NavMeta(icon: Icons.tune_rounded, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay =
        (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.navBar,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                for (int i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      meta: _items[i],
                      selected: _index == i,
                      onTap: () => setState(() => _index = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavMeta {
  const _NavMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final _NavMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.faint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.accent.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(meta.icon, size: 19, color: color),
            const SizedBox(height: 3),
            Text(
              meta.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}