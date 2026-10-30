/// Every route of the app. `/diary`, `/field`, `/alerts`, `/ask` and `/settings` are final names.
abstract final class Routes {
  static const splash = '/';
  static const language = '/language';
  static const welcome = '/welcome';
  static const login = '/login';
  static const home = '/home';

  static const scan = '/scan';
  static const scanReview = '/scan/review';
  static const scanUploading = '/scan/uploading';
  static const scanRetake = '/scan/retake';
  static const scanAdvice = '/scan/advice';
  static const scanExpert = '/scan/expert';

  /// "Saved, will be sent when you have internet" (the photos are in the offline queue).
  static const scanSaved = '/scan/saved';

  static const diary = '/diary';
  static const diaryAdd = '/diary/add';
  static const field = '/field';

  /// "Choose a place" on My field: search by name, the phone's position, or a touch on the map.
  static const fieldPlace = '/field/place';

  /// "Weather map" on My field: rain radar, clouds and rain amount laid over a free map, with a play button for the last hours.
  static const weatherMap = '/field/map';
  static const alerts = '/alerts';
  static const alertDetail = '/alerts/detail';
  static const ask = '/ask';
  static const askType = '/ask/type';
  static const askAnswer = '/ask/answer';
  static const settings = '/settings';
  static const settingsLogout = '/settings/logout';

  /// Routes that work without being logged in.
  static const publicRoutes = {splash, language, welcome, login};

  /// `/diary` opened from an advice card ("I sprayed"): the advice is preselected through these query keys.
  static String diaryFor({String? adviceId, String? cropId, String? productId}) {
    final query = {'advice': ?adviceId, 'crop': ?cropId, 'product': ?productId};
    return Uri(path: diary, queryParameters: query.isEmpty ? null : query).toString();
  }

  /// One alert, opened from the alert list or from a push message.
  static String alertDetailFor(String alertId) => Uri(path: alertDetail, queryParameters: {'id': alertId}).toString();

  /// Home after a fresh login (it greets with `login_ok` first).
  static const homeFresh = '$home?fresh=1';
}
