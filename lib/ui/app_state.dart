// lib/ui/app_state.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global UI settings: language (Khmer / English) and board theme.
class AppSettings {
  static final ValueNotifier<bool> km = ValueNotifier<bool>(true);
  static final ValueNotifier<int> boardTheme = ValueNotifier<int>(0);
  static final ValueNotifier<bool> unlockAllBots = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    km.value = p.getBool('lang_km') ?? true;
    boardTheme.value = p.getInt('board_theme') ?? 0;
    unlockAllBots.value = p.getBool('unlock_all') ?? false;
  }

  static Future<void> setKm(bool v) async {
    km.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('lang_km', v);
  }

  static Future<void> setUnlockAll(bool v) async {
    unlockAllBots.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('unlock_all', v);
  }

  static Future<void> setTheme(int i) async {
    boardTheme.value = i;
    final p = await SharedPreferences.getInstance();
    await p.setInt('board_theme', i);
  }
}

/// Pick Khmer or English text.
String t(String khmer, String english) =>
    AppSettings.km.value ? khmer : english;

class BoardTheme {
  final String name;
  final Color light;
  final Color dark;
  final Color lastMove;
  final Color select;
  const BoardTheme(this.name, this.light, this.dark, this.lastMove, this.select);
}

const List<BoardTheme> boardThemes = [
  BoardTheme('Walnut', Color(0xFFF0D9B5), Color(0xFFB58863),
      Color(0x88F6F669), Color(0x99BACA2B)),
  BoardTheme('Stone', Color(0xFFDDE3E8), Color(0xFF7D8FA0),
      Color(0x88F6F669), Color(0x99BACA2B)),
  BoardTheme('Green', Color(0xFFEEEED2), Color(0xFF769656),
      Color(0x88F6F669), Color(0x99F5D142)),
  BoardTheme('Khmer Gold', Color(0xFFF3E2B3), Color(0xFFA9742F),
      Color(0x88FFE066), Color(0x99D4A017)),
];

BoardTheme get currentBoardTheme =>
    boardThemes[AppSettings.boardTheme.value.clamp(0, boardThemes.length - 1).toInt()];
