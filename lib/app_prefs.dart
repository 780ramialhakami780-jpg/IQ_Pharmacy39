import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class AppPrefs {
  static final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
  static final localeNotifier = ValueNotifier<Locale>(const Locale('ar'));
  static final settingsNotifier = ValueNotifier<int>(0);

  // السمات والخلفيات
  static String themePreset = 'dark'; // dark, amoled, light, pharmacy
  static String wallpaperType = 'none'; // none, preset, gallery
  static String wallpaperValue = '';
  static double wallpaperDim = 0.72;

  // الخطوط والأحجام
  static String fontFamily = 'system'; // system, cairo, tajawal, amiri, ruqaa, almarai
  static double fontScale = 1.0;

  // عرض وترتيب المواد
  static bool subjectsGrid = false;
  static List<String> subjectOrder = [];

  // الشكل وعناصر الرئيسية
  static double cardRadius = 14.0;
  static bool showAnnouncements = true;
  static bool showQuickCards = true;
  static bool quizHaptics = true;
  static bool dataSaver = false;

  // قفل التطبيق
  static bool pinEnabled = false;
  static String appPin = '';

  static bool get isEnglish => localeNotifier.value.languageCode == 'en';
  static bool get isDark => themePreset != 'light';

  static String tr(String ar, String en) => isEnglish ? en : ar;

  static void _notify() {
    settingsNotifier.value++;
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('lang_code') ?? 'ar';
    localeNotifier.value = Locale(lang);

    themePreset = prefs.getString('theme_preset') ??
        ((prefs.getBool('is_dark') ?? true) ? 'dark' : 'light');
    themeNotifier.value = themePreset == 'light' ? ThemeMode.light : ThemeMode.dark;

    wallpaperType = prefs.getString('wallpaper_type') ?? 'none';
    wallpaperValue = prefs.getString('wallpaper_value') ?? '';
    wallpaperDim = prefs.getDouble('wallpaper_dim') ?? 0.72;

    fontFamily = prefs.getString('font_family') ?? 'system';
    fontScale = prefs.getDouble('font_scale') ?? 1.0;

    subjectsGrid = prefs.getBool('subjects_grid') ?? false;
    subjectOrder = prefs.getStringList('subject_order') ?? [];

    cardRadius = prefs.getDouble('card_radius') ?? 14.0;
    showAnnouncements = prefs.getBool('show_announcements') ?? true;
    showQuickCards = prefs.getBool('show_quick_cards') ?? true;
    quizHaptics = prefs.getBool('quiz_haptics') ?? true;
    dataSaver = prefs.getBool('data_saver') ?? false;

    pinEnabled = prefs.getBool('pin_enabled') ?? false;
    appPin = prefs.getString('app_pin') ?? '';
  }

  static Future<void> setDark(bool dark) async {
    await setThemePreset(dark ? 'dark' : 'light');
  }

  static Future<void> setThemePreset(String preset) async {
    themePreset = preset;
    themeNotifier.value = preset == 'light' ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preset', preset);
    await prefs.setBool('is_dark', preset != 'light');
    _notify();
  }

  static Future<void> setLang(String code) async {
    localeNotifier.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang_code', code);
    _notify();
  }

  static Future<void> setWallpaper(String type, String value) async {
    wallpaperType = type;
    wallpaperValue = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallpaper_type', type);
    await prefs.setString('wallpaper_value', value);
    _notify();
  }

  static Future<void> setWallpaperDim(double dim) async {
    wallpaperDim = dim;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('wallpaper_dim', dim);
    _notify();
  }

  static Future<void> setFontFamily(String family) async {
    fontFamily = family;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('font_family', family);
    _notify();
  }

  static Future<void> setFontScale(double scale) async {
    fontScale = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_scale', scale);
    _notify();
  }

  static Future<void> setSubjectsGrid(bool grid) async {
    subjectsGrid = grid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subjects_grid', grid);
    _notify();
  }

  static Future<void> setSubjectOrder(List<String> order) async {
    subjectOrder = order;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('subject_order', order);
    _notify();
  }

  static List<dynamic> applySubjectOrder(List<dynamic> rawSubjects) {
    if (subjectOrder.isEmpty || rawSubjects.isEmpty) return List.from(rawSubjects);
    final list = List<dynamic>.from(rawSubjects);
    list.sort((a, b) {
      final idA = (a['id'] ?? '').toString();
      final idB = (b['id'] ?? '').toString();
      final idxA = subjectOrder.indexOf(idA);
      final idxB = subjectOrder.indexOf(idB);
      if (idxA == -1 && idxB == -1) return 0;
      if (idxA == -1) return 1;
      if (idxB == -1) return -1;
      return idxA.compareTo(idxB);
    });
    return list;
  }

  static Future<void> setCardRadius(double radius) async {
    cardRadius = radius;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('card_radius', radius);
    _notify();
  }

  static Future<void> setTogglePref(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
    switch (key) {
      case 'show_announcements':
        showAnnouncements = val;
        break;
      case 'show_quick_cards':
        showQuickCards = val;
        break;
      case 'quiz_haptics':
        quizHaptics = val;
        break;
      case 'data_saver':
        dataSaver = val;
        break;
    }
    _notify();
  }

  static Future<void> setAppPin(bool enabled, String pin) async {
    pinEnabled = enabled;
    appPin = pin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pin_enabled', enabled);
    await prefs.setString('app_pin', pin);
    _notify();
  }

  static TextTheme applyFontToTextTheme(TextTheme base) {
    switch (fontFamily) {
      case 'cairo':
        return GoogleFonts.cairoTextTheme(base);
      case 'tajawal':
        return GoogleFonts.tajawalTextTheme(base);
      case 'amiri':
        return GoogleFonts.amiriTextTheme(base);
      case 'ruqaa':
        return GoogleFonts.arefRuqaaTextTheme(base);
      case 'almarai':
        return GoogleFonts.almaraiTextTheme(base);
      default:
        return base;
    }
  }

  static String exportBackupJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'IQ_Pharmacy39',
      'version': 1,
      'theme_preset': themePreset,
      'lang_code': localeNotifier.value.languageCode,
      'wallpaper_type': wallpaperType == 'gallery' ? 'none' : wallpaperType,
      'wallpaper_value': wallpaperType == 'gallery' ? '' : wallpaperValue,
      'wallpaper_dim': wallpaperDim,
      'font_family': fontFamily,
      'font_scale': fontScale,
      'subjects_grid': subjectsGrid,
      'subject_order': subjectOrder,
      'card_radius': cardRadius,
      'show_announcements': showAnnouncements,
      'show_quick_cards': showQuickCards,
      'quiz_haptics': quizHaptics,
      'data_saver': dataSaver,
    });
  }

  static Future<bool> importBackupJson(String rawJson) async {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      if (map['app'] != 'IQ_Pharmacy39') return false;

      if (map['theme_preset'] != null) await setThemePreset(map['theme_preset']);
      if (map['lang_code'] != null) await setLang(map['lang_code']);
      if (map['wallpaper_type'] != null) {
        await setWallpaper(map['wallpaper_type'], map['wallpaper_value'] ?? '');
      }
      if (map['wallpaper_dim'] != null) {
        await setWallpaperDim((map['wallpaper_dim'] as num).toDouble());
      }
      if (map['font_family'] != null) await setFontFamily(map['font_family']);
      if (map['font_scale'] != null) {
        await setFontScale((map['font_scale'] as num).toDouble());
      }
      if (map['subjects_grid'] != null) await setSubjectsGrid(map['subjects_grid']);
      if (map['subject_order'] != null) {
        await setSubjectOrder(List<String>.from(map['subject_order']));
      }
      if (map['card_radius'] != null) {
        await setCardRadius((map['card_radius'] as num).toDouble());
      }
      if (map['show_announcements'] != null) {
        await setTogglePref('show_announcements', map['show_announcements']);
      }
      if (map['show_quick_cards'] != null) {
        await setTogglePref('show_quick_cards', map['show_quick_cards']);
      }
      if (map['quiz_haptics'] != null) {
        await setTogglePref('quiz_haptics', map['quiz_haptics']);
      }
      if (map['data_saver'] != null) {
        await setTogglePref('data_saver', map['data_saver']);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> resetAllSettings() async {
    await setThemePreset('dark');
    await setLang('ar');
    await setWallpaper('none', '');
    await setWallpaperDim(0.72);
    await setFontFamily('system');
    await setFontScale(1.0);
    await setSubjectsGrid(false);
    await setSubjectOrder([]);
    await setCardRadius(14.0);
    await setTogglePref('show_announcements', true);
    await setTogglePref('show_quick_cards', true);
    await setTogglePref('quiz_haptics', true);
    await setTogglePref('data_saver', false);
  }
}
