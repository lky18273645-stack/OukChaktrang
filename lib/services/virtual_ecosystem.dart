// lib/services/virtual_ecosystem.dart
//
// Offline virtual player ecosystem for OukChaktrang.com:
//  - 60+ persistent bots (Elo 400..3000+) with Khmer / international names
//  - background bot-vs-bot simulation -> dynamic leaderboard
//  - human-like thinking delays
//  - BotGameBrain: resign (-700cp x3), draw offers (+-30cp x6 in endgames),
//    draw-offer responses
//  - Elo + game summary, clubs, achievements
//  - 8 / 16 player Swiss and Arena tournaments (simulated offline)

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glicko.dart';
import 'profile_models.dart';
import 'tournament_engine.dart';

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

String flagEmoji(String code) => String.fromCharCodes(
    code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));

double expectedScore(int a, int b) =>
    1.0 / (1.0 + pow(10, (b - a) / 400.0));

const Set<String> _womenNames = {
  'Sreypich', 'Sophea', 'Sreyneang', 'Bopha', 'Thida', 'Kunthea', 'Channary',
  'ស្រីនាង', 'Hana', 'Aisha', 'Elena', 'Chloe', 'Dewi', 'Anya',
};

/// Title for a simulated bot from its rating. Under 2000 there is no title.
/// Open: GM 2500+, IM 2400+, FM 2300+, CM 2200+, NM 2000-2199 (some).
/// Women: WGM 2300+, WIM 2200+, WFM 2100+, WCM 2000+.
String titleForBot(String name, int elo) {
  final base = name.split('_').first;
  if (_womenNames.contains(base)) {
    if (elo >= 2500) return 'GM'; // women can earn the open GM title too
    if (elo >= 2300) return 'WGM';
    if (elo >= 2200) return 'WIM';
    if (elo >= 2100) return 'WFM';
    if (elo >= 2000) return 'WCM';
    return '';
  }
  if (elo >= 2500) return 'GM';
  if (elo >= 2400) return 'IM';
  if (elo >= 2300) return 'FM';
  if (elo >= 2200) return 'CM';
  if (elo >= 2000 && name.codeUnits.fold<int>(0, (a, c) => a + c).isEven) {
    return 'NM';
  }
  return '';
}

String formatDelta(int d) => d >= 0 ? '+$d' : '$d';

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum BotStyle { aggressive, solid, tricky, endgame }

class BotPlayer {
  final String id;
  String name;
  final String countryCode;
  final int avatar;
  final BotStyle style;
  final int clubId;
  int elo;
  int wins;
  int losses;
  int draws;
  String? title; // FIDE-style title; null = not assigned yet, '' = none
  final int seed; // 0 = none, 1..3 = Cambodian champion seed

  BotPlayer({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.avatar,
    required this.style,
    required this.clubId,
    required this.elo,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.title,
    this.seed = 0,
  });

  String get flag => flagEmoji(countryCode);
  int get games => wins + losses + draws;

  /// Named master bots: fixed rating, never touched by the background simulation.
  bool get isGm => id.startsWith('gm_');

  /// Cambodian champion bots (fixed rating, seeded 1..3).
  bool get isChampion => id.startsWith('kh_');

  /// Fixed-rating named bots: never touched by the background simulation.
  bool get isFixed => isGm || isChampion;

  /// Title to display (GM, IM, FM, CM, NM, WGM, WIM, WFM, WCM) or null.
  String? get shownTitle => (title == null || title!.isEmpty) ? null : title;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cc': countryCode,
        'av': avatar,
        'st': style.index,
        'club': clubId,
        'elo': elo,
        'w': wins,
        'l': losses,
        'd': draws,
        't': title,
        'sd': seed,
      };

  factory BotPlayer.fromJson(Map<String, dynamic> j) => BotPlayer(
        id: j['id'] as String,
        name: j['name'] as String,
        countryCode: j['cc'] as String,
        avatar: j['av'] as int,
        style: BotStyle.values[j['st'] as int],
        clubId: j['club'] as int,
        elo: j['elo'] as int,
        wins: j['w'] as int,
        losses: j['l'] as int,
        draws: j['d'] as int,
        title: j['t'] as String?,
        seed: (j['sd'] as int?) ?? 0,
      );
}

/// Master-level bots named after famous players. Ratings are approximate bot
/// strength labels (mostly peak classical ratings, from memory) - edit freely.
/// These are simulated bots, not affiliated with the real players.
class _Gm {
  final String id;
  final String name;
  final String cc;
  final int elo;
  final BotStyle style; // arbitrary personality label
  const _Gm(this.id, this.name, this.cc, this.elo, this.style);
}

const List<_Gm> _gmRoster = [
  _Gm('gm_magnus', 'Magnus Carlsen', 'NO', 2882, BotStyle.endgame),
  _Gm('gm_hikaru', 'Hikaru Nakamura', 'US', 2820, BotStyle.tricky),
  _Gm('gm_kasparov', 'Garry Kasparov', 'RU', 2851, BotStyle.aggressive),
  _Gm('gm_caruana', 'Fabiano Caruana', 'US', 2844, BotStyle.solid),
  _Gm('gm_aronian', 'Levon Aronian', 'US', 2830, BotStyle.tricky),
  _Gm('gm_so', 'Wesley So', 'US', 2822, BotStyle.solid),
  _Gm('gm_anand', 'Viswanathan Anand', 'IN', 2817, BotStyle.tricky),
  _Gm('gm_ding', 'Ding Liren', 'CN', 2816, BotStyle.solid),
  _Gm('gm_firouzja', 'Alireza Firouzja', 'FR', 2804, BotStyle.aggressive),
  _Gm('gm_arjun', 'Arjun Erigaisi', 'IN', 2801, BotStyle.aggressive),
  _Gm('gm_giri', 'Anish Giri', 'NL', 2798, BotStyle.solid),
  _Gm('gm_gukesh', 'Gukesh D', 'IN', 2794, BotStyle.solid),
  _Gm('gm_nepo', 'Ian Nepomniachtchi', 'RU', 2792, BotStyle.aggressive),
  _Gm('gm_fischer', 'Bobby Fischer', 'US', 2785, BotStyle.aggressive),
  _Gm('gm_keymer', 'Vincent Keymer', 'DE', 2776, BotStyle.solid),
  _Gm('gm_abdusattorov', 'Nodirbek Abdusattorov', 'UZ', 2766, BotStyle.tricky),
  _Gm('gm_sindarov', 'Javokhir Sindarov', 'UZ', 2760, BotStyle.solid),
  _Gm('gm_praggnanandhaa', 'R Praggnanandhaa', 'IN', 2758, BotStyle.tricky),
  _Gm('gm_polgar', 'Judit Polgar', 'HU', 2735, BotStyle.aggressive),
  _Gm('gm_hou', 'Hou Yifan', 'CN', 2686, BotStyle.solid),
];

/// Strong Cambodian players as simulated seeded bots. The ratings below are
/// PLACEHOLDERS (I do not know their real ratings) - edit them freely.
class _Champ {
  final String id;
  final String name;
  final int seed;
  final int elo;
  final BotStyle style;
  const _Champ(this.id, this.name, this.seed, this.elo, this.style);
}

const List<_Champ> _khRoster = [
  _Champ('kh_sok_limheng', 'សុខលីមហេង', 1, 2450, BotStyle.solid),
  _Champ('kh_chhay_vireak', 'ឆយវីរ៉ា', 2, 2400, BotStyle.aggressive),
  _Champ('kh_chiv_bora', 'ឈាវបូរ៉ា', 3, 2350, BotStyle.tricky),
];

/// Shown once after a tournament that earned a trophy / title.
class RewardNotice {
  final String tournamentName;
  final TnReward reward;
  const RewardNotice(this.tournamentName, this.reward);
}

class Club {
  final int id;
  final String nameKm;
  final String nameEn;
  int points;
  Club(this.id, this.nameKm, this.nameEn, [this.points = 0]);

  Map<String, dynamic> toJson() => {'id': id, 'p': points};
}

const List<List<String>> _clubDefs = [
  ['ភ្នំពេញ', 'Phnom Penh Chess Club'],
  ['សៀមរាប', 'Siem Reap Chess Club'],
  ['បាត់ដំបង', 'Battambang Chess Club'],
  ['កំពត', 'Kampot Chess Club'],
  ['កំពង់ចាម', 'Kampong Cham Chess Club'],
  ['ព្រះសីហនុ', 'Sihanoukville Chess Club'],
];

class AchievementDef {
  final String id;
  final String titleKm;
  final String titleEn;
  final String descEn;
  const AchievementDef(this.id, this.titleKm, this.titleEn, this.descEn);
}

const List<AchievementDef> achievementDefs = [
  AchievementDef('first_win', 'ជ័យជម្នះដំបូង', 'First Win', 'Win your first game.'),
  AchievementDef('first_checkmate', 'ម៉ាតដំបូង', 'First Checkmate', 'Win by checkmate.'),
  AchievementDef('streak_10', 'ឈ្នះ ១០ ជាប់គ្នា', '10-Game Win Streak', 'Win 10 games in a row.'),
  AchievementDef('counting_master', 'ម្ចាស់គេចរាប់', 'Counting Escape Master', 'Draw by the counting rule 3 times.'),
  AchievementDef('giant_killer', 'អ្នកផ្តួលយក្ស', 'Giant Killer', 'Beat a bot rated 200+ above you.'),
  AchievementDef('bot_resign', 'គេចុះចាញ់', 'Forced Resignation', 'Make a bot resign.'),
  AchievementDef('veteran_50', 'អ្នកចាស់ការ', 'Veteran', 'Play 50 games.'),
  AchievementDef('club_member', 'សមាជិកក្លឹប', 'Club Member', 'Join a regional club.'),
  AchievementDef('tournament_champion', 'ជើងឯកព្រឹត្តិការណ៍', 'Tournament Champion', 'Win a tournament.'),
  AchievementDef('draw_diplomat', 'អ្នកការទូត', 'Draw Diplomat', 'Agree a draw with a bot.'),
];

class UserProfile {
  String name;
  String countryCode;
  int elo;
  int wins;
  int losses;
  int draws;
  int streak;
  int bestStreak;
  int countingEscapes;
  int clubId; // -1 = none
  int trophies;
  double rd; // Glicko rating deviation
  int lastPlayed; // millisecondsSinceEpoch of the last rated game (0 = never)
  bool onboarded; // chose a starting level
  Set<String> achievements;

  // ---- profile (Chess.com style)
  Map<String, CatStats> cats; // bullet / blitz / rapid / daily
  String? activeTitle; // chosen title badge (must be an earned one)
  List<TitleAward> awards;
  List<Trophy> trophyCase;
  List<MatchRecord> history;
  String bio;
  int joinedMs;
  int avatarSeed;
  String flair;
  int friends;
  int tournamentWins;

  UserProfile({
    this.name = 'Player',
    this.countryCode = 'KH',
    this.elo = 800,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.countingEscapes = 0,
    this.clubId = -1,
    this.trophies = 0,
    this.rd = kInitialRd,
    this.lastPlayed = 0,
    this.onboarded = false,
    Set<String>? achievements,
    Map<String, CatStats>? cats,
    this.activeTitle,
    List<TitleAward>? awards,
    List<Trophy>? trophyCase,
    List<MatchRecord>? history,
    this.bio = '',
    this.joinedMs = 0,
    this.avatarSeed = 7,
    this.flair = '♟',
    this.friends = 0,
    this.tournamentWins = 0,
  })  : achievements = achievements ?? <String>{},
        cats = cats ?? <String, CatStats>{},
        awards = awards ?? <TitleAward>[],
        trophyCase = trophyCase ?? <Trophy>[],
        history = history ?? <MatchRecord>[];

  /// Rating record of one time-control category (created on demand).
  CatStats cat(TimeCategory c) =>
      cats.putIfAbsent(c.key, () => CatStats(rating: elo.toDouble(), rd: rd));

  /// Creates missing categories (saves from before profiles existed).
  void ensureCats() {
    for (final c in TimeCategory.values) {
      if (!cats.containsKey(c.key)) {
        final rapid = c == TimeCategory.rapid;
        cats[c.key] = CatStats(
          rating: elo.toDouble(),
          rd: rd,
          wins: rapid ? wins : 0,
          draws: rapid ? draws : 0,
          losses: rapid ? losses : 0,
        );
      }
    }
    if (joinedMs == 0) joinedMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Headline rating (used for bot locks, ranking, random match) = the best
  /// rating among categories you have played, else your Rapid rating.
  void syncHeadline() {
    CatStats? best;
    for (final c in cats.values) {
      if (c.games > 0 && (best == null || c.rating > best.rating)) best = c;
    }
    best ??= cats[TimeCategory.rapid.key];
    if (best != null) {
      elo = best.rating.round();
      rd = best.rd;
    }
  }

  /// Earned titles that are still valid (seasonal ones expire).
  Set<String> earnedTitles(int nowMs) =>
      awards.where((a) => a.activeAt(nowMs)).map((a) => a.title).toSet();

  /// The badge shown next to the name everywhere (lobby, profile, board, ranking).
  String? titleAt(int nowMs) {
    final active = earnedTitles(nowMs);
    final chosen = activeTitle;
    if (chosen != null && chosen.isEmpty) return null; // user chose to hide titles
    if (chosen != null && active.contains(chosen)) return chosen;
    for (final t in kTitlePriority) {
      if (active.contains(t)) return t;
    }
    return null;
  }

  String? get title => titleAt(DateTime.now().millisecondsSinceEpoch);

  int get games => wins + losses + draws;

  Map<String, dynamic> toJson() => {
        'name': name,
        'cc': countryCode,
        'elo': elo,
        'w': wins,
        'l': losses,
        'd': draws,
        'streak': streak,
        'best': bestStreak,
        'ce': countingEscapes,
        'club': clubId,
        'tr': trophies,
        'rd': rd,
        'lp': lastPlayed,
        'ob': onboarded,
        'ach': achievements.toList(),
        'cats': cats.map((k, v) => MapEntry(k, v.toJson())),
        'at': activeTitle,
        'aw': awards.map((e) => e.toJson()).toList(),
        'tcase': trophyCase.map((e) => e.toJson()).toList(),
        'hist': history.map((e) => e.toJson()).toList(),
        'bio': bio,
        'jm': joinedMs,
        'av': avatarSeed,
        'fl': flair,
        'fr': friends,
        'tw': tournamentWins,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String,
        countryCode: j['cc'] as String,
        elo: j['elo'] as int,
        wins: j['w'] as int,
        losses: j['l'] as int,
        draws: j['d'] as int,
        streak: j['streak'] as int,
        bestStreak: j['best'] as int,
        countingEscapes: j['ce'] as int,
        clubId: j['club'] as int,
        trophies: j['tr'] as int,
        rd: (j['rd'] as num?)?.toDouble() ?? 100, // saves from before Glicko
        lastPlayed: (j['lp'] as int?) ?? 0,
        onboarded: (j['ob'] as bool?) ?? true,
        achievements: Set<String>.from(j['ach'] as List),
        cats: (j['cats'] as Map?)?.map((k, v) => MapEntry(
            k as String, CatStats.fromJson(Map<String, dynamic>.from(v as Map)))),
        activeTitle: j['at'] as String?,
        awards: (j['aw'] as List?)
            ?.map((e) => TitleAward.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        trophyCase: (j['tcase'] as List?)
            ?.map((e) => Trophy.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        history: (j['hist'] as List?)
            ?.map((e) => MatchRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        bio: (j['bio'] as String?) ?? '',
        joinedMs: (j['jm'] as int?) ?? 0,
        avatarSeed: (j['av'] as int?) ?? 7,
        flair: (j['fl'] as String?) ?? '♟',
        friends: (j['fr'] as int?) ?? 0,
        tournamentWins: (j['tw'] as int?) ?? 0,
      );
}

class LeaderboardEntry {
  final String id;
  final String name;
  final String flag;
  final int elo;
  final int clubId;
  final int games;
  final bool isUser;
  final String? title;
  int rank = 0;
  int trend = 0; // + moved up, - moved down since the last simulation
  LeaderboardEntry(this.id, this.name, this.flag, this.elo, this.clubId,
      this.games, this.isUser, {this.title});
}

class GameSummary {
  final double score; // 1 win, 0.5 draw, 0 loss (user's view)
  final String reason;
  final BotPlayer opponent;
  final int eloBefore;
  final int eloAfter;
  final int delta;
  final double accuracy;
  final List<AchievementDef> newAchievements;

  GameSummary(this.score, this.reason, this.opponent, this.eloBefore,
      this.eloAfter, this.delta, this.accuracy, this.newAchievements);

  bool get isWin => score == 1.0;
  bool get isDraw => score == 0.5;

  /// "1450 (+9)" style label, new rating first.
  String get eloLabel => '$eloAfter (${formatDelta(delta)})';
}

// -----------------------------------------------------------------------------
// Bot behaviour inside one game
// -----------------------------------------------------------------------------

enum BotAction { none, resign, offerDraw }

class BotDecision {
  final BotAction action;
  final String? chat;
  const BotDecision(this.action, [this.chat]);
}

class BotGameBrain {
  final int elo;
  final BotStyle style;
  final Random _rng;

  int _hopeless = 0; // consecutive bot turns with eval <= -700
  int _equalEndgame = 0; // consecutive bot turns with |eval| <= 30 in an endgame
  int _drawCooldown = 0;

  BotGameBrain({required this.elo, this.style = BotStyle.solid, Random? rng})
      : _rng = rng ?? Random();

  static const int resignThreshold = -700;
  static const int drawBand = 30;
  static const int resignMoves = 3;
  static const int drawMoves = 6;

  /// Call after every bot move with the engine score from the BOT's view (cp).
  BotDecision afterBotMove({required int evalCp, required bool isEndgame}) {
    if (_drawCooldown > 0) _drawCooldown--;

    // Resignation: only bots above 1000 Elo.
    if (evalCp <= resignThreshold) {
      _hopeless++;
    } else {
      _hopeless = 0;
    }
    if (elo > 1000 && _hopeless >= resignMoves) {
      return const BotDecision(BotAction.resign, 'លេងល្អណាស់ ខ្ញុំសុំចុះចាញ់!');
    }

    // Draw offer in a balanced endgame.
    if (isEndgame && evalCp.abs() <= drawBand) {
      _equalEndgame++;
    } else {
      _equalEndgame = 0;
    }
    if (_equalEndgame >= drawMoves && _drawCooldown == 0) {
      _equalEndgame = 0;
      _drawCooldown = 12;
      return const BotDecision(BotAction.offerDraw, 'ស្មើគ្នាទេ? 🤝');
    }
    return const BotDecision(BotAction.none);
  }

  /// Decide on a draw offer from the player. [evalCp] is from the BOT's view.
  /// Returns the chat line and whether it accepts.
  ({bool accept, String chat}) respondToDraw({
    required int evalCp,
    required bool isEndgame,
    required int fullMove,
    bool countingActive = false,
  }) {
    double p = 0.5 - evalCp / 400.0; // worse for the bot -> more willing
    if (isEndgame && evalCp.abs() <= drawBand) p += 0.25;
    if (countingActive && evalCp <= 50) p += 0.15;
    if (fullMove < 15) p -= 0.35; // too early to draw
    if (elo < 1000) p += (_rng.nextDouble() - 0.5) * 0.3; // weaker bots erratic
    if (style == BotStyle.aggressive) p -= 0.1;
    p = p.clamp(0.02, 0.95).toDouble();
    final ok = _rng.nextDouble() < p;
    return (
      accept: ok,
      chat: ok ? 'យល់ព្រម! ស្មើគ្នា 🤝' : 'សុំលេងបន្តសិន 😄',
    );
  }
}

/// Human-like thinking time. Fast intuitive moves (1-2 s), long pauses (4-12 s)
/// in complex positions.
Duration thinkingDelay({
  required int legalMoveCount,
  required int evalSwingCp, // |eval change| vs previous move, in cp
  required int elo,
  bool isOpening = false,
  int clockMsLeft = 600000,
  Random? rng,
}) {
  final r = rng ?? Random();
  if (legalMoveCount <= 2) {
    return Duration(milliseconds: 500 + r.nextInt(700));
  }
  double c = (legalMoveCount / 40.0).clamp(0.0, 1.0).toDouble() * 0.4 +
      (evalSwingCp / 300.0).clamp(0.0, 1.0).toDouble() * 0.4 +
      (isOpening ? 0.0 : 0.2);
  if (isOpening) c *= 0.4;
  final deep = r.nextDouble() < c;
  int ms;
  if (deep) {
    final eloBoost = ((elo - 400) / 2600.0).clamp(0.0, 1.0).toDouble(); // 0..1
    ms = 4000 + r.nextInt(5000) + (eloBoost * 3000).round(); // 4..12 s
  } else {
    ms = 1000 + r.nextInt(1000); // 1..2 s
  }
  if (clockMsLeft < 20000) ms = min(ms, 1500);
  return Duration(milliseconds: ms.clamp(500, 12000).toInt());
}

// -----------------------------------------------------------------------------
// Tournaments
// -----------------------------------------------------------------------------

enum TournamentFormat { swiss, arena }

class TPlayer {
  final String id; // bot id or 'user'
  final String name;
  final int elo;
  final String flag;
  final bool isUser;
  double score = 0;
  int streak = 0; // consecutive wins (arena doubling)
  final List<String> opponents = [];
  TPlayer(this.id, this.name, this.elo, this.flag, this.isUser);

  Map<String, dynamic> toJson() => {
        'id': id, 'n': name, 'e': elo, 'f': flag, 'u': isUser,
        's': score, 'k': streak, 'o': opponents,
      };

  factory TPlayer.fromJson(Map<String, dynamic> j) {
    final p = TPlayer(j['id'] as String, j['n'] as String, j['e'] as int,
        j['f'] as String, j['u'] as bool);
    p.score = (j['s'] as num).toDouble();
    p.streak = j['k'] as int;
    p.opponents.addAll(List<String>.from(j['o'] as List));
    return p;
  }
}

class Pairing {
  final String whiteId;
  final String blackId;
  double? whiteScore; // 1 / 0.5 / 0 once played
  Pairing(this.whiteId, this.blackId, [this.whiteScore]);

  Map<String, dynamic> toJson() => {'w': whiteId, 'b': blackId, 's': whiteScore};
  factory Pairing.fromJson(Map<String, dynamic> j) => Pairing(
      j['w'] as String, j['b'] as String, (j['s'] as num?)?.toDouble());
}

class Tournament {
  final String id;
  final String name;
  final TournamentFormat format;
  final int size; // 8 or 16
  final int totalRounds;
  final List<TPlayer> players;
  final List<List<Pairing>> rounds = [];
  int currentRound = -1;
  bool finished = false;
  int userRank = 0;
  int bonusElo = 0;
  String? trophy; // gold / silver / bronze

  Tournament(this.id, this.name, this.format, this.size, this.totalRounds,
      this.players);

  TPlayer player(String id) => players.firstWhere((p) => p.id == id);

  /// Standings: score, then sum of opponents' Elo, then own Elo.
  List<TPlayer> get standings {
    double tb(TPlayer p) =>
        p.opponents.fold<double>(0, (a, id) => a + player(id).elo);
    final list = List<TPlayer>.from(players);
    list.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      final t = tb(b).compareTo(tb(a));
      if (t != 0) return t;
      return b.elo.compareTo(a.elo);
    });
    return list;
  }

  /// The user's pairing in the current round (null when finished).
  Pairing? get userPairing {
    if (finished || currentRound < 0) return null;
    for (final p in rounds[currentRound]) {
      if (p.whiteId == 'user' || p.blackId == 'user') return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'fmt': format.index, 'size': size,
        'tr': totalRounds,
        'players': players.map((e) => e.toJson()).toList(),
        'rounds': rounds.map((r) => r.map((p) => p.toJson()).toList()).toList(),
        'cur': currentRound, 'fin': finished, 'ur': userRank,
        'bonus': bonusElo, 'trophy': trophy,
      };

  factory Tournament.fromJson(Map<String, dynamic> j) {
    final t = Tournament(
      j['id'] as String,
      j['name'] as String,
      TournamentFormat.values[j['fmt'] as int],
      j['size'] as int,
      j['tr'] as int,
      (j['players'] as List)
          .map((e) => TPlayer.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    for (final r in j['rounds'] as List) {
      t.rounds.add((r as List)
          .map((e) => Pairing.fromJson(e as Map<String, dynamic>))
          .toList());
    }
    t.currentRound = j['cur'] as int;
    t.finished = j['fin'] as bool;
    t.userRank = j['ur'] as int;
    t.bonusElo = j['bonus'] as int;
    t.trophy = j['trophy'] as String?;
    return t;
  }
}

// -----------------------------------------------------------------------------
// The ecosystem service
// -----------------------------------------------------------------------------

class VirtualEcosystem extends ChangeNotifier {
  static const String _prefsKey = 'ouk_ecosystem_v1';

  final Random _rng = Random();
  final List<BotPlayer> bots;
  final List<Club> clubs;
  UserProfile user;
  Tournament? activeTournament;
  final List<Tourney> tournaments = [];
  RewardNotice? pendingReward; // shown once by the tournament screens
  DateTime lastSim;
  Map<String, int> _prevRank = {};

  VirtualEcosystem._(
      this.bots, this.clubs, this.user, this.activeTournament, this.lastSim);

  // ---- creation / persistence ----------------------------------------------

  static const List<String> _khmerNames = [
    'Sokha', 'Dara', 'Vannak', 'Sreypich', 'Chantha', 'Rithy', 'Sophea',
    'Bunthoeun', 'Kosal', 'Piseth', 'Veasna', 'Rotha', 'Sreyneang', 'Makara',
    'Visal', 'Samnang', 'Chenda', 'Bopha', 'Sovann', 'Rathana', 'Vibol',
    'Thida', 'Pheakdey', 'Narith', 'Kunthea', 'Monirom', 'Sambath',
    'Channary', 'Vichea', 'Sopheak', 'Ratanak', 'Seyha',
    'សុខា', 'ដារា', 'វិសាល', 'ស្រីនាង', 'មករា', 'ចន្ថា',
  ];

  static const List<List<String>> _intl = [
    ['Alex', 'US'], ['Yuki', 'JP'], ['Wei', 'CN'], ['Minh', 'VN'],
    ['Somchai', 'TH'], ['Arjun', 'IN'], ['Lukas', 'DE'], ['Pierre', 'FR'],
    ['Ivan', 'RU'], ['Carlos', 'BR'], ['Hana', 'KR'], ['Aisha', 'MY'],
    ['Sven', 'SE'], ['Marco', 'IT'], ['Elena', 'ES'], ['Kofi', 'GH'],
    ['Liam', 'GB'], ['Noah', 'CA'], ['Chloe', 'AU'], ['Omar', 'EG'],
    ['Dewi', 'ID'], ['Jose', 'PH'], ['Anya', 'PL'], ['Mehmet', 'TR'],
  ];

  static List<BotPlayer> _generateBots() {
    final r = Random(42); // deterministic roster
    final roster = <List<String>>[
      for (final n in _khmerNames) ['${n}_KH', 'KH'],
      for (final p in _intl) ['${p[0]}_${p[1]}', p[1]],
    ];
    roster.shuffle(r);
    final n = roster.length;
    final out = <BotPlayer>[];
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final elo = (400 + pow(t, 1.15) * 2700 + r.nextInt(41) - 20).round();
      out.add(BotPlayer(
        id: 'bot_$i',
        name: roster[i][0],
        countryCode: roster[i][1],
        avatar: r.nextInt(24),
        style: BotStyle.values[r.nextInt(BotStyle.values.length)],
        clubId: roster[i][1] == 'KH' ? r.nextInt(_clubDefs.length) : -1,
        elo: elo,
      ));
    }
    return out;
  }

  static List<Club> _freshClubs() => [
        for (int i = 0; i < _clubDefs.length; i++)
          Club(i, _clubDefs[i][0], _clubDefs[i][1]),
      ];

  static Future<VirtualEcosystem> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    VirtualEcosystem eco;
    if (raw == null) {
      eco = VirtualEcosystem._(_generateBots(), _freshClubs(), UserProfile(),
          null, DateTime.now());
      eco.simulateBackgroundMatches(rounds: 20); // warm-up so ranks look alive
    } else {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final clubs = _freshClubs();
      for (final c in j['clubs'] as List) {
        final m = c as Map<String, dynamic>;
        clubs[m['id'] as int].points = m['p'] as int;
      }
      eco = VirtualEcosystem._(
        (j['bots'] as List)
            .map((e) => BotPlayer.fromJson(e as Map<String, dynamic>))
            .toList(),
        clubs,
        UserProfile.fromJson(j['user'] as Map<String, dynamic>),
        j['tour'] == null
            ? null
            : Tournament.fromJson(j['tour'] as Map<String, dynamic>),
        DateTime.fromMillisecondsSinceEpoch(j['last'] as int),
      );
      for (final e in (j['tourns'] as List?) ?? const []) {
        eco.tournaments.add(Tourney.fromJson(Map<String, dynamic>.from(e as Map)));
      }
    }
    eco._ensureGrandmasters();
    eco._ensureChampions();
    eco._ensureTitles();
    eco.user.ensureCats();
    eco._ensureTournaments();
    await eco.save();
    return eco;
  }

  /// Adds the named master bots to saved games that predate them and keeps
  /// their ratings in sync with [_gmRoster].
  void _ensureGrandmasters() {
    for (int i = 0; i < _gmRoster.length; i++) {
      final g = _gmRoster[i];
      final idx = bots.indexWhere((b) => b.id == g.id);
      if (idx < 0) {
        bots.add(BotPlayer(
          id: g.id,
          name: g.name,
          countryCode: g.cc,
          avatar: 100 + i,
          style: g.style,
          clubId: -1,
          elo: g.elo,
        ));
      } else {
        bots[idx].elo = g.elo;
      }
    }
  }

  void _ensureChampions() {
    for (final c in _khRoster) {
      final idx = bots.indexWhere((b) => b.id == c.id);
      if (idx < 0) {
        bots.add(BotPlayer(
          id: c.id,
          name: c.name,
          countryCode: 'KH',
          avatar: 200 + c.seed,
          style: c.style,
          clubId: -1,
          elo: c.elo,
          title: 'ស៊ីដេត ${c.seed}',
          seed: c.seed,
        ));
      } else {
        bots[idx].name = c.name;
        bots[idx].elo = c.elo;
        bots[idx].title = 'ស៊ីដេត ${c.seed}';
      }
    }
  }

  /// Assigns titles once (saved games from before titles existed get them too).
  void _ensureTitles() {
    for (final b in bots) {
      if (b.isGm) {
        b.title = 'GM';
      } else if (b.title == null) {
        b.title = titleForBot(b.name, b.elo);
      }
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey,
        jsonEncode({
          'bots': bots.map((b) => b.toJson()).toList(),
          'clubs': clubs.map((c) => c.toJson()).toList(),
          'user': user.toJson(),
          'tour': activeTournament?.toJson(),
          'last': lastSim.millisecondsSinceEpoch,
          'tourns': tournaments.map((t) => t.toJson()).toList(),
        }));
  }

  // ---- background bot-vs-bot simulation ------------------------------------

  /// Call when the app opens: simulates catch-up rounds for the time away.
  Future<void> onAppOpen() async {
    final hours = DateTime.now().difference(lastSim).inMinutes / 60.0;
    final rounds = (3 + hours * 2).round().clamp(3, 30).toInt();
    simulateBackgroundMatches(rounds: rounds);
    await save();
  }

  /// Call after the user finishes a game.
  Future<void> onGameFinished() async {
    simulateBackgroundMatches(rounds: 2);
    await save();
  }

  BotPlayer botById(String id) => bots.firstWhere((b) => b.id == id);

  void _snapshotRanks() {
    _prevRank = {for (final e in leaderboard()) e.id: e.rank};
  }

  /// One round = every bot plays one rated game against a similar-rated bot.
  void simulateBackgroundMatches({int rounds = 5}) {
    _snapshotRanks();
    for (int i = 0; i < rounds; i++) {
      final order = bots.where((b) => !b.isFixed).toList()
        ..sort((a, b) => (a.elo + _rng.nextInt(160))
            .compareTo(b.elo + _rng.nextInt(160)));
      for (int j = 0; j + 1 < order.length; j += 2) {
        _playBotGame(order[j], order[j + 1]);
      }
    }
    lastSim = DateTime.now();
    notifyListeners();
  }

  /// Returns the score of [a] (1 / 0.5 / 0) and updates both bots' Elo.
  double _playBotGame(BotPlayer a, BotPlayer b) {
    final ea = expectedScore(a.elo, b.elo);
    final gap = (a.elo - b.elo).abs();
    final avg = (a.elo + b.elo) / 2;
    final drawP = (0.10 + 0.22 * (1 - (gap / 800).clamp(0.0, 1.0)) +
            (avg - 1200) / 8000)
        .clamp(0.05, 0.40);
    final winA = ((ea - drawP / 2) / (1 - drawP)).clamp(0.02, 0.98);
    final u = _rng.nextDouble();
    double sa;
    if (u < drawP) {
      sa = 0.5;
      a.draws++;
      b.draws++;
    } else if (_rng.nextDouble() < winA) {
      sa = 1.0;
      a.wins++;
      b.losses++;
    } else {
      sa = 0.0;
      a.losses++;
      b.wins++;
    }
    final ka = a.elo >= 2400 ? 16 : 24;
    final kb = b.elo >= 2400 ? 16 : 24;
    final da = (ka * (sa - ea)).round();
    final db = (kb * ((1 - sa) - (1 - ea))).round();
    a.elo = (a.elo + da).clamp(300, 3300).toInt();
    b.elo = (b.elo + db).clamp(300, 3300).toInt();
    _clubGain(a, da);
    _clubGain(b, db);
    return sa;
  }

  void _clubGain(BotPlayer b, int delta) {
    if (b.clubId >= 0 && delta > 0) clubs[b.clubId].points += delta;
  }

  // ---- leaderboard -----------------------------------------------------------

  List<LeaderboardEntry> leaderboard({int? clubId, int? limit}) {
    final all = <LeaderboardEntry>[
      for (final b in bots)
        LeaderboardEntry(b.id, b.name, b.flag, b.elo, b.clubId, b.games, false,
            title: b.shownTitle),
      LeaderboardEntry('user', user.name, flagEmoji(user.countryCode),
          user.elo, user.clubId, user.games, true,
          title: user.title),
    ];
    all.sort((a, b) => b.elo.compareTo(a.elo));
    for (int i = 0; i < all.length; i++) {
      all[i].rank = i + 1;
      all[i].trend = (_prevRank[all[i].id] ?? all[i].rank) - all[i].rank;
    }
    var res = clubId == null ? all : all.where((e) => e.clubId == clubId).toList();
    if (limit != null && res.length > limit) res = res.sublist(0, limit);
    return res;
  }

  int get userRank => leaderboard().firstWhere((e) => e.isUser).rank;

  List<Club> clubRanking() =>
      List<Club>.from(clubs)..sort((a, b) => b.points.compareTo(a.points));

  // ---- opponents --------------------------------------------------------------

  /// Chance that a Random match picks a titled / featured player (GM bots and
  /// Cambodian seeds included) instead of someone near your rating.
  static const double kFeaturedChance = 0.2;

  /// Random match: usually someone near your rating, sometimes a titled player.
  BotPlayer pickRandomOpponent() {
    final u = user.elo;
    final featured =
        bots.where((b) => b.isFixed || b.shownTitle != null).toList();
    if (featured.isNotEmpty && _rng.nextDouble() < kFeaturedChance) {
      return featured[_rng.nextInt(featured.length)];
    }
    final near = bots.where((b) => (b.elo - u).abs() <= 300).toList();
    if (near.isNotEmpty) return near[_rng.nextInt(near.length)];
    return pickOpponent();
  }

  /// Random bot near [targetElo] (defaults to the user's rating).
  BotPlayer pickOpponent({int? targetElo, int spread = 150}) {
    final t = targetElo ?? user.elo;
    final regular = bots.where((b) => !b.isFixed).toList();
    final near = regular.where((b) => (b.elo - t).abs() <= spread).toList();
    if (near.isNotEmpty) return near[_rng.nextInt(near.length)];
    final sorted = List<BotPlayer>.from(regular)
      ..sort((a, b) => (a.elo - t).abs().compareTo((b.elo - t).abs()));
    return sorted.first;
  }

  BotGameBrain brainFor(BotPlayer bot) =>
      BotGameBrain(elo: bot.elo, style: bot.style, rng: _rng);

  // ---- recording the user's game ---------------------------------------------

  /// [score]: 1 win, 0.5 draw, 0 loss. [reason]: 'checkmate', 'resign',
  /// 'timeout', 'stalemate', 'counting', 'agreement', 'bot_resign' ...
  GameSummary recordUserGame({
    required BotPlayer opponent,
    required double score,
    required String reason,
    double accuracy = 0,
    bool wasCountingEscape = false,
    int minutes = 10,
    String? tournamentId,
  }) {
    // Each time control (Bullet / Blitz / Rapid) has its own Glicko rating.
    final cat = categoryForMinutes(minutes);
    final cs = user.cat(cat);
    final before = cs.rating.round();
    final oppEloBefore = opponent.elo;
    // Glicko-1: both sides are updated together (rating + RD), floor 100.
    final now = DateTime.now().millisecondsSinceEpoch;
    final me = RatingProfile(
      rating: cs.rating,
      rd: cs.rd,
      lastPlayedMs: cs.lastPlayedMs,
      gamesPlayed: cs.games,
    );
    final opp = RatingProfile(
      rating: opponent.elo.toDouble(),
      rd: kEstablishedRd, // bots count as established players
      lastPlayedMs: now,
      gamesPlayed: 100,
    );
    final res = Glicko.play(me, opp, score, nowMs: now);
    cs.rating = res.a.rating;
    cs.rd = res.a.rd;
    cs.lastPlayedMs = now;
    final after = cs.rating.round();
    if (after > cs.peak) cs.peak = after;
    user.lastPlayed = now;
    final applied = after - before;
    if (score == 1.0) {
      cs.wins++;
    } else if (score == 0.0) {
      cs.losses++;
    } else {
      cs.draws++;
    }

    // opponent mirrors (named bots keep a fixed rating)
    if (!opponent.isFixed) {
      opponent.elo = res.b.displayRating.clamp(300, 3300).toInt();
    }
    if (score == 1.0) {
      user.wins++;
      opponent.losses++;
      user.streak++;
      user.bestStreak = max(user.bestStreak, user.streak);
    } else if (score == 0.0) {
      user.losses++;
      opponent.wins++;
      user.streak = 0;
    } else {
      user.draws++;
      opponent.draws++;
      user.streak = 0;
    }
    if (wasCountingEscape && score == 0.5 && reason == 'counting') {
      user.countingEscapes++;
    }
    if (user.clubId >= 0 && applied > 0) clubs[user.clubId].points += applied;

    final unlocked = <AchievementDef>[];
    void unlock(String id) {
      if (user.achievements.add(id)) {
        unlocked.add(achievementDefs.firstWhere((a) => a.id == id));
      }
    }

    if (score == 1.0) unlock('first_win');
    if (score == 1.0 && reason == 'checkmate') unlock('first_checkmate');
    if (score == 1.0 && reason == 'bot_resign') unlock('bot_resign');
    if (score == 1.0 && oppEloBefore >= before + 200) unlock('giant_killer');
    if (user.streak >= 10) unlock('streak_10');
    if (user.countingEscapes >= 3) unlock('counting_master');
    if (user.games >= 50) unlock('veteran_50');
    if (score == 0.5 && reason == 'agreement') unlock('draw_diplomat');

    user.syncHeadline();
    user.history.insert(
      0,
      MatchRecord(
        id: 'g$now',
        dateMs: now,
        minutes: minutes,
        category: cat.key,
        opponentName: opponent.name,
        opponentTitle: opponent.shownTitle,
        opponentFlag: opponent.flag,
        opponentElo: oppEloBefore,
        score: score,
        delta: applied,
        accuracy: accuracy,
        reason: reason,
        tournamentId: tournamentId,
      ),
    );
    if (user.history.length > 100) {
      user.history.removeRange(100, user.history.length);
    }
    notifyListeners();
    save();
    return GameSummary(score, reason, opponent, before, after, applied,
        accuracy, unlocked);
  }

  // ---- clubs -------------------------------------------------------------------

  /// Call after editing the profile from the UI.
  void touch() {
    notifyListeners();
    save();
  }

  /// Registration: the player picks a starting level (400/800/1200/1600/2000).
  /// Rating Deviation starts at 350 so the first games move the rating quickly.
  void setStartingLevel(SkillLevel level) {
    user.elo = level.rating;
    user.rd = kInitialRd;
    user.lastPlayed = 0;
    user.onboarded = true;
    for (final c in TimeCategory.values) {
      user.cats[c.key] = CatStats(rating: level.rating.toDouble());
    }
    if (user.joinedMs == 0) user.joinedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    save();
  }

  // ---- tournaments (offline, simulated) ---------------------------------------

  List<TnEntrant> _pool() => [
        for (final b in bots)
          TnEntrant(b.id, b.name, b.flag, b.shownTitle, b.elo),
      ];

  TnEntrant _me() => TnEntrant(
      'user', user.name, flagEmoji(user.countryCode), user.title, user.elo);

  void _ensureTournaments() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (tournaments.isEmpty) TnScheduler.seedHistory(tournaments, now, _pool());
    TnScheduler.ensure(tournaments, now, _pool());
    TnScheduler.prune(tournaments);
  }

  Tourney? tourneyById(String id) {
    for (final t in tournaments) {
      if (t.id == id) return t;
    }
    return null;
  }

  int _lastTournamentSave = 0;

  /// Moves every tournament forward in time, hands out rewards and keeps the
  /// schedule full. Returns true when anything changed.
  bool tickTournaments() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final t in tournaments) {
      if (!t.finished) {
        if (TnEngine.advance(t, now)) changed = true;
      }
      if (t.finished && !t.rewarded) {
        _finalizeTournament(t);
        changed = true;
      }
    }
    if (TnScheduler.ensure(tournaments, now, _pool()) > 0) changed = true;
    TnScheduler.prune(tournaments);
    if (changed) {
      notifyListeners();
      if (now - _lastTournamentSave > 20000) {
        _lastTournamentSave = now;
        save();
      }
    }
    return changed;
  }

  String? _bestActiveTitle() {
    final active = user.earnedTitles(DateTime.now().millisecondsSinceEpoch);
    for (final t in kTitlePriority) {
      if (active.contains(t)) return t;
    }
    return null;
  }

  /// Trophy for the top 3, title badge for the winner, shown everywhere.
  void _finalizeTournament(Tourney t) {
    if (t.rewarded) return;
    t.rewarded = true;
    final r = TnEngine.rewardFor(t, winsBefore: user.tournamentWins);
    if (r == null) return;
    final tc = t.timeControl;
    if (r.trophyPlace != null) {
      user.trophyCase.insert(
        0,
        Trophy(
          place: r.trophyPlace!,
          tournamentId: t.id,
          tournamentName: t.name,
          format: t.format.name,
          timeControl: tc,
          dateMs: t.finishedMs,
        ),
      );
      user.trophies++;
    }
    if (r.rank == 1) user.tournamentWins++;
    if (r.title != null) {
      user.awards.add(TitleAward(
        title: r.title!,
        tournamentId: t.id,
        tournamentName: t.name,
        awardedMs: t.finishedMs,
        expiresMs: r.titleExpiresMs,
      ));
      user.activeTitle = _bestActiveTitle();
    }
    pendingReward = RewardNotice(t.name, r);
    save();
  }

  void joinTourney(Tourney t) {
    final now = DateTime.now().millisecondsSinceEpoch;
    TnEngine.join(t, _me(), now);
    notifyListeners();
    save();
  }

  void leaveTourney(Tourney t) {
    TnEngine.leave(t, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
    save();
  }

  /// Next game of the user in this tournament (arena: new pairing, swiss: the
  /// current round's pairing). null = nobody available / nothing to play yet.
  TnMatch? startTourneyMatch(Tourney t, {bool berserk = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    TnMatch? m;
    if (t.format == TnFormat.arena) {
      m = TnEngine.startUserArenaMatch(t, now, berserk: berserk);
    } else {
      TnEngine.advance(t, now);
      m = t.userOpenMatch;
    }
    notifyListeners();
    return m;
  }

  /// The bot that plays against the user in [m].
  BotPlayer? opponentOf(TnMatch m) {
    final id = m.whiteId == 'user' ? m.blackId : m.whiteId;
    for (final b in bots) {
      if (b.id == id) return b;
    }
    return null;
  }

  void reportTourneyGame(TourneyGameInfo info, double score, int plies) {
    final t = tourneyById(info.tournamentId);
    if (t == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    TnEngine.reportUserMatch(t, info.matchId, score, plies, info.berserk, now);
    TnEngine.advance(t, now);
    if (t.finished && !t.rewarded) _finalizeTournament(t);
    notifyListeners();
    save();
  }

  void joinClub(int clubId) {
    user.clubId = clubId;
    if (user.achievements.add('club_member')) {
      // surfaced via achievementsUnlockedNow if UI wants a toast
    }
    notifyListeners();
    save();
  }

  void leaveClub() {
    user.clubId = -1;
    notifyListeners();
    save();
  }

  // ---- tournaments ---------------------------------------------------------------

  /// Creates a Swiss or Arena tournament (size 8 or 16) and starts round 1.
  Tournament createTournament(
      {required TournamentFormat format, int size = 8}) {
    assert(size == 8 || size == 16);
    final pool = bots.where((b) => !b.isFixed).toList()
      ..sort((a, b) => (a.elo - user.elo).abs().compareTo((b.elo - user.elo).abs()));
    final candidates = pool.take(size * 2).toList()..shuffle(_rng);
    final chosen = candidates.take(size - 1).toList();
    final players = <TPlayer>[
      TPlayer('user', user.name, user.elo, flagEmoji(user.countryCode), true),
      for (final b in chosen) TPlayer(b.id, b.name, b.elo, b.flag, false),
    ];
    final rounds = format == TournamentFormat.swiss
        ? (size == 8 ? 3 : 4)
        : (size == 8 ? 5 : 6);
    final label = format == TournamentFormat.swiss ? 'Swiss' : 'Arena';
    final t = Tournament(
      'tour_${DateTime.now().millisecondsSinceEpoch}',
      '$label $size',
      format,
      size,
      rounds,
      players,
    );
    activeTournament = t;
    _startNextRound(t);
    notifyListeners();
    save();
    return t;
  }

  void _startNextRound(Tournament t) {
    t.currentRound++;
    final sorted = List<TPlayer>.from(t.players)
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : b.elo.compareTo(a.elo);
      });
    final used = <String>{};
    final pairs = <Pairing>[];
    for (final p in sorted) {
      if (used.contains(p.id)) continue;
      TPlayer? opp;
      for (final q in sorted) {
        if (q.id == p.id || used.contains(q.id)) continue;
        if (!p.opponents.contains(q.id)) {
          opp = q;
          break;
        }
      }
      // everyone met already (small fields): allow a rematch
      opp ??= sorted.firstWhere((q) => q.id != p.id && !used.contains(q.id));
      used..add(p.id)..add(opp.id);
      final whiteFirst = t.currentRound.isEven == (p.id.hashCode.isEven);
      pairs.add(whiteFirst ? Pairing(p.id, opp.id) : Pairing(opp.id, p.id));
    }
    t.rounds.add(pairs);
  }

  /// Report the result of the user's tournament game (1 win, 0.5 draw, 0 loss).
  /// Other boards are simulated, scores applied, and the next round is created
  /// (or the tournament is finalised). Call [recordUserGame] separately for the
  /// rated game itself.
  Tournament reportUserResult(double userScore) {
    final t = activeTournament!;
    final round = t.rounds[t.currentRound];
    for (final p in round) {
      if (p.whiteScore != null) continue;
      if (p.whiteId == 'user') {
        p.whiteScore = userScore;
      } else if (p.blackId == 'user') {
        p.whiteScore = 1.0 - userScore;
      } else {
        p.whiteScore = _playBotGame(botById(p.whiteId), botById(p.blackId));
      }
    }
    _applyRoundScores(t, round);
    if (t.currentRound + 1 >= t.totalRounds) {
      _finishTournament(t);
    } else {
      _startNextRound(t);
    }
    notifyListeners();
    save();
    return t;
  }

  void _applyRoundScores(Tournament t, List<Pairing> round) {
    for (final p in round) {
      final w = t.player(p.whiteId);
      final b = t.player(p.blackId);
      final ws = p.whiteScore!;
      w.opponents.add(b.id);
      b.opponents.add(w.id);
      _award(t.format, w, ws);
      _award(t.format, b, 1.0 - ws);
    }
  }

  void _award(TournamentFormat f, TPlayer p, double s) {
    if (f == TournamentFormat.swiss) {
      p.score += s;
      return;
    }
    // Arena: win 2 (4 on a 2+ win streak), draw 1, loss 0.
    if (s == 1.0) {
      p.score += p.streak >= 2 ? 4 : 2;
      p.streak++;
    } else if (s == 0.5) {
      p.score += 1;
      p.streak = 0;
    } else {
      p.streak = 0;
    }
  }

  void _finishTournament(Tournament t) {
    t.finished = true;
    final st = t.standings;
    t.userRank = st.indexWhere((p) => p.isUser) + 1;
    final big = t.size == 16;
    const names = ['gold', 'silver', 'bronze'];
    final bonus = [big ? 18 : 12, big ? 12 : 8, big ? 7 : 4];
    if (t.userRank >= 1 && t.userRank <= 3) {
      t.trophy = names[t.userRank - 1];
      t.bonusElo = bonus[t.userRank - 1];
      user.elo += t.bonusElo;
      user.trophies++;
      if (user.clubId >= 0) clubs[user.clubId].points += t.bonusElo;
    }
    if (t.userRank == 1) user.achievements.add('tournament_champion');
  }

  /// Leave the tournament: remaining rounds are simulated without the user.
  void abandonTournament() {
    final t = activeTournament;
    if (t == null || t.finished) return;
    while (!t.finished) {
      final round = t.rounds[t.currentRound];
      for (final p in round) {
        if (p.whiteScore != null) continue;
        if (p.whiteId == 'user') {
          p.whiteScore = 0.0;
        } else if (p.blackId == 'user') {
          p.whiteScore = 1.0;
        } else {
          p.whiteScore = _playBotGame(botById(p.whiteId), botById(p.blackId));
        }
      }
      _applyRoundScores(t, round);
      if (t.currentRound + 1 >= t.totalRounds) {
        _finishTournament(t);
      } else {
        _startNextRound(t);
      }
    }
    notifyListeners();
    save();
  }

  void clearTournament() {
    activeTournament = null;
    notifyListeners();
    save();
  }
}
