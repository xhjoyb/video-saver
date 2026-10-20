import 'dart:io';

import 'package:flutter/services.dart';

/// 通过原生 channel 把下载好的文件写入系统相册（Movies/VideoSaver）
class MediaStore {
  MediaStore._();

  static const MethodChannel _channel = MethodChannel('videosaver/media');

  /// 返回 content:// uri；失败返回 null
  static Future<String?> saveVideo(File file, String displayName) async {
    try {
      return await _channel.invokeMethod<String>('saveVideo', {
        'path': file.path,
        'name': displayName,
        'mime': 'video/mp4',
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> saveImage(File file, String displayName, {String mime = 'image/jpeg'}) async {
    try {
      return await _channel.invokeMethod<String>('saveImage', {
        'path': file.path,
        'name': displayName,
        'mime': mime,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> isSupported() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isSupported');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 用系统查看器打开刚保存的媒体（相册 / 视频播放器）
  static Future<bool> openMedia(String uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openMedia', {'uri': uri});
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}