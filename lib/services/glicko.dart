// lib/services/glicko.dart
//
// Glicko-1 rating system for Ouk Chaktrang (pure Dart, no Flutter imports).
//
//  * RatingProfile  - rating, rating deviation (RD), last game time, games played, tier
//  * SkillLevel     - the 5 starting levels chosen at registration
//  * getPlayerTier  - the 9 rank tiers (English + Khmer)
//  * Glicko.play    - updates BOTH players at once (rating + RD), applies inactivity,
//                     the 100-point floor and the RD floor
//
// Glicko-1 (Mark Glickman):
//   q    = ln(10) / 400
//   g(RD)= 1 / sqrt(1 + 3 q^2 RD^2 / pi^2)
//   E    = 1 / (1 + 10^(-g(RDj) (r - rj) / 400))
//   d^2  = 1 / (q^2 g(RDj)^2 E (1 - E))
//   r'   = r + q / (1/RD^2 + 1/d^2) * g(RDj) * (S - E)
//   RD'  = sqrt(1 / (1/RD^2 + 1/d^2))
//
// Calibration: with both players at RD ~ 54 ("established") the rating changes
// follow the benchmark table (equal rating: win +8 / draw 0 / loss -8, ...).
// See test/glicko_test.dart for the exact comparison and the few cells that differ
// by 1 point because pure Glicko-1 is smooth.

import 'dart:math';

const double kInitialRd = 350; // brand-new account
const double kMinRd = 30; // most stable active players
const double kMaxRd = 350; // inactivity never pushes RD above this
const double kMinRating = 100; // rating floor
const double kEstablishedRd = 54; // typical RD of an active player / bot
const double kProvisionalRd = 110; // above this the rating is "provisional" (?)

// -----------------------------------------------------------------------------
// Starting level + tiers
// -----------------------------------------------------------------------------

enum SkillLevel {
  newPlayer(400, 'New to Ouk Chaktrang', 'ទើបចាប់ផ្តើមលេងអុកចត្រង្គ'),
  beginner(800, 'Beginner', 'អ្នកចាប់ផ្តើម'),
  intermediate(1200, 'Intermediate', 'មធ្យម'),
  advanced(1600, 'Advanced', 'កម្រិតខ្ពស់'),
  expert(2000, 'Expert', 'អ្នកជំនាញ');

  final int rating;
  final String en;
  final String km;
  const SkillLevel(this.rating, this.en, this.km);
}

class PlayerTier {
  final int level; // 1..9
  final String en;
  final String km;
  final int min;
  final int? max; // null = no upper bound
  const PlayerTier(this.level, this.en, this.km, this.min, this.max);
}

const List<PlayerTier> kTiers = [
  PlayerTier(1, 'Absolute Beginner', 'ទើបចេះដើរកូន', 100, 399),
  PlayerTier(2, 'Beginner', 'កម្រិតដំបូង', 400, 799),
  PlayerTier(3, 'Novice / Upper Beginner', 'កម្រិតដំបូងថ្នាក់ខ្ពស់', 800, 999),
  PlayerTier(4, 'Low Intermediate', 'មធ្យមកម្រិតទាប', 1000, 1199),
  PlayerTier(5, 'High Intermediate', 'មធ្យមកម្រិតខ្ពស់', 1200, 1399),
  PlayerTier(6, 'Advanced', 'កម្រិតខ្ពស់', 1400, 1799),
  PlayerTier(7, 'Expert / Candidate Master', 'កម្រិតជំនាញ', 1800, 2199),
  PlayerTier(8, 'Master Level', 'កម្រិតគ្រូអុក', 2200, 2499),
  PlayerTier(9, 'Grandmaster / Super GM', 'កម្រិតកំពូល', 2500, null),
];

/// Tier for a rating (the rating is floored first; anything below 100 is tier 1).
PlayerTier getPlayerTier(num rating) {
  final r = rating.floor();
  for (final t in kTiers.reversed) {
    if (r >= t.min) return t;
  }
  return kTiers.first;
}

// -----------------------------------------------------------------------------
// Data model
// -----------------------------------------------------------------------------

class RatingProfile {
  final double rating;
  final double rd;
  final int lastPlayedMs; // millisecondsSinceEpoch (0 = never)
  final int gamesPlayed;

  const RatingProfile({
    required this.rating,
    required this.rd,
    required this.lastPlayedMs,
    required this.gamesPlayed,
  });

  /// New account: chosen starting level, RD 350 (provisional period).
  factory RatingProfile.newAccount(SkillLevel level, {int nowMs = 0}) =>
      RatingProfile(
        rating: level.rating.toDouble(),
        rd: kInitialRd,
        lastPlayedMs: nowMs,
        gamesPlayed: 0,
      );

  PlayerTier get tier => getPlayerTier(rating);
  int get displayRating => rating.round();
  bool get provisional => rd > kProvisionalRd;

  RatingProfile copyWith({
    double? rating,
    double? rd,
    int? lastPlayedMs,
    int? gamesPlayed,
  }) =>
      RatingProfile(
        rating: rating ?? this.rating,
        rd: rd ?? this.rd,
        lastPlayedMs: lastPlayedMs ?? this.lastPlayedMs,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      );

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'rd': rd,
        'lastPlayed': lastPlayedMs,
        'games': gamesPlayed,
        'tier': tier.level,
      };

  factory RatingProfile.fromJson(Map<String, dynamic> j) => RatingProfile(
        rating: (j['rating'] as num).toDouble(),
        rd: (j['rd'] as num).toDouble(),
        lastPlayedMs: j['lastPlayed'] as int,
        gamesPlayed: j['games'] as int,
      );
}

class GlickoConfig {
  final double minRd;
  final double maxRd;
  final double minRating;

  /// RD growth per sqrt(day) of inactivity. 18.13 takes RD from 50 back to 350
  /// in about a year (about 70 after a week, 110 after a month, 180 after 3 months).
  final double inactivityC;

  /// Safety cap for one game (rating points). null = no cap. With RD 350 the raw
  /// Glicko change can exceed +170; 150 keeps the first games in the +30..+150 range.
  /// It is not a bonus: it only limits extreme provisional swings.
  final double? maxDelta;

  const GlickoConfig({
    this.minRd = kMinRd,
    this.maxRd = kMaxRd,
    this.minRating = kMinRating,
    this.inactivityC = 18.13,
    this.maxDelta = 150,
  });
}

class MatchResult {
  final RatingProfile a;
  final RatingProfile b;
  final int deltaA; // change in the displayed (rounded) rating
  final int deltaB;
  const MatchResult(this.a, this.b, this.deltaA, this.deltaB);
}

// -----------------------------------------------------------------------------
// Engine
// -----------------------------------------------------------------------------

class Glicko {
  static final double q = ln10 / 400;

  static double g(double rd) => 1 / sqrt(1 + 3 * q * q * rd * rd / (pi * pi));

  /// Expected score of a player rated [r] against [rOpp] (opponent deviation [rdOpp]).
  static double expected(double r, double rOpp, double rdOpp) =>
      1 / (1 + pow(10, -g(rdOpp) * (r - rOpp) / 400));

  /// RD after [nowMs] - lastPlayed of inactivity: sqrt(RD^2 + c^2 * days), max 350.
  static RatingProfile withInactivity(RatingProfile p, int nowMs,
      {GlickoConfig config = const GlickoConfig()}) {
    if (p.lastPlayedMs <= 0 || nowMs <= p.lastPlayedMs) return p;
    final days = (nowMs - p.lastPlayedMs) / 86400000.0;
    final rd = min(config.maxRd,
        sqrt(p.rd * p.rd + config.inactivityC * config.inactivityC * days));
    return p.copyWith(rd: rd);
  }

  static ({double rating, double rd}) _step(
      double r, double rd, double rOpp, double rdOpp, double s) {
    final gOpp = g(rdOpp);
    final e = expected(r, rOpp, rdOpp);
    final d2 = 1 / (q * q * gOpp * gOpp * e * (1 - e));
    final denom = 1 / (rd * rd) + 1 / d2;
    return (
      rating: r + (q / denom) * gOpp * (s - e),
      rd: sqrt(1 / denom),
    );
  }

  /// Plays one game. [scoreA]: 1 win, 0.5 draw, 0 loss for [a]. Both players are
  /// updated from their PRE-game values, so the result does not depend on order.
  static MatchResult play(
    RatingProfile a,
    RatingProfile b,
    double scoreA, {
    required int nowMs,
    GlickoConfig config = const GlickoConfig(),
  }) {
    final a0 = withInactivity(a, nowMs, config: config);
    final b0 = withInactivity(b, nowMs, config: config);
    final sa = scoreA.clamp(0.0, 1.0).toDouble();

    final ua = _step(a0.rating, a0.rd, b0.rating, b0.rd, sa);
    final ub = _step(b0.rating, b0.rd, a0.rating, a0.rd, 1 - sa);

    RatingProfile finish(RatingProfile p0, ({double rating, double rd}) u) {
      var delta = u.rating - p0.rating;
      final cap = config.maxDelta;
      if (cap != null) delta = delta.clamp(-cap, cap).toDouble();
      final newRating = max(config.minRating, p0.rating + delta); // floor 100
      final newRd = u.rd.clamp(config.minRd, config.maxRd).toDouble();
      return p0.copyWith(
        rating: newRating,
        rd: newRd,
        lastPlayedMs: nowMs,
        gamesPlayed: p0.gamesPlayed + 1,
      );
    }

    final na = finish(a0, ua);
    final nb = finish(b0, ub);
    return MatchResult(
      na,
      nb,
      na.rating.round() - a.rating.round(),
      nb.rating.round() - b.rating.round(),
    );
  }
}
