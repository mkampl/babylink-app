import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// BabyLink "Nursery Calm" design tokens, ported from the web app's
/// public/css/variables.css so the app and website read as one product.
class BabyLinkColors {
  BabyLinkColors._();

  // Brand (light)
  static const primary = Color(0xFF6B8EAE); // soft dusty blue
  static const babyAccent = Color(0xFFE8887A); // warm coral
  static const success = Color(0xFF5F8C72);
  static const warning = Color(0xFFE4A853);
  static const danger = Color(0xFFD4544E);

  static const bg = Color(0xFFFAF8F5); // warm cream
  static const bgAlt = Color(0xFFF4F1EC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF8F6F2);
  static const border = Color(0xFFE8E4DE);
  static const borderDark = Color(0xFFD8D3CC);
  static const text = Color(0xFF2D2926);
  static const textSecondary = Color(0xFF635B54);
  static const textMuted = Color(0xFF747069);
  static const heading = Color(0xFF3D3632);

  // Brand (dark)
  static const primaryDark = Color(0xFF8AAFCC);
  static const babyAccentDark = Color(0xFFE8887A);
  static const successDark = Color(0xFF8FBB9D);
  static const warningDark = Color(0xFFEDB96A);
  static const dangerDark = Color(0xFFE07070);

  static const bgD = Color(0xFF13161A);
  static const surfaceD = Color(0xFF1F2329);
  static const surfaceAltD = Color(0xFF262B32);
  static const borderD = Color(0xFF2E343C);
  static const borderDarkD = Color(0xFF3A414A);
  static const textD = Color(0xFFE8E4E0);
  static const textSecondaryD = Color(0xFFB0AAA4);
  static const textMutedD = Color(0xFF7A756F);
  static const headingD = Color(0xFFD8D4D0);
}

/// Spacing scale (dp).
class Gap {
  Gap._();
  static const double xs = 4, sm = 8, md = 16, lg = 24, xl = 32, xxl = 48;
  static const hSm = SizedBox(height: sm);
  static const hMd = SizedBox(height: md);
  static const hLg = SizedBox(height: lg);
  static const hXl = SizedBox(height: xl);
  static const wSm = SizedBox(width: sm);
  static const wMd = SizedBox(width: md);
}

/// Corner radii.
class Radii {
  Radii._();
  static const double sm = 10, md = 14, card = 16, lg = 20, pill = 100;
  static const rCard = BorderRadius.all(Radius.circular(card));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rMd = BorderRadius.all(Radius.circular(md));
}

/// Semantic status colors (not in ColorScheme). Read via `context.status`.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  final Color success, successBg, warning, warningBg, danger, dangerBg, info, infoBg;
  const StatusColors({
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
  });

  static const light = StatusColors(
    success: BabyLinkColors.success, successBg: Color(0xFFEEF5F0),
    warning: BabyLinkColors.warning, warningBg: Color(0xFFFDF4E5),
    danger: BabyLinkColors.danger, dangerBg: Color(0xFFFCEAEA),
    info: Color(0xFF4A7DA8), infoBg: Color(0xFFEAF2F8),
  );
  static const dark = StatusColors(
    success: BabyLinkColors.successDark, successBg: Color(0x1F7BA68C),
    warning: BabyLinkColors.warningDark, warningBg: Color(0x1FE4A853),
    danger: BabyLinkColors.dangerDark, dangerBg: Color(0x1FD4544E),
    info: BabyLinkColors.primaryDark, infoBg: Color(0x1A6B8EAE),
  );

  @override
  StatusColors copyWith() => this;
  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) => this;
}

extension StatusColorsX on BuildContext {
  StatusColors get status =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}

class BabyLinkTheme {
  BabyLinkTheme._();

  static const _lightOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );
  static const _darkOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BabyLinkColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: BabyLinkColors.primary,
      onPrimary: Colors.white,
      secondary: BabyLinkColors.babyAccent,
      onSecondary: Colors.white,
      tertiary: BabyLinkColors.success,
      error: BabyLinkColors.danger,
      onError: Colors.white,
      surface: BabyLinkColors.surface,
      onSurface: BabyLinkColors.text,
      surfaceContainerLowest: BabyLinkColors.surface,
      surfaceContainerLow: BabyLinkColors.surfaceAlt,
      surfaceContainer: BabyLinkColors.bgAlt,
      outline: BabyLinkColors.borderDark,
      outlineVariant: BabyLinkColors.border,
    );
    return _base(
      scheme: scheme,
      scaffoldBg: BabyLinkColors.bg,
      heading: BabyLinkColors.heading,
      body: BabyLinkColors.text,
      secondaryText: BabyLinkColors.textSecondary,
      mutedText: BabyLinkColors.textMuted,
      fieldFill: BabyLinkColors.surfaceAlt,
      border: BabyLinkColors.border,
      overlay: _lightOverlay,
    ).copyWith(extensions: const [StatusColors.light]);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BabyLinkColors.primaryDark,
      brightness: Brightness.dark,
    ).copyWith(
      primary: BabyLinkColors.primaryDark,
      onPrimary: const Color(0xFF10222F),
      secondary: BabyLinkColors.babyAccentDark,
      onSecondary: const Color(0xFF3A1712),
      tertiary: BabyLinkColors.successDark,
      error: BabyLinkColors.dangerDark,
      onError: const Color(0xFF3A1210),
      surface: BabyLinkColors.surfaceD,
      onSurface: BabyLinkColors.textD,
      surfaceContainerLowest: BabyLinkColors.bgD,
      surfaceContainerLow: BabyLinkColors.surfaceD,
      surfaceContainer: BabyLinkColors.surfaceAltD,
      outline: BabyLinkColors.borderDarkD,
      outlineVariant: BabyLinkColors.borderD,
    );
    return _base(
      scheme: scheme,
      scaffoldBg: BabyLinkColors.bgD,
      heading: BabyLinkColors.headingD,
      body: BabyLinkColors.textD,
      secondaryText: BabyLinkColors.textSecondaryD,
      mutedText: BabyLinkColors.textMutedD,
      fieldFill: BabyLinkColors.surfaceAltD,
      border: BabyLinkColors.borderD,
      overlay: _darkOverlay,
    ).copyWith(extensions: const [StatusColors.dark]);
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffoldBg,
    required Color heading,
    required Color body,
    required Color secondaryText,
    required Color mutedText,
    required Color fieldFill,
    required Color border,
    required SystemUiOverlayStyle overlay,
  }) {
    final textTheme = TextTheme(
      displaySmall: TextStyle(
          fontSize: 32, height: 1.15, fontWeight: FontWeight.w700, color: heading, letterSpacing: -0.5),
      headlineMedium: TextStyle(
          fontSize: 26, height: 1.2, fontWeight: FontWeight.w700, color: heading, letterSpacing: -0.3),
      headlineSmall: TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w600, color: heading),
      titleLarge: TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, color: heading),
      titleMedium: TextStyle(fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w600, color: body),
      bodyLarge: TextStyle(fontSize: 16.5, height: 1.45, fontWeight: FontWeight.w400, color: secondaryText),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w400, color: secondaryText),
      labelLarge: const TextStyle(fontSize: 17, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w500, color: mutedText),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.comfortable,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: body, size: 26),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: Radii.rCard, side: BorderSide(color: border, width: 1)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.35),
          disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.7),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: Radii.rLg),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 1.5),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: Radii.rLg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        hintStyle: textTheme.bodyLarge!.copyWith(color: mutedText),
        labelStyle: textTheme.bodyMedium!.copyWith(color: secondaryText),
        floatingLabelStyle: textTheme.bodyMedium!.copyWith(color: scheme.primary),
        prefixIconColor: mutedText,
        suffixIconColor: mutedText,
        border: OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: border, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: border, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: scheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: scheme.error, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: scheme.error, width: 2)),
      ),
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        iconColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 15),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.15),
        circularTrackColor: scheme.primary.withValues(alpha: 0.15),
      ),
    );
  }
}
