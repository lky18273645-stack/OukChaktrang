// test/tournament_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ouk_chaktrang/services/tournament_engine.dart';

const int base = 1700000000000;
const int minute = 60000;

List<TnEntrant> pool(int n) => [
      for (int i = 0; i < n; i++)
        TnEntrant('b$i', 'Bot$i', 'KH', i % 7 == 0 ? 'IM' : null, 800 + i * 40),
    ];

Tourney arena({int n = 40, int minutes = 3}) => TnEngine.create(
      id: 'a',
      name: 'Test Arena',
      format: TnFormat.arena,
      minutes: minutes,
      startMs: base,
      durationMs: 30 * minute,
      capacity: 64,
      createdMs: base - 10 * minute,
      pool: pool(n),
    );

Tourney swiss({required int players, int rounds = 4}) => TnEngine.create(
      id: 's',
      name: 'Test Swiss',
      format: TnFormat.swiss,
      minutes: 3,
      startMs: base,
      rounds: rounds,
      capacity: (players / 0.7).ceil(),
      createdMs: base - 10 * minute,
      pool: pool(players + 10),
    );

TnPlayer dummy() => TnPlayer(
    id: 'x', name: 'X', flag: 'KH', title: null, rating: 1000, isUser: false, joinMs: 0);

void main() {
  group('arena points', () {
    test('base values', () {
      int pts(double s, {bool fire = false, bool berserk = false, int plies = 40}) =>
          TnRules.arenaPoints(score: s, onFire: fire, berserk: berserk, plies: plies);
      expect(pts(1.0), 2);
      expect(pts(0.5), 1);
      expect(pts(0.0), 0);
      expect(pts(1.0, fire: true), 4);
      expect(pts(0.5, fire: true), 2);
      expect(pts(0.0, fire: true), 0);
    });

    test('berserk gives +1 only when you win a real game', () {
      int pts(double s, {bool fire = false, int plies = 40}) => TnRules.arenaPoints(
          score: s, onFire: fire, berserk: true, plies: plies);
      expect(pts(1.0), 3);
      expect(pts(1.0, fire: true), 5);
      expect(pts(0.5), 1);
      expect(pts(0.0), 0);
      expect(pts(1.0, plies: 6), 2); // too short: no bonus
    });

    test('draws shorter than 10 moves score nothing and break the streak', () {
      final p = dummy()..streak = 2;
      TnRules.applyArena(p, 0.5, false, 12);
      expect(p.score, 0);
      expect(p.streak, 0);
    });

    test('win streak: W W W D L = 2 + 2 + 4 + 2 + 0', () {
      final p = dummy();
      for (final s in [1.0, 1.0, 1.0, 0.5, 0.0]) {
        TnRules.applyArena(p, s, false, 40);
      }
      expect(p.score, 10);
      expect(p.wins, 3);
      expect(p.draws, 1);
      expect(p.losses, 1);
      expect(p.streak, 0);
      expect(p.games, 5);
    });
  });

  group('arena simulation', () {
    test('runs to completion and keeps the books straight', () {
      final t = arena();
      expect(TnEngine.advance(t, base + 5 * minute), isTrue);
      expect(t.finished, isFalse);
      TnEngine.advance(t, base + 70 * minute);
      expect(t.finished, isTrue);
      expect(t.matches.isNotEmpty, isTrue);
      expect(t.matches.every((m) => m.applied), isTrue);
      final gamesSum = t.players.fold<int>(0, (a, p) => a + p.games);
      expect(gamesSum, 2 * t.matches.length);
      for (final p in t.players) {
        expect(p.games, p.wins + p.draws + p.losses);
        expect(p.score, greaterThanOrEqualTo(0));
      }
      final s = t.standings();
      for (int i = 1; i < s.length; i++) {
        expect(s[i - 1].score, greaterThanOrEqualTo(s[i].score));
      }
    });

    test('same seed = same result, whenever you look', () {
      final a = arena();
      final b = arena();
      TnEngine.advance(a, base + 70 * minute);
      // b is advanced in many small steps
      for (int m = 1; m <= 70; m++) {
        TnEngine.advance(b, base + m * minute);
      }
      expect(b.finished, isTrue);
      expect(a.standings().map((p) => '${p.id}:${p.score}').toList(),
          b.standings().map((p) => '${p.id}:${p.score}').toList());
    });

    test('nobody plays twice at the same time', () {
      final t = arena();
      TnEngine.advance(t, base + 70 * minute);
      for (final p in t.players) {
        final ms = t.matches
            .where((m) => m.whiteId == p.id || m.blackId == p.id)
            .toList()
          ..sort((x, y) => x.startMs.compareTo(y.startMs));
        for (int i = 1; i < ms.length; i++) {
          expect(ms[i].startMs, greaterThanOrEqualTo(ms[i - 1].endMs));
        }
      }
    });

    test('JSON round trip keeps the tournament identical', () {
      final t = arena();
      TnEngine.advance(t, base + 70 * minute);
      final copy = Tourney.fromJson(t.toJson());
      expect(copy.finished, t.finished);
      expect(copy.standings().map((p) => '${p.id}:${p.score}').toList(),
          t.standings().map((p) => '${p.id}:${p.score}').toList());
    });
  });

  group('user in an arena', () {
    test('three wins in a row = 2 + 2 + 4 points, fire on', () {
      final t = arena();
      var now = base + 5 * minute;
      TnEngine.advance(t, now);
      final me = TnEngine.join(
          t, const TnEntrant('user', 'Me', 'KH', null, 1200), now)!;
      for (int i = 0; i < 3; i++) {
        final m = TnEngine.startUserArenaMatch(t, now);
        expect(m, isNotNull);
        now += 4 * minute;
        TnEngine.reportUserMatch(t, m!.id, 1.0, 40, false, now);
      }
      expect(me.score, 8);
      expect(me.wins, 3);
      expect(me.onFire, isTrue);
    });

    test('abandoning a game is a forfeit loss', () {
      final t = arena();
      var now = base + 5 * minute;
      TnEngine.advance(t, now);
      final me = TnEngine.join(
          t, const TnEntrant('user', 'Me', 'KH', null, 1200), now)!;
      final m = TnEngine.startUserArenaMatch(t, now);
      expect(m, isNotNull);
      now += 20 * minute; // way past the game deadline
      TnEngine.advance(t, now);
      expect(me.losses, 1);
      expect(t.userOpenMatch, isNull);
    });

    test('registration rules', () {
      final t = arena();
      expect(TnEngine.canJoin(t, base - minute), isTrue);
      expect(TnEngine.canJoin(t, base + 29 * minute + 30000), isFalse);
      final s = swiss(players: 16);
      expect(TnEngine.canJoin(s, base - minute), isTrue);
      expect(TnEngine.canJoin(s, base + minute), isFalse); // swiss closes at start
    });
  });

  group('swiss', () {
    test('even field: every round pairs everyone, no rematches', () {
      final t = swiss(players: 16, rounds: 4);
      TnEngine.advance(t, base + 90 * minute);
      expect(t.finished, isTrue);
      expect(t.currentRound, 4);
      for (final p in t.players) {
        expect(p.games, 4);
        expect(p.opps.length, p.opps.toSet().length);
      }
      // each game hands out exactly one point: 4 rounds x 8 games
      final total = t.players.fold<double>(0, (a, p) => a + p.score);
      expect(total, closeTo(32, 1e-9));
    });

    test('odd field: one bye per round, never the same player twice', () {
      final t = swiss(players: 15, rounds: 5);
      TnEngine.advance(t, base + 120 * minute);
      expect(t.finished, isTrue);
      final byes = t.matches.where((m) => m.isBye).toList();
      expect(byes.length, 5);
      expect(byes.map((m) => m.whiteId).toSet().length, 5);
    });

    test('user who never plays forfeits and the tournament still ends', () {
      final t = swiss(players: 16, rounds: 3);
      TnEngine.join(t, const TnEntrant('user', 'Me', 'KH', null, 1200), base - minute);
      TnEngine.advance(t, base + 120 * minute);
      expect(t.finished, isTrue);
      expect(t.user!.losses, greaterThanOrEqualTo(2));
    });
  });

  group('rewards', () {
    Tourney finishedWithUser(TnFormat f, {int others = 20}) {
      final t = f == TnFormat.arena ? arena(n: others) : swiss(players: others);
      TnEngine.join(t, const TnEntrant('user', 'Me', 'KH', null, 1200), base - minute);
      for (final p in t.players) {
        p.score = 0;
      }
      t.finished = true;
      t.finishedMs = t.endMs;
      return t;
    }

    test('arena winner: trophy 1 + seasonal ARENA KING', () {
      final t = finishedWithUser(TnFormat.arena);
      t.user!.score = 10;
      t.user!.games = 3;
      final r = TnEngine.rewardFor(t, winsBefore: 0)!;
      expect(r.rank, 1);
      expect(r.trophyPlace, 1);
      expect(r.title, 'ARENA KING');
      expect(r.titleExpiresMs, t.finishedMs + 30 * 86400000);
    });

    test('swiss winner: permanent CHAMP', () {
      final t = finishedWithUser(TnFormat.swiss);
      t.user!.score = 4;
      t.user!.games = 4;
      final r = TnEngine.rewardFor(t, winsBefore: 0)!;
      expect(r.title, 'CHAMP');
      expect(r.titleExpiresMs, isNull);
    });

    test('third tournament win earns CM', () {
      final t = finishedWithUser(TnFormat.arena);
      t.user!.score = 10;
      t.user!.games = 3;
      expect(TnEngine.rewardFor(t, winsBefore: 2)!.title, 'CM');
    });

    test('third place: trophy but no title', () {
      final t = finishedWithUser(TnFormat.arena);
      final bots = t.players.where((p) => !p.isUser).toList();
      bots[0].score = 20;
      bots[1].score = 18;
      t.user!.score = 10;
      t.user!.games = 3;
      final r = TnEngine.rewardFor(t, winsBefore: 0)!;
      expect(r.rank, 3);
      expect(r.trophyPlace, 3);
      expect(r.title, isNull);
    });

    test('no games played = no reward; tiny fields give no title', () {
      final t = finishedWithUser(TnFormat.arena);
      t.user!.score = 10;
      expect(TnEngine.rewardFor(t, winsBefore: 0), isNull); // games == 0
      final small = finishedWithUser(TnFormat.arena, others: 3);
      small.user!.score = 10;
      small.user!.games = 2;
      expect(TnEngine.rewardFor(small, winsBefore: 0)!.title, isNull);
    });
  });

  group('schedule', () {
    test('keeps 4 upcoming tournaments, spaced apart', () {
      final list = <Tourney>[];
      final now = base;
      expect(TnScheduler.ensure(list, now, pool(60)), 4);
      expect(list.every((t) => t.startMs > now), isTrue);
      final starts = list.map((t) => t.startMs).toList()..sort();
      for (int i = 1; i < starts.length; i++) {
        expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(10 * minute));
      }
      expect(TnScheduler.ensure(list, now, pool(60)), 0);
    });

    test('history is finished and prune keeps the newest', () {
      final list = <Tourney>[];
      TnScheduler.seedHistory(list, base, pool(60));
      expect(list.length, 2);
      expect(list.every((t) => t.finished), isTrue);
      TnScheduler.prune(list, keepCompleted: 1);
      expect(list.length, 1);
    });
  });
}
