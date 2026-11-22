// lib/services/profile_models.dart
//
// Data models for the Chess.com-style profile: per time-control ratings,
// trophies, earned titles and match history. Plain JSON-friendly classes, so
// they map 1:1 to Firestore / SQL documents (see docs/DATABASE_SCHEMA.md).

import 'glicko.dart';

enum TimeCategory { bullet, blitz, rapid, daily }

/// 1-2 min = Bullet, 3-5 = Blitz, 10+ = Rapid. (Daily needs asynchronous play,
/// which the offline app does not have yet, so it just keeps its starting rating.)
TimeCategory categoryForMinutes(int minutes) {
  if (minutes <= 2) return TimeCategory.bullet;
  if (minutes <= 5) return TimeCategory.blitz;
  return TimeCategory.rapid;
}

extension TimeCategoryX on TimeCategory {
  String get key => name;

  String get km {
    switch (this) {
      case TimeCategory.bullet:
        return 'ប៊ុលឡេត';
      case TimeCategory.blitz:
        return 'ប្លីត';
      case TimeCategory.rapid:
        return 'រ៉ាភីត';
      case TimeCategory.daily:
        return 'ប្រចាំថ្ងៃ';
    }
  }

  String get en {
    switch (this) {
      case TimeCategory.bullet:
        return 'Bullet';
      case TimeCategory.blitz:
        return 'Blitz';
      case TimeCategory.rapid:
        return 'Rapid';
      case TimeCategory.daily:
        return 'Daily';
    }
  }

  String get range {
    switch (this) {
      case TimeCategory.bullet:
        return '1–2m';
      case TimeCategory.blitz:
        return '3–5m';
      case TimeCategory.rapid:
        return '10–15m';
      case TimeCategory.daily:
        return 'Daily';
    }
  }
}

/// Rating + record for one time-control category.
class CatStats {
  double rating;
  double rd;
  int peak;
  int wins;
  int draws;
  int losses;
  int lastPlayedMs;

  CatStats({
    required this.rating,
    this.rd = kInitialRd,
    int? peak,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.lastPlayedMs = 0,
  }) : peak = peak ?? rating.round();

  int get games => wins + draws + losses;

  Map<String, dynamic> toJson() => {
        'r': rating,
        'rd': rd,
        'pk': peak,
        'w': wins,
        'd': draws,
        'l': losses,
        'lp': lastPlayedMs,
      };

  factory CatStats.fromJson(Map<String, dynamic> j) => CatStats(
        rating: (j['r'] as num).toDouble(),
        rd: (j['rd'] as num).toDouble(),
        peak: j['pk'] as int,
        wins: j['w'] as int,
        draws: j['d'] as int,
        losses: j['l'] as int,
        lastPlayedMs: (j['lp'] as int?) ?? 0,
      );
}

class Trophy {
  final int place; // 1, 2, 3
  final String tournamentId;
  final String tournamentName;
  final String format; // 'arena' | 'swiss'
  final String timeControl; // e.g. '3+0'
  final int dateMs;

  const Trophy({
    required this.place,
    required this.tournamentId,
    required this.tournamentName,
    required this.format,
    required this.timeControl,
    required this.dateMs,
  });

  Map<String, dynamic> toJson() => {
        'p': place,
        'id': tournamentId,
        'n': tournamentName,
        'f': format,
        'tc': timeControl,
        'd': dateMs,
      };

  factory Trophy.fromJson(Map<String, dynamic> j) => Trophy(
        place: j['p'] as int,
        tournamentId: j['id'] as String,
        tournamentName: j['n'] as String,
        format: j['f'] as String,
        timeControl: j['tc'] as String,
        dateMs: j['d'] as int,
      );
}

/// A title badge earned from a tournament. Permanent when [expiresMs] is null,
/// seasonal otherwise.
class TitleAward {
  final String title; // 'ARENA KING', 'CHAMP', 'CM'
  final String tournamentId;
  final String tournamentName;
  final int awardedMs;
  final int? expiresMs;

  const TitleAward({
    required this.title,
    required this.tournamentId,
    required this.tournamentName,
    required this.awardedMs,
    this.expiresMs,
  });

  bool get permanent => expiresMs == null;
  bool activeAt(int nowMs) => expiresMs == null || nowMs < expiresMs!;

  Map<String, dynamic> toJson() => {
        't': title,
        'id': tournamentId,
        'n': tournamentName,
        'a': awardedMs,
        'x': expiresMs,
      };

  factory TitleAward.fromJson(Map<String, dynamic> j) => TitleAward(
        title: j['t'] as String,
        tournamentId: j['id'] as String,
        tournamentName: j['n'] as String,
        awardedMs: j['a'] as int,
        expiresMs: j['x'] as int?,
      );
}

/// One row of the match history list.
class MatchRecord {
  final String id;
  final int dateMs;
  final int minutes;
  final String category; // TimeCategory.key
  final String opponentName;
  final String? opponentTitle;
  final String opponentFlag;
  final int opponentElo;
  final double score; // 1 / 0.5 / 0 from the user's view
  final int delta; // rating change in that category
  final double accuracy; // 0 = unknown
  final String reason;
  final String? tournamentId;

  const MatchRecord({
    required this.id,
    required this.dateMs,
    required this.minutes,
    required this.category,
    required this.opponentName,
    required this.opponentTitle,
    required this.opponentFlag,
    required this.opponentElo,
    required this.score,
    required this.delta,
    required this.accuracy,
    required this.reason,
    this.tournamentId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'd': dateMs,
        'm': minutes,
        'c': category,
        'on': opponentName,
        'ot': opponentTitle,
        'of': opponentFlag,
        'oe': opponentElo,
        's': score,
        'dl': delta,
        'ac': accuracy,
        'rs': reason,
        'tid': tournamentId,
      };

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
        id: j['id'] as String,
        dateMs: j['d'] as int,
        minutes: j['m'] as int,
        category: j['c'] as String,
        opponentName: j['on'] as String,
        opponentTitle: j['ot'] as String?,
        opponentFlag: j['of'] as String,
        opponentElo: j['oe'] as int,
        score: (j['s'] as num).toDouble(),
        delta: j['dl'] as int,
        accuracy: (j['ac'] as num).toDouble(),
        reason: j['rs'] as String,
        tournamentId: j['tid'] as String?,
      );
}

/// Which title a tournament result earns. Order = display priority.
const List<String> kTitlePriority = ['CM', 'CHAMP', 'ARENA KING'];
