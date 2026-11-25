import 'dart:io';

import 'package:flutter/services.dart';

class PickedFolder {
  const PickedFolder(this.path, this.name, this.bookmark);
  final String path;
  final String name;
  final String? bookmark;
}

class ImageSize {
  const ImageSize(this.width, this.height);
  final int width;
  final int height;
}

/// iOS-only native helpers (see ios/Runner/AppDelegate.swift).
class Native {
  static const _ch = MethodChannel('imagedate/native');

  static bool get available => Platform.isIOS;

  /// Opens the Files folder picker. Keeps access to the folder for this app run
  /// and returns a bookmark to open it again in later runs.
  static Future<PickedFolder?> pickFolder() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('pickFolder');
    if (r == null) return null;
    return PickedFolder(r['path'] as String, r['name'] as String, r['bookmark'] as String?);
  }

  /// Opens a folder again from its bookmark. The result's bookmark is set when
  /// iOS gave a fresh one that must replace the stored one.
  static Future<PickedFolder> resolveBookmark(String bookmark) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('resolveBookmark', {'bookmark': bookmark});
    return PickedFolder(r!['path'] as String, r['name'] as String, r['bookmark'] as String?);
  }

  /// Asks iCloud Drive to download files that are not on the device yet.
  static Future<void> downloadICloud(List<String> paths) =>
      _ch.invokeMethod('downloadICloud', {'paths': paths});

  /// Decodes any image iOS can read (HEIC, AVIF, TIFF, DNG...) to JPEG bytes,
  /// with the longest side at most [maxPixel] (0 = full size).
  static Future<Uint8List> decodeToJpeg(String path, int maxPixel) async {
    final r = await _ch.invokeMethod<Uint8List>('decodeImage', {'path': path, 'maxPixel': maxPixel});
    if (r == null) throw const FormatException('Image could not be decoded');
    return r;
  }

  /// Reads the pixel size from the file header, with EXIF rotation applied.
  static Future<ImageSize?> imageSize(String path) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('imageInfo', {'path': path});
    if (r == null) return null;
    return ImageSize(r['width'] as int, r['height'] as int);
  }
}
