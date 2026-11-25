import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../platform/images.dart';
import '../../platform/library.dart';
import '../theme.dart';

/// Resolves an [ImageProvider] and gives the decoded image to [builder].
/// When the provider changes, the old image stays until the new one is ready
/// (used to swap in a sharper image on zoom without a flash).
class ResolvedImage extends StatefulWidget {
  const ResolvedImage({super.key, required this.provider, required this.builder});

  final ImageProvider provider;
  final Widget Function(BuildContext context, ui.Image? image, Object? error) builder;

  @override
  State<ResolvedImage> createState() => _ResolvedImageState();
}

class _ResolvedImageState extends State<ResolvedImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  Object? _error;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: _onError);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  void _onImage(ImageInfo info, bool sync) {
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _info?.dispose();
      _info = info;
      _error = null;
    });
  }

  void _onError(Object error, StackTrace? stack) {
    if (!mounted) return;
    setState(() => _error = _info == null ? error : null);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _info?.image, _error);
}

/// How an image is placed in the card.
class CardFit {
  const CardFit(this.fit, this.quarterTurns);
  final BoxFit fit;
  final int quarterTurns;
}

CardFit cardFit({
  required int imageWidth,
  required int imageHeight,
  required bool deviceLandscape,
  required AppSettings settings,
  required bool showWhole,
}) {
  final landscapeImage = imageWidth > imageHeight * 1.05;
  final portraitImage = imageHeight > imageWidth * 1.05;
  if (deviceLandscape) {
    if (showWhole || portraitImage) return const CardFit(BoxFit.contain, 0);
    return CardFit(settings.fillWhenSideways ? BoxFit.cover : BoxFit.contain, 0);
  }
  if (landscapeImage) {
    switch (settings.uprightLandscape) {
      case UprightLandscape.fit:
        return const CardFit(BoxFit.contain, 0);
      case UprightLandscape.fill:
        return CardFit(showWhole ? BoxFit.contain : BoxFit.cover, 0);
      case UprightLandscape.rotate:
        return const CardFit(BoxFit.contain, 1);
    }
  }
  return CardFit(showWhole ? BoxFit.contain : BoxFit.cover, 0);
}

/// The picture inside a swipe card: fit, rotation, zoom and loading states.
class CardImage extends StatelessWidget {
  const CardImage({
    super.key,
    required this.library,
    required this.item,
    required this.displayPixels,
    required this.settings,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.showWhole = false,
  });

  final Library library;
  final Item item;
  final int displayPixels;
  final AppSettings settings;
  final double zoom;
  final Offset pan;
  final bool showWhole;

  /// Longest side loaded while zoomed. Enough to judge detail on a phone
  /// without decoding a 100+ MB bitmap for an 8K image.
  static const zoomPixels = 4096;

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final provider = ItemImage(library, item, zoom > 1.05 ? zoomPixels : displayPixels);
    return ColoredBox(
      color: Colors.black,
      child: ResolvedImage(
        provider: provider,
        builder: (context, image, error) {
          if (error != null) return _Missing(name: item.name);
          if (image == null) return const _Loading();
          final f = cardFit(
            imageWidth: image.width,
            imageHeight: image.height,
            deviceLandscape: landscape,
            settings: settings,
            showWhole: showWhole,
          );
          Widget pic = RawImage(
            image: image,
            fit: f.fit,
            filterQuality: FilterQuality.medium,
            width: double.infinity,
            height: double.infinity,
          );
          if (f.quarterTurns != 0) pic = RotatedBox(quarterTurns: f.quarterTurns, child: pic);
          final backdrop = f.fit == BoxFit.contain && zoom <= 1.05;
          if (zoom != 1 || pan != Offset.zero) {
            pic = Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(pan.dx, pan.dy, 0, 1)
                ..scaleByDouble(zoom, zoom, 1, 1),
              child: pic,
            );
          }
          if (!backdrop) return ClipRect(child: pic);
          // Fill the empty bars with a blurred, darker copy of the image.
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.mirror),
                  child: RawImage(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
                ),
                const ColoredBox(color: Color(0x73000000)),
                pic,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 48, color: Palette.dark.muted),
            const SizedBox(height: 12),
            Text('Cannot open this image',
                style: TextStyle(color: Palette.dark.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(name,
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.dark.muted, fontSize: 13)),
            const SizedBox(height: 4),
            Text('It may have been moved or deleted. You can still swipe it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.dark.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
