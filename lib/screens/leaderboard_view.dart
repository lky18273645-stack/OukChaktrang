// lib/screens/leaderboard_view.dart
//
// Chess.com-style ranking: Blitz / Rapid / Bullet tabs, a Top 10 preview for
// each, "View all" with pagination + search over 10,000 players.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bot_directory.dart';
import '../services/profile_models.dart';
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';
import '../ui/cc_theme.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/dir_widgets.dart';
import 'bot_profile_screen.dart';

const List<TimeCategory> kRankCats = [
  TimeCategory.blitz,
  TimeCategory.rapid,
  TimeCategory.bullet,
];

IconData catIcon(TimeCategory c) {
  switch (c) {
    case TimeCategory.bullet:
      return Icons.rocket_launch;
    case TimeCategory.blitz:
      return Icons.bolt;
    case TimeCategory.rapid:
      return Icons.timer;
    case TimeCategory.daily:
      return Icons.wb_sunny;
  }
}

Color catColor(TimeCategory c) {
  switch (c) {
    case TimeCategory.bullet:
      return const Color(0xFFE05B4F);
    case TimeCategory.blitz:
      return const Color(0xFFF7C631);
    case TimeCategory.rapid:
      return ccGreen;
    case TimeCategory.daily:
      return const Color(0xFFE08A1E);
  }
}

/// The user's own avatar (same face as on the profile).
Widget userAvatar(UserProfile u, double size) => BotAvatar(
      bot: BotPlayer(
        id: 'user_avatar',
        name: 'u${u.avatarSeed}',
        countryCode: u.countryCode,
        avatar: u.avatarSeed,
        style: BotStyle.solid,
        clubId: -1,
        elo: 0,
      ),
      size: size,
    );

class LeaderboardView extends StatefulWidget {
  final VirtualEcosystem eco;
  const LeaderboardView(this.eco, {super.key});

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  BotDirectory? _dir;

  @override
  void initState() {
    super.initState();
    // let the first frame render, then build the 10,000-player directory
    Future.delayed(const Duration(milliseconds: 30), () {
      if (!mounted) return;
      setState(() => _dir = BotDirectory.of(widget.eco.bots));
    });
  }

  @override
  Widget build(BuildContext context) {
    final dir = _dir;
    return Theme(
      data: ccTheme(),
      child: Container(
        color: ccBg,
        child: dir == null
            ? const Center(child: CircularProgressIndicator(color: ccGreen))
            : DefaultTabController(
                length: kRankCats.length,
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(children: [
                      const Icon(Icons.leaderboard, color: ccGreen),
                      const SizedBox(width: 10),
                      Text(t('ចំណាត់ថ្នាក់', 'Leaderboard'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${fmtInt(dir.total)} ${t('អ្នកលេង', 'players')}',
                          style: const TextStyle(color: ccMuted, fontSize: 12)),
                    ]),
                  ),
                  TabBar(
                    indicatorColor: ccGreen,
                    labelColor: Colors.white,
                    unselectedLabelColor: ccMuted,
                    tabs: [
                      for (final c in kRankCats)
                        Tab(
                          icon: Icon(catIcon(c), color: catColor(c), size: 20),
                          text: t(c.km, c.en),
                        ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      for (final c in kRankCats) _CategoryTab(widget.eco, dir, c),
                    ]),
                  ),
                ]),
              ),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  final VirtualEcosystem eco;
  final BotDirectory dir;
  final TimeCategory cat;
  const _CategoryTab(this.eco, this.dir, this.cat);

  @override
  Widget build(BuildContext context) {
    final top = dir.top(cat, 10);
    final u = eco.user;
    final myRating = u.cat(cat).rating.round();
    final myRank = dir.rankOfRating(cat, myRating);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(children: [
          Icon(catIcon(cat), color: catColor(cat), size: 22),
          const SizedBox(width: 8),
          Text('${t('កំពូល ១០', 'Top 10')} · ${t(cat.km, cat.en)}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
      ),
      Container(
        decoration:
            BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (int i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: ccLine),
            PlayerRow(
              rank: i + 1,
              avatar: DirAvatar(top[i]),
              title: top[i].title,
              flag: top[i].flag,
              name: top[i].username,
              rating: top[i].rating(cat),
              onTap: () => _open(context, top[i]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        decoration:
            BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: PlayerRow(
          rank: myRank,
          avatar: userAvatar(u, 44),
          title: u.title,
          flag: flagEmoji(u.countryCode),
          name: '${u.name} (${t('អ្នក', 'you')})',
          rating: myRating,
          highlight: true,
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: ccGreen, padding: const EdgeInsets.all(14)),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeaderboardAllScreen(eco, dir, cat),
            ),
          ),
          icon: const Icon(Icons.list_alt),
          label: Text(
              '${t('មើលទាំងអស់', 'View all')} (${fmtInt(dir.total)}) · ${t(cat.km, cat.en)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 16),
    ]);
  }

  void _open(BuildContext context, DirBot b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BotProfileScreen(eco, dir, b, cat)),
    );
  }
}

// -----------------------------------------------------------------------------
// View all: pagination + search
// -----------------------------------------------------------------------------

class LeaderboardAllScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  final BotDirectory dir;
  final TimeCategory initial;
  const LeaderboardAllScreen(this.eco, this.dir, this.initial, {super.key});

  @override
  State<LeaderboardAllScreen> createState() => _LeaderboardAllScreenState();
}

class _LeaderboardAllScreenState extends State<LeaderboardAllScreen> {
  static const int pageSize = 50;
  late TimeCategory _cat;
  int _page = 0;
  String _query = '';
  List<DirBot> _results = const [];
  Timer? _debounce;
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  BotDirectory get dir => widget.dir;

  @override
  void initState() {
    super.initState();
    _cat = widget.initial;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = v.trim();
        _results = _query.isEmpty ? const [] : dir.search(_query, _cat);
      });
    });
  }

  void _setCat(TimeCategory c) {
    setState(() {
      _cat = c;
      _page = 0;
      _results = _query.isEmpty ? const [] : dir.search(_query, _cat);
    });
    _toTop();
  }

  void _goto(int p) {
    final last = dir.pageCount(pageSize) - 1;
    setState(() => _page = p.clamp(0, last).toInt());
    _toTop();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _jumpDialog() async {
    final ctrl = TextEditingController(text: '${_page + 1}');
    final last = dir.pageCount(pageSize);
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ccCard,
        title: Text(t('ទៅទំព័រ', 'Go to page')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: '1 – $last'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t('បោះបង់', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ccGreen),
            onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)),
            child: Text(t('ទៅ', 'Go')),
          ),
        ],
      ),
    );
    if (v != null) _goto(v - 1);
  }

  void _open(DirBot b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BotProfileScreen(widget.eco, dir, b, _cat),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    final pageItems = searching ? _results : dir.page(_cat, _page, pageSize);
    final pages = dir.pageCount(pageSize);
    final myRating = widget.eco.user.cat(_cat).rating.round();
    final myRank = dir.rankOfRating(_cat, myRating);

    return Theme(
      data: ccTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text('${t('ចំណាត់ថ្នាក់', 'Ranking')} · ${t(_cat.km, _cat.en)}')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: _onQuery,
              decoration: InputDecoration(
                hintText: t('ស្វែងរកឈ្មោះអ្នកលេង…', 'Search username…'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _onQuery('');
                        },
                      ),
                filled: true,
                fillColor: ccCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final c in kRankCats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(catIcon(c), size: 16, color: catColor(c)),
                      label: Text(t(c.km, c.en)),
                      selected: _cat == c,
                      onSelected: (_) => _setCat(c),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.person_pin_circle, size: 16),
                  label: Text('${t('ចំណាត់ថ្នាក់អ្នក', 'Your rank')} #${fmtInt(myRank)}'),
                  onPressed: () {
                    _search.clear();
                    setState(() {
                      _query = '';
                      _results = const [];
                    });
                    _goto((myRank - 1) ~/ pageSize);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '${t('ពិន្ទុអ្នក', 'Your rating')} $myRating → #${fmtInt(myRank)}'),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
              ],
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_results.length} ${t('លទ្ធផល', 'results')}'
                  '${_results.length >= 50 ? ' (${t('កំពូល ៥០', 'top 50')})' : ''}',
                  style: const TextStyle(color: ccMuted, fontSize: 12),
                ),
              ),
            )
          else
            _pager(pages),
          const Divider(height: 1, color: ccLine),
          Expanded(
            child: pageItems.isEmpty
                ? Center(
                    child: Text(t('រកមិនឃើញ', 'No players found'),
                        style: const TextStyle(color: ccMuted)))
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: 64,
                    itemCount: pageItems.length,
                    itemBuilder: (context, i) {
                      final b = pageItems[i];
                      final rank = searching ? dir.rankOf(_cat, b) : _page * pageSize + i + 1;
                      return PlayerRow(
                        rank: rank,
                        avatar: DirAvatar(b),
                        title: b.title,
                        flag: b.flag,
                        name: b.username,
                        rating: b.rating(_cat),
                        onTap: () => _open(b),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _pager(int pages) {
    Widget btn(IconData icon, VoidCallback? f) => IconButton(
          onPressed: f,
          icon: Icon(icon),
          color: Colors.white,
          disabledColor: const Color(0xFF55524F),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        btn(Icons.first_page, _page > 0 ? () => _goto(0) : null),
        btn(Icons.chevron_left, _page > 0 ? () => _goto(_page - 1) : null),
        InkWell(
          onTap: _jumpDialog,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('${t('ទំព័រ', 'Page')} ${_page + 1} / $pages',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        btn(Icons.chevron_right, _page < pages - 1 ? () => _goto(_page + 1) : null),
        btn(Icons.last_page, _page < pages - 1 ? () => _goto(pages - 1) : null),
      ]),
    );
  }
}
