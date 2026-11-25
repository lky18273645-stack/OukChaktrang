// lib/services/game_analyzer.dart
//
// Post-game analysis: runs Fairy-Stockfish on every position of a finished game,
// measures how much each move lost (win-probability based, like Chess.com),
// classifies every move into 10 tiers, and computes accuracy per side / per phase
// plus an estimated performance Elo.

import 'dart:math';
import 'dart:ui' show Color;

import '../engine/fairy_engine.dart';
import '../engine/ouk_rules.dart';

// -----------------------------------------------------------------------------
// Move classes
// -----------------------------------------------------------------------------

enum MoveClass {
  book,
  brilliant,
  great,
  best,
  excellent,
  good,
  inaccuracy,
  mistake,
  miss,
  blunder,
}

extension MoveClassX on MoveClass {
  String get km {
    switch (this) {
      case MoveClass.book:
        return 'សៀវភៅ';
      case MoveClass.brilliant:
        return 'អស្ចារ្យ';
      case MoveClass.great:
        return 'ល្អប្រសើរ';
      case MoveClass.best:
        return 'ល្អបំផុត';
      case MoveClass.excellent:
        return 'ល្អណាស់';
      case MoveClass.good:
        return 'ល្អ';
      case MoveClass.inaccuracy:
        return 'មិនសូវត្រឹមត្រូវ';
      case MoveClass.mistake:
        return 'កំហុស';
      case MoveClass.miss:
        return 'ខកខាន';
      case MoveClass.blunder:
        return 'កំហុសធ្ងន់';
    }
  }

  String get en {
    switch (this) {
      case MoveClass.book:
        return 'Book';
      case MoveClass.brilliant:
        return 'Brilliant';
      case MoveClass.great:
        return 'Great';
      case MoveClass.best:
        return 'Best';
      case MoveClass.excellent:
        return 'Excellent';
      case MoveClass.good:
        return 'Good';
      case MoveClass.inaccuracy:
        return 'Inaccuracy';
      case MoveClass.mistake:
        return 'Mistake';
      case MoveClass.miss:
        return 'Miss';
      case MoveClass.blunder:
        return 'Blunder';
    }
  }

  /// Short symbol drawn on the board / in the move list.
  String get symbol {
    switch (this) {
      case MoveClass.book:
        return '≡';
      case MoveClass.brilliant:
        return '!!';
      case MoveClass.great:
        return '!';
      case MoveClass.best:
        return '★';
      case MoveClass.excellent:
        return '✓';
      case MoveClass.good:
        return '✓';
      case MoveClass.inaccuracy:
        return '?!';
      case MoveClass.mistake:
        return '?';
      case MoveClass.miss:
        return '✕';
      case MoveClass.blunder:
        return '??';
    }
  }

  Color get color {
    switch (this) {
      case MoveClass.book:
        return const Color(0xFFA88865);
      case MoveClass.brilliant:
        return const Color(0xFF1BACA6);
      case MoveClass.great:
        return const Color(0xFF5C8BB0);
      case MoveClass.best:
        return const Color(0xFF81B64C);
      case MoveClass.excellent:
        return const Color(0xFF96BC4B);
      case MoveClass.good:
        return const Color(0xFF6FA040);
      case MoveClass.inaccuracy:
        return const Color(0xFFF7C631);
      case MoveClass.mistake:
        return const Color(0xFFE58F2A);
      case MoveClass.miss:
        return const Color(0xFFE05B4F);
      case MoveClass.blunder:
        return const Color(0xFFB02A2A);
    }
  }
}

enum Phase { opening, middle, end }

// -----------------------------------------------------------------------------
// Data classes
// -----------------------------------------------------------------------------

/// A finished game, replayable from [startFen] with UCI moves.
class GameRecord {
  final String startFen;
  final List<String> moves; // UCI, e.g. "e3e4"
  final String whiteName;
  final String blackName;
  final String result; // "1-0", "0-1", "1/2-1/2" or "*"
  final bool userIsWhite;

  const GameRecord({
    required this.startFen,
    required this.moves,
    required this.whiteName,
    required this.blackName,
    this.result = '*',
    this.userIsWhite = true,
  });
}

class MoveReview {
  final int ply; // 0-based index of the move
  final String san;
  final String uci;
  final Side side;
  final MoveClass cls;
  final double loss; // win-probability points lost (0..100)
  final double accuracy; // 0..100
  final int cpLoss; // centipawns lost (capped)
  final Phase phase;
  final String? bestUci;
  final String? bestSan;

  const MoveReview({
    required this.ply,
    required this.san,
    required this.uci,
    required this.side,
    required this.cls,
    required this.loss,
    required this.accuracy,
    required this.cpLoss,
    required this.phase,
    required this.bestUci,
    required this.bestSan,
  });
}

class SideSummary {
  final double accuracy; // overall
  final List<double?> phaseAccuracy; // [opening, middle, end]; null = no moves
  final Map<MoveClass, int> counts;
  final double acpl; // average centipawn loss
  final int performanceElo;

  const SideSummary({
    required this.accuracy,
    required this.phaseAccuracy,
    required this.counts,
    required this.acpl,
    required this.performanceElo,
  });
}

class GameReview {
  final GameRecord record;
  final List<OukPosition> positions; // positions[i] = before move i
  final List<MoveReview> moves;
  final List<List<EngineLine>> lines; // engine lines per position
  final List<int> evalWhite; // centipawns, White's view, per position
  final SideSummary white;
  final SideSummary black;
  final int middleStart; // cursor index where the middlegame begins (-1 none)
  final int endStart; // cursor index where the endgame begins (-1 none)
  final int threads;

  const GameReview({
    required this.record,
    required this.positions,
    required this.moves,
    required this.lines,
    required this.evalWhite,
    required this.white,
    required this.black,
    required this.middleStart,
    required this.endStart,
    required this.threads,
  });

  int get plyCount => moves.length;

  /// Counts for both sides combined.
  Map<MoveClass, int> get totalCounts {
    final m = <MoveClass, int>{for (final c in MoveClass.values) c: 0};
    for (final mv in moves) {
      m[mv.cls] = m[mv.cls]! + 1;
    }
    return m;
  }

  /// "13.e5 gxf4 14.gxf4 ..." principal variation of position [cursor].
  String pvText(int cursor, {int maxMoves = 8}) {
    if (cursor < 0 || cursor >= lines.length) return '';
    final ls = lines[cursor];
    if (ls.isEmpty) return '';
    var pos = positions[cursor];
    final sb = StringBuffer();
    var first = true;
    var count = 0;
    for (final uci in ls.first.pv) {
      if (count >= maxMoves) break;
      final m = pos.findLegal(uci);
      if (m == null) break;
      final san = sanOf(pos, m);
      if (pos.turn == Side.white) {
        sb.write('${first ? '' : ' '}${pos.fullmove}.$san');
      } else {
        sb.write(first ? '${pos.fullmove}...$san' : ' $san');
      }
      first = false;
      pos = pos.makeMove(m);
      count++;
    }
    return sb.toString();
  }

  /// Evaluation text from White's view: "+0.84", "-1.20", "#3".
  String evalText(int cursor) {
    if (cursor < 0 || cursor >= lines.length) return '0.00';
    final ls = lines[cursor];
    final turn = positions[cursor].turn;
    if (ls.isNotEmpty && ls.first.mate != null) {
      final m = ls.first.mate!;
      final white = turn == Side.white ? m : -m;
      if (m == 0) {
        // side to move is checkmated
        return turn == Side.white ? '0-1' : '1-0';
      }
      return '${white > 0 ? '' : '-'}#${white.abs()}';
    }
    final cp = evalWhite[cursor];
    final v = (cp / 100).toStringAsFixed(2);
    return cp > 0 ? '+$v' : v;
  }

  /// PGN-like export (Ouk Chaktrang has no standard PGN, so this follows the
  /// PGN layout with Variant/FEN headers).
  String toPgn() {
    final r = record;
    final d = DateTime.now();
    final date =
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    final sb = StringBuffer()
      ..writeln('[Event "OukChaktrang.com game"]')
      ..writeln('[Site "OukChaktrang.com"]')
      ..writeln('[Date "$date"]')
      ..writeln('[White "${r.whiteName}"]')
      ..writeln('[Black "${r.blackName}"]')
      ..writeln('[Result "${r.result}"]')
      ..writeln('[Variant "Cambodian"]')
      ..writeln('[FEN "${r.startFen}"]')
      ..writeln('[SetUp "1"]');
    sb.writeln();
    final parts = <String>[];
    for (final m in moves) {
      final pos = positions[m.ply];
      if (pos.turn == Side.white) {
        parts.add('${pos.fullmove}. ${m.san}');
      } else if (parts.isEmpty) {
        parts.add('${pos.fullmove}... ${m.san}');
      } else {
        parts.add(m.san);
      }
    }
    sb.write(parts.join(' '));
    sb.write(' ${r.result}');
    return sb.toString();
  }
}

// -----------------------------------------------------------------------------
// Notation
// -----------------------------------------------------------------------------

const Map<int, String> _letters = {
  kKhun: 'K',
  kNeang: 'M',
  kKol: 'S',
  kSes: 'N',
  kTouk: 'R',
  kTrey: '',
};

/// Algebraic notation: K Khun, M Neang, S Kol, N Ses, R Touk, no letter = Trey.
String sanOf(OukPosition pos, Move m, {bool withCheck = true}) {
  final piece = pos.pieceAt(m.from);
  final type = piece.abs();
  final capture = pos.pieceAt(m.to) != 0;
  final fromFile = String.fromCharCode(97 + (m.from & 7));
  var dis = '';
  if (type == kTrey) {
    if (capture) dis = fromFile;
  } else {
    final others = pos
        .legalMoves()
        .where((o) =>
            o.to == m.to && o.from != m.from && pos.pieceAt(o.from) == piece)
        .toList();
    if (others.isNotEmpty) {
      final sameFile = others.any((o) => (o.from & 7) == (m.from & 7));
      final sameRank = others.any((o) => (o.from >> 3) == (m.from >> 3));
      if (!sameFile) {
        dis = fromFile;
      } else if (!sameRank) {
        dis = '${(m.from >> 3) + 1}';
      } else {
        dis = squareName(m.from);
      }
    }
  }
  var s = '${_letters[type]}$dis${capture ? 'x' : ''}${squareName(m.to)}'
      '${m.promote ? '=M' : ''}';
  if (withCheck) {
    final next = pos.makeMove(m);
    if (next.status == GameStatus.checkmate) {
      s += '#';
    } else if (next.inCheck) {
      s += '+';
    }
  }
  return s;
}

// -----------------------------------------------------------------------------
// Analyzer
// -----------------------------------------------------------------------------

double winPercent(int cp) =>
    50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1);

double moveAccuracy(double winLoss) =>
    (103.1668 * exp(-0.04354 * winLoss) - 3.1669).clamp(0.0, 100.0).toDouble();

int _value(int piece) {
  switch (piece.abs()) {
    case kNeang:
      return 2;
    case kKol:
    case kSes:
      return 3;
    case kTouk:
      return 5;
    case kTrey:
      return 1;
    default:
      return 0;
  }
}

class GameAnalyzer {
  final FairyEngine engine;
  GameAnalyzer(this.engine);

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  /// Returns null if cancelled.
  Future<GameReview?> analyze(
    GameRecord rec, {
    int movetimeMs = 300,
    int threads = 1,
    void Function(int done, int total)? onProgress,
  }) async {
    _cancelled = false;

    // 1) Replay the game.
    var pos = OukPosition.fromFen(rec.startFen);
    final positions = <OukPosition>[pos];
    final moves = <Move>[];
    for (final uci in rec.moves) {
      final m = pos.findLegal(uci);
      if (m == null) break;
      moves.add(m);
      pos = pos.makeMove(m);
      positions.add(pos);
    }
    final n = moves.length;

    // 2) Engine pass over every position.
    final lines = <List<EngineLine>>[];
    for (int i = 0; i <= n; i++) {
      if (_cancelled) return null;
      onProgress?.call(i, n + 1);
      final p = positions[i];
      final st = p.status;
      if (st != GameStatus.ongoing) {
        final mated = st == GameStatus.checkmate;
        lines.add([
          EngineLine(
              cp: mated ? -10000 : 0, mate: mated ? 0 : null, depth: 0, pv: const [])
        ]);
        continue;
      }
      var ls = await engine.analyseMulti(p.toFen(),
          movetimeMs: movetimeMs, multiPv: 2);
      if (ls.isEmpty) {
        ls = const [EngineLine(cp: 0, mate: null, depth: 0, pv: [])];
      }
      lines.add(ls);
    }
    onProgress?.call(n + 1, n + 1);

    // 3) Evaluations from White's view.
    final evalWhite = <int>[];
    for (int i = 0; i <= n; i++) {
      final s = lines[i].first.cp;
      evalWhite.add(positions[i].turn == Side.white ? s : -s);
    }

    // 4) Classify every move.
    final reviews = <MoveReview>[];
    double prevLoss = 0;
    for (int i = 0; i < n; i++) {
      final before = positions[i];
      final m = moves[i];
      final mover = before.turn;
      final bestLine = lines[i].first;
      final bestUci = bestLine.pv.isNotEmpty ? bestLine.pv.first : null;
      final playedBest = bestUci != null &&
          bestUci.length >= 4 &&
          bestUci.substring(0, 4) == m.uci.substring(0, 4);

      final cpBefore = bestLine.cp; // mover's view
      final cpAfter = -lines[i + 1].first.cp; // mover's view
      final wBefore = winPercent(cpBefore);
      final wAfter = playedBest ? wBefore : winPercent(cpAfter);
      final loss = max(0.0, wBefore - wAfter);
      final cpLoss = playedBest ? 0 : max(0, cpBefore - cpAfter).clamp(0, 500).toInt();

      final isEnd = before.isEndgame;
      final phase = isEnd ? Phase.end : (i < 20 ? Phase.opening : Phase.middle);

      MoveClass cls;
      if (i < 8 && loss <= 2.0) {
        cls = MoveClass.book;
      } else if (loss <= 2.0 &&
          wBefore <= 85 &&
          wAfter >= 40 &&
          _isSacrifice(before, m)) {
        cls = MoveClass.brilliant;
      } else if (playedBest || loss <= 0.3) {
        final gap = lines[i].length >= 2
            ? wBefore - winPercent(lines[i][1].cp)
            : 0.0;
        cls = (gap >= 15 && wBefore <= 90) ? MoveClass.great : MoveClass.best;
      } else if (loss <= 2.0) {
        cls = MoveClass.excellent;
      } else if (loss <= 5.0) {
        cls = MoveClass.good;
      } else if (loss <= 20.0 && prevLoss >= 10.0) {
        cls = MoveClass.miss;
      } else if (loss <= 10.0) {
        cls = MoveClass.inaccuracy;
      } else if (loss <= 20.0) {
        cls = MoveClass.mistake;
      } else {
        cls = MoveClass.blunder;
      }

      String? bestSan;
      if (bestUci != null && !playedBest) {
        final bm = before.findLegal(bestUci);
        if (bm != null) bestSan = sanOf(before, bm);
      } else if (bestUci != null) {
        bestSan = sanOf(before, m);
      }

      reviews.add(MoveReview(
        ply: i,
        san: sanOf(before, m),
        uci: m.uci,
        side: mover,
        cls: cls,
        loss: loss,
        accuracy: moveAccuracy(loss),
        cpLoss: cpLoss,
        phase: phase,
        bestUci: bestUci,
        bestSan: bestSan,
      ));
      prevLoss = loss;
    }

    // 5) Phase boundaries (cursor indices).
    var middleStart = -1;
    var endStart = -1;
    for (final r in reviews) {
      if (r.phase == Phase.middle && middleStart < 0) middleStart = r.ply;
      if (r.phase == Phase.end && endStart < 0) endStart = r.ply;
    }

    return GameReview(
      record: rec,
      positions: positions,
      moves: reviews,
      lines: lines,
      evalWhite: evalWhite,
      white: _summarize(reviews, Side.white),
      black: _summarize(reviews, Side.black),
      middleStart: middleStart,
      endStart: endStart,
      threads: threads,
    );
  }

  /// A move that gives up material (piece worth 2+ more than what it takes)
  /// without getting it back through a recapture.
  bool _isSacrifice(OukPosition before, Move m) {
    final v = _value(before.pieceAt(m.from));
    final c = _value(before.pieceAt(m.to));
    if (v - c < 2) return false;
    final after = before.makeMove(m);
    if (after.isGameOver) return false;
    final caps = after.legalMoves().where((x) => x.to == m.to).toList();
    if (caps.isEmpty) return false;
    for (final x in caps) {
      final capturer = _value(after.pieceAt(x.from));
      final next = after.makeMove(x);
      final recapture = !next.isGameOver && next.legalMoves().any((y) => y.to == m.to);
      final net = recapture ? (c - v + capturer) : (c - v);
      if (net <= -2) return true;
    }
    return false;
  }

  SideSummary _summarize(List<MoveReview> all, Side side) {
    final mine = all.where((m) => m.side == side).toList();
    final counts = <MoveClass, int>{for (final c in MoveClass.values) c: 0};
    for (final m in mine) {
      counts[m.cls] = counts[m.cls]! + 1;
    }
    double avg(Iterable<double> xs) {
      final l = xs.toList();
      return l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
    }

    double? phaseAcc(Phase p) {
      final xs = mine.where((m) => m.phase == p).map((m) => m.accuracy).toList();
      return xs.isEmpty ? null : avg(xs);
    }

    final acc = mine.isEmpty ? 0.0 : avg(mine.map((m) => m.accuracy));
    final acpl = mine.isEmpty
        ? 0.0
        : mine.map((m) => m.cpLoss).reduce((a, b) => a + b) / mine.length;
    final elo = mine.isEmpty
        ? 0
        : ((3000 * exp(-0.009 * acpl)).clamp(300.0, 3200.0) / 10).round() * 10;
    return SideSummary(
      accuracy: acc,
      phaseAccuracy: [
        phaseAcc(Phase.opening),
        phaseAcc(Phase.middle),
        phaseAcc(Phase.end),
      ],
      counts: counts,
      acpl: acpl,
      performanceElo: elo,
    );
  }
}
