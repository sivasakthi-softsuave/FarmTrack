import 'package:flutter/material.dart';

import '../models/models.dart';
import 'farmtrack_icons.dart';

/// High-contrast colours that carry meaning: green = done / yes / safe, red = no / stop / danger, grey ([inkSoft],
/// [neutralSoft]) = waiting, amber = a warning only (never a button, never "waiting"), blue = information.
///
/// The values are the design tokens of the approved UI mockup (`docs/design/ui-redesign-mockup.html`, `:root`).
class AppColors {
  const AppColors._();

  /// Deep green of the Home header: a surface, never a button (buttons stay [green]).
  static const brand = Color(0xFF14532D);
  static const green = Color(0xFF1B7F3A);
  static const greenSoft = Color(0xFFE3F2E7);
  static const red = Color(0xFFC62828);
  static const redSoft = Color(0xFFFCE4E2);
  static const amber = Color(0xFFF2A900);

  /// Amber for icons, borders and text drawn ON light backgrounds (paper, white, [amberSoft]): 5.4 to 5.5 against
  /// them. [amber] itself is a fill that carries ink text (8.9:1); drawn as an icon on a light panel it is only
  /// 1.8 to 2.0:1.
  static const amberDark = Color(0xFF8A5A00);
  static const amberSoft = Color(0xFFFFF3D1);
  static const neutralSoft = Color(0xFFEEF2EC);
  static const blue = Color(0xFF1F5FA8);
  static const blueSoft = Color(0xFFE3EDF8);
  static const ink = Color(0xFF17201A);
  static const inkSoft = Color(0xFF4F5B52);

  /// The screen background: a light green-grey, so the white cards stand out without borders.
  static const paper = Color(0xFFF3F6F1);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE1E7DE);

  /// Thin border of an amber / red tinted panel, and of the red "Log out" button.
  static const amberLine = Color(0xFFEFD891);
  static const redLine = Color(0xFFF2C2BE);

  /// The little arrow at the end of a row, and the dashed ring of a step that has not started.
  static const chevron = Color(0xFF8A958C);
  static const dashed = Color(0xFFB9C4BB);

  /// Empty part of a progress ring or bar.
  static const track = Color(0xFFDCE7DD);

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

  /// The tappable area of every button. A round picture button is drawn [ibtn] wide inside it (the mockup's 48 px).
  static const minTouch = 56.0;

  /// The round picture buttons of the top bars, as drawn in the mockup.
  static const ibtn = 48.0;

  /// The same buttons drawn a little smaller where three of them share one line (the Home header: alerts, settings, voice).
  /// Their tap area stays [minTouch].
  static const compactIbtn = 40.0;
  static const primary = 96.0;
  static const hero = 148.0;
  static const gutter = 16.0;
  static const radius = 20.0;
  static const radiusSmall = 14.0;

  /// The mockup's bars: top bar of the inner screens, main action strip, bottom navigation.
  static const topBar = 64.0;
  static const actionButton = 60.0;
  static const nav = 80.0;

  /// How far the camera circle of the navigation bar rises above the bar.
  static const navRise = 26.0;
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
  static BoxDecoration card({Color color = AppColors.card, double radius = Dimens.radius}) =>
      BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: shadows);

  /// A tinted card as the mockup draws warnings and answers: the soft colour, no shadow, and (when [line] is given) a
  /// one pixel border.
  static BoxDecoration tinted(Color fill, {Color? line, double radius = Dimens.radius}) => BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: line == null ? null : Border.all(color: line),
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

/// The text styles of the approved mockup, by their CSS names. Colours are not part of them (they inherit the ink
/// colour); size and weight are exactly the mockup's.
class AppText {
  const AppText._();

  /// `.topbar .title`: the name of an inner screen.
  static const title = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3);

  /// `.h-name`: the first line of a card.
  static const hName = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3);

  /// `.h-meta`: the grey second line of a card.
  static const hMeta = TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.35);

  /// `.label`: a small heading above a group of cards (set it in capitals in Latin scripts).
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.inkSoft,
    letterSpacing: 0.52,
    height: 1.35,
  );

  /// The same heading in Devanagari: bigger, no capitals, no letter spacing (letter spacing breaks the conjuncts).
  static const labelHindi = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.inkSoft,
    height: 1.35,
  );

  /// The big word of a result or a state ("Apple scab", "Looking at your leaf").
  static const big = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2);

  /// `.btn`: the word on a button of the action strip.
  static const button = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);

  /// `.pill`.
  static const pill = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

  /// Running text on a card.
  static const body = TextStyle(fontSize: 15, height: 1.45);
}

/// The picture of every button, in one place. The voice prompts name exactly these pictures. They are the line
/// pictures of the approved mockup (`FtIcons`, an icon font built from the mockup's SVG).
class AppIcons {
  const AppIcons._();

  static const tick = FtIcons.check; // "green tick"
  static const tickBold = FtIcons.checkBold; // the same, 2.6 wide, on green buttons
  static const cross = FtIcons.x; // "red cross"
  static const crossBold = FtIcons.xBold;
  static const plus = FtIcons.plus; // "plus sign"
  static const camera = FtIcons.camera; // "camera picture"
  static const cameraOff = FtIcons.cameraOff;
  static const gallery = FtIcons.gallery; // "gallery picture" (photos already in the phone)
  static const speaker = FtIcons.speaker; // "speaker picture"
  static const notebook = FtIcons.book; // "notebook picture"
  static const gear = FtIcons.gear; // "gear picture"
  static const bell = FtIcons.bell; // "bell picture"
  static const cloud = FtIcons.cloud; // "cloud picture"
  static const field = FtIcons.field; // "field picture" (shown with the cloud on the My field button)
  static const house = FtIcons.home; // "house picture"
  static const back = FtIcons.back; // "arrow that points left"
  static const question = FtIcons.ask; // "question mark picture" (speech bubble with a ?)
  static const roundArrow = FtIcons.refresh; // "round arrow"
  static const greenArrow = FtIcons.next; // "green arrow"
  static const expert = FtIcons.expert;
  static const offline = FtIcons.cloudOff;
  static const warning = FtIcons.warn;
  static const danger = FtIcons.danger;
  static const leaf = FtIcons.leaf;
  static const leafThin = FtIcons.leafThin;
  static const tree = FtIcons.tree;
  static const grass = FtIcons.field;
  static const noVoice = FtIcons.volumeX; // the crossed-out speaker: "mute" / "no voice"
  static const medicine = FtIcons.flask;
  static const clock = FtIcons.clock;
  static const slow = FtIcons.slow;
  static const normalSpeed = FtIcons.play;
  static const fast = FtIcons.fastForward;
  static const volumeLow = FtIcons.volumeLow;
  static const volumeMedium = FtIcons.volume;
  static const volumeHigh = FtIcons.speaker;
  static const captions = FtIcons.captions;
  static const logout = FtIcons.logout;
  static const person = FtIcons.user; // "person picture" (user name)
  static const lock = FtIcons.lock; // "lock picture" (password)
  static const eye = FtIcons.eye; // "eye picture": shows the password
  static const eyeOff = FtIcons.eyeOff; // crossed-out eye: hides the password
  static const noDisease = FtIcons.searchOff;
  static const info = FtIcons.info;
  static const server = FtIcons.server;
  static const sun = FtIcons.sun;
  static const drop = FtIcons.drop;
  static const rain = FtIcons.rain;
  static const soil = FtIcons.soil;
  static const pen = FtIcons.pen;
  static const hourglass = FtIcons.hour;
  static const shield = FtIcons.shield;
  static const send = FtIcons.send;
  static const chevron = FtIcons.chevron;
  static const down = FtIcons.down;
  static const up = FtIcons.up;
  static const phone = FtIcons.phone;
  static const calendar = FtIcons.calendar;
  static const repeat = FtIcons.repeat;
  static const upload = FtIcons.upload;
  static const moon = FtIcons.moon;
  static const zoom = FtIcons.zoom;
  static const blur = FtIcons.blur;
  static const dot = FtIcons.dot;
  static const checkCircle = FtIcons.checkCircle;
}

/// The font of the whole app: Noto Sans for Latin, Noto Sans Devanagari for Hindi, as in the mockup.
const appFontFamily = 'NotoSans';
const appFontFallback = ['NotoSansDevanagari'];

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
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerColor: AppColors.line,
    textTheme: TextTheme(
      displaySmall: text.copyWith(fontSize: 30, fontWeight: FontWeight.w800, height: 1.2),
      headlineMedium: text.copyWith(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2),
      headlineSmall: text.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
      titleLarge: text.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: text.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
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
      linearTrackColor: AppColors.track,
      linearMinHeight: 10,
    ),
  );
}
