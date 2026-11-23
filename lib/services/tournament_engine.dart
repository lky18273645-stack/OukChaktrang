// lib/services/tournament_engine.dart
//
// Offline tournament engine (pure Dart, deterministic and unit-testable).
//
//  * Arena : continuous auto-pairing for a fixed duration.
//            Win 2 / Draw 1 / Loss 0. After 2 straight wins ("on fire") wins are
//            worth 4 and draws 2 until the streak breaks. Berserk (half clock)
//            gives +1 point when you win. Draws shorter than 10 moves score 0.
//  * Swiss : fixed number of rounds; everyone waits for the round to finish,
//            then players with similar scores are paired (no rematches, one bye
//            for an odd field).
//  * Rewards: top 3 get a trophy; 1st place earns a title badge.
//
// Bots are simulated in "ticks" from the tournament's own seed, so the same
// tournament always plays out the same way no matter when the app is opened.

import 'dart:math';

enum TnFormat { arena, swiss }

enum TnStatus { upcoming, inProgress, completed }

const int kTickMs = 15000;

// -----------------------------------------------------------------------------
// Rules
// -----------------------------------------------------------------------------

class TnRules {
  /// Arena points for ONE game, from one player's point of view.
  /// [onFire] = the player already had a 2+ win streak before this game.
  static int arenaPoints({
    required double score,
    required bool onFire,
    required bool berserk,
    required int plies,
  }) {
    int base;
    if (score == 1.0) {
      base = 2;
    } else if (score == 0.5) {
      base = plies >= 20 ? 1 : 0; // draws under 10 moves are worth nothing
    } else {
      base = 0;
    }
    var pts = onFire ? base * 2 : base;
    if (berserk && score == 1.0 && plies >= 14) pts += 1; // berserk bonus
    return pts;
  }

  static void applyArena(TnPlayer p, double score, bool berserk, int plies) {
    final shortDraw = score == 0.5 && plies < 20;
    p.score += arenaPoints(
        score: score, onFire: p.onFire, berserk: berserk, plies: plies);
    p.games++;
    if (berserk) p.berserks++;
    if (score == 1.0) {
      p.wins++;
      p.streak++;
    } else if (score == 0.5) {
      p.draws++;
      p.streak = 0;
    } else {
      p.losses++;
      p.streak = 0;
    }
    if (shortDraw) p.streak = 0;
  }

  static void applySwiss(TnPlayer p, double score) {
    p.score += score;
    p.games++;
    if (score == 1.0) {
      p.wins++;
    } else if (score == 0.5) {
      p.draws++;
    } else {
      p.losses++;
    }
  }

  /// Result of a simulated bot game (score for the first player + length in plies).
  static ({double score, int plies}) simulate(int rA, int rB, Random rng) {
    final e = 1 / (1 + pow(10, (rB - rA) / 400.0));
    final gap = (rA - rB).abs();
    var drawP = 0.10 +
        0.20 * (1 - (gap / 700).clamp(0.0, 1.0)) +
        ((rA + rB) / 2 - 1200) / 9000;
    drawP = drawP.clamp(0.04, 0.38).toDouble();
    final u = rng.nextDouble();
    if (u < drawP) {
      final quick = rng.nextDouble() < 0.12;
      return (score: 0.5, plies: quick ? 10 + rng.nextInt(10) : 30 + rng.nextInt(90));
    }
    final winA = ((e - drawP / 2) / (1 - drawP)).clamp(0.02, 0.98);
    return (
      score: rng.nextDouble() < winA ? 1.0 : 0.0,
      plies: 24 + rng.nextInt(100),
    );
  }
}

// -----------------------------------------------------------------------------
// Data
// -----------------------------------------------------------------------------

/// Someone who can enter a tournament (bot or the user).
class TnEntrant {
  final String id;
  final String name;
  final String flag;
  final String? title;
  final int rating;
  const TnEntrant(this.id, this.name, this.flag, this.title, this.rating);
}

/// Old saves used a seed label; the app now shows the red GM badge instead.
String? _fixTitle(String? t) =>
    (t != null && t.startsWith('ស៊ីដេត')) ? 'GM' : t;

class TnPlayer {
  final String id; // bot id or 'user'
  final String name;
  final String flag;
  final String? title;
  final int rating;
  final bool isUser;
  final int joinMs;

  double score = 0;
  int streak = 0; // consecutive wins
  int games = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int berserks = 0;
  int busyUntilMs = 0;
  String? lastOpp;
  bool withdrawn = false;
  bool hadBye = false;
  final List<String> opps = [];

  TnPlayer({
    required this.id,
    required this.name,
    required this.flag,
    required this.title,
    required this.rating,
    required this.isUser,
    required this.joinMs,
  });

  bool get onFire => streak >= 2;

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'f': flag,
        't': title,
        'r': rating,
        'u': isUser,
        'j': joinMs,
        's': score,
        'k': streak,
        'g': games,
        'w': wins,
        'd': draws,
        'l': losses,
        'b': berserks,
        'bu': busyUntilMs,
        'lo': lastOpp,
        'wd': withdrawn,
        'by': hadBye,
        'o': opps,
      };

  factory TnPlayer.fromJson(Map<String, dynamic> j) {
    final p = TnPlayer(
      id: j['id'] as String,
      name: j['n'] as String,
      flag: j['f'] as String,
      title: _fixTitle(j['t'] as String?),
      rating: j['r'] as int,
      isUser: j['u'] as bool,
      joinMs: j['j'] as int,
    );
    p.score = (j['s'] as num).toDouble();
    p.streak = j['k'] as int;
    p.games = j['g'] as int;
    p.wins = j['w'] as int;
    p.draws = j['d'] as int;
    p.losses = j['l'] as int;
    p.berserks = j['b'] as int;
    p.busyUntilMs = j['bu'] as int;
    p.lastOpp = j['lo'] as String?;
    p.withdrawn = j['wd'] as bool;
    p.hadBye = j['by'] as bool;
    p.opps.addAll(List<String>.from(j['o'] as List));
    return p;
  }
}

class TnMatch {
  final String id;
  final int round; // 0 in an arena
  final String whiteId;
  final String blackId; // '' for a bye
  final int startMs;
  int endMs;
  double? whiteScore; // null while a user game is being played
  bool berserkW = false;
  bool berserkB = false;
  int plies = 0;
  bool applied = false;
  final bool isUser;

  TnMatch({
    required this.id,
    required this.round,
    required this.whiteId,
    required this.blackId,
    required this.startMs,
    required this.endMs,
    required this.isUser,
  });

  bool get resolved => whiteScore != null;
  bool get isBye => blackId.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'r': round,
        'w': whiteId,
        'b': blackId,
        's': startMs,
        'e': endMs,
        'ws': whiteScore,
        'bw': berserkW,
        'bb': berserkB,
        'p': plies,
        'a': applied,
        'u': isUser,
      };

  factory TnMatch.fromJson(Map<String, dynamic> j) {
    final m = TnMatch(
      id: j['id'] as String,
      round: j['r'] as int,
      whiteId: j['w'] as String,
      blackId: j['b'] as String,
      startMs: j['s'] as int,
      endMs: j['e'] as int,
      isUser: j['u'] as bool,
    );
    m.whiteScore = (j['ws'] as num?)?.toDouble();
    m.berserkW = j['bw'] as bool;
    m.berserkB = j['bb'] as bool;
    m.plies = j['p'] as int;
    m.applied = j['a'] as bool;
    return m;
  }
}

/// Passed to the game screen so it can report the result back.
class TourneyGameInfo {
  final String tournamentId;
  final String matchId;
  final bool userWhite;
  final bool berserk;
  final TnFormat format;
  final int minutes;
  const TourneyGameInfo({
    required this.tournamentId,
    required this.matchId,
    required this.userWhite,
    required this.berserk,
    required this.format,
    required this.minutes,
  });
}

class TnReward {
  final int rank;
  final int? trophyPlace; // 1..3 or null
  final String? title;
  final int? titleExpiresMs; // null = permanent
  const TnReward(this.rank, this.trophyPlace, this.title, this.titleExpiresMs);
}

class Tourney {
  final String id;
  final String name;
  final TnFormat format;
  final int minutes; // base time (no increment)
  final int startMs;
  final int durationMs; // arena
  final int rounds; // swiss
  final int capacity;
  final int createdMs;
  final int seed;

  final List<TnPlayer> players;
  final List<TnMatch> matches;

  int simClockMs;
  int currentRound;
  int roundStartMs;
  bool finished;
  bool rewarded;
  int finishedMs;

  Tourney({
    required this.id,
    required this.name,
    required this.format,
    required this.minutes,
    required this.startMs,
    required this.durationMs,
    required this.rounds,
    required this.capacity,
    required this.createdMs,
    required this.seed,
    List<TnPlayer>? players,
    List<TnMatch>? matches,
    this.simClockMs = 0,
    this.currentRound = 0,
    this.roundStartMs = 0,
    this.finished = false,
    this.rewarded = false,
    this.finishedMs = 0,
  })  : players = players ?? [],
        matches = matches ?? [];

  String get timeControl => '$minutes+0';

  String get categoryLabel => minutes <= 2 ? 'Bullet' : (minutes <= 5 ? 'Blitz' : 'Rapid');

  /// Swiss: time given to one round (both clocks + a break).
  int get windowMs => (minutes * 2 + 2) * 60000;

  int get endMs => format == TnFormat.arena
      ? startMs + durationMs
      : (finished && finishedMs > 0 ? finishedMs : startMs + rounds * (windowMs + 30000));

  TnStatus status(int nowMs) {
    if (finished) return TnStatus.completed;
    if (nowMs < startMs) return TnStatus.upcoming;
    return TnStatus.inProgress;
  }

  TnPlayer? byId(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  TnPlayer? get user => byId('user');

  int registered(int nowMs) => players.where((p) => p.joinMs <= nowMs).length;

  TnMatch? get userOpenMatch {
    for (final m in matches) {
      if (m.isUser && !m.resolved) return m;
    }
    return null;
  }

  bool isLive(TnMatch m, int nowMs) =>
      !m.applied && !m.isBye && m.startMs <= nowMs;

  List<TnMatch> liveMatches(int nowMs) =>
      matches.where((m) => isLive(m, nowMs)).toList();

  /// Score, then (arena) wins / (swiss) Buchholz, then rating.
  List<TnPlayer> standings() {
    final list = [...players];
    double buch(TnPlayer p) =>
        p.opps.fold<double>(0, (a, id) => a + (byId(id)?.score ?? 0));
    list.sort((a, b) {
      var c = b.score.compareTo(a.score);
      if (c != 0) return c;
      c = format == TnFormat.swiss
          ? buch(b).compareTo(buch(a))
          : b.wins.compareTo(a.wins);
      if (c != 0) return c;
      return b.rating.compareTo(a.rating);
    });
    return list;
  }

  int get userRank {
    final s = standings();
    final i = s.indexWhere((p) => p.isUser);
    return i < 0 ? 0 : i + 1;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'f': format.index,
        'm': minutes,
        's': startMs,
        'du': durationMs,
        'ro': rounds,
        'c': capacity,
        'cr': createdMs,
        'sd': seed,
        'sc': simClockMs,
        'cu': currentRound,
        'rs': roundStartMs,
        'fi': finished,
        'rw': rewarded,
        'fm': finishedMs,
        'pl': players.map((p) => p.toJson()).toList(),
        'ma': matches.map((m) => m.toJson()).toList(),
      };

  factory Tourney.fromJson(Map<String, dynamic> j) => Tourney(
        id: j['id'] as String,
        name: j['n'] as String,
        format: TnFormat.values[j['f'] as int],
        minutes: j['m'] as int,
        startMs: j['s'] as int,
        durationMs: j['du'] as int,
        rounds: j['ro'] as int,
        capacity: j['c'] as int,
        createdMs: j['cr'] as int,
        seed: j['sd'] as int,
        simClockMs: j['sc'] as int,
        currentRound: j['cu'] as int,
        roundStartMs: j['rs'] as int,
        finished: j['fi'] as bool,
        rewarded: j['rw'] as bool,
        finishedMs: j['fm'] as int,
        players: (j['pl'] as List)
            .map((e) => TnPlayer.fromJson(e as Map<String, dynamic>))
            .toList(),
        matches: (j['ma'] as List)
            .map((e) => TnMatch.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// -----------------------------------------------------------------------------
// Engine
// -----------------------------------------------------------------------------

class TnEngine {
  static Tourney create({
    required String id,
    required String name,
    required TnFormat format,
    required int minutes,
    required int startMs,
    int durationMs = 0,
    int rounds = 0,
    required int capacity,
    required int createdMs,
    required List<TnEntrant> pool,
  }) {
    final seed = (startMs ~/ 1000) & 0x7fffffff;
    final rng = Random(seed);
    final shuffled = [...pool]..shuffle(rng);
    final n = min(shuffled.length, (capacity * 0.7).round());
    final span = max(1, startMs - createdMs);
    final players = <TnPlayer>[
      for (int i = 0; i < n; i++)
        TnPlayer(
          id: shuffled[i].id,
          name: shuffled[i].name,
          flag: shuffled[i].flag,
          title: shuffled[i].title,
          rating: shuffled[i].rating,
          isUser: false,
          joinMs: createdMs + (rng.nextDouble() * span * 0.95).round(),
        ),
    ];
    return Tourney(
      id: id,
      name: name,
      format: format,
      minutes: minutes,
      startMs: startMs,
      durationMs: durationMs,
      rounds: rounds,
      capacity: capacity,
      createdMs: createdMs,
      seed: seed,
      players: players,
    );
  }

  // ---- user actions ---------------------------------------------------------

  static bool canJoin(Tourney t, int nowMs) {
    if (t.finished || t.user != null) return false;
    if (t.format == TnFormat.swiss) return nowMs < t.startMs; // registration closes
    return nowMs < t.endMs - 60000;
  }

  static TnPlayer? join(Tourney t, TnEntrant me, int nowMs) {
    if (!canJoin(t, nowMs)) return t.user;
    final p = TnPlayer(
      id: 'user',
      name: me.name,
      flag: me.flag,
      title: me.title,
      rating: me.rating,
      isUser: true,
      joinMs: nowMs,
    );
    t.players.add(p);
    return p;
  }

  /// Leave before the start (removed) or during an arena (stop playing).
  static void leave(Tourney t, int nowMs) {
    final me = t.user;
    if (me == null) return;
    if (nowMs < t.startMs) {
      t.players.remove(me);
    } else {
      me.withdrawn = true;
    }
  }

  /// Arena: pairs the user with an available bot straight away.
  static TnMatch? startUserArenaMatch(Tourney t, int nowMs, {bool berserk = false}) {
    if (t.format != TnFormat.arena) return null;
    final me = t.user;
    if (me == null || me.withdrawn) return null;
    if (nowMs < t.startMs || nowMs >= t.endMs) return null;
    final open = t.userOpenMatch;
    if (open != null) return open;
    advance(t, nowMs);
    final rng = Random(t.seed + nowMs ~/ 1000);
    final avail = t.players
        .where((p) =>
            !p.isUser && !p.withdrawn && p.joinMs <= nowMs && p.busyUntilMs <= nowMs)
        .toList();
    if (avail.isEmpty) return null;
    avail.sort((a, b) {
      final c = (a.score - me.score).abs().compareTo((b.score - me.score).abs());
      return c != 0 ? c : (a.rating - me.rating).abs().compareTo((b.rating - me.rating).abs());
    });
    final fresh = avail.where((p) => p.id != me.lastOpp).toList();
    final cands = fresh.isNotEmpty ? fresh : avail;
    final pick = cands[rng.nextInt(min(3, cands.length))];
    final userWhite = rng.nextBool();
    final m = TnMatch(
      id: '${t.id}_m${t.matches.length}',
      round: 0,
      whiteId: userWhite ? 'user' : pick.id,
      blackId: userWhite ? pick.id : 'user',
      startMs: nowMs,
      endMs: nowMs + t.minutes * 2 * 60000 + 60000, // deadline until reported
      isUser: true,
    );
    if (userWhite) {
      m.berserkW = berserk;
    } else {
      m.berserkB = berserk;
    }
    pick.busyUntilMs = nowMs + 24 * 3600 * 1000;
    t.matches.add(m);
    return m;
  }

  /// Result of the user's game. [userScore]: 1 win, 0.5 draw, 0 loss.
  static void reportUserMatch(Tourney t, String matchId, double userScore,
      int plies, bool berserk, int nowMs) {
    final i = t.matches.indexWhere((x) => x.id == matchId);
    if (i < 0) return;
    final m = t.matches[i];
    if (m.applied) return;
    final userIsWhite = m.whiteId == 'user';
    m.whiteScore = userIsWhite ? userScore : 1 - userScore;
    m.plies = plies;
    m.endMs = nowMs;
    if (userIsWhite) {
      m.berserkW = berserk;
    } else {
      m.berserkB = berserk;
    }
    _applyMatch(t, m);
    final opp = t.byId(userIsWhite ? m.blackId : m.whiteId);
    if (opp != null) opp.busyUntilMs = nowMs;
  }

  // ---- time-driven simulation -----------------------------------------------

  static int _sig(Tourney t) =>
      t.matches.length * 100003 +
      t.matches.where((m) => m.applied).length * 7 +
      t.currentRound * 13 +
      (t.finished ? 1 : 0);

  /// Moves the tournament forward to [nowMs]. Returns true when anything changed.
  static bool advance(Tourney t, int nowMs) {
    if (t.finished || nowMs < t.startMs) return false;
    final before = _sig(t);
    if (t.format == TnFormat.arena) {
      _advanceArena(t, nowMs);
    } else {
      _advanceSwiss(t, nowMs);
    }
    return _sig(t) != before;
  }

  static void _advanceArena(Tourney t, int nowMs) {
    final limit = min(nowMs, t.endMs + 30 * 60000);
    var c = max(t.simClockMs, t.startMs);
    while (c <= limit) {
      _applyDue(t, c);
      _forfeitStale(t, c);
      if (c < t.endMs) {
        final tick = (c - t.startMs) ~/ kTickMs;
        _pairBotsArena(t, c, Random(t.seed + tick * 7919));
      }
      c += kTickMs;
    }
    t.simClockMs = c;
    if (nowMs >= t.endMs && t.matches.every((m) => m.applied)) {
      t.finished = true;
      t.finishedMs = t.endMs;
    }
  }

  static void _applyDue(Tourney t, int c) {
    for (final m in t.matches) {
      if (m.applied || m.whiteScore == null || m.endMs > c) continue;
      _applyMatch(t, m);
    }
  }

  static void _forfeitStale(Tourney t, int c) {
    for (final m in t.matches) {
      if (m.isUser && !m.resolved && c > m.endMs) _forfeit(t, m, c);
    }
  }

  static void _forfeit(Tourney t, TnMatch m, int nowMs) {
    m.whiteScore = m.whiteId == 'user' ? 0.0 : 1.0;
    m.plies = 0;
    m.endMs = nowMs;
    _applyMatch(t, m);
    final opp = t.byId(m.whiteId == 'user' ? m.blackId : m.whiteId);
    if (opp != null) opp.busyUntilMs = nowMs;
  }

  static void _applyMatch(Tourney t, TnMatch m) {
    final w = t.byId(m.whiteId);
    final b = t.byId(m.blackId);
    final ws = m.whiteScore ?? 0.0;
    if (w == null || b == null) {
      m.applied = true;
      return;
    }
    if (t.format == TnFormat.arena) {
      TnRules.applyArena(w, ws, m.berserkW, m.plies);
      TnRules.applyArena(b, 1 - ws, m.berserkB, m.plies);
    } else {
      TnRules.applySwiss(w, ws);
      TnRules.applySwiss(b, 1 - ws);
    }
    w.lastOpp = b.id;
    b.lastOpp = w.id;
    m.applied = true;
  }

  static TnMatch _startBotMatch(Tourney t, TnPlayer a, TnPlayer b, int c, Random rng,
      {required int round, int? maxDurMs}) {
    final aWhite = rng.nextBool();
    final white = aWhite ? a : b;
    final black = aWhite ? b : a;
    final res = TnRules.simulate(white.rating, black.rating, rng);
    final arena = t.format == TnFormat.arena;
    var dur = (t.minutes * 2 * 60000 * (0.45 + 0.4 * rng.nextDouble())).round();
    if (maxDurMs != null) dur = min(dur, maxDurMs);
    final m = TnMatch(
      id: '${t.id}_m${t.matches.length}',
      round: round,
      whiteId: white.id,
      blackId: black.id,
      startMs: c,
      endMs: c + dur,
      isUser: false,
    );
    m.whiteScore = res.score;
    m.plies = res.plies;
    m.berserkW = arena && rng.nextDouble() < 0.10;
    m.berserkB = arena && rng.nextDouble() < 0.10;
    t.matches.add(m);
    white.busyUntilMs = c + dur;
    black.busyUntilMs = c + dur;
    return m;
  }

  static void _pairBotsArena(Tourney t, int c, Random rng) {
    final avail = t.players
        .where((p) =>
            !p.isUser && !p.withdrawn && p.joinMs <= c && p.busyUntilMs <= c)
        .toList();
    if (avail.length < 2) return;
    avail.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : b.rating.compareTo(a.rating);
    });
    final used = <String>{};
    for (int i = 0; i < avail.length; i++) {
      final p = avail[i];
      if (used.contains(p.id)) continue;
      if (rng.nextDouble() < 0.3) continue; // hesitates, pairs on a later tick
      TnPlayer? q;
      for (int j = i + 1; j < avail.length; j++) {
        final cand = avail[j];
        if (used.contains(cand.id)) continue;
        if (cand.id == p.lastOpp || p.id == cand.lastOpp) continue;
        q = cand;
        break;
      }
      if (q == null) continue;
      used
        ..add(p.id)
        ..add(q.id);
      _startBotMatch(t, p, q, c, rng, round: 0);
    }
  }

  // ---- swiss ------------------------------------------------------------------

  static void _advanceSwiss(Tourney t, int nowMs) {
    var guard = 0;
    while (!t.finished && guard++ < 64) {
      if (t.currentRound == 0) {
        if (nowMs < t.startMs) return;
        _startSwissRound(t, 1, t.startMs);
      }
      _applyDue(t, nowMs);
      for (final m in t.matches) {
        if (m.round == t.currentRound &&
            m.isUser &&
            !m.resolved &&
            nowMs >= t.roundStartMs + t.windowMs) {
          _forfeit(t, m, nowMs);
        }
      }
      final roundMatches = t.matches.where((m) => m.round == t.currentRound).toList();
      if (roundMatches.any((m) => !m.applied)) return;
      final doneAt = roundMatches.fold<int>(t.roundStartMs, (a, m) => max(a, m.endMs));
      if (t.currentRound >= t.rounds) {
        t.finished = true;
        t.finishedMs = doneAt;
        return;
      }
      final nextStart = doneAt + 30000;
      if (nowMs < nextStart) return;
      _startSwissRound(t, t.currentRound + 1, nextStart);
    }
  }

  /// Pairs [list] (already sorted) so nobody meets an old opponent again.
  /// Backtracking; returns null if that is impossible within a small budget.
  static List<List<TnPlayer>>? _pairNoRematch(List<TnPlayer> list) {
    var budget = 20000;
    final used = List<bool>.filled(list.length, false);
    final out = <List<TnPlayer>>[];
    bool go() {
      if (--budget < 0) return false;
      final i = used.indexOf(false);
      if (i < 0) return true;
      used[i] = true;
      for (int j = i + 1; j < list.length; j++) {
        if (used[j] || list[i].opps.contains(list[j].id)) continue;
        used[j] = true;
        out.add([list[i], list[j]]);
        if (go()) return true;
        out.removeLast();
        used[j] = false;
      }
      used[i] = false;
      return false;
    }

    return go() ? out : null;
  }

  static void _startSwissRound(Tourney t, int round, int startMs) {
    t.currentRound = round;
    t.roundStartMs = startMs;
    final rng = Random(t.seed + round * 104729);
    final active = t.players.where((p) => !p.withdrawn).toList();
    active.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : b.rating.compareTo(a.rating);
    });
    final byeIds = <String>{};

    if (active.length.isOdd) {
      TnPlayer bye = active.last;
      for (final p in active.reversed) {
        if (!p.hadBye) {
          bye = p;
          break;
        }
      }
      bye.hadBye = true;
      byeIds.add(bye.id);
      final m = TnMatch(
        id: '${t.id}_m${t.matches.length}',
        round: round,
        whiteId: bye.id,
        blackId: '',
        startMs: startMs,
        endMs: startMs,
        isUser: false,
      );
      m.whiteScore = 1.0;
      m.applied = true;
      TnRules.applySwiss(bye, 1.0);
      t.matches.add(m);
    }

    final remaining = active.where((p) => !byeIds.contains(p.id)).toList();
    var pairs = _pairNoRematch(remaining);
    if (pairs == null) {
      // Not possible without a rematch: pair greedily and allow one.
      pairs = <List<TnPlayer>>[];
      final taken = <String>{};
      for (int i = 0; i < remaining.length; i++) {
        final p = remaining[i];
        if (taken.contains(p.id)) continue;
        TnPlayer? q;
        for (int j = i + 1; j < remaining.length; j++) {
          if (!taken.contains(remaining[j].id)) {
            q = remaining[j];
            break;
          }
        }
        if (q == null) continue;
        taken
          ..add(p.id)
          ..add(q.id);
        pairs.add([p, q]);
      }
    }

    for (final pr in pairs) {
      final p = pr[0];
      final q = pr[1];
      p.opps.add(q.id);
      q.opps.add(p.id);
      if (p.isUser || q.isUser) {
        final userWhite = rng.nextBool();
        final other = p.isUser ? q : p;
        t.matches.add(TnMatch(
          id: '${t.id}_m${t.matches.length}',
          round: round,
          whiteId: userWhite ? 'user' : other.id,
          blackId: userWhite ? other.id : 'user',
          startMs: startMs,
          endMs: startMs + t.windowMs,
          isUser: true,
        ));
      } else {
        _startBotMatch(t, p, q, startMs, rng,
            round: round, maxDurMs: (t.windowMs * 0.9).round());
      }
    }
  }

  // ---- rewards ---------------------------------------------------------------

  /// What the user earns when the tournament has finished (null = nothing).
  /// [winsBefore]: tournaments the user already won.
  static TnReward? rewardFor(Tourney t, {required int winsBefore, int seasonDays = 30}) {
    final me = t.user;
    if (me == null || !t.finished || me.games == 0) return null;
    final rank = t.userRank;
    final place = (rank >= 1 && rank <= 3) ? rank : null;
    String? title;
    int? expires;
    if (rank == 1 && t.players.length >= 8) {
      if (winsBefore + 1 >= 3) {
        title = 'CM'; // third tournament win
      } else if (t.format == TnFormat.swiss) {
        title = 'CHAMP';
      } else {
        title = 'ARENA KING';
        expires = t.finishedMs + seasonDays * 86400000;
      }
    }
    return TnReward(rank, place, title, expires);
  }
}

// -----------------------------------------------------------------------------
// Schedule
// -----------------------------------------------------------------------------

class TnTemplate {
  final String name;
  final TnFormat format;
  final int minutes;
  final int durationMin;
  final int rounds;
  final int capacity;
  const TnTemplate(this.name, this.format, this.minutes, this.durationMin,
      this.rounds, this.capacity);
}

const List<TnTemplate> kTemplates = [
  TnTemplate('Blitz Arena', TnFormat.arena, 3, 30, 0, 64),
  TnTemplate('Bullet Arena', TnFormat.arena, 1, 20, 0, 64),
  TnTemplate('Blitz Swiss', TnFormat.swiss, 3, 0, 5, 32),
  TnTemplate('Rapid Arena', TnFormat.arena, 10, 60, 0, 48),
  TnTemplate('Blitz Swiss 5+0', TnFormat.swiss, 5, 0, 4, 32),
];

class TnScheduler {
  static Tourney _make(TnTemplate tpl, int startMs, int createdMs, List<TnEntrant> pool) {
    return TnEngine.create(
      id: 'tn_$startMs',
      name: tpl.name,
      format: tpl.format,
      minutes: tpl.minutes,
      startMs: startMs,
      durationMs: tpl.durationMin * 60000,
      rounds: tpl.rounds,
      capacity: tpl.capacity,
      createdMs: createdMs,
      pool: pool,
    );
  }

  /// Keeps at least [minUpcoming] future tournaments. Returns how many were added.
  static int ensure(List<Tourney> list, int nowMs, List<TnEntrant> pool,
      {int minUpcoming = 4}) {
    var added = 0;
    var upcoming = list.where((t) => t.startMs > nowMs).length;
    var lastStart = list.isEmpty ? nowMs : list.map((t) => t.startMs).reduce(max);
    while (upcoming < minUpcoming) {
      final raw = upcoming == 0 && lastStart <= nowMs
          ? nowMs + 3 * 60000
          : max(lastStart, nowMs) + 12 * 60000;
      final start = (raw ~/ 60000) * 60000;
      final tpl = kTemplates[(start ~/ (12 * 60000)) % kTemplates.length];
      list.add(_make(tpl, start, nowMs, pool));
      lastStart = start;
      upcoming++;
      added++;
    }
    return added;
  }

  /// First launch: a couple of finished tournaments so "Completed" is not empty.
  static void seedHistory(List<Tourney> list, int nowMs, List<TnEntrant> pool) {
    final specs = [
      (kTemplates[0], nowMs - 3 * 3600000),
      (kTemplates[2], nowMs - 90 * 60000),
    ];
    for (final s in specs) {
      final start = (s.$2 ~/ 60000) * 60000;
      final t = _make(s.$1, start, start - 30 * 60000, pool);
      TnEngine.advance(t, nowMs);
      t.rewarded = true;
      list.add(t);
    }
  }

  /// Keeps every active tournament and the newest [keepCompleted] finished ones.
  static void prune(List<Tourney> list, {int keepCompleted = 8}) {
    final done = list.where((t) => t.finished).toList()
      ..sort((a, b) => b.startMs.compareTo(a.startMs));
    for (int i = keepCompleted; i < done.length; i++) {
      list.remove(done[i]);
    }
  }
}
