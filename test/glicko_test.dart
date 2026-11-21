// test/glicko_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ouk_chaktrang/services/glicko.dart';

const int now = 1700000000000;
const int day = 86400000;

RatingProfile established(double rating, {double rd = kEstablishedRd}) =>
    RatingProfile(rating: rating, rd: rd, lastPlayedMs: now, gamesPlayed: 100);

int deltaFor(int diffOppMinusA, double score, {double rd = kEstablishedRd}) {
  final a = established(1500, rd: rd);
  final b = established(1500.0 + diffOppMinusA, rd: rd);
  return Glicko.play(a, b, score, nowMs: now).deltaA;
}

void main() {
  group('starting levels and tiers', () {
    test('five starting levels', () {
      expect(SkillLevel.newPlayer.rating, 400);
      expect(SkillLevel.beginner.rating, 800);
      expect(SkillLevel.intermediate.rating, 1200);
      expect(SkillLevel.advanced.rating, 1600);
      expect(SkillLevel.expert.rating, 2000);
      final p = RatingProfile.newAccount(SkillLevel.beginner);
      expect(p.rd, 350);
      expect(p.provisional, isTrue);
    });

    test('nine tiers with exact boundaries', () {
      expect(getPlayerTier(100).level, 1);
      expect(getPlayerTier(399).level, 1);
      expect(getPlayerTier(400).level, 2);
      expect(getPlayerTier(799).level, 2);
      expect(getPlayerTier(800).level, 3);
      expect(getPlayerTier(999).level, 3);
      expect(getPlayerTier(1000).level, 4);
      expect(getPlayerTier(1199).level, 4);
      expect(getPlayerTier(1200).level, 5);
      expect(getPlayerTier(1399).level, 5);
      expect(getPlayerTier(1400).level, 6);
      expect(getPlayerTier(1799).level, 6);
      expect(getPlayerTier(1800).level, 7);
      expect(getPlayerTier(2199).level, 7);
      expect(getPlayerTier(2200).level, 8);
      expect(getPlayerTier(2499).level, 8);
      expect(getPlayerTier(2500).level, 9);
      expect(getPlayerTier(3100).level, 9);
      expect(getPlayerTier(1450).km, 'កម្រិតខ្ពស់');
      expect(getPlayerTier(1450).en, 'Advanced');
    });
  });

  group('calibration table (both players RD ~ 54)', () {
    // diff = opponent - player A. (winMin, winMax, drawMin, drawMax, lossMin, lossMax)
    final table = <int, List<int>>{
      0: [8, 8, 0, 0, -8, -8],
      100: [10, 11, 2, 3, -6, -5],
      200: [12, 13, 4, 5, -4, -3],
      300: [14, 14, 6, 7, -2, -2],
      400: [15, 15, 7, 8, -1, -1],
      500: [15, 16, 8, 14, -1, 0],
      -100: [5, 6, -3, -2, -11, -10],
      -200: [3, 4, -5, -4, -13, -12],
      -400: [1, 1, -8, -7, -15, -15],
    };

    // Pure Glicko-1 is smooth, so a few cells land 1 point outside the table
    // (e.g. 300 lower, loss: -2.5 -> -3). We therefore allow +-1 on every bound.
    table.forEach((diff, r) {
      test('diff $diff', () {
        final w = deltaFor(diff, 1.0);
        final d = deltaFor(diff, 0.5);
        final l = deltaFor(diff, 0.0);
        expect(w, inInclusiveRange(r[0] - 1, r[1] + 1), reason: 'win $w');
        expect(d, inInclusiveRange(r[2] - 1, r[3] + 1), reason: 'draw $d');
        expect(l, inInclusiveRange(r[4] - 1, r[5] + 1), reason: 'loss $l');
      });
    });

    test('equal ratings are zero-sum and symmetric', () {
      final a = established(1500);
      final b = established(1500);
      final res = Glicko.play(a, b, 1.0, nowMs: now);
      expect(res.deltaA, 8);
      expect(res.deltaB, -8);
    });
  });

  group('provisional accounts', () {
    test('new 400 account winning its first games jumps and RD shrinks', () {
      var me = RatingProfile.newAccount(SkillLevel.newPlayer, nowMs: now);
      final opp = established(400);
      final r1 = Glicko.play(me, opp, 1.0, nowMs: now);
      expect(r1.deltaA, inInclusiveRange(100, 150)); // capped at 150
      expect(r1.a.rd, lessThan(350));
      expect(r1.a.rd, greaterThan(200));
      me = r1.a;
      final r2 = Glicko.play(me, established(me.rating), 1.0, nowMs: now);
      expect(r2.deltaA, inInclusiveRange(30, 150));
      expect(r2.a.rd, lessThan(r1.a.rd));
    });

    test('RD keeps falling toward the stable range over 20 games', () {
      var me = RatingProfile.newAccount(SkillLevel.beginner, nowMs: now);
      var last = me.rd;
      for (int i = 0; i < 20; i++) {
        final res = Glicko.play(me, established(me.rating), i.isEven ? 1.0 : 0.0,
            nowMs: now);
        me = res.a;
        expect(me.rd, lessThan(last));
        last = me.rd;
      }
      expect(me.rd, lessThan(100));
      expect(me.rd, greaterThanOrEqualTo(kMinRd));
    });
  });

  group('established players', () {
    test('draw against a player 500 higher gains about +8 to +14', () {
      final me = established(1500, rd: 60);
      final opp = established(2000, rd: 60);
      final res = Glicko.play(me, opp, 0.5, nowMs: now);
      expect(res.deltaA, inInclusiveRange(8, 14));
    });
  });

  group('rating floor', () {
    test('a 105 player who loses is clamped to 100', () {
      final me = established(105);
      final opp = established(105);
      final res = Glicko.play(me, opp, 0.0, nowMs: now);
      expect(res.a.rating, 100);
      expect(res.a.rating, greaterThanOrEqualTo(kMinRating));
    });

    test('even a huge provisional loss never goes below 100', () {
      final me = RatingProfile.newAccount(SkillLevel.newPlayer, nowMs: now);
      final res = Glicko.play(me, established(100), 0.0, nowMs: now);
      expect(res.a.rating, greaterThanOrEqualTo(100));
    });
  });

  group('inactivity', () {
    test('RD grows with time and never exceeds 350', () {
      final p = established(1500, rd: 50);
      final w = Glicko.withInactivity(p, now + 7 * day);
      final m = Glicko.withInactivity(p, now + 30 * day);
      final y = Glicko.withInactivity(p, now + 400 * day);
      expect(w.rd, greaterThan(50));
      expect(m.rd, greaterThan(w.rd));
      expect(y.rd, 350);
    });

    test('an inactive player moves more after a game', () {
      final fresh = established(1500, rd: 54);
      final rusty = fresh.copyWith(lastPlayedMs: now - 180 * day);
      final opp = established(1500);
      final a = Glicko.play(fresh, opp, 1.0, nowMs: now).deltaA;
      final b = Glicko.play(rusty, opp, 1.0, nowMs: now).deltaA;
      expect(b, greaterThan(a));
    });
  });
}
