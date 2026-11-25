// lib/services/bot_directory.dart
//
// A deterministic "virtual database" of 10,000 bot accounts.
//
//  * Nothing is stored: bot #k is generated from its own seed, so the same 10,000
//    accounts exist on every launch (usernames, avatars, flags, join dates,
//    Blitz / Rapid / Bullet ratings and titles).
//  * The named bots of the app (GM roster, Cambodian champions, the 62 regular
//    bots) are part of the directory and keep their live ratings.
//  * Sorted index arrays + rank arrays make top-N, pagination, rank lookup and
//    search fast (10,000 rows build in a few milliseconds).

import 'dart:math';

import 'profile_models.dart';
import 'virtual_ecosystem.dart';

const int kDirectorySize = 10000;

/// Fixed anchor (2026-11-01) so join dates never change between launches.
const int _anchorMs = 1793491200000;
const int _dayMs = 86400000;

class DirBot {
  final int id; // unique: 0..999 named bots, 1000.. generated
  final String username;
  final String lower; // lowercase username (search)
  final String cc;
  final int avatarNo;
  final int joinedMs;
  final String? title;
  final int blitz;
  final int rapid;
  final int bullet;
  final BotPlayer? eco; // playable named bot, null for generated ones

  const DirBot({
    required this.id,
    required this.username,
    required this.lower,
    required this.cc,
    required this.avatarNo,
    required this.joinedMs,
    required this.title,
    required this.blitz,
    required this.rapid,
    required this.bullet,
    this.eco,
  });

  int rating(TimeCategory c) {
    switch (c) {
      case TimeCategory.blitz:
        return blitz;
      case TimeCategory.bullet:
        return bullet;
      default:
        return rapid;
    }
  }

  String get flag => flagEmoji(cc);

  DirBot withName(String name) => DirBot(
        id: id,
        username: name,
        lower: name.toLowerCase(),
        cc: cc,
        avatarNo: avatarNo,
        joinedMs: joinedMs,
        title: title,
        blitz: blitz,
        rapid: rapid,
        bullet: bullet,
        eco: eco,
      );

  /// Same formula as BotAvatar, so the face is identical everywhere.
  int get faceSeed =>
      avatarNo * 7 + username.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xFFFF);

  /// A playable opponent for "Challenge Bot".
  BotPlayer toPlayable(TimeCategory c) {
    final e = eco;
    if (e != null) return e;
    return BotPlayer(
      id: 'dir_$id',
      name: username,
      countryCode: cc,
      avatar: avatarNo,
      style: BotStyle.values[id % BotStyle.values.length],
      clubId: -1,
      elo: rating(c),
      title: title ?? '',
    );
  }
}

class CatSummary {
  final int rating;
  final int peak;
  final int wins;
  final int draws;
  final int losses;
  const CatSummary(this.rating, this.peak, this.wins, this.draws, this.losses);
  int get games => wins + draws + losses;
}

class DirMatch {
  final DirBot opponent;
  final TimeCategory cat;
  final int minutes;
  final double score; // 1 / 0.5 / 0 for the profile's bot
  final int delta;
  final double accuracy;
  final int agoMs;
  const DirMatch(this.opponent, this.cat, this.minutes, this.score, this.delta,
      this.accuracy, this.agoMs);
}

// -----------------------------------------------------------------------------
// Name data
// -----------------------------------------------------------------------------

const List<String> _khMale = [
  'Sokha', 'Dara', 'Vannak', 'Rithy', 'Kosal', 'Piseth', 'Veasna', 'Rotha',
  'Makara', 'Visal', 'Samnang', 'Sovann', 'Rathana', 'Vibol', 'Narith',
  'Sambath', 'Vichea', 'Sopheak', 'Ratanak', 'Seyha', 'Chanthou', 'Bunthoeun',
  'Pheakdey', 'Sothea', 'Phirun', 'Kimheng', 'Sambo', 'Borey', 'Vuthy',
  'Socheat', 'Panha', 'Rithea', 'Samath', 'Chhorn', 'Vireak', 'Bora',
];
const List<String> _khFemale = [
  'Sreypich', 'Sophea', 'Sreyneang', 'Bopha', 'Thida', 'Kunthea', 'Channary',
  'Sreymom', 'Sreyleak', 'Chantrea', 'Davy', 'Sophy', 'Malis', 'Sreynich',
  'Rachana', 'Kanha', 'Leakhena', 'Sreyroth', 'Phalla', 'Sokunthea',
];
const List<String> _khLast = [
  'Sok', 'Chea', 'Chhay', 'Kim', 'Lim', 'Heng', 'Sao', 'Mao', 'Ouk', 'Pich',
  'Ly', 'Seng', 'Vong', 'Keo', 'Noun', 'Thy', 'Meas', 'Yim', 'Ros', 'San',
  'Khem', 'Phan', 'Soeun', 'Hun', 'Tep',
];
const List<String> _seaMale = [
  'Minh', 'Tuan', 'Huy', 'Long', 'Anh', 'Somchai', 'Narong', 'Krit', 'Arif',
  'Budi', 'Joko', 'Hafiz', 'Amir', 'Jose', 'Mark', 'Rizal', 'Thanh',
];
const List<String> _seaFemale = [
  'Linh', 'Mai', 'Lan', 'Nok', 'Siri', 'Dewi', 'Putri', 'Aisha', 'Nur',
  'Maria', 'Joy', 'Thao',
];
const List<String> _southMale = [
  'Arjun', 'Rahul', 'Vikram', 'Aditya', 'Rohan', 'Karthik', 'Siddharth',
  'Nikhil', 'Pranav', 'Ishaan',
];
const List<String> _southFemale = ['Priya', 'Ananya', 'Diya', 'Meera', 'Kavya', 'Isha'];
const List<String> _eastMale = [
  'Wei', 'Hiro', 'Kenji', 'Jun', 'Minho', 'Taro', 'Jian', 'Haruto', 'Chen',
  'Daichi',
];
const List<String> _eastFemale = ['Yuki', 'Mei', 'Hana', 'Sakura', 'Jia', 'Min'];
const List<String> _euMale = [
  'Lukas', 'Pierre', 'Ivan', 'Marco', 'Sven', 'Liam', 'Mehmet', 'Pavel', 'Hans',
  'Jean', 'Piotr', 'Andrei', 'Luca', 'Erik', 'Oleg', 'Dmitri', 'Felix',
];
const List<String> _euFemale = [
  'Elena', 'Anya', 'Sofia', 'Clara', 'Emma', 'Olga', 'Ingrid', 'Chloe', 'Nina',
];
const List<String> _amMale = [
  'Alex', 'Carlos', 'Noah', 'Jack', 'Omar', 'Diego', 'Ethan', 'Mateo', 'Tyler',
  'Lucas', 'Ryan',
];
const List<String> _amFemale = ['Maria', 'Sarah', 'Emily', 'Isabella', 'Sophie', 'Zoe'];

const List<String> _words = [
  'Knight', 'Rook', 'Bishop', 'Pawn', 'Queen', 'King', 'Gambit', 'Mate',
  'Blitz', 'Tempo', 'Zugzwang', 'Endgame', 'Opening', 'Master', 'Tiger',
  'Dragon', 'Naga', 'Angkor', 'Mekong', 'Lotus', 'Phoenix', 'Shadow', 'Storm',
  'Thunder', 'Falcon', 'Wolf', 'Lion', 'Eagle', 'Cobra', 'Ninja', 'Wizard',
  'Sniper', 'Hunter', 'Legend', 'Prodigy', 'Tactician', 'Fork', 'Pin',
  'Skewer', 'Castle', 'Check', 'Bullet', 'Rapid', 'Chaos', 'Silent', 'Neo',
  'Pixel', 'Turbo', 'Atlas', 'Orion', 'Nova', 'Titan', 'Viper', 'Raven',
];
const List<String> _tails = [
  'Chess', 'Ouk', 'Chaktrang', 'Gambit', 'Mate', 'Pro', 'GM', 'Official', 'Plays',
];

/// (country, weight, region 0..5)  0 KH, 1 SEA, 2 South Asia, 3 East Asia, 4 Europe, 5 Americas/other
const List<(String, int, int)> _countries = [
  ('KH', 300, 0),
  ('VN', 60, 1), ('TH', 55, 1), ('ID', 50, 1), ('MY', 35, 1), ('PH', 40, 1),
  ('IN', 90, 2), ('BD', 15, 2), ('PK', 10, 2),
  ('CN', 40, 3), ('JP', 30, 3), ('KR', 25, 3), ('SG', 10, 3),
  ('RU', 45, 4), ('DE', 35, 4), ('FR', 35, 4), ('ES', 25, 4), ('IT', 20, 4),
  ('PL', 20, 4), ('GB', 30, 4), ('NL', 15, 4), ('SE', 10, 4), ('UA', 20, 4),
  ('TR', 20, 4),
  ('US', 80, 5), ('BR', 35, 5), ('CA', 20, 5), ('AU', 15, 5), ('EG', 10, 5),
  ('MX', 15, 5), ('AR', 10, 5),
];

double _gauss(Random r, double mu, double sd) {
  final u1 = max(1e-12, r.nextDouble());
  final u2 = r.nextDouble();
  return mu + sd * sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

// -----------------------------------------------------------------------------
// Directory
// -----------------------------------------------------------------------------

class BotDirectory {
  final List<DirBot> all;
  final Map<TimeCategory, List<int>> _order; // indexes into [all], best first
  final Map<TimeCategory, List<int>> _rank; // rank (1-based) of all[i]
  final Map<TimeCategory, List<int>> _sorted; // ratings, best first
  final Map<int, int> _indexOfId; // DirBot.id -> index in [all]

  BotDirectory._(this.all, this._order, this._rank, this._sorted, this._indexOfId);

  int get total => all.length;

  // ---- construction ---------------------------------------------------------

  static List<DirBot>? _generated;
  static BotDirectory? _cache;
  static int _cacheSig = 0;

  /// Cached directory; rebuilt only when the named bots' ratings changed.
  static BotDirectory of(List<BotPlayer> eco) {
    var sig = eco.length;
    for (final b in eco) {
      sig = (sig * 31 + b.elo) & 0x3fffffff;
    }
    final c = _cache;
    if (c != null && sig == _cacheSig) return c;
    final d = build(eco);
    _cache = d;
    _cacheSig = sig;
    return d;
  }

  static BotDirectory build(List<BotPlayer> eco, {int size = kDirectorySize}) {
    final gen = _generated ??= _makeGenerated();
    final all = <DirBot>[
      for (int i = 0; i < eco.length; i++) _fromEco(i, eco[i]),
    ];
    final used = <String>{for (final b in all) b.lower};
    for (int k = 0; all.length < size && k < gen.length; k++) {
      var b = gen[k];
      var name = b.username;
      while (used.contains(name.toLowerCase())) {
        name = '${name}_'; // only happens when a name equals a named bot
      }
      if (name != b.username) b = b.withName(name);
      used.add(b.lower);
      all.add(b);
    }
    final indexOfId = <int, int>{for (int i = 0; i < all.length; i++) all[i].id: i};
    final order = <TimeCategory, List<int>>{};
    final rank = <TimeCategory, List<int>>{};
    final sorted = <TimeCategory, List<int>>{};
    for (final c in [TimeCategory.blitz, TimeCategory.rapid, TimeCategory.bullet]) {
      final r = List<int>.generate(all.length, (i) => all[i].rating(c));
      final idx = List<int>.generate(all.length, (i) => i)
        ..sort((a, b) {
          final d = r[b].compareTo(r[a]);
          return d != 0 ? d : a.compareTo(b);
        });
      final rk = List<int>.filled(all.length, 0);
      for (int p = 0; p < idx.length; p++) {
        rk[idx[p]] = p + 1;
      }
      order[c] = idx;
      rank[c] = rk;
      sorted[c] = [for (final i in idx) r[i]];
    }
    return BotDirectory._(all, order, rank, sorted, indexOfId);
  }

  /// All 10,000 generated bots with guaranteed unique usernames (case-insensitive).
  static List<DirBot> _makeGenerated() {
    final seen = <String>{};
    final out = <DirBot>[];
    for (int k = 0; k < kDirectorySize; k++) {
      final b = _generate(k);
      var name = b.username;
      var n = 0;
      while (seen.contains(name.toLowerCase())) {
        n++;
        name = '${b.username}${(k + n * 37) % 1000}';
      }
      seen.add(name.toLowerCase());
      out.add(name == b.username ? b : b.withName(name));
    }
    return out;
  }

  static DirBot _fromEco(int i, BotPlayer b) {
    final rng = Random(i * 31 + 7);
    int clamp(double v) => v.round().clamp(400, 3300).toInt();
    final joined = _anchorMs - (60 + rng.nextInt(1800)) * _dayMs;
    return DirBot(
      id: i,
      username: b.name,
      lower: b.name.toLowerCase(),
      cc: b.countryCode,
      avatarNo: b.avatar,
      joinedMs: joined,
      title: b.shownTitle,
      blitz: clamp(b.elo + (rng.nextDouble() - 0.5) * 60),
      rapid: clamp(b.elo.toDouble()),
      bullet: clamp(b.elo + (rng.nextDouble() - 0.5) * 90),
      eco: b,
    );
  }

  static DirBot _generate(int k) {
    final rng = Random(k * 7919 + 104729);

    // country -> region
    var total = 0;
    for (final c in _countries) {
      total += c.$2;
    }
    var pick = rng.nextInt(total);
    var cc = 'KH';
    var region = 0;
    for (final c in _countries) {
      if (pick < c.$2) {
        cc = c.$1;
        region = c.$3;
        break;
      }
      pick -= c.$2;
    }

    // name
    final female = rng.nextDouble() < 0.28;
    List<String> male;
    List<String> fem;
    switch (region) {
      case 0:
        male = _khMale;
        fem = _khFemale;
        break;
      case 1:
        male = _seaMale;
        fem = _seaFemale;
        break;
      case 2:
        male = _southMale;
        fem = _southFemale;
        break;
      case 3:
        male = _eastMale;
        fem = _eastFemale;
        break;
      case 4:
        male = _euMale;
        fem = _euFemale;
        break;
      default:
        male = _amMale;
        fem = _amFemale;
    }
    final names = female ? fem : male;
    final first = names[rng.nextInt(names.length)];
    final word = _words[rng.nextInt(_words.length)];
    final tail = _tails[rng.nextInt(_tails.length)];
    final lastOrWord =
        region == 0 && rng.nextDouble() < 0.6 ? _khLast[rng.nextInt(_khLast.length)] : word;
    final year = 1975 + rng.nextInt(38);
    final num2 = 10 + rng.nextInt(90);
    final num3 = 100 + rng.nextInt(900);
    String username;
    switch (rng.nextInt(10)) {
      case 0:
        username = '$first$lastOrWord';
        break;
      case 1:
        username = '${first}_$lastOrWord';
        break;
      case 2:
        username = '$word$first';
        break;
      case 3:
        username = '$first$tail';
        break;
      case 4:
        username = '${first.toLowerCase()}$year';
        break;
      case 5:
        username = '${word}_$num2';
        break;
      case 6:
        username = 'The$word$first';
        break;
      case 7:
        username = '$first$num3';
        break;
      case 8:
        username = '${first.toLowerCase()}_${cc.toLowerCase()}';
        break;
      default:
        username = '$first.$lastOrWord$num2';
    }
    // a third of the names get a small number, like real usernames
    if (k % 3 == 0) username = '$username${(k % 97) + 1}';

    // ratings
    final r = rng.nextDouble();
    double elo;
    if (r < 0.80) {
      elo = _gauss(rng, 1050, 340);
    } else if (r < 0.96) {
      elo = 1500 + rng.nextDouble() * 600 + _gauss(rng, 0, 120);
    } else if (r < 0.995) {
      elo = 2000 + rng.nextDouble() * 600 + _gauss(rng, 0, 80);
    } else {
      elo = 2500 + pow(rng.nextDouble(), 1.6) * 750;
    }
    int cl(double v) => v.round().clamp(400, 3300).toInt();
    final rapid = cl(elo);
    final blitz = cl(elo + _gauss(rng, 0, 50));
    final bullet = cl(elo + _gauss(rng, -20, 80));

    final best = max(rapid, max(blitz, bullet));
    String? title;
    if (best >= 2500) {
      title = 'GM';
    } else if (female) {
      if (best >= 2300) {
        title = 'WGM';
      } else if (best >= 2200) {
        title = 'WIM';
      } else if (best >= 2100) {
        title = 'WFM';
      } else if (best >= 2000) {
        title = 'WCM';
      }
    } else if (best >= 2400) {
      title = 'IM';
    } else if (best >= 2300) {
      title = 'FM';
    } else if (best >= 2200) {
      title = 'CM';
    } else if (best >= 2000 && k.isEven) {
      title = 'NM';
    }

    return DirBot(
      id: 1000 + k,
      username: username,
      lower: username.toLowerCase(),
      cc: cc,
      avatarNo: rng.nextInt(1000),
      joinedMs: _anchorMs - (30 + rng.nextInt(2400)) * _dayMs - rng.nextInt(_dayMs),
      title: title,
      blitz: blitz,
      rapid: rapid,
      bullet: bullet,
    );
  }

  // ---- queries --------------------------------------------------------------

  List<DirBot> top(TimeCategory c, int n) => page(c, 0, n);

  int pageCount(int pageSize) => (all.length + pageSize - 1) ~/ pageSize;

  /// Players ranked [page*size+1 .. (page+1)*size] in [c].
  List<DirBot> page(TimeCategory c, int page, int size) {
    final idx = _order[c]!;
    final from = (page * size).clamp(0, idx.length).toInt();
    final to = (from + size).clamp(0, idx.length).toInt();
    return [for (int i = from; i < to; i++) all[idx[i]]];
  }

  int rankOf(TimeCategory c, DirBot b) => _rank[c]![_indexOfId[b.id]!];

  /// Faster rank lookup for rows that already know their index in [all].
  int rankAt(TimeCategory c, int indexInAll) => _rank[c]![indexInAll];

  /// Where a rating would rank (1 = best). Used for "your rank".
  int rankOfRating(TimeCategory c, int rating) {
    final s = _sorted[c]!;
    var lo = 0;
    var hi = s.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (s[mid] > rating) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo + 1;
  }

  /// Username search (prefix matches first, then "contains"), best rated first.
  List<DirBot> search(String query, TimeCategory c, {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final starts = <DirBot>[];
    final contains = <DirBot>[];
    for (final b in all) {
      final i = b.lower.indexOf(q);
      if (i == 0) {
        starts.add(b);
      } else if (i > 0) {
        contains.add(b);
      }
    }
    int byRating(DirBot a, DirBot b) => b.rating(c).compareTo(a.rating(c));
    starts.sort(byRating);
    contains.sort(byRating);
    return [...starts, ...contains].take(limit).toList();
  }

  int indexOf(DirBot b) => _indexOfId[b.id]!;

  DirBot byIndex(int i) => all[i];

  // ---- profile data (deterministic) ----------------------------------------

  CatSummary summary(DirBot b, TimeCategory c) {
    final rng = Random(b.id * 131 + c.index * 17 + 5);
    final r = b.rating(c);
    final peak = r + rng.nextInt(1 + (r * 0.07).round());
    final games = 20 + (pow(rng.nextDouble(), 2.0) * 2800).round();
    final e = 1 / (1 + pow(10, (1100 - r) / 400));
    final winP = (0.28 + 0.5 * e).clamp(0.22, 0.78).toDouble();
    final drawP = 0.04 + 0.08 * (r / 3200);
    final wins = (games * winP).round();
    final draws = (games * drawP).round();
    final losses = max(0, games - wins - draws);
    return CatSummary(r, peak, wins, draws, losses);
  }

  /// Simulated recent games against other directory players.
  List<DirMatch> recentMatches(DirBot b, {int count = 12}) {
    final rng = Random(b.id * 2654435 + 99);
    final cats = [TimeCategory.blitz, TimeCategory.rapid, TimeCategory.bullet];
    final out = <DirMatch>[];
    var ago = 20 * 60000 + rng.nextInt(90 * 60000);
    for (int i = 0; i < count; i++) {
      final c = cats[rng.nextInt(cats.length)];
      final r = b.rating(c);
      // sample a few opponents, keep the one closest in rating
      DirBot best = all[rng.nextInt(all.length)];
      for (int s = 0; s < 6; s++) {
        final cand = all[rng.nextInt(all.length)];
        if ((cand.rating(c) - r).abs() < (best.rating(c) - r).abs()) best = cand;
      }
      if (best.id == b.id) best = all[(indexOf(b) + 1) % all.length];
      final ro = best.rating(c);
      final e = 1 / (1 + pow(10, (ro - r) / 400));
      final drawP = 0.08 + 0.12 * (1 - ((r - ro).abs() / 600).clamp(0.0, 1.0));
      final u = rng.nextDouble();
      double score;
      if (u < drawP) {
        score = 0.5;
      } else {
        score = rng.nextDouble() < e ? 1.0 : 0.0;
      }
      final delta = (16 * (score - e)).round();
      final acc = (55 + (r - 400) / 2900 * 38 + _gauss(rng, 0, 6)).clamp(38.0, 99.4).toDouble();
      final minutes = c == TimeCategory.bullet ? 1 : (c == TimeCategory.blitz ? (rng.nextBool() ? 3 : 5) : (rng.nextBool() ? 10 : 15));
      out.add(DirMatch(best, c, minutes, score, delta, acc, ago));
      ago += 25 * 60000 + rng.nextInt(5 * 3600000);
    }
    return out;
  }
}
