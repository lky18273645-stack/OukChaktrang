// lib/screens/bot_menu_screen.dart
//
// Bot menu (Chess.com style): rating slider, personality filter, avatar grids by
// level, Engine section, Options (time / rated), colour choice and a big Play button.

import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/ouk_rules.dart' show kKhun;
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';
import '../ui/game_screen.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/ouk_board_widget.dart' show PieceImage;

const Color _bg = Color(0xFF262522);
const Color _panel = Color(0xFF312E2B);
const Color _tile = Color(0xFF3A3835);
const Color _green = Color(0xFF81B64C);
const Color _muted = Color(0xFFA0A0A0);

class _Tier {
  final int from;
  final int to; // exclusive
  final String km;
  final String en;
  const _Tier(this.from, this.to, this.km, this.en);
}

const List<_Tier> _tiers = [
  _Tier(0, 800, 'អ្នកចាប់ផ្តើម', 'Beginner'),
  _Tier(800, 1400, 'មធ្យម', 'Intermediate'),
  _Tier(1400, 2000, 'កម្រិតខ្ពស់', 'Advanced'),
  _Tier(2000, 2600, 'ជំនាញ', 'Master'),
  _Tier(2600, 99999, 'មហាគ្រូ', 'Grandmaster'),
];

String _tierName(int elo) {
  for (final t0 in _tiers) {
    if (elo >= t0.from && elo < t0.to) return t(t0.km, t0.en);
  }
  return t(_tiers.last.km, _tiers.last.en);
}

String _styleLabel(BotStyle s) {
  switch (s) {
    case BotStyle.aggressive:
      return t('⚔ វាយលុក', '⚔ Aggressive');
    case BotStyle.solid:
      return t('🛡 រឹងមាំ', '🛡 Solid');
    case BotStyle.tricky:
      return t('🎭 ល្បិច', '🎭 Tricky');
    case BotStyle.endgame:
      return t('♟ ចុងហ្គេម', '♟ Endgame');
  }
}

class BotMenuScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  const BotMenuScreen(this.eco, {super.key});

  @override
  State<BotMenuScreen> createState() => _BotMenuScreenState();
}

class _BotMenuScreenState extends State<BotMenuScreen> {
  late final List<BotPlayer> _engines;
  BotPlayer? _selected;
  double _slider = 800;
  int _minutes = 10;
  bool _rated = true;
  bool? _white; // true white, false black, null random
  BotStyle? _filter;

  @override
  void initState() {
    super.initState();
    const elos = [1000, 1600, 2200, 2800, 3200];
    _engines = [
      for (int i = 0; i < elos.length; i++)
        BotPlayer(
          id: 'engine_${i + 1}',
          name: 'Fairy-Stockfish ${i + 1}',
          countryCode: 'UN',
          avatar: i + 1,
          style: BotStyle.solid,
          clubId: -1,
          elo: elos[i],
        ),
    ];
    _selected = _nearest(widget.eco.user.elo.toDouble());
    _slider = (_selected?.elo ?? 800).toDouble();
  }

  bool _locked(BotPlayer b) {
    if (AppSettings.unlockAllBots.value) return false;
    final limit = max(widget.eco.user.elo, 600) + 500;
    return b.elo > limit;
  }

  BotPlayer? _nearest(double v) {
    final open = widget.eco.bots.where((b) => !_locked(b)).toList();
    if (open.isEmpty) return null;
    open.sort((a, b) => (a.elo - v).abs().compareTo((b.elo - v).abs()));
    return open.first;
  }

  void _pick(BotPlayer b) {
    if (_locked(b)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('ឈ្នះ bot កម្រិតទាបជាងមុនដើម្បីបើកវា',
            'Win against lower-rated bots to unlock this one')),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    setState(() {
      _selected = b;
      _slider = b.elo.toDouble();
    });
  }

  void _play({bool showTitles = false}) {
    final b = _selected;
    if (b == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          eco: widget.eco,
          bot: b,
          minutes: _minutes,
          casual: !_rated,
          userWhite: _white,
          showTitles: showTitles,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Random match (may pick a titled player), then start.
  void _randomMatch() {
    // Random match: titles are shown inside the game (not in this menu).
    final b = widget.eco.pickRandomOpponent();
    setState(() {
      _selected = b;
      _slider = b.elo.toDouble();
    });
    _play(showTitles: true);
  }

  void _options() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('ពេលវេលា (នាទី)', 'Time (minutes)'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in const [1, 3, 5, 10, 15])
                  ChoiceChip(
                    label: Text('$m'),
                    selected: _minutes == m,
                    onSelected: (_) {
                      setState(() => _minutes = m);
                      setSheet(() {});
                    },
                  ),
              ]),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: true, label: Text(t('ចំណាត់ថ្នាក់', 'Rated'))),
                  ButtonSegment(
                      value: false,
                      label: Text(t('សាកល្បង (Undo)', 'Casual (undo)'))),
                ],
                selected: {_rated},
                onSelectionChanged: (s) {
                  setState(() => _rated = s.first);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.km,
      builder: (context, _, __) => Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: _bg,
          colorScheme: const ColorScheme.dark(primary: _green),
        ),
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              _header(),
              Expanded(child: _scrollArea()),
              _bottomBar(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final sel = _selected;
    final elo = sel?.elo ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: _muted)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: const Color(0xFF4A90D9),
                borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.smart_toy, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(t('បូត', 'Bots'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Spacer(),
          const SizedBox(width: 48),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_tierName(elo),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Text('$elo', style: const TextStyle(fontSize: 18, color: _muted)),
          ]),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            activeTrackColor: const Color(0xFF4A4946),
            inactiveTrackColor: const Color(0xFF3A3835),
            thumbColor: Colors.white,
            overlayColor: const Color(0x22FFFFFF),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            min: 250,
            max: 3200,
            value: _slider.clamp(250.0, 3200.0).toDouble(),
            onChanged: (v) {
              final b = _nearest(v);
              setState(() {
                _slider = v;
                if (b != null) _selected = b;
              });
            },
            onChangeEnd: (_) {
              final b = _selected;
              if (b != null) setState(() => _slider = b.elo.toDouble());
            },
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _chip(t('ទាំងអស់', 'All'), _filter == null, () => setState(() => _filter = null)),
            for (final s in BotStyle.values)
              _chip(_styleLabel(s), _filter == s, () => setState(() => _filter = s)),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: on,
          onSelected: (_) => f(),
        ),
      );

  Widget _scrollArea() {
    final bots = widget.eco.bots
        .where((b) => _filter == null || b.style == _filter)
        .toList()
      ..sort((a, b) => a.elo.compareTo(b.elo));
    final sections = <Widget>[];
    final gms = bots.where((b) => b.isGm).toList()
      ..sort((a, b) => b.elo.compareTo(a.elo));
    if (gms.isNotEmpty) {
      sections.add(_sectionTitle(t('អ្នកលេងកំពូល', 'Top players'), gms.length));
      sections.add(_grid(gms));
    }
    final champs = bots.where((b) => b.seed > 0).toList()
      ..sort((a, b) => a.seed.compareTo(b.seed));
    if (champs.isNotEmpty) {
      sections.add(_sectionTitle(
          t('ជើងខ្លាំងកម្ពុជា', 'Cambodian champions'), champs.length));
      sections.add(_grid(champs));
    }
    if (gms.isNotEmpty || champs.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          t('បូតក្លែងធ្វើដោយកម្មវិធី Elo ជាការប៉ាន់ស្មាន មិនទាក់ទងនឹងអ្នកលេងពិតទេ។',
              'Simulated bots; ratings are approximate and not affiliated with the real players.'),
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B6967)),
        ),
      ));
    }
    for (final tier in _tiers) {
      final list = bots
          .where((b) => !b.isFixed && b.elo >= tier.from && b.elo < tier.to)
          .toList();
      if (list.isEmpty) continue;
      sections.add(_sectionTitle(t(tier.km, tier.en), list.length));
      sections.add(_grid(list));
    }
    if (_filter == null) {
      sections.add(_sectionTitle(t('ម៉ាស៊ីន', 'Engine'), _engines.length));
      sections.add(_grid(_engines));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      children: sections,
    );
  }

  Widget _sectionTitle(String text, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
        child: Row(children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: _muted)),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(color: Color(0xFF6B6967))),
        ]),
      );

  Widget _grid(List<BotPlayer> list) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (final b in list) _botTile(b)],
    );
  }

  Widget _botTile(BotPlayer b) {
    final locked = _locked(b);
    final selected = _selected?.id == b.id;
    return GestureDetector(
      onTap: () => _pick(b),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? _green : Colors.transparent, width: 3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(fit: StackFit.expand, children: [
            LayoutBuilder(
              builder: (c, cs) =>
                  BotAvatar(bot: b, size: cs.maxWidth, rounded: false),
            ),
            if (locked)
              Container(
                color: const Color(0x99000000),
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.only(bottom: 3),
                child: const Icon(Icons.lock, size: 16, color: Colors.white),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final b = _selected;
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (b != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              BotAvatar(bot: b, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(
                      '${b.flag} ${b.name}  ·  ${_styleLabel(b.style)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
              Text('Elo ${b.elo}', style: const TextStyle(color: _muted)),
            ]),
          ),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _options,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: _panel, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.timer_outlined, color: _muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_minutes ${t('នាទី', 'min')} · ${_rated ? t('ចំណាត់ថ្នាក់', 'Rated') : t('សាកល្បង', 'Casual')}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: _muted),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _colorTile(true),
          const SizedBox(width: 6),
          _colorTile(null),
          const SizedBox(width: 6),
          _colorTile(false),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: b == null ? null : _play,
            child: Text(t('លេង', 'Play'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
        )),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            height: 56,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _randomMatch,
              child: const Icon(Icons.casino, size: 28),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _colorTile(bool? white) {
    final on = _white == white;
    Widget child;
    Color bg;
    if (white == true) {
      bg = const Color(0xFFE8E8E8);
      child = const PieceImage(piece: kKhun, size: 34);
    } else if (white == false) {
      bg = const Color(0xFF2A2A2A);
      child = const PieceImage(piece: -kKhun, size: 34);
    } else {
      bg = const Color(0xFF8A8A8A);
      child = const Text('?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white));
    }
    return GestureDetector(
      onTap: () => setState(() => _white = white),
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? _green : Colors.transparent, width: 3),
        ),
        child: child,
      ),
    );
  }
}
