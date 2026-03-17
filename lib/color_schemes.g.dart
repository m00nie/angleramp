import 'package:flutter/material.dart';

const jellyfinBlueColor = Color(0xFF00A4DC);
const jellyfinPurpleColor = Color(0xFFAA5CC3);

// ── Trading-game inspired dark palette ────────────────────────────────────────
const tgSurface950 = Color(0xFF03070F); // scaffold / page background
const tgSurface900 = Color(0xFF080F1E); // cards, app bar, bottom nav
const tgSurface800 = Color(0xFF0F182E); // elevated cards, input fill
const tgSurface700 = Color(0xFF17243E); // dividers, highlighted rows
const tgSurface600 = Color(0xFF1E3054); // borders, outlines
const tgBrandGreen = Color(0xFF34D399); // primary CTA / playback / progress
const tgBrandBlue  = Color(0xFF60A5FA); // links, tabs, info highlights
const tgBrandRed   = Color(0xFFF87171); // errors, destructive
const tgBrandGold  = Color(0xFFFBBF24); // tertiary / accent
// ─────────────────────────────────────────────────────────────────────────────

const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  // Primary
  primary: Color(0xFF00668A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFC4E8FF),
  onPrimaryContainer: Color(0xFF001E2C),
  // Secondary
  secondary: Color(0xFF406374),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFCCE8F8),
  onSecondaryContainer: Color(0xFF1B333F),
  // Tertiary
  tertiary: Color(0xFF893DA2),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFAD7FF),
  onTertiaryContainer: Color(0xFF330044),
  // Error
  error: Color(0xFFBA1A1A),
  errorContainer: Color(0xFFFFDAD6),
  onError: Color(0xFFFFFFFF),
  onErrorContainer: Color(0xFF410002),
  // Background & Surface
  background: Color(0xFFFCFDFE),
  onBackground: Color(0xFF191C1E),
  surface: Color(0xFFFCFDFE),
  onSurface: Color(0xFF191C1E),
  surfaceVariant: Color(0xFFDDE4E8),
  onSurfaceVariant: Color(0xFF41484D),
  // Other colors
  outline: Color(0xFF727A7F),
  onInverseSurface: Color(0xFFF0F1F3),
  inverseSurface: Color(0xFF2E3133),
  inversePrimary: Color(0xFF7BD0FF),
  shadow: Color(0xFF000000),
  surfaceTint: Color(0xFF00668A),
  outlineVariant: Color(0xFFC0C7CD),
  scrim: Color(0xFF000000),
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  // Primary — emerald green for active/playback states
  primary: tgBrandGreen,
  onPrimary: Color(0xFF001A0E),
  primaryContainer: tgSurface800,
  onPrimaryContainer: Color(0xFFD1FAE5),
  // Secondary — blue for links, info, tabs
  secondary: tgBrandBlue,
  onSecondary: Color(0xFF0A1A3E),
  secondaryContainer: tgSurface800,
  onSecondaryContainer: Color(0xFFDBEAFE),
  // Tertiary — gold accent
  tertiary: tgBrandGold,
  onTertiary: Color(0xFF1A1000),
  tertiaryContainer: tgSurface800,
  onTertiaryContainer: Color(0xFFFEF3C7),
  // Error
  error: tgBrandRed,
  errorContainer: Color(0xFF2C0000),
  onError: Color(0xFF1A0000),
  onErrorContainer: Color(0xFFFECACA),
  // Background & Surface
  background: tgSurface950,
  onBackground: Color(0xFFFFFFFF),
  surface: tgSurface900,
  onSurface: Color(0xFFFFFFFF),
  surfaceVariant: tgSurface700,
  onSurfaceVariant: Color(0xFF94A3B8),
  // Other colors
  outline: tgSurface600,
  onInverseSurface: Color(0xFF191C1E),
  inverseSurface: Color(0xFFE1E2E5),
  inversePrimary: tgBrandGreen,
  shadow: Color(0xFF000000),
  surfaceTint: tgBrandGreen,
  outlineVariant: tgSurface700,
  scrim: Color(0xFF000000),
);