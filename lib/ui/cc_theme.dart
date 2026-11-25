// lib/ui/cc_theme.dart  -  Chess.com-like dark palette used by profile + tournaments
import 'package:flutter/material.dart';

const Color ccBg = Color(0xFF262421);
const Color ccCard = Color(0xFF312E2B);
const Color ccLine = Color(0xFF3D3A37);
const Color ccGreen = Color(0xFF81B64C);
const Color ccRed = Color(0xFFB33430);
const Color ccMuted = Color(0xFFA0A0A0);
const Color ccGold = Color(0xFFFFC107);
const Color ccSilver = Color(0xFFB0BEC5);
const Color ccBronze = Color(0xFFCD7F32);

ThemeData ccTheme() => ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: ccBg,
      colorScheme: const ColorScheme.dark(primary: ccGreen, surface: ccCard),
    );

String fmtDate(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

/// 3725000 -> "1:02:05", 125000 -> "2:05".
String fmtCountdown(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

String ordinal(int n) {
  if (n == 1) return '1st';
  if (n == 2) return '2nd';
  if (n == 3) return '3rd';
  return '${n}th';
}
