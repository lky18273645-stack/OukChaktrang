// lib/screens/bot_profile_screen.dart
//
// Chess.com-style player profile for any of the 10,000 bots: header, rating
// cards (Blitz / Rapid / Bullet), recent games and a "Challenge Bot" button.

import 'package:flutter/material.dart';

import '../services/bot_directory.dart';
import '../services/profile_models.dart';
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';
import '../ui/cc_theme.dart';
import '../ui/game_screen.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/dir_widgets.dart';
import 'leaderboard_view.dart' show kRankCats, catIcon, catColor;

class BotProfileScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  final BotDirectory dir;
  final DirBot bot;
  final TimeCategory focus;
  const BotProfileScreen(this.eco, this.dir, this.bot, this.focus, {super.key});

  @override
  State<BotProfileScreen> createState() => _BotProfileScreenState();
}

class _BotProfileScreenState extends State<BotProfileScreen> {
  late final List<DirMatch> _matches;

  DirBot get b => widget.bot;

  @override
  void initState() {
    super.initState();
    _matches = widget.dir.recentMatches(b, count: 12);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ccTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text(b.username, overflow: TextOverflow.ellipsis)),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          _header(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: ccGreen, padding: const EdgeInsets.all(15)),
              onPressed: _challenge,
              icon: const Icon(Icons.sports_esports),
              label: Text(t('ប្រកួតជាមួយបូតនេះ', 'Challenge Bot'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
          _section(t('ពិន្ទុ', 'Ratings')),
          for (final c in kRankCats) ...[
            _ratingCard(c),
            const SizedBox(height: 10),
          ],
          _section(t('ការប្រកួតថ្មីៗ', 'Recent games')),
          _matchesList(),
          const SizedBox(height: 10),
          Text(
            t('គណនីបូតក្លែងធ្វើដោយកម្មវិធី ទិន្នន័យជាការក្លែងធ្វើ។',
                'Simulated bot account; the statistics are generated.'),
            style: const TextStyle(color: ccMuted, fontSize: 11),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ header

  Widget _header() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(width: 88, height: 88, child: DirAvatar(b, size: 88)),
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
            if (b.title != null && b.title!.isNotEmpty) ...[
              TitleBadge(title: b.title!, fontSize: 12),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(b.username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Text(b.flag, style: const TextStyle(fontSize: 18)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: Color(0xFF3FB950), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(t('អនឡាញ', 'Online'),
                style: const TextStyle(color: ccMuted, fontSize: 12)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: ccLine, borderRadius: BorderRadius.circular(4)),
              child: const Text('BOT',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${t('ចូលរួម', 'Joined')} ${fmtDate(b.joinedMs)}',
              style: const TextStyle(color: ccMuted, fontSize: 12)),
        ]),
      ),
    ]);
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );

  // ------------------------------------------------------------------ ratings

  Widget _ratingCard(TimeCategory c) {
    final s = widget.dir.summary(b, c);
    final rank = widget.dir.rankOf(c, b);
    final focused = c == widget.focus;
    Widget seg(int n, Color col) => n == 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: Container(height: 7, color: col));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ccCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: focused ? ccGreen : Colors.transparent, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(catIcon(c), color: catColor(c), size: 22),
          const SizedBox(width: 8),
          Text(t(c.km, c.en),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Text('${t('ចំណាត់ថ្នាក់', 'Rank')} #${fmtInt(rank)}',
              style: const TextStyle(color: ccMuted, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtInt(s.rating),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text('${t('ខ្ពស់បំផុត', 'Highest')} ${fmtInt(s.peak)}',
                style: const TextStyle(color: ccMuted, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(children: [
            seg(s.wins, ccGreen),
            seg(s.draws, const Color(0xFF8A8A8A)),
            seg(s.losses, ccRed),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('${fmtInt(s.wins)} ${t('ឈ្នះ', 'W')}',
              style: const TextStyle(color: ccGreen, fontSize: 12)),
          const SizedBox(width: 12),
          Text('${fmtInt(s.draws)} ${t('ស្មើ', 'D')}',
              style: const TextStyle(color: ccMuted, fontSize: 12)),
          const SizedBox(width: 12),
          Text('${fmtInt(s.losses)} ${t('ចាញ់', 'L')}',
              style: const TextStyle(color: Color(0xFFE57373), fontSize: 12)),
          const Spacer(),
          Text('${fmtInt(s.games)} ${t('ហ្គេម', 'games')}',
              style: const TextStyle(color: ccMuted, fontSize: 12)),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------ recent games

  Widget _matchesList() {
    return Container(
      decoration:
          BoxDecoration(color: ccCard, borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (int i = 0; i < _matches.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: ccLine),
          _matchRow(_matches[i]),
        ],
      ]),
    );
  }

  Widget _matchRow(DirMatch m) {
    final String letter = m.score == 1.0 ? 'W' : (m.score == 0.0 ? 'L' : 'D');
    final Color col = m.score == 1.0
        ? ccGreen
        : (m.score == 0.0 ? ccRed : const Color(0xFF8A8A8A));
    final o = m.opponent;
    final Color dc = m.delta > 0 ? ccGreen : (m.delta < 0 ? ccRed : ccMuted);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BotProfileScreen(widget.eco, widget.dir, o, m.cat),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: col, borderRadius: BorderRadius.circular(5)),
            child: Text(letter,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Icon(catIcon(m.cat), color: catColor(m.cat), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (o.title != null && o.title!.isNotEmpty) ...[
                  TitleBadge(title: o.title!, fontSize: 10),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text('${o.flag} ${o.username} (${fmtInt(o.rating(m.cat))})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
              Text(
                '${m.minutes}+0 · ${agoText(m.agoMs, AppSettings.km.value)}',
                style: const TextStyle(color: ccMuted, fontSize: 11),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(m.delta > 0 ? '+${m.delta}' : '${m.delta}',
                style: TextStyle(color: dc, fontWeight: FontWeight.bold)),
            Text('${m.accuracy.toStringAsFixed(1)}%',
                style: const TextStyle(color: ccMuted, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }

  // --------------------------------------------------------------- challenge

  void _challenge() {
    var minutes = 3;
    var rated = true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ccCard,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t('ប្រកួតជាមួយ', 'Challenge')} ${b.username}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in const [1, 3, 5, 10, 15])
                  ChoiceChip(
                    avatar: Icon(catIcon(categoryForMinutes(m)),
                        size: 16, color: catColor(categoryForMinutes(m))),
                    label: Text('$m+0'),
                    selected: minutes == m,
                    onSelected: (_) => setSheet(() => minutes = m),
                  ),
              ]),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(t('ចំណាត់ថ្នាក់', 'Rated'))),
                  ButtonSegment(
                      value: false, label: Text(t('សាកល្បង (Undo)', 'Casual (undo)'))),
                ],
                selected: {rated},
                onSelectionChanged: (s) => setSheet(() => rated = s.first),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: ccGreen, padding: const EdgeInsets.all(14)),
                  onPressed: () {
                    Navigator.pop(c);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GameScreen(
                          eco: widget.eco,
                          bot: b.toPlayable(categoryForMinutes(minutes)),
                          minutes: minutes,
                          casual: !rated,
                          showTitles: true,
                        ),
                      ),
                    );
                  },
                  child: Text(t('ចាប់ផ្តើម', 'Start'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
