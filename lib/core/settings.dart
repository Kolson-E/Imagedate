import 'package:flutter/material.dart';

/// How a landscape image shows while the phone is upright.
enum UprightLandscape {
  fit('Show whole image'),
  fill('Fill the card'),
  rotate('Turn image sideways');

  const UprightLandscape(this.label);
  final String label;
}

class AppSettings {
  AppSettings({
    this.themeMode = ThemeMode.dark,
    this.uprightLandscape = UprightLandscape.fit,
    this.fillWhenSideways = true,
    this.shakeToUndo = true,
    this.haptics = true,
  });

  ThemeMode themeMode;
  UprightLandscape uprightLandscape;

  /// When the device is sideways, landscape images fill the whole screen.
  bool fillWhenSideways;
  bool shakeToUndo;
  bool haptics;

  Map<String, dynamic> toJson() => {
        'theme': themeMode.name,
        'uprightLandscape': uprightLandscape.name,
        'fillWhenSideways': fillWhenSideways,
        'shakeToUndo': shakeToUndo,
        'haptics': haptics,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.asNameMap()[j['theme']] ?? ThemeMode.dark,
        uprightLandscape:
            UprightLandscape.values.asNameMap()[j['uprightLandscape']] ?? UprightLandscape.fit,
        fillWhenSideways: j['fillWhenSideways'] as bool? ?? true,
        shakeToUndo: j['shakeToUndo'] as bool? ?? true,
        haptics: j['haptics'] as bool? ?? true,
      );
}
