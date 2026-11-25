// lib/services/pgn_import.dart
//
// Imports PGN text (e.g. from PyChess, Variant "Cambodian") into a GameRecord.
// Move notation: K Khun, M Neang, S Kol, N Ses, R Touk, no letter = Trey.

import '../engine/ouk_rules.dart';
import 'game_analyzer.dart';

class PgnParseResult {
  final GameRecord? record; // null when nothing could be read
  final int parsedPlies;
  final int totalPlies;
  final String? error; // set when parsing stopped early
  final Map<String, String> headers;

  const PgnParseResult({
    required this.record,
    required this.parsedPlies,
    required this.totalPlies,
    required this.error,
    required this.headers,
  });
}

String _clean(String s) => s
    .replaceAll(RegExp(r'=\w'), '')
    .replaceAll(RegExp(r'[+#!?x]'), '')
    .replaceAll('-', '')
    .replaceAll('–', '');

Move? _matchSan(OukPosition pos, String token) {
  final tk = _clean(token);
  if (tk.isEmpty) return null;
  final legal = pos.legalMoves();

  // 1) exact match with our own notation
  for (final m in legal) {
    if (_clean(sanOf(pos, m, withCheck: false)) == tk) return m;
  }

  // 2) lenient: piece letter + destination (+ optional disambiguation)
  if (tk.length < 2) return null;
  final dest = tk.substring(tk.length - 2);
  if (!RegExp(r'^[a-h][1-8]$').hasMatch(dest)) return null;
  var head = tk.substring(0, tk.length - 2);
  var letter = '';
  if (head.isNotEmpty && 'KMSNR'.contains(head[0])) {
    letter = head[0];
    head = head.substring(1);
  }
  final cands = legal.where((m) {
    if (squareName(m.to) != dest) return false;
    final s = sanOf(pos, m, withCheck: false);
    final l = 'KMSNR'.contains(s[0]) ? s[0] : '';
    if (l != letter) return false;
    if (head.isEmpty) return true;
    final from = squareName(m.from);
    return head.length == 1 ? (head == from[0] || head == from[1]) : head == from;
  }).toList();
  return cands.length == 1 ? cands.first : null;
}

PgnParseResult parsePgn(String text) {
  // headers
  final headers = <String, String>{};
  for (final m
      in RegExp(r'\[\s*(\w+)\s+"([^"]*)"\s*\]').allMatches(text)) {
    headers[m.group(1)!] = m.group(2)!;
  }

  final variant = (headers['Variant'] ?? 'Cambodian').toLowerCase();
  if (!variant.contains('cambodian')) {
    return PgnParseResult(
      record: null,
      parsedPlies: 0,
      totalPlies: 0,
      error: 'Variant "${headers['Variant']}" is not Cambodian',
      headers: headers,
    );
  }

  var startFen = OukPosition.startFen;
  final fen = headers['FEN'];
  if (fen != null && fen.trim().isNotEmpty) startFen = fen.trim();

  // movetext
  var body = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  body = body.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
  body = body.replaceAll(RegExp(r';[^\n]*'), ' ');
  var prev = '';
  while (prev != body) {
    prev = body;
    body = body.replaceAll(RegExp(r'\([^()]*\)'), ' '); // variations
  }
  body = body.replaceAll(RegExp(r'\$\d+'), ' ');

  final tokens = <String>[];
  for (var tk in body.split(RegExp(r'\s+'))) {
    if (tk.isEmpty) continue;
    if (tk == '1-0' || tk == '0-1' || tk == '1/2-1/2' || tk == '*') continue;
    tk = tk.replaceFirst(RegExp(r'^\d+\.+'), '');
    if (tk.isEmpty) continue;
    tokens.add(tk);
  }

  OukPosition pos;
  try {
    pos = OukPosition.fromFen(startFen);
  } catch (e) {
    return PgnParseResult(
        record: null,
        parsedPlies: 0,
        totalPlies: tokens.length,
        error: 'Bad FEN: $e',
        headers: headers);
  }

  final moves = <String>[];
  String? error;
  for (int i = 0; i < tokens.length; i++) {
    final m = _matchSan(pos, tokens[i]);
    if (m == null) {
      final no = pos.fullmove;
      error = 'Cannot read move "${tokens[i]}" (move $no, ply ${i + 1})';
      break;
    }
    moves.add(m.uci);
    pos = pos.makeMove(m);
    if (pos.isGameOver) break;
  }

  if (moves.isEmpty) {
    return PgnParseResult(
        record: null,
        parsedPlies: 0,
        totalPlies: tokens.length,
        error: error ?? 'No moves found',
        headers: headers);
  }

  final white = headers['White'] ?? 'White';
  final black = headers['Black'] ?? 'Black';
  bool isEngine(String n) => n.toLowerCase().contains('stockfish');
  final userIsWhite = isEngine(black) || !isEngine(white);

  return PgnParseResult(
    record: GameRecord(
      startFen: startFen,
      moves: moves,
      whiteName: white,
      blackName: black,
      result: headers['Result'] ?? '*',
      userIsWhite: userIsWhite,
    ),
    parsedPlies: moves.length,
    totalPlies: tokens.length,
    error: error,
    headers: headers,
  );
}
