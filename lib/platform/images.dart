import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';
import 'library.dart';
import 'native.dart';

/// Loads an [Item] at a reduced size (longest side at most [maxPixel]).
/// Big wallpapers decode to screen size, so swiping stays smooth and memory
/// stays low. [maxPixel] 0 loads the full resolution (for zoom).
class ItemImage extends ImageProvider<ItemImage> {
  const ItemImage(this.library, this.item, this.maxPixel);

  final Library library;
  final Item item;
  final int maxPixel;

  @override
  Future<ItemImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ItemImage>(this);

  @override
  ImageStreamCompleter loadImage(ItemImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load(decode), informationCollector: () sync* {
      yield ErrorDescription('Image: ${item.name}');
    });
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await loadBytes(library, item, maxPixel);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer, getTargetSize: (w, h) {
      if (maxPixel <= 0) return ui.TargetImageSize(width: w, height: h);
      final longest = w > h ? w : h;
      if (longest <= maxPixel) return ui.TargetImageSize(width: w, height: h);
      return w >= h
          ? ui.TargetImageSize(width: maxPixel)
          : ui.TargetImageSize(height: maxPixel);
    });
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemImage && other.item.id == item.id && other.item.ref == item.ref &&
      other.maxPixel == maxPixel;

  @override
  int get hashCode => Object.hash(item.id, item.ref, maxPixel);
}

/// Encoded image bytes for [item]. Formats Flutter cannot decode (HEIC...)
/// come back as JPEG from iOS.
Future<Uint8List> loadBytes(Library library, Item item, int maxPixel) async {
  if (item.kind == ItemKind.asset) {
    final asset = await AssetEntity.fromId(item.ref);
    if (asset == null) throw const FileSystemException('Photo was deleted');
    if (maxPixel <= 0) {
      final file = await asset.file; // HEIC comes as JPEG
      if (file == null) throw const FileSystemException('Photo not available');
      return file.readAsBytes();
    }
    final w = asset.orientatedWidth, h = asset.orientatedHeight;
    final scale = (w > h ? w : h) > maxPixel ? maxPixel / (w > h ? w : h) : 1.0;
    final data = await asset.thumbnailDataWithOption(ThumbnailOption.ios(
      size: ThumbnailSize((w * scale).round().clamp(1, 1 << 15), (h * scale).round().clamp(1, 1 << 15)),
      quality: 92,
      deliveryMode: DeliveryMode.highQualityFormat,
      resizeMode: ResizeMode.exact,
      resizeContentMode: ResizeContentMode.fit,
    ));
    if (data == null) throw const FileSystemException('Photo not available');
    return data;
  }
  final path = library.pathFor(item);
  if (path == null) throw const FileSystemException('Folder not available');
  if (Native.available && iosFormats.contains(item.extension)) {
    return Native.decodeToJpeg(path, maxPixel);
  }
  return File(path).readAsBytes();
}

/// Pixel size of the original image, or null if unknown.
Future<ImageSize?> originalSize(Library library, Item item) async {
  try {
    if (item.kind == ItemKind.asset) {
      final a = await AssetEntity.fromId(item.ref);
      return a == null ? null : ImageSize(a.orientatedWidth, a.orientatedHeight);
    }
    final path = library.pathFor(item);
    if (path == null) return null;
    if (Native.available) return await Native.imageSize(path);
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final size = ImageSize(desc.width, desc.height);
    desc.dispose();
    buffer.dispose();
    return size;
  } catch (e) {
    debugPrint('originalSize ${item.name}: $e');
    return null;
  }
}

/// The original file for export (Photos assets are exported to a temp file).
Future<File?> originalFile(Library library, Item item) async {
  if (item.kind == ItemKind.asset) {
    final a = await AssetEntity.fromId(item.ref);
    return a?.originFile;
  }
  final path = library.pathFor(item);
  return path == null ? null : File(path);
}
