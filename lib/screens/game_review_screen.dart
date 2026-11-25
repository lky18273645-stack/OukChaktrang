// lib/screens/game_review_screen.dart
//
// "វិភាគអុកចត្រង្គខ្មែរ" - Game Review & Post-Match Analysis (dark mode).
// Tabs: សង្ខេប (Summary) | ការដើរ (Moves / analysis board) | PGN | ការកំណត់ (Settings)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/fairy_engine.dart';
import '../engine/ouk_rules.dart';
import '../services/game_analyzer.dart';
import '../ui/app_state.dart';
import '../ui/board_view.dart';
import '../widgets/ouk_board_widget.dart';
import '../widgets/eval_graph_widget.dart';

const Color _bg = Color(0xFF1E1E1E);
const Color _bar = Color(0xFF262522);
const Color _card = Color(0xFF2B2A28);
const Color _muted = Color(0xFFA0A0A0);
const Color _green = Color(0xFF81B64C);

class GameReviewScreen extends StatefulWidget {
  final GameRecord record;
  const GameReviewScreen({super.key, required this.record});

  @override
  State<GameReviewScreen> createState() => _GameReviewScreenState();
}

class _GameReviewScreenState extends State<GameReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final FairyEngine _engine = FairyEngine();
  late final GameAnalyzer _analyzer;

  GameReview? _review;
  String? _error;
  bool _analysing = false;
  int _done = 0;
  int _total = 1;

  int _cursor = 0; // number of plies played in the displayed position
  late bool _flipped;
  Timer? _play;
  bool _playing = false;

  int _ms = 300;
  late int _threads;
  bool _showArrows = true;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _analyzer = GameAnalyzer(_engine);
    _flipped = !widget.record.userIsWhite;
    _threads = FairyEngine.cores.clamp(1, 4).toInt();
    _run();
  }

  @override
  void dispose() {
    _play?.cancel();
    _analyzer.cancel();
    _tabs.dispose();
    _scroll.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _analysing = true;
      _error = null;
      _review = null;
      _done = 0;
      _total = widget.record.moves.length + 1;
    });
    try {
      if (!_engine.running) await _engine.start();
      await _engine.setOption('Threads', _threads);
      await _engine.setOption('Hash', 32);
      final r = await _analyzer.analyze(
        widget.record,
        movetimeMs: _ms,
        threads: _threads,
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _review = r;
        _cursor = 0;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysing = false;
          _error = '$e';
        });
      }
    }
  }

  // ---------------------------------------------------------------- cursor

  void _goto(int c) {
    final r = _review;
    if (r == null) return;
    final next = c.clamp(0, r.plyCount).toInt();
    setState(() => _cursor = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || _cursor == 0) return;
      final target = ((_cursor - 1) * 78.0 - 120)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  void _togglePlay() {
    final r = _review;
    if (r == null) return;
    if (_playing) {
      _play?.cancel();
      setState(() => _playing = false);
      return;
    }
    if (_cursor >= r.plyCount) _goto(0);
    setState(() => _playing = true);
    _play = Timer.periodic(const Duration(milliseconds: 900), (tm) {
      if (!mounted) return;
      if (_cursor >= r.plyCount) {
        tm.cancel();
        setState(() => _playing = false);
      } else {
        _goto(_cursor + 1);
      }
    });
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
              Container(
                color: _bar,
                child: TabBar(
                  controller: _tabs,
                  indicatorColor: _green,
                  labelColor: Colors.white,
                  unselectedLabelColor: _muted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: [
                    Tab(text: t('សង្ខេប', 'Summary')),
                    Tab(text: t('ការដើរ', 'Moves')),
                    const Tab(text: 'PGN'),
                    Tab(text: t('ការកំណត់', 'Settings')),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final ready = _review != null;
    return Container(
      color: _bar,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(children: [
        Expanded(
          child: Text(t('វិភាគអុកចត្រង្គខ្មែរ', 'Ouk Chaktrang Analysis'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ready ? const Color(0x3381B64C) : const Color(0x33FFC107),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            ready
                ? '✓ Fairy-Stockfish · ${_threads}T'
                : (_error != null ? '✕ engine' : '… Fairy-Stockfish'),
            style: TextStyle(
                fontSize: 11,
                color: ready ? _green : const Color(0xFFFFC107)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('បិទ', 'Close')),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: _run, child: Text(t('ព្យាយាមម្តងទៀត', 'Retry'))),
          ]),
        ),
      );
    }
    if (_analysing || _review == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('កំពុងវិភាគហ្គេម…', 'Analysing the game…'),
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 8),
            Text('$_done / $_total', style: const TextStyle(color: _muted)),
          ]),
        ),
      );
    }
    return TabBarView(
      controller: _tabs,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _summaryTab(_review!),
        _movesTab(_review!),
        _pgnTab(_review!),
        _settingsTab(),
      ],
    );
  }

  // ============================================================ SUMMARY TAB

  Widget _summaryTab(GameReview r) {
    final rec = r.record;
    return ListView(padding: const EdgeInsets.all(12), children: [
      // --- evaluation graph
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('គុណសម្បត្តិតាមការវាយតម្លៃ', 'Evaluation advantage'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        EvalGraphWidget(
          evalWhite: r.evalWhite,
          cursor: _cursor,
          middleStart: r.middleStart,
          endStart: r.endStart,
          classes: r.moves.map<MoveClass?>((m) => m.cls).toList(),
          khmer: AppSettings.km.value,
          onSelect: _goto,
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text(
              _cursor == 0
                  ? t('ទីតាំងចាប់ផ្តើម', 'Start position')
                  : '${_numberOf(r, _cursor - 1)} ${r.moves[_cursor - 1].san} '
                      '${r.moves[_cursor - 1].cls.symbol}  ${r.evalText(_cursor)}',
              style: const TextStyle(color: _muted),
            ),
          ),
          TextButton(
            onPressed: () => _tabs.animateTo(1),
            child: Text(t('មើលលើក្តារ →', 'Open board →')),
          ),
        ]),
      ])),
      const SizedBox(height: 12),

      // --- phase accuracy
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _dot(const Color(0xFFEEEEEE)),
          const SizedBox(width: 6),
          Expanded(child: Text(rec.whiteName, overflow: TextOverflow.ellipsis)),
          _dot(const Color(0xFF7A7A7A)),
          const SizedBox(width: 6),
          Expanded(child: Text(rec.blackName, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 10),
        _phaseRow(t('បើក', 'Opening'), r.white.phaseAccuracy[0], r.black.phaseAccuracy[0]),
        _phaseRow(t('កណ្ដាល', 'Middlegame'), r.white.phaseAccuracy[1], r.black.phaseAccuracy[1]),
        _phaseRow(t('បញ្ចប់', 'Endgame'), r.white.phaseAccuracy[2], r.black.phaseAccuracy[2]),
      ])),
      const SizedBox(height: 12),

      // --- player cards
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _playerCard(rec.whiteName, const Color(0xFFEEEEEE), r.white)),
        const SizedBox(width: 10),
        Expanded(child: _playerCard(rec.blackName, const Color(0xFF7A7A7A), r.black)),
      ]),
      const SizedBox(height: 12),

      // --- classification table
      _panel(Column(children: [
        for (final c in MoveClass.values) _classRow(c, r),
      ])),
      const SizedBox(height: 20),
    ]);
  }

  Widget _panel(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(10)),
        child: child,
      );

  Widget _dot(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.white24)),
      );

  Widget _phaseRow(String label, double? w, double? b) {
    Widget bar(double? v, Color c) => Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v == null ? 0 : v / 100,
                minHeight: 8,
                color: c,
                backgroundColor: const Color(0xFF3A3A3A),
              ),
            ),
          ),
          SizedBox(
              width: 46,
              child: Text(v == null ? '—' : '${v.round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12))),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        bar(w, const Color(0xFFEEEEEE)),
        const SizedBox(height: 4),
        bar(b, const Color(0xFF9A9A9A)),
      ]),
    );
  }

  Widget _pill(String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withAlpha(45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(120))),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );

  Widget _playerCard(String name, Color sideColor, SideSummary s) {
    return _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _dot(sideColor),
        const SizedBox(width: 6),
        Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold))),
      ]),
      _pill('🎯 ${t('ភាពត្រឹមត្រូវ', 'Accuracy')}៖ ${s.accuracy.toStringAsFixed(1)}%', _green),
      _pill(
          '📈 ${t('Elo ប៉ាន់ស្មាន', 'Est. Elo')}៖ ${s.performanceElo == 0 ? '—' : s.performanceElo}',
          const Color(0xFF5C8BB0)),
    ]));
  }

  Widget _badge(MoveClass c, {double size = 24}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
        child: Text(c.symbol,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.46)),
      );

  Widget _classRow(MoveClass c, GameReview r) {
    final w = r.white.counts[c] ?? 0;
    final b = r.black.counts[c] ?? 0;
    TextStyle st(int v) => TextStyle(
        fontSize: 16,
        fontWeight: v > 0 ? FontWeight.bold : FontWeight.normal,
        color: v > 0 ? c.color : _muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text('$w', textAlign: TextAlign.center, style: st(w))),
        SizedBox(
          width: 170,
          child: Row(children: [
            _badge(c),
            const SizedBox(width: 8),
            Expanded(
                child: Text(AppSettings.km.value ? c.km : c.en,
                    style: const TextStyle(fontSize: 14))),
          ]),
        ),
        Expanded(child: Text('$b', textAlign: TextAlign.center, style: st(b))),
      ]),
    );
  }

  String _numberOf(GameReview r, int ply) {
    final mv = r.moves[ply];
    final p = r.positions[ply];
    return mv.side == Side.white ? '${p.fullmove}.' : '${p.fullmove}...';
  }

  // =========================================================== MOVES TAB

  Widget _movesTab(GameReview r) {
    final rec = r.record;
    final pos = r.positions[_cursor];
    final MoveReview? mr = _cursor > 0 ? r.moves[_cursor - 1] : null;

    // arrows + badge for the selected move
    final arrows = <Arrow>[];
    int? badgeSq;
    String? badgeText;
    Color? badgeColor;
    Move? last;
    if (mr != null) {
      last = Move.tryParse(mr.uci);
      if (last != null) {
        badgeSq = last.to;
        badgeText = mr.cls.symbol;
        badgeColor = mr.cls.color;
      }
      if (_showArrows) {
        final best = mr.bestUci;
        final played = mr.uci.substring(0, 4);
        if (best != null && best.length >= 4) {
          if (best.substring(0, 4) != played) {
            arrows.add(Arrow(parseSquare(played.substring(0, 2)),
                parseSquare(played.substring(2, 4)), const Color(0xCC4A90D9)));
          }
          arrows.add(Arrow(parseSquare(best.substring(0, 2)),
              parseSquare(best.substring(2, 4)), const Color(0xCC81B64C)));
        }
      }
    }

    final topIsWhite = _flipped;
    final whiteAcc = r.white.accuracy;
    final blackAcc = r.black.accuracy;

    Widget playerHeader(bool white) {
      final acc = white ? whiteAcc : blackAcc;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          _dot(white ? const Color(0xFFEEEEEE) : const Color(0xFF7A7A7A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(white ? rec.whiteName : rec.blackName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0x3381B64C),
                borderRadius: BorderRadius.circular(10)),
            child: Text('${acc.toStringAsFixed(1)}%',
                style: const TextStyle(
                    color: _green, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ]),
      );
    }

    return SingleChildScrollView(
      child: Column(children: [
        _moveScroller(r),
        playerHeader(topIsWhite),
        LayoutBuilder(builder: (context, c) {
          final bw = c.maxWidth - 28;
          final cp = r.evalWhite[_cursor];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _EvalBar(
                height: bw,
                cp: cp,
                label: r.evalText(_cursor),
                whiteAtBottom: !_flipped,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: bw,
                child: OukBoardWidget(
                  pos: pos,
                  flipped: _flipped,
                  selected: null,
                  targets: const {},
                  last: last,
                  premove: null,
                  arrows: arrows,
                  onTap: (_) {},
                  onArrow: (_) {},
                  badgeSquare: badgeSq,
                  badgeText: badgeText,
                  badgeColor: badgeColor,
                ),
              ),
            ]),
          );
        }),
        playerHeader(!topIsWhite),
        _feedbackBox(r, mr),
        _controls(r),
        _summaryIcons(r),
        const SizedBox(height: 14),
      ]),
    );
  }

  Widget _moveScroller(GameReview r) {
    return Container(
      height: 44,
      color: _bar,
      child: r.moves.isEmpty
          ? const SizedBox()
          : ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemExtent: 78,
              itemCount: r.moves.length,
              itemBuilder: (context, i) {
                final m = r.moves[i];
                final p = r.positions[i];
                final label = m.side == Side.white
                    ? '${p.fullmove}. ${m.san}'
                    : (i == 0 ? '${p.fullmove}... ${m.san}' : m.san);
                final sel = _cursor == i + 1;
                return InkWell(
                  onTap: () => _goto(i + 1),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF4A4946) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12.5, color: Colors.white),
                        children: [
                          TextSpan(text: label),
                          TextSpan(
                              text: ' ${m.cls.symbol}',
                              style: TextStyle(
                                  color: m.cls.color, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _feedbackBox(GameReview r, MoveReview? mr) {
    final bad = mr != null &&
        (mr.cls == MoveClass.inaccuracy ||
            mr.cls == MoveClass.mistake ||
            mr.cls == MoveClass.miss ||
            mr.cls == MoveClass.blunder);
    final String line1;
    if (mr == null) {
      line1 = t('ទីតាំងចាប់ផ្តើម', 'Start position');
    } else {
      line1 = '${_numberOf(r, mr.ply)} ${mr.san} ${mr.cls.symbol} '
          '${AppSettings.km.value ? mr.cls.km : mr.cls.en}'
          '${bad && mr.bestSan != null ? ' · ${t('ល្អជាងគឺ', 'Better is')} ${mr.bestSan}' : ''}';
    }
    final ls = r.lines[_cursor];
    final depth = ls.isNotEmpty ? ls.first.depth : 0;
    final terminal = r.positions[_cursor].isGameOver;
    final String line2 = terminal
        ? '${r.record.result}'
        : '${r.evalText(_cursor)} (${t('ជម្រៅ', 'depth')} $depth) ${r.pvText(_cursor)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (mr != null) ...[_badge(mr.cls, size: 22), const SizedBox(width: 8)],
          Expanded(
            child: Text(line1,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: mr?.cls.color ?? Colors.white)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(line2, style: const TextStyle(color: _muted, fontSize: 13)),
      ]),
    );
  }

  Widget _controls(GameReview r) {
    Widget btn(IconData icon, VoidCallback f, {String? tip}) => IconButton(
          onPressed: f,
          tooltip: tip,
          iconSize: 30,
          icon: Icon(icon),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        btn(Icons.swap_vert, () => setState(() => _flipped = !_flipped), tip: 'Flip'),
        btn(Icons.first_page, () => _goto(0)),
        btn(Icons.chevron_left, () => _goto(_cursor - 1)),
        btn(_playing ? Icons.pause : Icons.play_arrow, _togglePlay),
        btn(Icons.chevron_right, () => _goto(_cursor + 1)),
        btn(Icons.last_page, () => _goto(r.plyCount)),
      ]),
    );
  }

  Widget _summaryIcons(GameReview r) {
    final counts = r.totalCounts;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration:
          BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final c in MoveClass.values)
          Expanded(
            child: Opacity(
              opacity: (counts[c] ?? 0) > 0 ? 1.0 : 0.35,
              child: Column(children: [
                _badge(c, size: 22),
                const SizedBox(height: 3),
                Text('${counts[c] ?? 0}', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ============================================================== PGN TAB

  Widget _pgnTab(GameReview r) {
    final pgn = r.toPgn();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: pgn));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('បានចម្លង', 'Copied'))));
          },
          icon: const Icon(Icons.copy),
          label: Text(t('ចម្លង PGN', 'Copy PGN')),
        ),
      ]),
      const SizedBox(height: 12),
      _panel(SelectableText(
        pgn,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
      )),
    ]);
  }

  // ======================================================== SETTINGS TAB

  Widget _settingsTab() {
    final maxThreads = FairyEngine.cores.clamp(1, 4).toInt();
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text(t('ពេលវិភាគក្នុងមួយទីតាំង', 'Analysis time per position'),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final ms in const [150, 300, 600, 1000])
          ChoiceChip(
            label: Text('${ms}ms'),
            selected: _ms == ms,
            onSelected: (_) => setState(() => _ms = ms),
          ),
      ]),
      const SizedBox(height: 16),
      Text(t('ចំនួន Thread', 'Engine threads'),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (int th = 1; th <= maxThreads; th++)
          ChoiceChip(
            label: Text('${th}T'),
            selected: _threads == th,
            onSelected: (_) => setState(() => _threads = th),
          ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t('បង្ហាញព្រួញ', 'Show arrows')),
        value: _showArrows,
        onChanged: (v) => setState(() => _showArrows = v),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _analysing
            ? null
            : () {
                _tabs.animateTo(0);
                _run();
              },
        icon: const Icon(Icons.refresh),
        label: Text(t('វិភាគឡើងវិញ', 'Re-analyse')),
      ),
      const SizedBox(height: 14),
      Text(
        t('ពេលវេលាកាន់តែយូរ ការវាយតម្លៃកាន់តែត្រឹមត្រូវ ប៉ុន្តែការវិភាគយឺតជាង។',
            'More time per position gives better evaluations but a slower review.'),
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    ]);
  }
}

/// Vertical evaluation bar: White's share fills from the White side of the board.
class _EvalBar extends StatelessWidget {
  final double height;
  final int cp; // White's view
  final String label;
  final bool whiteAtBottom;

  const _EvalBar({
    required this.height,
    required this.cp,
    required this.label,
    required this.whiteAtBottom,
  });

  @override
  Widget build(BuildContext context) {
    final pct = winPercent(cp.clamp(-2000, 2000).toInt()) / 100.0;
    final whiteLeads = cp >= 0;
    final text = label.replaceFirst('+', '').replaceFirst('-', '');
    final textWidget = SizedBox(
      width: 22,
      child: FittedBox(
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: whiteLeads ? Colors.black87 : Colors.white)),
      ),
    );
    // Label sits on the side of whoever is ahead.
    final labelAtBottom = whiteLeads ? whiteAtBottom : !whiteAtBottom;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: height,
        color: const Color(0xFF3A3A3A),
        child: Stack(children: [
          Align(
            alignment:
                whiteAtBottom ? Alignment.bottomCenter : Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: height * pct,
              color: const Color(0xFFEEEEEE),
            ),
          ),
          Align(
            alignment:
                labelAtBottom ? Alignment.bottomCenter : Alignment.topCenter,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: textWidget),
          ),
        ]),
      ),
    );
  }
}
