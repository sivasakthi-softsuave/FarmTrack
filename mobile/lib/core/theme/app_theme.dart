import 'package:flutter/material.dart';

import '../models/models.dart';

/// High-contrast colours that carry meaning: green = done / yes / safe, red = no / stop / danger, grey ([inkSoft],
/// [neutralSoft]) = waiting, amber = a warning only (never a button, never "waiting"), blue = information.
class AppColors {
  const AppColors._();

  /// Deep green of the Home header: a surface, never a button (buttons stay [green]).
  static const brand = Color(0xFF14532D);
  static const green = Color(0xFF1B7F3A);
  static const greenSoft = Color(0xFFDDF3E2);
  static const red = Color(0xFFC62828);
  static const redSoft = Color(0xFFFBE0DE);
  static const amber = Color(0xFFF2A900);

  /// Amber for icons, borders and text drawn ON light backgrounds (paper, white, [amberSoft]): 4.7 to 5.3 against
  /// them. [amber] itself is a fill that carries ink text (8.9:1); drawn as an icon on a light panel it is only
  /// 1.8 to 2.0:1.
  static const amberDark = Color(0xFF946100);
  static const amberSoft = Color(0xFFFFF1C7);
  static const neutralSoft = Color(0xFFEEF2EC);
  static const blue = Color(0xFF1F5FA8);
  static const blueSoft = Color(0xFFE3EDF8);
  static const ink = Color(0xFF17201A);
  static const inkSoft = Color(0xFF4B574E);

  /// The screen background: a light green-grey, so the white cards stand out without borders.
  static const paper = Color(0xFFF3F6F1);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE1E7DE);

  /// Colour of the soft card shadows.
  static const shadow = Color(0x33102818);

  static Color severity(Severity s) => switch (s) {
    Severity.green => green,
    Severity.yellow => amber,
    Severity.red => red,
  };

  static Color severitySoft(Severity s) => switch (s) {
    Severity.green => greenSoft,
    Severity.yellow => amberSoft,
    Severity.red => redSoft,
  };

  /// The severity colour as an icon, border or text on a light background (see [amberDark]): at least 4.5:1 on paper
  /// and white, and at least 3:1 on its own soft panel.
  static Color severityAccent(Severity s) => switch (s) {
    Severity.green => green,
    Severity.yellow => amberDark,
    Severity.red => red,
  };

  /// Text colour that stays readable on [severity] backgrounds.
  static Color onSeverity(Severity s) => s == Severity.yellow ? ink : Colors.white;
}

/// Touch target and spacing sizes in dp. No target is smaller than [minTouch].
class Dimens {
  const Dimens._();

  static const minTouch = 56.0;
  static const primary = 96.0;
  static const hero = 148.0;
  static const gutter = 16.0;
  static const radius = 20.0;
  static const radiusSmall = 14.0;
}

/// The card look shared by every screen: white cards with a soft shadow on the light ground, and tinted panels with a
/// thin border of their colour. Thick borders are kept only where they mean "chosen" or "new".
class AppDecor {
  const AppDecor._();

  static const shadows = [
    BoxShadow(color: Color(0x0F102818), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x12102818), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// A white card with a soft shadow.
  static BoxDecoration card({Color color = AppColors.card, double radius = Dimens.radius}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadows,
  );

  /// A tinted panel (warning, timing, risk): the soft colour with a thin border of its accent.
  static BoxDecoration panel(Color fill, Color accent, {double radius = Dimens.radius}) => BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
  );

  /// The outline of a [Material] card: a hairline, or the full colour when [strong] (chosen, new).
  static BorderSide side(Color color, {bool strong = false}) {
    if (strong) return BorderSide(color: color, width: 2.5);
    return BorderSide(color: color.withValues(alpha: 0.4), width: 1.5);
  }

  /// The rounded shape of a [Material] card with [side].
  static RoundedRectangleBorder shape(BorderSide side, {double radius = Dimens.radius}) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
  }
}

/// The picture of every button, in one place. The voice prompts name exactly these pictures.
class AppIcons {
  const AppIcons._();

  static const tick = Icons.check_rounded; // "green tick"
  static const cross = Icons.close_rounded; // "red cross"
  static const plus = Icons.add_rounded; // "plus sign"
  static const camera = Icons.photo_camera_rounded; // "camera picture"
  static const gallery = Icons.photo_library_rounded; // "gallery picture" (photos already in the phone)
  static const speaker = Icons.volume_up_rounded; // "speaker picture"
  static const notebook = Icons.edit_note_rounded; // "notebook picture"
  static const gear = Icons.settings_rounded; // "gear picture"
  static const bell = Icons.notifications_rounded; // "bell picture"
  static const cloud = Icons.cloud_rounded; // "cloud picture"
  static const field = Icons.grass_rounded; // "field picture" (shown with the cloud on the My field button)
  static const house = Icons.home_rounded; // "house picture"
  static const back = Icons.arrow_back_rounded; // "arrow that points left"
  static const question = Icons.live_help_rounded; // "question mark picture" (speech bubble with a ?)
  static const roundArrow = Icons.refresh_rounded; // "round arrow"
  static const greenArrow = Icons.arrow_forward_rounded; // "green arrow"
  static const expert = Icons.support_agent_rounded;
  static const offline = Icons.cloud_off_rounded;
  static const warning = Icons.warning_amber_rounded;
  static const danger = Icons.report_rounded;
  static const leaf = Icons.eco_rounded;
  static const tree = Icons.park_rounded;
  static const grass = Icons.grass_rounded;
  static const noVoice = Icons.volume_off_rounded;
  static const medicine = Icons.science_rounded;
  static const clock = Icons.schedule_rounded;
  static const slow = Icons.slow_motion_video_rounded;
  static const normalSpeed = Icons.play_arrow_rounded;
  static const fast = Icons.fast_forward_rounded;
  static const volumeLow = Icons.volume_mute_rounded;
  static const volumeMedium = Icons.volume_down_rounded;
  static const volumeHigh = Icons.volume_up_rounded;
  static const captions = Icons.subtitles_rounded;
  static const logout = Icons.logout_rounded;
  static const person = Icons.person_rounded; // "person picture" (user name)
  static const lock = Icons.lock_rounded; // "lock picture" (password)
  static const eye = Icons.visibility_rounded; // "eye picture": shows the password
  static const eyeOff = Icons.visibility_off_rounded; // crossed-out eye: hides the password
  static const noDisease = Icons.search_off_rounded;
  static const info = Icons.info_outline_rounded;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.green, brightness: Brightness.light).copyWith(
    primary: AppColors.green,
    onPrimary: Colors.white,
    error: AppColors.red,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
  );

  // Calmer sizes than before (body 16-17, titles 18-22); the farmer's own text-size setting still scales them.
  const text = TextStyle(color: AppColors.ink, height: 1.35);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerColor: AppColors.line,
    textTheme: TextTheme(
      displaySmall: text.copyWith(fontSize: 30, fontWeight: FontWeight.w800, height: 1.2),
      headlineMedium: text.copyWith(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2),
      headlineSmall: text.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
      titleLarge: text.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: text.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      bodyLarge: text.copyWith(fontSize: 17),
      bodyMedium: text.copyWith(fontSize: 16),
      labelLarge: text.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(Dimens.minTouch, Dimens.minTouch),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(Dimens.minTouch, Dimens.minTouch),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.card,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.line, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.line, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.green, width: 2.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(Dimens.minTouch, Dimens.minTouch)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(Dimens.minTouch, Dimens.minTouch)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.green,
      linearTrackColor: Color(0xFFDCE7DD),
      linearMinHeight: 10,
    ),
  );
}
