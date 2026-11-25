// lib/engine/ouk_rules.dart
//
// Ouk Chaktrang (Cambodian chess) rules + Chbap Rab counting engine.
// Pure Dart, no Flutter imports, so it can be unit-tested with `dart test`.
//
// Squares: index = rank * 8 + file, a1 = 0, h8 = 63.
// Positive piece ids = White, negative = Black.
//
// FEN is compatible with Fairy-Stockfish `cambodian`:
//   rnsmksnr/8/pppppppp/8/8/PPPPPPPP/8/RNSKMSNR w DEde - 0 1
// Letters: k = Khun, m = Neang, s = Kol, n = Ses, r = Touk, p = Trey.
// The 3rd FEN field lists the files of the Khun / Neang that have not moved yet
// (they keep their special first-move jump).

const int kEmpty = 0;
const int kKhun = 1; // King
const int kNeang = 2; // Queen (Met)
const int kKol = 3; // Bishop (Silver general)
const int kSes = 4; // Knight
const int kTouk = 5; // Rook
const int kTrey = 6; // Pawn

const Map<String, int> _charToType = {
  'k': kKhun,
  'm': kNeang,
  's': kKol,
  'n': kSes,
  'r': kTouk,
  'p': kTrey,
};
const List<String> _typeToChar = ['', 'k', 'm', 's', 'n', 'r', 'p'];

const List<List<int>> _knightOffsets = [
  [1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2],
];
const List<List<int>> _diagOffsets = [
  [1, 1], [1, -1], [-1, 1], [-1, -1],
];
const List<List<int>> _orthoOffsets = [
  [1, 0], [-1, 0], [0, 1], [0, -1],
];

enum Side { white, black }

extension SideX on Side {
  Side get opp => this == Side.white ? Side.black : Side.white;
  int get sign => this == Side.white ? 1 : -1;
  int get idx => this == Side.white ? 0 : 1;
}

enum CountType { none, board, piece }

enum GameStatus {
  ongoing,
  checkmate, // side to move is mated
  stalemate, // draw
  drawCounting, // Chbap Rab limit reached
  drawInsufficient, // bare Khun vs bare Khun
  drawRepetition, // threefold repetition
}

String squareName(int s) =>
    '${String.fromCharCode(97 + (s & 7))}${(s >> 3) + 1}';

int parseSquare(String s) => (s.codeUnitAt(1) - 49) * 8 + (s.codeUnitAt(0) - 97);

class Move {
  final int from;
  final int to;
  final bool promote; // Trey -> Neang
  const Move(this.from, this.to, {this.promote = false});

  String get uci => '${squareName(from)}${squareName(to)}${promote ? 'm' : ''}';

  static Move? tryParse(String s) {
    if (s.length < 4) return null;
    final f = parseSquare(s.substring(0, 2));
    final t = parseSquare(s.substring(2, 4));
    if (f < 0 || f > 63 || t < 0 || t > 63) return null;
    return Move(f, t, promote: s.length >= 5);
  }

  @override
  bool operator ==(Object o) =>
      o is Move && o.from == from && o.to == to && o.promote == promote;

  @override
  int get hashCode => Object.hash(from, to, promote);

  @override
  String toString() => uci;
}

/// Snapshot of the counting state, for the on-screen counter.
class CountingInfo {
  final CountType type;
  final int count; // current count
  final int limit; // draw when count >= limit
  final Side? attacker; // only for piece counting
  const CountingInfo(this.type, this.count, this.limit, this.attacker);

  bool get active => type != CountType.none;
  String get label => active ? '$count/$limit' : '';
}

class OukPosition {
  static const String startFen =
      'rnsmksnr/8/pppppppp/8/8/PPPPPPPP/8/RNSKMSNR w DEde - 0 1';

  final List<int> b; // 64 squares
  final Side turn;
  final List<int> kingHome; // per side: home square while Khun unmoved, else -1
  final List<int> neangHome; // per side: home square while Neang unmoved, else -1
  int halfmove;
  int fullmove;

  CountType countType = CountType.none;
  int countMoves = 0;
  int countLimit = 0;
  Side? countAttacker;

  final List<String> _keys = [];
  List<Move>? _legalCache;

  OukPosition._(this.b, this.turn, this.kingHome, this.neangHome,
      this.halfmove, this.fullmove);

  factory OukPosition.start() => OukPosition.fromFen(startFen);

  factory OukPosition.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final rows = parts[0].split('/');
    if (rows.length != 8) {
      throw FormatException('FEN needs 8 ranks: $fen');
    }
    final board = List<int>.filled(64, 0);
    for (int i = 0; i < 8; i++) {
      final rank = 7 - i;
      int file = 0;
      for (final ch in rows[i].split('')) {
        final d = int.tryParse(ch);
        if (d != null) {
          file += d;
          continue;
        }
        final lower = ch.toLowerCase();
        final t = _charToType[lower];
        if (t == null || file > 7) {
          throw FormatException('Bad FEN char "$ch" in $fen');
        }
        board[rank * 8 + file] = ch == lower ? -t : t;
        file++;
      }
    }
    final turn = (parts.length > 1 && parts[1] == 'b') ? Side.black : Side.white;
    final kingHome = [-1, -1];
    final neangHome = [-1, -1];
    final flags = parts.length > 2 ? parts[2] : '-';
    for (final ch in flags.split('')) {
      if (ch == '-') continue;
      final lower = ch.toLowerCase();
      final f = lower.codeUnitAt(0) - 97;
      if (f < 0 || f > 7) continue;
      final side = ch == lower ? Side.black : Side.white;
      final home = (side == Side.white ? 0 : 7) * 8 + f;
      final piece = board[home];
      if (piece != 0 && piece.sign == side.sign) {
        if (piece.abs() == kKhun) kingHome[side.idx] = home;
        if (piece.abs() == kNeang) neangHome[side.idx] = home;
      }
    }
    final half = parts.length > 4 ? (int.tryParse(parts[4]) ?? 0) : 0;
    final full = parts.length > 5 ? (int.tryParse(parts[5]) ?? 1) : 1;
    final pos = OukPosition._(board, turn, kingHome, neangHome, half, full);
    pos._updateCounting(null);
    pos._keys.add(pos._key());
    return pos;
  }

  OukPosition _copy() {
    final n = OukPosition._(List<int>.from(b), turn, List<int>.from(kingHome),
        List<int>.from(neangHome), halfmove, fullmove);
    n.countType = countType;
    n.countMoves = countMoves;
    n.countLimit = countLimit;
    n.countAttacker = countAttacker;
    n._keys.addAll(_keys);
    return n;
  }

  String toFen() {
    final rows = <String>[];
    for (int rank = 7; rank >= 0; rank--) {
      final sb = StringBuffer();
      int empty = 0;
      for (int file = 0; file < 8; file++) {
        final p = b[rank * 8 + file];
        if (p == 0) {
          empty++;
          continue;
        }
        if (empty > 0) {
          sb.write(empty);
          empty = 0;
        }
        final c = _typeToChar[p.abs()];
        sb.write(p > 0 ? c.toUpperCase() : c);
      }
      if (empty > 0) sb.write(empty);
      rows.add(sb.toString());
    }
    final flags = <String>[];
    for (final side in Side.values) {
      final files = <int>{};
      if (kingHome[side.idx] >= 0) files.add(kingHome[side.idx] & 7);
      if (neangHome[side.idx] >= 0) files.add(neangHome[side.idx] & 7);
      final sorted = files.toList()..sort();
      for (final f in sorted) {
        final c = String.fromCharCode(97 + f);
        flags.add(side == Side.white ? c.toUpperCase() : c);
      }
    }
    final flagStr = flags.isEmpty ? '-' : flags.join();
    return '${rows.join('/')} ${turn == Side.white ? 'w' : 'b'} $flagStr - $halfmove $fullmove';
  }

  String _key() =>
      '${Object.hashAll(b)}|${turn.idx}|${kingHome.join(',')}|${neangHome.join(',')}';

  // ---------------------------------------------------------------------------
  // Move generation
  // ---------------------------------------------------------------------------

  List<Move> _pseudo(List<int> bd, Side s, {required bool attackOnly}) {
    final out = <Move>[];
    final sg = s.sign;

    void step(int from, int df, int dr) {
      final f = (from & 7) + df;
      final r = (from >> 3) + dr;
      if (f < 0 || f > 7 || r < 0 || r > 7) return;
      final to = r * 8 + f;
      final t = bd[to];
      if (t == 0 || t.sign != sg) out.add(Move(from, to));
    }

    void slide(int from, int df, int dr) {
      int f = (from & 7) + df;
      int r = (from >> 3) + dr;
      while (f >= 0 && f < 8 && r >= 0 && r < 8) {
        final to = r * 8 + f;
        final t = bd[to];
        if (t == 0) {
          out.add(Move(from, to));
        } else {
          if (t.sign != sg) out.add(Move(from, to));
          break;
        }
        f += df;
        r += dr;
      }
    }

    for (int from = 0; from < 64; from++) {
      final p = bd[from];
      if (p == 0 || p.sign != sg) continue;
      switch (p.abs()) {
        case kKhun:
          for (final d in _diagOffsets) {
            step(from, d[0], d[1]);
          }
          for (final d in _orthoOffsets) {
            step(from, d[0], d[1]);
          }
          // First-move knight jump of the Khun (not while in check).
          if (!attackOnly &&
              kingHome[s.idx] == from &&
              !_attacked(bd, from, s.opp)) {
            for (final d in _knightOffsets) {
              step(from, d[0], d[1]);
            }
          }
          break;
        case kNeang:
          for (final d in _diagOffsets) {
            step(from, d[0], d[1]);
          }
          // First-move 2-square forward jump of the Neang.
          if (!attackOnly && neangHome[s.idx] == from) {
            final r2 = (from >> 3) + 2 * sg;
            if (r2 >= 0 && r2 < 8) {
              final to = r2 * 8 + (from & 7);
              if (bd[to] == 0) out.add(Move(from, to));
            }
          }
          break;
        case kKol:
          for (final d in _diagOffsets) {
            step(from, d[0], d[1]);
          }
          step(from, 0, sg); // one step straight forward
          break;
        case kSes:
          for (final d in _knightOffsets) {
            step(from, d[0], d[1]);
          }
          break;
        case kTouk:
          for (final d in _orthoOffsets) {
            slide(from, d[0], d[1]);
          }
          break;
        case kTrey:
          {
            final r = from >> 3;
            final f = from & 7;
            final nr = r + sg;
            if (nr < 0 || nr > 7) break;
            final promoRank = s == Side.white ? 5 : 2; // 6th rank, relative
            if (!attackOnly) {
              final to = nr * 8 + f;
              if (bd[to] == 0) {
                out.add(Move(from, to, promote: nr == promoRank));
              }
            }
            for (final df in const [-1, 1]) {
              final nf = f + df;
              if (nf < 0 || nf > 7) continue;
              final to = nr * 8 + nf;
              final t = bd[to];
              if (t != 0 && t.sign != sg) {
                out.add(Move(from, to, promote: nr == promoRank));
              }
            }
          }
          break;
      }
    }
    return out;
  }

  bool _attacked(List<int> bd, int sq, Side by) {
    for (final m in _pseudo(bd, by, attackOnly: true)) {
      if (m.to == sq) return true;
    }
    return false;
  }

  List<int> _boardAfter(Move m) {
    final nb = List<int>.from(b);
    final p = nb[m.from];
    nb[m.to] = m.promote ? kNeang * p.sign : p;
    nb[m.from] = 0;
    return nb;
  }

  int kingSquare(Side s, [List<int>? bd]) {
    final board = bd ?? b;
    final k = kKhun * s.sign;
    for (int i = 0; i < 64; i++) {
      if (board[i] == k) return i;
    }
    return -1;
  }

  bool get inCheck {
    final ks = kingSquare(turn);
    return ks >= 0 && _attacked(b, ks, turn.opp);
  }

  List<Move> legalMoves() {
    final cached = _legalCache;
    if (cached != null) return cached;
    final res = <Move>[];
    for (final m in _pseudo(b, turn, attackOnly: false)) {
      final nb = _boardAfter(m);
      final ks = kingSquare(turn, nb);
      if (ks >= 0 && !_attacked(nb, ks, turn.opp)) res.add(m);
    }
    return _legalCache = res;
  }

  List<Move> legalMovesFrom(int sq) =>
      legalMoves().where((m) => m.from == sq).toList();

  /// Accepts UCI like "e3e4" or "e5e6m". Returns the matching legal move or null.
  Move? findLegal(String uci) {
    final p = Move.tryParse(uci);
    if (p == null) return null;
    for (final m in legalMoves()) {
      if (m.from == p.from && m.to == p.to) return m; // promotion is automatic
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Playing a move
  // ---------------------------------------------------------------------------

  /// Returns the new position. Throws if the move is illegal.
  OukPosition makeMove(Move m) {
    if (!legalMoves().contains(m)) {
      throw ArgumentError('Illegal move ${m.uci} in ${toFen()}');
    }
    final n = _copy();
    final p = n.b[m.from];
    final captured = n.b[m.to] != 0;
    n.b[m.to] = m.promote ? kNeang * p.sign : p;
    n.b[m.from] = 0;
    for (final side in Side.values) {
      for (final homes in [n.kingHome, n.neangHome]) {
        if (homes[side.idx] == m.from || homes[side.idx] == m.to) {
          homes[side.idx] = -1; // moved away, or captured / occupied
        }
      }
    }
    final next = OukPosition._(n.b, turn.opp, n.kingHome, n.neangHome,
        (p.abs() == kTrey || captured) ? 0 : halfmove + 1,
        turn == Side.black ? fullmove + 1 : fullmove);
    next.countType = n.countType;
    next.countMoves = n.countMoves;
    next.countLimit = n.countLimit;
    next.countAttacker = n.countAttacker;
    next._keys.addAll(n._keys);
    next._updateCounting(turn);
    next._keys.add(next._key());
    return next;
  }

  OukPosition makeUci(String uci) {
    final m = findLegal(uci);
    if (m == null) throw ArgumentError('Illegal move $uci in ${toFen()}');
    return makeMove(m);
  }

  // ---------------------------------------------------------------------------
  // Chbap Rab counting rules (simplified, tournament-style)
  //
  //  * No Trey left on the board (either side)         -> counting begins.
  //  * Both sides still have pieces: BOARD COUNT, 64 full moves (Ouk count).
  //  * One side down to a bare Khun: PIECE COUNT for the stronger side, limit
  //    by its strongest material:  2 Touk 8 | 1 Touk 16 | 2 Kol 22 | 2 Ses 32
  //    | 1 Kol 44 | Ses or Neang only 64.  Counted in the attacker's moves.
  //  * Checkmate on the last counted move still wins; otherwise it is a draw.
  // ---------------------------------------------------------------------------

  static int pieceLimit(List<int> cnt) {
    if (cnt[kTouk] >= 2) return 8;
    if (cnt[kTouk] == 1) return 16;
    if (cnt[kKol] >= 2) return 22;
    if (cnt[kSes] >= 2) return 32;
    if (cnt[kKol] == 1) return 44;
    return 64;
  }

  List<List<int>> _material() {
    final cnt = [List<int>.filled(7, 0), List<int>.filled(7, 0)];
    for (final p in b) {
      if (p == 0) continue;
      cnt[p > 0 ? 0 : 1][p.abs()]++;
    }
    return cnt;
  }

  void _updateCounting(Side? mover) {
    final cnt = _material();
    final pawns = cnt[0][kTrey] + cnt[1][kTrey];
    if (pawns > 0) {
      countType = CountType.none;
      countMoves = 0;
      countLimit = 0;
      countAttacker = null;
      return;
    }
    int pieces(int i) =>
        cnt[i][kNeang] + cnt[i][kKol] + cnt[i][kSes] + cnt[i][kTouk];
    final pw = pieces(0);
    final pb = pieces(1);
    if (pw == 0 && pb == 0) {
      countType = CountType.none;
      return;
    }
    if (pw == 0 || pb == 0) {
      final attacker = pw > 0 ? Side.white : Side.black;
      final limit = pieceLimit(cnt[attacker.idx]);
      if (countType != CountType.piece || countAttacker != attacker) {
        countType = CountType.piece;
        countAttacker = attacker;
        countMoves = 0;
      }
      countLimit = limit;
      if (mover == attacker) countMoves++;
    } else {
      if (countType != CountType.board) {
        countType = CountType.board;
        countAttacker = null;
        countMoves = 0;
      }
      countLimit = 64;
      if (mover == Side.black) countMoves++; // one full move
    }
  }

  CountingInfo get counting =>
      CountingInfo(countType, countMoves, countLimit, countAttacker);

  // ---------------------------------------------------------------------------
  // Status / helpers
  // ---------------------------------------------------------------------------

  GameStatus get status {
    if (legalMoves().isEmpty) {
      return inCheck ? GameStatus.checkmate : GameStatus.stalemate;
    }
    final cnt = _material();
    int nonKing(int i) => cnt[i].fold<int>(0, (a, c) => a + c) - 1;
    if (nonKing(0) == 0 && nonKing(1) == 0) return GameStatus.drawInsufficient;
    if (countType != CountType.none && countMoves >= countLimit) {
      return GameStatus.drawCounting;
    }
    final k = _keys.isEmpty ? _key() : _keys.last;
    if (_keys.where((e) => e == k).length >= 3) return GameStatus.drawRepetition;
    return GameStatus.ongoing;
  }

  bool get isGameOver => status != GameStatus.ongoing;

  /// Winner when the game ended by checkmate, else null.
  Side? get winner =>
      status == GameStatus.checkmate ? turn.opp : null;

  static const List<int> _value = [0, 0, 2, 3, 3, 5, 1];

  /// Material (white - black) using Touk 5, Kol/Ses 3, Neang 2, Trey 1.
  int get materialBalance {
    int s = 0;
    for (final p in b) {
      if (p == 0) continue;
      s += p.sign * _value[p.abs()];
    }
    return s;
  }

  /// True when pawns are gone or little material is left (used by bot draw AI).
  bool get isEndgame {
    final cnt = _material();
    int total = 0;
    for (final side in cnt) {
      total += side[kNeang] + side[kKol] + side[kSes] + side[kTouk];
    }
    return cnt[0][kTrey] + cnt[1][kTrey] == 0 || total <= 6;
  }

  int pieceAt(int sq) => b[sq];

  /// Node counter for testing the move generator.
  int perft(int depth) {
    if (depth == 0) return 1;
    int n = 0;
    for (final m in legalMoves()) {
      n += makeMove(m).perft(depth - 1);
    }
    return n;
  }
}
