// lib/ui/home_screen.dart
import 'package:flutter/material.dart';

import '../services/virtual_ecosystem.dart';
import 'app_state.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  const HomeScreen(this.eco, {super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _minutes = 10;
  bool _rated = true;
  late double _oppElo;

  @override
  void initState() {
    super.initState();
    _oppElo = widget.eco.user.elo.clamp(400, 3000).toDouble();
  }

  void _start(BotPlayer bot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          eco: widget.eco,
          bot: bot,
          minutes: _minutes,
          casual: !_rated,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.km,
      builder: (context, _, __) => AnimatedBuilder(
        animation: widget.eco,
        builder: (context, ___) {
          final pages = [_playPage(), _leaderboardPage(), _settingsPage()];
          return Scaffold(
            appBar: AppBar(title: const Text('OukChaktrang.com')),
            body: pages[_tab],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.sports_esports),
                    label: t('លេង', 'Play')),
                NavigationDestination(
                    icon: const Icon(Icons.leaderboard),
                    label: t('ចំណាត់ថ្នាក់', 'Ranking')),
                NavigationDestination(
                    icon: const Icon(Icons.settings),
                    label: t('ការកំណត់', 'Settings')),
              ],
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------ play

  Widget _playPage() {
    final u = widget.eco.user;
    return ListView(padding: const EdgeInsets.all(14), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.brown,
                child: Icon(Icons.person, color: Colors.white, size: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${flagEmoji(u.countryCode)} ${u.name}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Elo ${u.elo}   •   #${widget.eco.userRank}'),
                    Text(
                        '${t('ឈ្នះ', 'W')} ${u.wins}  ${t('ស្មើ', 'D')} ${u.draws}  ${t('ចាញ់', 'L')} ${u.losses}',
                        style: const TextStyle(color: Colors.grey)),
                  ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Text(t('ពេលវេលា (នាទី)', 'Time (minutes)'),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final m in const [1, 3, 5, 10, 15])
          ChoiceChip(
            label: Text('$m'),
            selected: _minutes == m,
            onSelected: (_) => setState(() => _minutes = m),
          ),
      ]),
      const SizedBox(height: 14),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, label: Text(t('ចំណាត់ថ្នាក់', 'Rated'))),
          ButtonSegment(
              value: false, label: Text(t('សាកល្បង (Undo)', 'Casual (undo)'))),
        ],
        selected: {_rated},
        onSelectionChanged: (s) => setState(() => _rated = s.first),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
        onPressed: () => _start(widget.eco.pickOpponent()),
        icon: const Icon(Icons.bolt),
        label: Text(t('ស្វែងរកគូប្រកួតរហ័ស', 'Quick match')),
      ),
      const SizedBox(height: 22),
      Text('${t('ជ្រើសកម្លាំង bot', 'Choose bot strength')}: ~${_oppElo.round()} Elo',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      Slider(
        min: 400,
        max: 3000,
        divisions: 52,
        value: _oppElo,
        label: '${_oppElo.round()}',
        onChanged: (v) => setState(() => _oppElo = v),
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
        onPressed: () => _start(
            widget.eco.pickOpponent(targetElo: _oppElo.round(), spread: 120)),
        icon: const Icon(Icons.smart_toy_outlined),
        label: Text(t('លេងជាមួយ bot នេះ', 'Play this level')),
      ),
    ]);
  }

  // ----------------------------------------------------------- leaderboard

  Widget _leaderboardPage() {
    final list = widget.eco.leaderboard();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final e = list[i];
        Widget trend;
        if (e.trend > 0) {
          trend = Text('▲${e.trend}',
              style: const TextStyle(color: Colors.green, fontSize: 12));
        } else if (e.trend < 0) {
          trend = Text('▼${-e.trend}',
              style: const TextStyle(color: Colors.red, fontSize: 12));
        } else {
          trend = const Text('–', style: TextStyle(color: Colors.grey));
        }
        return ListTile(
          dense: true,
          tileColor: e.isUser ? const Color(0x33FFC107) : null,
          leading: SizedBox(
              width: 70,
              child: Row(children: [
                SizedBox(width: 38, child: Text('#${e.rank}')),
                trend,
              ])),
          title: Text('${e.flag} ${e.name}',
              style: TextStyle(
                  fontWeight: e.isUser ? FontWeight.bold : FontWeight.normal)),
          trailing: Text('${e.elo}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        );
      },
    );
  }

  // -------------------------------------------------------------- settings

  Widget _settingsPage() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      SwitchListTile(
        title: Text(t('ភាសាខ្មែរ', 'Khmer language')),
        subtitle: const Text('ភាសាខ្មែរ / English'),
        value: AppSettings.km.value,
        onChanged: (v) => AppSettings.setKm(v),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t('ស្បែកក្តារ', 'Board theme'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      ValueListenableBuilder<int>(
        valueListenable: AppSettings.boardTheme,
        builder: (context, sel, _) => Wrap(spacing: 10, runSpacing: 10, children: [
          for (int i = 0; i < boardThemes.length; i++)
            GestureDetector(
              onTap: () => AppSettings.setTheme(i),
              child: Container(
                width: 74,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: sel == i ? Colors.deepOrange : Colors.black26,
                      width: sel == i ? 3 : 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Container(
                            height: 26, color: boardThemes[i].light)),
                    Expanded(
                        child: Container(
                            height: 26, color: boardThemes[i].dark)),
                  ]),
                  Row(children: [
                    Expanded(
                        child: Container(
                            height: 26, color: boardThemes[i].dark)),
                    Expanded(
                        child: Container(
                            height: 26, color: boardThemes[i].light)),
                  ]),
                  const SizedBox(height: 4),
                  Text(boardThemes[i].name,
                      style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ),
        ]),
      ),
      const Divider(height: 30),
      TextFormField(
        initialValue: widget.eco.user.name,
        decoration: InputDecoration(
          labelText: t('ឈ្មោះអ្នកលេង', 'Player name'),
          border: const OutlineInputBorder(),
        ),
        onFieldSubmitted: (v) {
          final name = v.trim();
          if (name.isNotEmpty) {
            widget.eco.user.name = name;
            widget.eco.save();
            setState(() {});
          }
        },
      ),
    ]);
  }
}
