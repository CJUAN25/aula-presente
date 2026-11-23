import 'package:flutter/foundation.dart';

/// Local durations only. Labels must never contain IDs or personal data.
typedef AttendanceTiming = void Function(
  String operation,
  String phase,
  Duration elapsed,
);

class AttendanceOperationTrace {
  AttendanceOperationTrace(this.operation, {this.onTiming});

  final String operation;
  final AttendanceTiming? onTiming;
  final Stopwatch _watch = Stopwatch();
  final Stopwatch _total = Stopwatch()..start();
  final Set<String> _milestones = {};
  String phase = '';

  void start(String next) {
    finish();
    phase = next;
    _watch
      ..reset()
      ..start();
  }

  void finish() {
    if (!_watch.isRunning) return;
    _watch.stop();
    if (onTiming != null) {
      onTiming!(operation, phase, _watch.elapsed);
    } else if (kDebugMode) {
      debugPrint('[C8] $operation / $phase: ${_watch.elapsedMilliseconds} ms');
    }
  }

  void milestone(String name) {
    if (!_milestones.add(name)) return;
    final elapsed = _total.elapsed;
    if (onTiming != null) {
      onTiming!(operation, name, elapsed);
    } else if (kDebugMode) {
      debugPrint(
        '[C8] $operation / $name: ${elapsed.inMilliseconds} ms desde el toque',
      );
    }
  }
}
