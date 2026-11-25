// lib/screens/profile_view.dart
//
// Chess.com-style profile: header with title badge, rating cards per time
// control, trophy case, earned titles and match history.

import 'dart:math';

import 'package:flutter/material.dart';

import '../services/glicko.dart';
import '../services/profile_models.dart';
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';
import '../ui/cc_theme.dart';
import '../widgets/bot_avatar.dart';

class ProfileView extends StatefulWidget {
  final VirtualEcosystem eco;
  const ProfileView(this.eco, {super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  UserProfile get u => widget.eco.user;

  BotPlayer _avatarBot() => BotPlayer(
        id: 'user_avatar',
        name: 'u${u.avatarSeed}',
        countryCode: u.countryCode,
        avatar: u.avatarSeed,
        style: BotStyle.solid,
        clubId: -1,
        elo: 0,
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ccTheme(),
      child: Container(
        color: ccBg,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          _header(),
          const SizedBox(height: 12),
          _meta(),
          _section(t('ពិន្ទុតាមល្បឿន', 'Ratings')),
          _ratingGrid(),
          _section(t('ទូដាក់ពានរង្វាន់', 'Trophy case')),
          _trophyCase(),
          _section(t('ងារ (Title)', 'Titles')),
          _titles(),
          _section(t('ប្រវត្តិការប្រកួត', 'Match history')),
          _history(),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ header

  Widget _header() {
    final title = u.title;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: BotAvatar(bot: _avatarBot(), size: 88, rounded: false),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF3FB950),
              shape: BoxShape.circle,
              border: Border.all(color: ccBg, width: 2),
            ),
          ),
        ),
      ]),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (title != null) ...[
              TitleBadge(title: title, fontSize: 12),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(u.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Text(flagEmoji(u.countryCode), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(u.flair, style: const TextStyle(fontSize: 18)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                    color: Color(0xFF3FB950), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(t('កំពុងអនឡាញ', 'Online'),
                style: const TextStyle(color: ccMuted, fontSize: 12)),
          ]),
          if (u.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(u.bio, style: const TextStyle(color: Color(0xFFD0D0D0))),
            ),
        ]),
      ),
      IconButton(
        onPressed: _edit,
        icon: const Icon(Icons.edit_outlined, color: ccMuted),
      ),
    ]);
  }

  Widget _meta() {
    Widget box(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: ccCard, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text(value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: ccMuted)),
            ]),
          ),
        );
    return Row(children: [
      box(t('ចូលរួម', 'Joined'), fmtDate(u.joinedMs)),
      const SizedBox(width: 8),
      box(t('អនឡាញចុងក្រោយ', 'Last online'), t('ឥឡូវនេះ', 'Now')),
      const SizedBox(width: 8),
      box(t('មិត្តភក្តិ', 'Friends'), '${u.friends}'),
    ]);
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );

  // ----------------------------------------------------------------- ratings

  IconData _icon(TimeCategory c) {
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

  Color _color(TimeCategory c) {
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

  Widget _ratingGrid() {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 156,
      ),
      children: [for (final c in TimeCategory.values) _ratingCard(c)],
    );
  }

  Widget _ratingCard(TimeCategory c) {
    final cs = u.cat(c);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon(c), color: _color(c), size: 22),
          const SizedBox(width: 6),
          Expanded(
            child: Text(t(c.km, c.en),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Text(c.range, style: const TextStyle(color: ccMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Text('${cs.rating.round()}${cs.rd > kProvisionalRd ? '?' : ''}',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        Text('${t('កំពូល', 'Peak')} ${cs.peak}',
            style: const TextStyle(color: ccMuted, fontSize: 12)),
        const Spacer(),
        _wdl(cs),
      ]),
    );
  }

  Widget _wdl(CatStats cs) {
    if (cs.games == 0) {
      return Text(t('មិនទាន់មានហ្គេម', 'No games yet'),
          style: const TextStyle(color: ccMuted, fontSize: 11));
    }
    Widget seg(int n, Color c) => n == 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: Container(height: 6, color: c));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Row(children: [
          seg(cs.wins, ccGreen),
          seg(cs.draws, const Color(0xFF8A8A8A)),
          seg(cs.losses, ccRed),
        ]),
      ),
      const SizedBox(height: 3),
      Text('${cs.wins}W · ${cs.draws}D · ${cs.losses}L',
          style: const TextStyle(fontSize: 11, color: ccMuted)),
    ]);
  }

  // ------------------------------------------------------------------ trophies

  Widget _trophyCase() {
    if (u.trophyCase.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration:
            BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
        child: Text(
          t('ទូទទេ — ឈ្នះលេខ ១–៣ ក្នុងព្រឹត្តិការណ៍ដើម្បីទទួលពាន',
              'Empty — finish top 3 in a tournament to earn a trophy'),
          style: const TextStyle(color: ccMuted),
        ),
      );
    }
    return SizedBox(
      height: 138,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final tr in u.trophyCase) _trophyCard(tr),
      ]),
    );
  }

  Widget _trophyCard(Trophy tr) {
    final color = tr.place == 1 ? ccGold : (tr.place == 2 ? ccSilver : ccBronze);
    return Container(
      width: 132,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Icon(Icons.emoji_events, size: 46, color: color),
        Text(ordinal(tr.place),
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text('${tr.tournamentName} ${tr.timeControl}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        Text(fmtDate(tr.dateMs),
            style: const TextStyle(fontSize: 11, color: ccMuted)),
      ]),
    );
  }

  // -------------------------------------------------------------------- titles

  Widget _titles() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final earned = u.earnedTitles(now).toList()
      ..sort((a, b) => kTitlePriority.indexOf(a).compareTo(kTitlePriority.indexOf(b)));
    if (earned.isEmpty) {
      return Text(
        t('ឈ្នះព្រឹត្តិការណ៍ដើម្បីទទួលងារ [ARENA KING], [CHAMP] ឬ [CM]',
            'Win a tournament to earn [ARENA KING], [CHAMP] or [CM]'),
        style: const TextStyle(color: ccMuted),
      );
    }
    final shown = u.title;
    String expiry(String title) {
      final a = u.awards.where((x) => x.title == title && x.activeAt(now)).toList();
      if (a.any((x) => x.permanent)) return t('អចិន្ត្រៃយ៍', 'permanent');
      final last = a.map((x) => x.expiresMs ?? 0).fold<int>(0, max);
      return '${t('ដល់', 'until')} ${fmtDate(last)}';
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      ChoiceChip(
        label: Text(t('លាក់ងារ', 'Hide')),
        selected: u.activeTitle == '',
        onSelected: (_) {
          u.activeTitle = '';
          widget.eco.touch();
          setState(() {});
        },
      ),
      for (final title in earned)
        ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            TitleBadge(title: title, fontSize: 11),
            const SizedBox(width: 6),
            Text(expiry(title), style: const TextStyle(fontSize: 11)),
          ]),
          selected: shown == title,
          onSelected: (_) {
            u.activeTitle = title;
            widget.eco.touch();
            setState(() {});
          },
        ),
    ]);
  }

  // ------------------------------------------------------------------- history

  Widget _history() {
    if (u.history.isEmpty) {
      return Text(t('មិនទាន់មានការប្រកួត', 'No games yet'),
          style: const TextStyle(color: ccMuted));
    }
    return Container(
      decoration:
          BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        for (int i = 0; i < min(25, u.history.length); i++) ...[
          if (i > 0) const Divider(height: 1, color: ccLine),
          _historyRow(u.history[i]),
        ],
      ]),
    );
  }

  Widget _historyRow(MatchRecord m) {
    TimeCategory cat = TimeCategory.rapid;
    for (final c in TimeCategory.values) {
      if (c.key == m.category) cat = c;
    }
    final Color dc = m.delta > 0 ? ccGreen : (m.delta < 0 ? ccRed : ccMuted);
    final String result =
        m.delta > 0 ? '+${m.delta}' : (m.delta < 0 ? '${m.delta}' : '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Icon(_icon(cat), color: _color(cat), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (m.opponentTitle != null && m.opponentTitle!.isNotEmpty) ...[
                TitleBadge(title: m.opponentTitle!, fontSize: 10),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text('${m.opponentFlag} ${m.opponentName} (${m.opponentElo})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
            Text(
              '${m.minutes}+0${m.tournamentId != null ? '  ·  🏆' : ''}  ·  ${fmtDate(m.dateMs)}',
              style: const TextStyle(color: ccMuted, fontSize: 11),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(result,
              style: TextStyle(
                  color: dc, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(m.accuracy > 0 ? '${m.accuracy.toStringAsFixed(1)}%' : '—',
              style: const TextStyle(color: ccMuted, fontSize: 11)),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------------ edit sheet

  void _edit() {
    final name = TextEditingController(text: u.name);
    final bio = TextEditingController(text: u.bio);
    var flair = u.flair;
    var seed = u.avatarSeed;
    const flairs = ['♟', '🔥', '👑', '⭐', '🌸', '🚀', '🐉', '🏆'];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ccCard,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: BotAvatar(
                  bot: BotPlayer(
                    id: 'user_avatar',
                    name: 'u$seed',
                    countryCode: u.countryCode,
                    avatar: seed,
                    style: BotStyle.solid,
                    clubId: -1,
                    elo: 0,
                  ),
                  size: 64,
                  rounded: false,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => setSheet(() => seed = Random().nextInt(1000)),
                icon: const Icon(Icons.shuffle),
                label: Text(t('ប្តូររូបតំណាង', 'New avatar')),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              maxLength: 20,
              decoration: InputDecoration(
                  labelText: t('ឈ្មោះ', 'Username'), border: const OutlineInputBorder()),
            ),
            TextField(
              controller: bio,
              maxLength: 80,
              decoration: InputDecoration(
                  labelText: t('ពាក្យពណ៌នា', 'Bio'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final f in flairs)
                ChoiceChip(
                  label: Text(f, style: const TextStyle(fontSize: 18)),
                  selected: flair == f,
                  onSelected: (_) => setSheet(() => flair = f),
                ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ccGreen),
                onPressed: () {
                  final n = name.text.trim();
                  if (n.isNotEmpty) u.name = n;
                  u.bio = bio.text.trim();
                  u.flair = flair;
                  u.avatarSeed = seed;
                  widget.eco.touch();
                  Navigator.pop(c);
                  setState(() {});
                },
                child: Text(t('រក្សាទុក', 'Save')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
