// lib/ui/home_screen.dart
import 'package:flutter/material.dart';

import '../screens/bot_menu_screen.dart';
import '../screens/profile_view.dart';
import '../screens/tournament_hub.dart';
import '../services/glicko.dart';
import '../widgets/bot_avatar.dart';
import 'game_screen.dart';
import '../screens/pgn_import_screen.dart';
import '../services/virtual_ecosystem.dart';
import 'app_state.dart';

class HomeScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  const HomeScreen(this.eco, {super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.km,
      builder: (context, _, __) => AnimatedBuilder(
        animation: widget.eco,
        builder: (context, ___) {
          final pages = [
            _playPage(),
            TournamentHub(widget.eco),
            _leaderboardPage(),
            ProfileView(widget.eco),
            _settingsPage(),
          ];
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
                    icon: const Icon(Icons.emoji_events),
                    label: t('ព្រឹត្តិការណ៍', 'Events')),
                NavigationDestination(
                    icon: const Icon(Icons.leaderboard),
                    label: t('ចំណាត់ថ្នាក់', 'Ranking')),
                NavigationDestination(
                    icon: const Icon(Icons.person),
                    label: t('ប្រវត្តិរូប', 'Profile')),
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

  void _randomMatch() {
    final bot = widget.eco.pickRandomOpponent();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
            eco: widget.eco, bot: bot, minutes: 10, showTitles: true),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

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
                    Text(
                        'Elo ${u.elo}${u.rd > kProvisionalRd ? '?' : ''}   •   #${widget.eco.userRank}'),
                    Text(
                      '${t(getPlayerTier(u.elo).km, getPlayerTier(u.elo).en)}  ·  ${t('ជួរ', 'Tier')} ${getPlayerTier(u.elo).level}/9',
                      style: const TextStyle(
                          color: Colors.brown, fontWeight: FontWeight.w600),
                    ),
                    Text(
                        '${t('ឈ្នះ', 'W')} ${u.wins}  ${t('ស្មើ', 'D')} ${u.draws}  ${t('ចាញ់', 'L')} ${u.losses}',
                        style: const TextStyle(color: Colors.grey)),
                  ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      // Bots entry card
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BotMenuScreen(widget.eco)),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF81B64C),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.smart_toy, size: 34, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('លេងជាមួយបូត', 'Play Bots'),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(
                        t('ជ្រើសគូប្រកួតពី ${widget.eco.bots.length} នាក់',
                            'Choose from ${widget.eco.bots.length} players'),
                        style: const TextStyle(color: Colors.white70)),
                  ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 30),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
        onPressed: _randomMatch,
        icon: const Icon(Icons.casino),
        label: Text(t('ចៃដន្យ (Random match)', 'Random match')),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PgnImportScreen()),
        ),
        icon: const Icon(Icons.analytics_outlined),
        label: Text(t('នាំចូល PGN ហើយវិភាគ', 'Import PGN & analyse')),
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
          title: Row(children: [
            if (e.title != null && e.title!.isNotEmpty) ...[
              TitleBadge(title: e.title!, fontSize: 10),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text('${e.flag} ${e.name}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight:
                          e.isUser ? FontWeight.bold : FontWeight.normal)),
            ),
          ]),
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
      ValueListenableBuilder<bool>(
        valueListenable: AppSettings.unlockAllBots,
        builder: (context, on, _) => SwitchListTile(
          title: Text(t('បើកបូតទាំងអស់', 'Unlock all bots')),
          subtitle: Text(t('លេងជាមួយបូតខ្លាំងៗភ្លាមៗ',
              'Play the strongest bots right away')),
          value: on,
          onChanged: (v) => AppSettings.setUnlockAll(v),
        ),
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
                        child: Container(height: 26, color: boardThemes[i].light)),
                    Expanded(
                        child: Container(height: 26, color: boardThemes[i].dark)),
                  ]),
                  Row(children: [
                    Expanded(
                        child: Container(height: 26, color: boardThemes[i].dark)),
                    Expanded(
                        child: Container(height: 26, color: boardThemes[i].light)),
                  ]),
                  const SizedBox(height: 4),
                  Text(boardThemes[i].name, style: const TextStyle(fontSize: 11)),
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
