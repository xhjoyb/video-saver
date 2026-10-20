import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev/parse_probe_screen.dart';
import 'app/app_events.dart';
import 'app/splash_overlay.dart';
import 'history/history_store.dart';
import 'screens/history_screen.dart';
import 'screens/parse_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_settings.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';
import 'widgets/app_background.dart';
import 'widgets/liquid_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(prefs);
  await HistoryStore.instance.load();
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
              return MaterialPageRoute(builder: (_) => const RootShell());
            },
            builder: (context, child) {
              return AppBackground(
                child: SplashGate(child: child ?? const SizedBox.shrink()),
              );
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

  @override
  void initState() {
    super.initState();
    AppEvents.tabIndex.addListener(_syncTab);
  }

  void _syncTab() {
    if (!mounted) return;
    setState(() => _index = AppEvents.tabIndex.value);
  }

  @override
  void dispose() {
    AppEvents.tabIndex.removeListener(_syncTab);
    super.dispose();
  }

  static const _pages = <Widget>[
    ParseScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  static const _items = <LiquidNavItem>[
    LiquidNavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      label: '解析',
    ),
    LiquidNavItem(
      icon: Icons.video_library_outlined,
      activeIcon: Icons.video_library_rounded,
      label: '记录',
    ),
    LiquidNavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
    ),
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
            child: LiquidNavBar(
              items: _items,
              index: _index,
              onChanged: (i) => AppEvents.tabIndex.value = i,
            ),
          ),
        ),
      ),
    );
  }
}

// 旧的 _NavMeta / _NavItem 已由 widgets/liquid_nav_bar.dart 中的
// LiquidNavItem / LiquidNavBar 取代。