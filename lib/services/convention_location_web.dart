import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Called only after the buyer presses the location/checkout button. There is
/// no watchPosition subscription and no background location collection.
Future<Map<String, dynamic>> checkConventionLocation() async {
  final result = Completer<Map<String, dynamic>>();
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      if (result.isCompleted) return;
      result.complete({
        'latitude': position.coords.latitude,
        'longitude': position.coords.longitude,
        'accuracy': position.coords.accuracy,
        'measured_at': DateTime.fromMillisecondsSinceEpoch(
          position.timestamp.toInt(),
          isUtc: true,
        ).toIso8601String(),
      });
    }).toJS,
    ((web.GeolocationPositionError error) {
      if (result.isCompleted) return;
      result.completeError(
        StateError(switch (error.code) {
          1 =>
            'Location permission was declined. Allow location for this site and retry, or visit the booth for help.',
          3 =>
            'The location check timed out. Retry near a window or visit the booth for help.',
          _ =>
            'Your location is unavailable. Check your device location settings or visit the booth for help.',
        }),
      );
    }).toJS,
    web.PositionOptions(
      enableHighAccuracy: true,
      maximumAge: 0,
      timeout: 20000,
    ),
  );
  return result.future.timeout(
    const Duration(seconds: 25),
    onTimeout: () {
      throw StateError(
        'The location check timed out. Please retry or visit the booth for help.',
      );
    },
  );
}
