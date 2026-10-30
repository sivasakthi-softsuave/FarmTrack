import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Why the phone could not say where it is.
enum LocationFailure {
  /// The farmer said no to the location question.
  denied,

  /// "Never ask again": only the phone's settings can allow it now.
  deniedForever,

  /// The phone's location switch (GPS) is off.
  serviceOff,

  /// No position within the time limit (indoors, no signal).
  timeout,
  unknown,
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.reason);

  final LocationFailure reason;

  @override
  String toString() => 'DeviceLocationException($reason)';
}

typedef GeoPoint = ({double lat, double lon});

/// Where the phone is now. One call asks the farmer's permission the first time (the phone's own question), then reads one
/// position. It throws [DeviceLocationException] with the reason; it never returns a guess.
abstract interface class DeviceLocation {
  Future<GeoPoint> current();
}

/// The real one, on the `geolocator` package. A coarse fix is enough for weather (the forecast grid is several km wide),
/// and it is quicker and works indoors more often than the best one.
class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation({this.timeLimit = const Duration(seconds: 20)});

  final Duration timeLimit;

  @override
  Future<GeoPoint> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const DeviceLocationException(LocationFailure.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw const DeviceLocationException(LocationFailure.denied);
      if (permission == LocationPermission.deniedForever) {
        throw const DeviceLocationException(LocationFailure.deniedForever);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.low, timeLimit: timeLimit),
      );
      return (lat: position.latitude, lon: position.longitude);
    } on DeviceLocationException {
      rethrow;
    } on TimeoutException {
      throw const DeviceLocationException(LocationFailure.timeout);
    } on LocationServiceDisabledException {
      throw const DeviceLocationException(LocationFailure.serviceOff);
    } on PermissionDeniedException {
      throw const DeviceLocationException(LocationFailure.denied);
    } on Object {
      throw const DeviceLocationException(LocationFailure.unknown);
    }
  }
}

final deviceLocationProvider = Provider<DeviceLocation>((ref) => const GeolocatorDeviceLocation());
