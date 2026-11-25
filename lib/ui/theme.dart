import 'package:flutter/material.dart';

/// Colors that Material's ColorScheme does not cover.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.muted,
    required this.cardShadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color muted;
  final Color cardShadow;

  static const keep = Color(0xFF2ED47A);
  static const nope = Color(0xFFFF4D67);
  static const superLike = Color(0xFFFFB800);
  static const brandA = Color(0xFFFF5F6D);
  static const brandB = Color(0xFFA855F7);
  static const brand = LinearGradient(
    colors: [brandA, brandB],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const dark = Palette(
    background: Color(0xFF0D0D11),
    surface: Color(0xFF17171D),
    surfaceHigh: Color(0xFF24242C),
    text: Color(0xFFF4F4F6),
    muted: Color(0xFF9A9AA5),
    cardShadow: Color(0x99000000),
  );

  static const light = Palette(
    background: Color(0xFFF4F4F7),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE9E9EE),
    text: Color(0xFF15151A),
    muted: Color(0xFF6B6B76),
    cardShadow: Color(0x33000000),
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    return Palette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.brandA,
    brightness: brightness,
  ).copyWith(
    primary: Palette.brandA,
    onPrimary: Colors.white,
    secondary: Palette.brandB,
    surface: p.surface,
    onSurface: p.text,
    error: Palette.nope,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.muted.withValues(alpha: 0.5),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.text),
    dividerTheme: DividerThemeData(color: p.surfaceHigh, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.surfaceHigh,
      contentTextStyle: TextStyle(color: p.text),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.brandA,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Palette.brandA.withValues(alpha: 0.22) : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Palette.brandA : p.text),
        side: WidgetStatePropertyAll(BorderSide(color: p.surfaceHigh)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Text painted with the brand gradient.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => Palette.brand.createShader(r),
      child: Text(text, style: style),
    );
  }
}

/// A big gradient call-to-action button.
class BrandButton extends StatelessWidget {
  const BrandButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: Palette.brand, borderRadius: BorderRadius.circular(28)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onPressed,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, color: Colors.white), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
