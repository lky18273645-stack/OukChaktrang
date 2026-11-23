// test/bot_directory_test.dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ouk_chaktrang/services/bot_directory.dart';
import 'package:ouk_chaktrang/services/profile_models.dart';
import 'package:ouk_chaktrang/services/virtual_ecosystem.dart';

const cats = [TimeCategory.blitz, TimeCategory.rapid, TimeCategory.bullet];

BotPlayer named(String id, String name, int elo, {String? title}) => BotPlayer(
      id: id,
      name: name,
      countryCode: 'NO',
      avatar: 100,
      style: BotStyle.solid,
      clubId: -1,
      elo: elo,
      title: title,
    );

void main() {
  late BotDirectory dir;
  setUpAll(() {
    dir = BotDirectory.build(const <BotPlayer>[]);
  });

  group('10,000 accounts', () {
    test('size and unique usernames', () {
      expect(dir.total, 10000);
      final names = dir.all.map((b) => b.lower).toSet();
      expect(names.length, 10000);
      final ids = dir.all.map((b) => b.id).toSet();
      expect(ids.length, 10000);
    });

    test('ratings stay between 400 and 3300 in every category', () {
      for (final b in dir.all) {
        for (final c in cats) {
          expect(b.rating(c), inInclusiveRange(400, 3300));
        }
      }
    });

    test('rating spread: strong top, low median', () {
      for (final c in cats) {
        final top = dir.top(c, 10);
        expect(top.first.rating(c), greaterThanOrEqualTo(3000));
        expect(top.last.rating(c), greaterThanOrEqualTo(2900));
        final mid = dir.page(c, 100, 50).first.rating(c); // rank ~5001
        expect(mid, inInclusiveRange(800, 1500));
      }
    });

    test('flags, avatars and join dates', () {
      final countries = dir.all.map((b) => b.cc).toSet();
      expect(countries.length, greaterThan(20));
      expect(dir.all.where((b) => b.cc == 'KH').length, greaterThan(1500));
      for (final b in dir.all) {
        expect(b.joinedMs, lessThan(1793491200000));
        expect(b.joinedMs, greaterThan(1500000000000));
        expect(b.avatarNo, inInclusiveRange(0, 999));
      }
    });

    test('titles: GM only for the strongest, none below 2000', () {
      var gm = 0;
      for (final b in dir.all) {
        final best = [b.blitz, b.rapid, b.bullet].reduce(max);
        if (b.title == 'GM') {
          gm++;
          expect(best, greaterThanOrEqualTo(2500));
        }
        if (best >= 2500) expect(b.title, 'GM');
        if (best < 2000) expect(b.title, isNull);
      }
      expect(gm, inInclusiveRange(40, 400));
      // the very top of every ranking holds the GM badge
      for (final c in cats) {
        expect(dir.top(c, 10).every((b) => b.title == 'GM'), isTrue);
      }
    });

    test('same accounts every time (deterministic)', () {
      final again = BotDirectory.build(const <BotPlayer>[]);
      for (int i = 0; i < 10000; i += 97) {
        expect(again.all[i].username, dir.all[i].username);
        expect(again.all[i].blitz, dir.all[i].blitz);
        expect(again.all[i].joinedMs, dir.all[i].joinedMs);
      }
    });
  });

  group('ranking queries', () {
    test('sorted best first and ranks match positions', () {
      for (final c in cats) {
        final p0 = dir.page(c, 0, 50);
        for (int i = 1; i < p0.length; i++) {
          expect(p0[i - 1].rating(c), greaterThanOrEqualTo(p0[i].rating(c)));
        }
        expect(dir.rankOf(c, p0.first), 1);
        expect(dir.rankOf(c, dir.page(c, 1, 50).first), 51);
        expect(dir.rankOf(c, dir.page(c, 199, 50).last), 10000);
      }
    });

    test('pagination', () {
      expect(dir.pageCount(50), 200);
      expect(dir.page(TimeCategory.rapid, 0, 50).length, 50);
      expect(dir.page(TimeCategory.rapid, 199, 50).length, 50);
      expect(dir.page(TimeCategory.rapid, 200, 50), isEmpty);
      expect(dir.top(TimeCategory.blitz, 10).length, 10);
    });

    test('where a rating would rank', () {
      expect(dir.rankOfRating(TimeCategory.blitz, 4000), 1);
      expect(dir.rankOfRating(TimeCategory.blitz, 100), 10001);
      final hundredth = dir.page(TimeCategory.blitz, 1, 50)[49].rating(TimeCategory.blitz);
      expect(dir.rankOfRating(TimeCategory.blitz, hundredth), lessThanOrEqualTo(100));
    });

    test('search finds players by username', () {
      final target = dir.all[500];
      final hits = dir.search(target.username, TimeCategory.rapid);
      expect(hits.any((b) => b.id == target.id), isTrue);
      expect(dir.search('', TimeCategory.rapid), isEmpty);
      expect(dir.search('zzzzzzzzzzzz', TimeCategory.rapid), isEmpty);
      expect(dir.search('a', TimeCategory.rapid, limit: 20).length, 20);
      // case-insensitive
      expect(dir.search(target.username.toUpperCase(), TimeCategory.rapid).isNotEmpty, isTrue);
    });

    test('building and sorting 10,000 rows is fast', () {
      final sw = Stopwatch()..start();
      BotDirectory.build(const <BotPlayer>[]);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('named bots join the directory', () {
    test('keep their rating, title and picture', () {
      final eco = [
        named('gm_magnus', 'Magnus Carlsen', 2882, title: 'GM'),
        named('bot_1', 'Sokha_KH', 900, title: ''),
      ];
      final d = BotDirectory.build(eco);
      expect(d.total, 10000);
      expect(d.all[0].eco, isNotNull);
      expect(d.all[0].rapid, 2882);
      expect(d.all[0].title, 'GM');
      expect(d.all[1].title, isNull);
      expect(d.all.map((b) => b.lower).toSet().length, 10000);
      final same = identical(BotDirectory.of(eco), BotDirectory.of(eco));
      expect(same, isTrue);
    });

    test('a generated bot can be challenged', () {
      final b = dir.all[1234];
      final p = b.toPlayable(TimeCategory.blitz);
      expect(p.name, b.username);
      expect(p.elo, b.blitz);
      expect(p.id.startsWith('dir_'), isTrue);
    });
  });

  group('profile data', () {
    test('rating summary is consistent', () {
      for (final b in [dir.all[0], dir.all[777], dir.all[9999]]) {
        for (final c in cats) {
          final s = dir.summary(b, c);
          expect(s.rating, b.rating(c));
          expect(s.peak, greaterThanOrEqualTo(s.rating));
          expect(s.games, greaterThanOrEqualTo(20));
          expect(s.wins + s.draws + s.losses, s.games);
        }
      }
    });

    test('recent games are stable and sensible', () {
      final b = dir.all[4242];
      final a = dir.recentMatches(b);
      final c = dir.recentMatches(b);
      expect(a.length, 12);
      for (int i = 0; i < a.length; i++) {
        expect(a[i].opponent.id, c[i].opponent.id);
        expect(a[i].opponent.id, isNot(b.id));
        expect([0.0, 0.5, 1.0].contains(a[i].score), isTrue);
        expect(a[i].accuracy, inInclusiveRange(38, 99.4));
        if (i > 0) expect(a[i].agoMs, greaterThan(a[i - 1].agoMs));
      }
    });
  });
}
