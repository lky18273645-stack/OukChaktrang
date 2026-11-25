// lib/screens/tournament_lobby_screen.dart
//
// One tournament: live standings, ongoing games (tap to watch), crosstable,
// Play / Berserk controls and the winner reward dialog.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/tournament_engine.dart';
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';
import '../ui/cc_theme.dart';
import '../ui/game_screen.dart';
import '../widgets/bot_avatar.dart';
import 'spectate_screen.dart';
import 'tournament_hub.dart' show FormatBadge;

class TournamentLobbyScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  final String tourneyId;
  const TournamentLobbyScreen(this.eco, this.tourneyId, {super.key});

  @override
  State<TournamentLobbyScreen> createState() => _TournamentLobbyScreenState();
}

class _TournamentLobbyScreenState extends State<TournamentLobbyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _timer;
  int _n = 0;
  bool _berserk = false;
  bool _busy = false;
  bool _rewardOpen = false;

  Tourney? get tn => widget.eco.tourneyById(widget.tourneyId);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.eco.tickTournaments();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _n++;
      if (_n % 2 == 0) widget.eco.tickTournaments();
      _maybeReward();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ actions

  void _maybeReward() {
    final r = widget.eco.pendingReward;
    if (r == null || _rewardOpen) return;
    widget.eco.pendingReward = null;
    _rewardOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _rewardOpen = false;
        return;
      }
      final place = r.reward.trophyPlace;
      final color = place == 1 ? ccGold : (place == 2 ? ccSilver : ccBronze);
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: ccCard,
          title: Text(r.tournamentName),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 72, color: place == null ? ccMuted : color),
            const SizedBox(height: 8),
            Text('${t('ចំណាត់ថ្នាក់', 'Rank')} #${r.reward.rank}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (place != null)
              Text(t('ពានត្រូវបានដាក់ក្នុងទូរបស់អ្នក', 'Trophy added to your case'),
                  style: const TextStyle(color: ccMuted)),
            if (r.reward.title != null) ...[
              const SizedBox(height: 12),
              Text(t('ទទួលបានងារថ្មី', 'New title earned')),
              const SizedBox(height: 6),
              TitleBadge(title: r.reward.title!, fontSize: 16),
            ],
          ]),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ccGreen),
              onPressed: () => Navigator.pop(c),
              child: Text(t('យល់ព្រម', 'OK')),
            ),
          ],
        ),
      );
      _rewardOpen = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _play() async {
    final t0 = tn;
    if (t0 == null || _busy) return;
    _busy = true;
    final m = widget.eco.startTourneyMatch(t0, berserk: _berserk);
    if (m == null) {
      _busy = false;
      _snack(t('កំពុងរង់ចាំគូប្រកួត…', 'Waiting for an opponent…'));
      return;
    }
    final bot = widget.eco.opponentOf(m);
    if (bot == null) {
      _busy = false;
      return;
    }
    final userWhite = m.whiteId == 'user';
    final berserk = userWhite ? m.berserkW : m.berserkB;
    final info = TourneyGameInfo(
      tournamentId: t0.id,
      matchId: m.id,
      userWhite: userWhite,
      berserk: berserk,
      format: t0.format,
      minutes: t0.minutes,
    );
    final next = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          eco: widget.eco,
          bot: bot,
          minutes: t0.minutes,
          casual: false,
          userWhite: userWhite,
          showTitles: true,
          tournament: info,
          userClockMs: berserk ? t0.minutes * 30000 : null,
        ),
      ),
    );
    _busy = false;
    if (!mounted) return;
    final cur = tn;
    if (next == true &&
        cur != null &&
        cur.format == TnFormat.arena &&
        cur.status(DateTime.now().millisecondsSinceEpoch) == TnStatus.inProgress) {
      unawaited(_play());
    } else {
      setState(() {});
    }
  }

  void _watch(Tourney t0, TnMatch m) {
    final w = t0.byId(m.whiteId);
    final b = t0.byId(m.blackId);
    if (w == null || b == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SpectateScreen(white: w, black: b)),
    );
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final t0 = tn;
    if (t0 == null) {
      return Theme(
        data: ccTheme(),
        child: Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(t('រកមិនឃើញ', 'Not found'))),
        ),
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return Theme(
      data: ccTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            FormatBadge(t0.format),
            const SizedBox(width: 8),
            Flexible(child: Text(t0.name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        body: Column(children: [
          _header(t0, now),
          TabBar(
            controller: _tabs,
            indicatorColor: ccGreen,
            labelColor: Colors.white,
            unselectedLabelColor: ccMuted,
            tabs: [
              Tab(text: t('ចំណាត់ថ្នាក់', 'Standings')),
              Tab(text: t('ហ្គេម', 'Games')),
              Tab(text: t('តារាងលទ្ធផល', 'Crosstable')),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _standings(t0),
              _games(t0, now),
              _crosstable(t0),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _header(Tourney t0, int now) {
    final status = t0.status(now);
    final joined = t0.user != null;
    String info;
    if (status == TnStatus.upcoming) {
      info = '${t('ចាប់ផ្តើមក្នុង', 'Starts in')} ${fmtCountdown(t0.startMs - now)}';
    } else if (status == TnStatus.inProgress) {
      info = t0.format == TnFormat.arena
          ? '${t('បញ្ចប់ក្នុង', 'Ends in')} ${fmtCountdown(t0.endMs - now)}'
          : '${t('ជុំទី', 'Round')} ${t0.currentRound == 0 ? 1 : t0.currentRound}/${t0.rounds}';
    } else {
      info = '${t('បានចប់', 'Finished')} ${fmtDate(t0.finishedMs)}';
    }

    Widget action;
    if (status == TnStatus.completed) {
      final r = t0.userRank;
      action = Text(
        joined && r > 0
            ? '${t('ចំណាត់ថ្នាក់របស់អ្នក', 'Your rank')}: #$r'
            : t('អ្នកមិនបានចូលរួម', 'You did not take part'),
        style: const TextStyle(color: ccMuted),
      );
    } else if (!joined) {
      action = TnEngine.canJoin(t0, now)
          ? SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ccGreen, padding: const EdgeInsets.all(14)),
                onPressed: () {
                  widget.eco.joinTourney(t0);
                  setState(() {});
                },
                child: Text(t('ចូលរួម', 'Join'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          : Text(t('បិទការចុះឈ្មោះ', 'Registration closed'),
              style: const TextStyle(color: ccMuted));
    } else if (status == TnStatus.upcoming) {
      action = Row(children: [
        Expanded(
          child: Text('✓ ${t('បានចូលរួម — រង់ចាំចាប់ផ្តើម', 'Joined — waiting to start')}',
              style: const TextStyle(color: ccGreen)),
        ),
        TextButton(
          onPressed: () {
            widget.eco.leaveTourney(t0);
            setState(() {});
          },
          child: Text(t('ចាកចេញ', 'Leave')),
        ),
      ]);
    } else if (t0.format == TnFormat.arena) {
      final me = t0.user!;
      action = Row(children: [
        FilterChip(
          label: const Text('⚡ Berserk'),
          selected: _berserk,
          onSelected: me.withdrawn ? null : (v) => setState(() => _berserk = v),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ccGreen, padding: const EdgeInsets.all(14)),
            onPressed: me.withdrawn || _busy ? null : _play,
            child: Text(
                t0.userOpenMatch != null ? t('បន្តហ្គេម', 'Resume game') : t('លេង', 'Play'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ]);
    } else {
      final open = t0.userOpenMatch;
      action = open != null
          ? SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ccGreen, padding: const EdgeInsets.all(14)),
                onPressed: _busy ? null : _play,
                child: Text('${t('លេងជុំទី', 'Play round')} ${t0.currentRound}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          : Text(t('រង់ចាំជុំបន្ទាប់ — ហ្គេមផ្សេងកំពុងលេង…',
                  'Waiting for the next round — other games in progress…'),
              style: const TextStyle(color: ccMuted));
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${t0.timeControl} ${t0.categoryLabel}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          const Icon(Icons.people_alt_outlined, size: 16, color: ccMuted),
          const SizedBox(width: 4),
          Text('${t0.registered(now)}/${t0.capacity}',
              style: const TextStyle(color: ccMuted)),
        ]),
        const SizedBox(height: 6),
        Text(info, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        if (t0.format == TnFormat.arena)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t('ឈ្នះ ២ · ស្មើ ១ · 🔥 ឈ្នះ ២ ជាប់គ្នា = ពិន្ទុទ្វេដង',
                  'Win 2 · Draw 1 · 🔥 two wins in a row = double points'),
              style: const TextStyle(color: ccMuted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        action,
      ]),
    );
  }

  // ---------------------------------------------------------------- standings

  String _score(double s) =>
      s == s.roundToDouble() ? s.round().toString() : s.toStringAsFixed(1);

  Widget _nameCell(TnPlayer p, {bool bold = false}) => Row(children: [
        if (p.title != null && p.title!.isNotEmpty) ...[
          TitleBadge(title: p.title!, fontSize: 10),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text('${p.flag} ${p.name}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: p.isUser || bold ? FontWeight.bold : FontWeight.normal)),
        ),
      ]);

  Widget _standings(Tourney t0) {
    final list = t0.standings();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final rankColor = i == 0 ? ccGold : (i == 1 ? ccSilver : (i == 2 ? ccBronze : ccMuted));
        return InkWell(
          onTap: () => _showPlayer(t0, p),
          child: Container(
            color: p.isUser ? const Color(0x2281B64C) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              SizedBox(
                width: 38,
                child: Text('#${i + 1}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: rankColor)),
              ),
              Expanded(child: _nameCell(p)),
              Text('${p.rating}', style: const TextStyle(color: ccMuted, fontSize: 12)),
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                child: t0.format == TnFormat.arena && p.onFire
                    ? const Icon(Icons.local_fire_department, color: ccArenaFire, size: 20)
                    : null,
              ),
              SizedBox(
                width: 34,
                child: Text(_score(p.score),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ]),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------- games

  Widget _matchRow(Tourney t0, TnMatch m, {required bool live}) {
    final w = t0.byId(m.whiteId);
    final b = t0.byId(m.blackId);
    if (w == null || b == null) return const SizedBox.shrink();
    String res;
    Color rc;
    if (live) {
      res = '● LIVE';
      rc = ccRed;
    } else if (m.whiteScore == 1.0) {
      res = '1-0';
      rc = ccGreen;
    } else if (m.whiteScore == 0.0) {
      res = '0-1';
      rc = ccGreen;
    } else {
      res = '½-½';
      rc = ccMuted;
    }
    return InkWell(
      onTap: live ? () => _watch(t0, m) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          Expanded(child: _nameCell(w)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(res,
                style: TextStyle(color: rc, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: _nameCell(b)),
          ),
        ]),
      ),
    );
  }

  Widget _games(Tourney t0, int now) {
    final live = t0.liveMatches(now);
    final recent =
        t0.matches.where((m) => m.applied && !m.isBye).toList().reversed.take(20).toList();
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text('${t('កំពុងលេង', 'Live')} (${live.length})',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      if (live.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(t('គ្មានហ្គេមកំពុងលេង', 'No games in progress'),
              style: const TextStyle(color: ccMuted)),
        ),
      for (final m in live.take(30)) _matchRow(t0, m, live: true),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Text(t('លទ្ធផលថ្មីៗ', 'Recent results'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      for (final m in recent) _matchRow(t0, m, live: false),
      const SizedBox(height: 20),
    ]);
  }

  // --------------------------------------------------------------- crosstable

  /// Result of [p] in [m]: 1 / 0.5 / 0, or null while still being played.
  double? _resultFor(TnPlayer p, TnMatch m) {
    if (!m.applied || m.whiteScore == null) return null;
    return m.whiteId == p.id ? m.whiteScore : 1 - m.whiteScore!;
  }

  Widget _chip(double? r) {
    final String s = r == null ? '…' : (r == 1.0 ? 'W' : (r == 0.5 ? 'D' : 'L'));
    final Color c = r == null
        ? ccMuted
        : (r == 1.0 ? ccGreen : (r == 0.5 ? const Color(0xFF8A8A8A) : ccRed));
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(right: 3, bottom: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      child: Text(s,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  List<TnMatch> _gamesOf(Tourney t0, TnPlayer p) => t0.matches
      .where((m) => !m.isBye && (m.whiteId == p.id || m.blackId == p.id))
      .toList();

  Widget _crosstable(Tourney t0) {
    final list = t0.standings().take(30).toList();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final games = _gamesOf(t0, p);
        return InkWell(
          onTap: () => _showPlayer(t0, p),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SizedBox(width: 34, child: Text('#${i + 1}')),
                Expanded(child: _nameCell(p)),
                Text(_score(p.score), style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              Wrap(children: [for (final m in games) _chip(_resultFor(p, m))]),
            ]),
          ),
        );
      },
    );
  }

  void _showPlayer(Tourney t0, TnPlayer p) {
    final games = _gamesOf(t0, p);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ccCard,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.all(14), children: [
          _nameCell(p, bold: true),
          const SizedBox(height: 4),
          Text(
            '${t('ពិន្ទុ', 'Score')} ${_score(p.score)}  ·  ${p.wins}W ${p.draws}D ${p.losses}L'
            '${t0.format == TnFormat.arena ? '  ·  ⚡ ${p.berserks}' : ''}',
            style: const TextStyle(color: ccMuted),
          ),
          const Divider(color: ccLine),
          for (final m in games)
            Builder(builder: (context) {
              final opp = t0.byId(m.whiteId == p.id ? m.blackId : m.whiteId);
              final r = _resultFor(p, m);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  _chip(r),
                  const SizedBox(width: 6),
                  if (t0.format == TnFormat.swiss)
                    Text('R${m.round}  ', style: const TextStyle(color: ccMuted, fontSize: 12)),
                  Expanded(
                    child: opp == null ? const Text('?') : _nameCell(opp),
                  ),
                  Text(opp == null ? '' : '${opp.rating}',
                      style: const TextStyle(color: ccMuted, fontSize: 12)),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}

const Color ccArenaFire = Color(0xFFFF7043);
