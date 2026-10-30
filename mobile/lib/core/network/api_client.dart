import 'dart:async';

import '../models/models.dart';

/// Lets the farmer cancel a running upload.
class CancelHandle {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get onCancel => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

typedef UploadProgressCallback = void Function(int sent, int total);

/// The whole backend as seen by the app (`contracts/openapi.json`). Every method throws [ApiException].
///
/// Implementations: `DioApiClient` (real) and `MockApiClient` (canned, for demos and tests).
abstract interface class ApiClient {
  /// Base URL against which relative audio urls are resolved.
  String get baseUrl;

  Future<HealthOut> health();
  Future<MetaOut> meta();

  /// User name and password (`POST /v1/auth/login`). A wrong pair is a 401 `invalid_credentials`, too many tries a 429.
  Future<TokenOut> login({required String username, required String password, String? deviceId});

  /// Revokes the refresh token on the server (always 204). The access token simply runs out.
  Future<void> logout(String refreshToken);

  Future<FarmerOut> me();
  Future<FarmerOut> patchMe(FarmerPatch patch);

  /// Uploads 1 to 4 photos. The pipeline always answers 200 with a status.
  ///
  /// [idempotencyKey] is sent as the `Idempotency-Key` header: the offline queue passes the same key on every retry, so
  /// a lost response never makes a second scan (the server returns the first answer again).
  Future<ScanOut> createScan({
    required List<String> photoPaths,
    String? clientCrop,
    double? clientConfidence,
    DateTime? takenAt,
    double? lat,
    double? lon,
    String? idempotencyKey,
    UploadProgressCallback? onProgress,
    CancelHandle? cancel,
  });
  Future<ScanOut> addPhotos(
    String scanId,
    List<String> photoPaths, {
    UploadProgressCallback? onProgress,
    CancelHandle? cancel,
  });
  Future<ScanOut> confirmCrop(String scanId, String cropId);
  Future<ScanOut> getScan(String scanId);
  Future<ScanListOut> listScans({int limit = 20, String? cursor});

  Future<SprayLogOut> createSprayLog(SprayLogIn log, {String? idempotencyKey});
  Future<List<SprayLogOut>> listSprayLogs({int limit = 50});

  Future<FieldOut> field();

  /// `GET /v1/weather`: live weather for a place the farmer picked on the map (the shape of My field, without sensors and risks).
  Future<FieldOut> weatherAt(double lat, double lon);

  /// `GET /v1/places/search`: a state, district, town or village by name. Call it when the farmer submits the search, never on
  /// every key press (the public OpenStreetMap search forbids that).
  Future<PlaceSearchOut> searchPlaces(String query, {String lang = 'en', int limit = 5});

  /// `GET /v1/places/reverse`: the named area a point lies in (the nearest village, its tehsil, district and state), so that a touch
  /// on the map or the phone's position is shown by its real name. A 404 `place_not_found` means nothing is known there.
  Future<PlaceOut> reversePlace(double lat, double lon, {String lang = 'en'});
  Future<AlertListOut> listAlerts({int limit = 30});
  Future<AlertOut> markAlertRead(String alertId);
  Future<void> registerDevice(DeviceIn device);

  Future<AskOut> ask(AskIn question);
  Future<ExpertRequestOut> createExpertRequest(ExpertRequestIn request);

  Future<VoiceCatalogueOut> voiceCatalogue(String lang);

  /// Downloads a (cacheable, public) audio file. [url] may be relative to [baseUrl].
  Future<List<int>> downloadBytes(String url);
}
