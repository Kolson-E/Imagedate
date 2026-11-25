import 'dart:io';

import 'package:flutter/material.dart';

import '../core/settings.dart';
import 'app_scope.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.settings;
        final p = Palette.of(context);
        void update(void Function() f) {
          f();
          store.saveSettings();
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _Header('Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => update(() => s.themeMode = v.first),
                ),
              ),
              const _Header('Landscape images while upright'),
              RadioGroup<UprightLandscape>(
                groupValue: s.uprightLandscape,
                onChanged: (v) => update(() => s.uprightLandscape = v!),
                child: Column(
                  children: [
                    for (final v in UprightLandscape.values)
                      RadioListTile<UprightLandscape>(
                        value: v,
                        activeColor: Palette.brandA,
                        title: Text(v.label),
                        subtitle: Text(switch (v) {
                          UprightLandscape.fit => 'Blurred edges above and below. Nothing is cut off.',
                          UprightLandscape.fill => 'Fills the card. The sides are cut off. Hold the card to see all of it.',
                          UprightLandscape.rotate => 'Turns the image 90° so it shows big without turning the phone.',
                        }),
                      ),
                  ],
                ),
              ),
              const _Header('Sideways'),
              SwitchListTile(
                value: s.fillWhenSideways,
                activeThumbColor: Palette.brandA,
                onChanged: (v) => update(() => s.fillWhenSideways = v),
                title: const Text('Fill the screen when sideways'),
                subtitle: const Text('Turn the phone and landscape images use the whole screen. Hold the image to see all of it.'),
              ),
              if (Platform.isIOS) ...[
                const _Header('Controls'),
                SwitchListTile(
                  value: s.shakeToUndo,
                  activeThumbColor: Palette.brandA,
                  onChanged: (v) => update(() => s.shakeToUndo = v),
                  title: const Text('Shake to undo'),
                  subtitle: const Text('Shake the phone to take back the last swipe.'),
                ),
                SwitchListTile(
                  value: s.haptics,
                  activeThumbColor: Palette.brandA,
                  onChanged: (v) => update(() => s.haptics = v),
                  title: const Text('Haptics'),
                ),
              ],
              if (!Platform.isIOS) ...[
                const _Header('Keyboard'),
                const _Key('→', 'Keep'),
                const _Key('←', 'Nope'),
                const _Key('↑', 'Super Like (round 1)'),
                const _Key('Ctrl + Z  /  Backspace', 'Undo last swipe'),
                const _Key('Space  /  Z', 'Zoom'),
                const _Key('Mouse wheel', 'Zoom'),
                const _Key('I', 'Image info'),
              ],
              const _Header('About'),
              ListTile(
                title: const Text('Image Date'),
                subtitle: Text(
                  'Three rounds of swipes to find the images you really like. '
                  'Image Date works offline and never deletes or moves your images.',
                  style: TextStyle(color: p.muted),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: Palette.of(context).muted, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.keys, this.action);
  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(6)),
            child: Text(keys, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Text(action, style: TextStyle(color: p.muted)),
        ],
      ),
    );
  }
}
