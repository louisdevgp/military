import 'dart:io';

import 'package:flutter/material.dart';

abstract final class MonoColors {
  static const ink = Color(0xFF172B23);
  static const green = Color(0xFF315B46);
  static const muted = Color(0xFF748077);
  static const background = Color(0xFFF3F5F1);
  static const line = Color(0xFFE1E7DF);
  static const pale = Color(0xFFEAF0E7);
  static const gold = Color(0xFFD7B575);
}

ThemeData monoTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: MonoColors.green,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: MonoColors.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: MonoColors.background,
    foregroundColor: MonoColors.ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: MonoColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: MonoColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: MonoColors.ink,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: MonoColors.ink, height: 1.4),
    bodySmall: TextStyle(fontSize: 12, color: MonoColors.muted, height: 1.4),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    hintStyle: const TextStyle(
      color: MonoColors.muted,
      fontWeight: FontWeight.normal,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: MonoColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: MonoColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: MonoColors.green, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 54),
      backgroundColor: MonoColors.green,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: MonoColors.line),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: MonoColors.ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: MonoColors.pale,
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  ),
);

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({super.key, this.path, this.size, this.radius = 16});
  final String? path;
  final double? size;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Container(
      width: size,
      height: size,
      color: MonoColors.pale,
      child: path == null
          ? _placeholder()
          : Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: 640,
              errorBuilder: (_, _, _) => _placeholder(unavailable: true),
            ),
    ),
  );
  Widget _placeholder({bool unavailable = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(
        unavailable ? Icons.broken_image_outlined : Icons.photo_outlined,
        color: const Color(0xFF96A68F),
        size: size == null || size! > 80 ? 40 : 25,
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFECE7) : MonoColors.pale,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          size: 18,
          color: error ? Colors.red.shade800 : MonoColors.green,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: error ? Colors.red.shade800 : MonoColors.green,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
