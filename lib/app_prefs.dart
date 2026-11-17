import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPrefs {
  static final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
  static final localeNotifier = ValueNotifier<Locale>(const Locale('ar'));

  static bool get isEnglish => localeNotifier.value.languageCode == 'en';
  static bool get isDark => themeNotifier.value == ThemeMode.dark;

  static String tr(String ar, String en) => isEnglish ? en : ar;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool('is_dark') ?? true;
    final lang = prefs.getString('lang_code') ?? 'ar';
    themeNotifier.value = dark ? ThemeMode.dark : ThemeMode.light;
    localeNotifier.value = Locale(lang);
  }

  static Future<void> setDark(bool dark) async {
    themeNotifier.value = dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark', dark);
  }

  static Future<void> setLang(String code) async {
    localeNotifier.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang_code', code);
  }
}
