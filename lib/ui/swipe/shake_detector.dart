import 'dart:async';
import 'dart:io';

import 'package:sensors_plus/sensors_plus.dart';

/// Calls [onShake] when the phone is shaken (two strong jolts within 0.7 s).
/// iOS only; on other platforms it does nothing.
class ShakeDetector {
  ShakeDetector(this.onShake);

  final void Function() onShake;
  StreamSubscription<UserAccelerometerEvent>? _sub;
  DateTime _lastSpike = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);
  int _spikes = 0;

  /// Acceleration without gravity, in m/s², that counts as a jolt.
  static const threshold = 14.0;

  void start() {
    if (!Platform.isIOS || _sub != null) return;
    _sub = userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      (e) {
        final m2 = e.x * e.x + e.y * e.y + e.z * e.z;
        if (m2 < threshold * threshold) return;
        final now = DateTime.now();
        if (now.difference(_lastShake).inMilliseconds < 1200) return;
        if (now.difference(_lastSpike).inMilliseconds > 700) _spikes = 0;
        if (now.difference(_lastSpike).inMilliseconds < 80) return; // same jolt
        _lastSpike = now;
        _spikes++;
        if (_spikes >= 2) {
          _spikes = 0;
          _lastShake = now;
          onShake();
        }
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
