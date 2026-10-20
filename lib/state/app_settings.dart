import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackgroundType { none, image, video }

/// 全局偏好：主题模式 + 自定义背景，持久化到 SharedPreferences
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs) {
    _themeMode = _parseThemeMode(_prefs.getString(_kThemeMode));
    _bgType = _parseBgType(_prefs.getString(_kBgType));
    _autoClipboard = _prefs.getBool(_kAutoClipboard) ?? true;
    _concurrency = _prefs.getInt(_kConcurrency) ?? 2;
    final path = _prefs.getString(_kBgPath);
    if (path != null && File(path).existsSync()) {
      _bgPath = path;
    } else {
      _bgType = BackgroundType.none;
      _bgPath = null;
    }
  }

  static const _kThemeMode = 'theme_mode';
  static const _kBgType = 'bg_type';
  static const _kBgPath = 'bg_path';
  static const _kAutoClipboard = 'auto_clipboard';
  static const _kConcurrency = 'download_concurrency';

  final SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  BackgroundType _bgType = BackgroundType.none;
  String? _bgPath;
  bool _autoClipboard = true;
  int _concurrency = 2;
  bool _busy = false;
  String? _lastError;

  ThemeMode get themeMode => _themeMode;
  BackgroundType get bgType => _bgType;
  String? get bgPath => _bgPath;

  /// 回到前台时自动读取剪贴板里的分享链接（只填入输入框，不自动解析）
  bool get autoClipboard => _autoClipboard;

  /// 下载并发上限（1–3，默认 2）
  int get downloadConcurrency => _concurrency;

  bool get busy => _busy;
  String? get lastError => _lastError;

  static ThemeMode _parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static BackgroundType _parseBgType(String? raw) {
    switch (raw) {
      case 'image':
        return BackgroundType.image;
      case 'video':
        return BackgroundType.video;
      default:
        return BackgroundType.none;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setAutoClipboard(bool value) async {
    if (_autoClipboard == value) return;
    _autoClipboard = value;
    await _prefs.setBool(_kAutoClipboard, value);
    notifyListeners();
  }

  Future<void> setDownloadConcurrency(int value) async {
    final next = value.clamp(1, 3).toInt();
    if (_concurrency == next) return;
    _concurrency = next;
    await _prefs.setInt(_kConcurrency, next);
    notifyListeners();
  }

  Future<bool> pickBackgroundImage() async {
    if (_busy) return false;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (picked == null) return false;
      await _store(picked, BackgroundType.image);
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> pickBackgroundVideo() async {
    if (_busy) return false;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (picked == null) return false;
      await _store(picked, BackgroundType.video);
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> _store(XFile picked, BackgroundType type) async {
    final supportDir = await getApplicationSupportDirectory();
    final bgDir = Directory('${supportDir.path}/backgrounds');
    if (!bgDir.existsSync()) {
      await bgDir.create(recursive: true);
    }
    final ext = _extensionOf(picked.path, type);
    final target = File('${bgDir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(picked.path).copy(target.path);
    await _cleanupOld(bgDir, target.path);

    _bgType = type;
    _bgPath = target.path;
    await _prefs.setString(_kBgType, type.name);
    await _prefs.setString(_kBgPath, target.path);
    notifyListeners();
    return null;
  }

  String _extensionOf(String path, BackgroundType type) {
    final dot = path.lastIndexOf('.');
    if (dot > 0 && path.length - dot <= 5) {
      return path.substring(dot).toLowerCase();
    }
    return type == BackgroundType.video ? '.mp4' : '.jpg';
  }

  Future<void> _cleanupOld(Directory dir, String keep) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path != keep) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> clearBackground() async {
    final path = _bgPath;
    _bgType = BackgroundType.none;
    _bgPath = null;
    await _prefs.remove(_kBgType);
    await _prefs.remove(_kBgPath);
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
  }
}

/// 用 InheritedNotifier 向下暴露设置，避免引入额外状态管理依赖
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope 未挂载');
    return scope!.notifier!;
  }
}