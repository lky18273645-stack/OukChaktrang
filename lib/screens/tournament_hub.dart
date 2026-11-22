// lib/screens/tournament_hub.dart
//
// Tournament hub: Upcoming / In progress / Completed, with Arena / Swiss cards.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/tournament_engine.dart';
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';
import '../ui/cc_theme.dart';
import '../widgets/bot_avatar.dart';
import 'tournament_lobby_screen.dart';

const Color ccArena = Color(0xFFE08A1E);
const Color ccSwiss = Color(0xFF4A90D9);

class FormatBadge extends StatelessWidget {
  final TnFormat format;
  const FormatBadge(this.format, {super.key});

  @override
  Widget build(BuildContext context) {
    final arena = format == TnFormat.arena;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: arena ? ccArena : ccSwiss,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(arena ? 'ARENA' : 'SWISS',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}

class TournamentHub extends StatefulWidget {
  final VirtualEcosystem eco;
  const TournamentHub(this.eco, {super.key});

  @override
  State<TournamentHub> createState() => _TournamentHubState();
}

class _TournamentHubState extends State<TournamentHub> {
  Timer? _timer;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.eco.tickTournaments();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _n++;
      if (_n % 3 == 0) widget.eco.tickTournaments();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _open(Tourney t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentLobbyScreen(widget.eco, t.id),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = widget.eco.tournaments;
    final upcoming = all.where((t) => t.status(now) == TnStatus.upcoming).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final live = all.where((t) => t.status(now) == TnStatus.inProgress).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final done = all.where((t) => t.status(now) == TnStatus.completed).toList()
      ..sort((a, b) => b.startMs.compareTo(a.startMs));

    return Theme(
      data: ccTheme(),
      child: DefaultTabController(
        length: 3,
        child: Container(
          color: ccBg,
          child: Column(children: [
            TabBar(
              indicatorColor: ccGreen,
              labelColor: Colors.white,
              unselectedLabelColor: ccMuted,
              tabs: [
                Tab(text: '${t('នឹងមកដល់', 'Upcoming')} (${upcoming.length})'),
                Tab(text: '${t('កំពុងដំណើរការ', 'In progress')} (${live.length})'),
                Tab(text: t('បានចប់', 'Completed')),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _list(upcoming, now),
                _list(live, now),
                _list(done, now),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _list(List<Tourney> list, int now) {
    if (list.isEmpty) {
      return Center(
        child: Text(t('គ្មានព្រឹត្តិការណ៍', 'No tournaments'),
            style: const TextStyle(color: ccMuted)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [for (final t in list) _card(t, now)],
    );
  }

  Widget _card(Tourney tn, int now) {
    final status = tn.status(now);
    final joined = tn.user != null;
    final canJoin = TnEngine.canJoin(tn, now);

    String info;
    if (status == TnStatus.upcoming) {
      info = '${t('ចាប់ផ្តើមក្នុង', 'Starts in')} ${fmtCountdown(tn.startMs - now)}';
    } else if (status == TnStatus.inProgress) {
      info = tn.format == TnFormat.arena
          ? '${t('បញ្ចប់ក្នុង', 'Ends in')} ${fmtCountdown(tn.endMs - now)}'
          : '${t('ជុំទី', 'Round')} ${tn.currentRound == 0 ? 1 : tn.currentRound}/${tn.rounds}';
    } else {
      info = fmtDate(tn.startMs);
    }

    Widget action;
    if (status == TnStatus.completed) {
      final win = tn.standings().first;
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events, color: ccGold, size: 18),
        const SizedBox(width: 4),
        if (win.title != null && win.title!.isNotEmpty) ...[
          TitleBadge(title: win.title!, fontSize: 9),
          const SizedBox(width: 4),
        ],
        Text(win.name, style: const TextStyle(fontSize: 12)),
      ]);
    } else if (!joined && canJoin) {
      action = FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: ccGreen,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        ),
        onPressed: () {
          widget.eco.joinTourney(tn);
          setState(() {});
        },
        child: Text(t('ចូលរួម', 'Join'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
    } else if (joined) {
      action = FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: status == TnStatus.inProgress ? ccGreen : ccLine,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
        onPressed: () => _open(tn),
        child: Text(
            status == TnStatus.inProgress
                ? t('លេង', 'Play')
                : '✓ ${t('បានចូលរួម', 'Joined')}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    } else {
      action = Text(t('បិទការចុះឈ្មោះ', 'Registration closed'),
          style: const TextStyle(color: ccMuted, fontSize: 12));
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(tn),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration:
            BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            FormatBadge(tn.format),
            const SizedBox(width: 8),
            Text('${tn.timeControl} ${tn.categoryLabel}',
                style: const TextStyle(color: ccMuted, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.people_alt_outlined, size: 16, color: ccMuted),
            const SizedBox(width: 4),
            Text('${tn.registered(now) + 0}/${tn.capacity}',
                style: const TextStyle(color: ccMuted)),
          ]),
          const SizedBox(height: 8),
          Text(tn.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(info, style: const TextStyle(color: ccMuted)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: action),
        ]),
      ),
    );
  }
}
