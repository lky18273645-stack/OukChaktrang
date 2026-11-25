// lib/ui/game_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/fairy_engine.dart';
import '../engine/ouk_rules.dart';
import '../screens/game_review_screen.dart';
import '../services/game_analyzer.dart';
import '../services/profile_models.dart';
import '../services/tournament_engine.dart' show TourneyGameInfo;
import '../services/virtual_ecosystem.dart';
import 'app_state.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/ouk_board_widget.dart';
import 'board_view.dart';

class GameScreen extends StatefulWidget {
  final VirtualEcosystem eco;
  final BotPlayer bot;
  final int minutes;
  final bool casual; // casual: undo allowed, rating unchanged
  final bool? userWhite; // null = random colour
  final bool showTitles; // show GM / IM / seed badges (Random match)
  final TourneyGameInfo? tournament; // set when this game belongs to a tournament
  final int? userClockMs; // berserk: the user's clock in ms (opponent keeps full time)

  const GameScreen({
    super.key,
    required this.eco,
    required this.bot,
    this.minutes = 10,
    this.casual = false,
    this.userWhite,
    this.showTitles = false,
    this.tournament,
    this.userClockMs,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final Random _rng = Random();
  final FairyEngine _engine = FairyEngine();
  bool _engineReady = false;
  String? _engineError;

  late final Side _userSide;
  late final Side _botSide;
  late final BotGameBrain _brain;

  OukPosition pos = OukPosition.start();
  final List<OukPosition> _history = [];
  final List<Move> _moves = [];
  Move? _last;

  int? _selected;
  Set<int> _targets = {};
  Move? _premove;
  final List<Arrow> _arrows = [];

  late int _whiteMs;
  late int _blackMs;
  Timer? _ticker;
  DateTime _lastTick = DateTime.now();

  bool _thinking = false;
  bool _over = false;
  String? _chat;
  final List<int> _botEvals = []; // bot's view (cp) before each of its moves

  BotPlayer get bot => widget.bot;

  @override
  void initState() {
    super.initState();
    _userSide = (widget.userWhite ?? _rng.nextBool()) ? Side.white : Side.black;
    _botSide = _userSide.opp;
    _brain = widget.eco.brainFor(bot);
    _whiteMs = _blackMs = widget.minutes * 60000;
    final uc = widget.userClockMs;
    if (uc != null) {
      if (_userSide == Side.white) {
        _whiteMs = uc;
      } else {
        _blackMs = uc;
      }
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _initEngine();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    try {
      await _engine.start();
      _engineReady = true;
    } catch (e) {
      _engineError = '$e';
    }
    if (!mounted) return;
    setState(() {});
    if (pos.turn == _botSide) _botTurn();
  }

  // ---------------------------------------------------------------- clocks

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMilliseconds;
    _lastTick = now;
    if (_over || _moves.length < 2 || !mounted) return;
    setState(() {
      if (pos.turn == Side.white) {
        _whiteMs -= dt;
      } else {
        _blackMs -= dt;
      }
    });
    if (_whiteMs <= 0) {
      _whiteMs = 0;
      _finish(_userSide == Side.white ? 0.0 : 1.0, 'timeout');
    } else if (_blackMs <= 0) {
      _blackMs = 0;
      _finish(_userSide == Side.black ? 0.0 : 1.0, 'timeout');
    }
  }

  String _fmt(int ms) {
    final total = max(0, ms);
    final m = total ~/ 60000;
    final s = (total % 60000) ~/ 1000;
    if (total < 10000) {
      final tenth = (total % 1000) ~/ 100;
      return '$m:${s.toString().padLeft(2, '0')}.$tenth';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------- user input

  void _onTap(int sq) {
    if (_over) return;
    _arrows.clear();
    final p = pos.pieceAt(sq);
    final mine = p != 0 && p.sign == _userSide.sign;
    if (pos.turn == _userSide && !_thinking) {
      _tapOnMyTurn(sq, mine);
    } else {
      _tapForPremove(sq, mine);
    }
    setState(() {});
  }

  // ---- drag & drop (tap-to-move still works)
  bool _canDrag(int sq) {
    if (_over) return false;
    final p = pos.pieceAt(sq);
    return p != 0 && p.sign == _userSide.sign;
  }

  void _onDragStart(int sq) {
    if (_over) return;
    _arrows.clear();
    setState(() {
      if (pos.turn == _userSide && !_thinking) {
        _select(sq);
      } else {
        _selected = sq; // premove source
        _targets = {};
      }
    });
  }

  void _onDragMove(int from, int to) {
    if (_over) return;
    if (pos.turn == _userSide && !_thinking) {
      final c = pos.legalMovesFrom(from).where((m) => m.to == to).toList();
      if (c.isNotEmpty) {
        _playUser(c.first);
        setState(() {});
        return;
      }
      setState(() => _select(from)); // illegal drop: keep it selected
    } else {
      setState(() {
        _premove = Move(from, to);
        _selected = null;
        _targets = {};
      });
    }
  }

  void _select(int sq) {
    _selected = sq;
    _targets = pos.legalMovesFrom(sq).map((m) => m.to).toSet();
  }

  void _clearSelection() {
    _selected = null;
    _targets = {};
  }

  void _tapOnMyTurn(int sq, bool mine) {
    final sel = _selected;
    if (sel != null) {
      final cands = pos.legalMovesFrom(sel).where((m) => m.to == sq).toList();
      if (cands.isNotEmpty) {
        _playUser(cands.first);
        return;
      }
    }
    if (mine && sq != sel) {
      _select(sq);
    } else {
      _clearSelection();
    }
  }

  void _tapForPremove(int sq, bool mine) {
    final sel = _selected;
    if (sel != null) {
      if (sq != sel) {
        _premove = Move(sel, sq);
      }
      _selected = null;
      _targets = {};
      return;
    }
    if (_premove != null) {
      _premove = null; // tap cancels an existing premove
      if (!mine) return;
    }
    if (mine) {
      _selected = sq;
      _targets = {};
    }
  }

  void _playUser(Move m) {
    _chat = null;
    _commit(m);
    if (_over) return;
    _botTurn();
  }

  void _commit(Move m) {
    _history.add(pos);
    _moves.add(m);
    _last = m;
    pos = pos.makeMove(m);
    _clearSelection();
    final st = pos.status;
    if (st != GameStatus.ongoing) {
      double score;
      String reason;
      switch (st) {
        case GameStatus.checkmate:
          final winner = pos.turn.opp;
          score = winner == _userSide ? 1.0 : 0.0;
          reason = 'checkmate';
          break;
        case GameStatus.stalemate:
          score = 0.5;
          reason = 'stalemate';
          break;
        case GameStatus.drawCounting:
          score = 0.5;
          reason = 'counting';
          break;
        case GameStatus.drawInsufficient:
          score = 0.5;
          reason = 'insufficient';
          break;
        default:
          score = 0.5;
          reason = 'repetition';
      }
      _finish(score, reason);
    }
  }

  // ------------------------------------------------------------------- bot

  int _moveTimeFor(int elo) {
    if (elo < 800) return 60;
    if (elo < 1500) return 150;
    if (elo < 2200) return 300;
    return 500;
  }

  Future<void> _botTurn() async {
    if (_over || _thinking || pos.turn != _botSide) return;
    setState(() => _thinking = true);
    final startPos = pos;
    final watch = Stopwatch()..start();

    EngineEval? ev;
    if (_engineReady) {
      try {
        ev = await _engine.analyse(pos.toFen(),
            movetimeMs: _moveTimeFor(bot.elo), botElo: bot.elo);
      } catch (_) {
        ev = null;
      }
    }
    if (!mounted || _over || !identical(pos, startPos)) {
      _thinking = false;
      return;
    }
    final legal = pos.legalMoves();
    if (legal.isEmpty) {
      _thinking = false;
      return;
    }
    final EngineEval? e = ev;
    final Move mv = (e == null ? null : pos.findLegal(e.bestMove)) ??
        legal[_rng.nextInt(legal.length)];

    final int swing =
        (e == null || _botEvals.isEmpty) ? 0 : (e.cp - _botEvals.last).abs();
    final delay = thinkingDelay(
      legalMoveCount: legal.length,
      evalSwingCp: swing,
      elo: bot.elo,
      isOpening: _moves.length < 8,
      clockMsLeft: _botSide == Side.white ? _whiteMs : _blackMs,
      rng: _rng,
    );
    final remaining = delay - watch.elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (!mounted || _over || !identical(pos, startPos)) {
      _thinking = false;
      return;
    }

    setState(() {
      _thinking = false;
      if (e != null) _botEvals.add(e.cp);
      _commit(mv);
    });
    if (_over) return;

    // Smart bot behaviour: resign / draw offer.
    if (e != null) {
      final d = _brain.afterBotMove(evalCp: e.cp, isEndgame: pos.isEndgame);
      if (d.action == BotAction.resign) {
        setState(() => _chat = d.chat);
        _finish(1.0, 'bot_resign');
        return;
      }
      if (d.action == BotAction.offerDraw) {
        setState(() => _chat = d.chat);
        await _botOffersDraw(d.chat ?? '');
        if (_over) return;
      }
    }
    _runPremove();
  }

  void _runPremove() {
    final pm = _premove;
    if (pm == null || _over) return;
    _premove = null;
    if (pos.turn != _userSide) return;
    final m = pos.findLegal(pm.uci);
    if (m != null) _playUser(m);
    if (mounted) setState(() {});
  }

  Future<void> _botOffersDraw(String text) async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('សំណើសុំស្មើ', 'Draw offer')),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('បដិសេធ', 'Decline'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('ព្រមព្រៀង', 'Accept'))),
        ],
      ),
    );
    if (accept == true) _finish(0.5, 'agreement');
  }

  // ---------------------------------------------------------------- buttons

  Future<void> _offerDraw() async {
    if (_over || _thinking || pos.turn != _userSide) return;
    int cp = 0;
    if (_engineReady) {
      try {
        final ev = await _engine.analyse(pos.toFen(), movetimeMs: 150);
        cp = -ev.cp; // side to move is the user -> flip to the bot's view
      } catch (_) {}
    }
    final r = _brain.respondToDraw(
      evalCp: cp,
      isEndgame: pos.isEndgame,
      fullMove: pos.fullmove,
      countingActive: pos.counting.active,
    );
    if (!mounted) return;
    setState(() => _chat = r.chat);
    if (r.accept) _finish(0.5, 'agreement');
  }

  Future<void> _confirmResign() async {
    if (_over) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('ចុះចាញ់?', 'Resign?')),
        content: Text(t('តើអ្នកពិតជាចង់ចុះចាញ់មែនទេ?',
            'Do you really want to resign this game?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('ទេ', 'No'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('ចុះចាញ់', 'Resign'))),
        ],
      ),
    );
    if (ok == true) _finish(0.0, 'resign');
  }

  void _undo() {
    if (!widget.casual || _thinking || _over) return;
    if (pos.turn != _userSide || _history.length < 2) return;
    setState(() {
      pos = _history[_history.length - 2];
      _history.removeRange(_history.length - 2, _history.length);
      _moves.removeRange(_moves.length - 2, _moves.length);
      _last = _moves.isEmpty ? null : _moves.last;
      if (_botEvals.isNotEmpty) _botEvals.removeLast();
      _clearSelection();
      _premove = null;
      _chat = null;
    });
  }

  // ----------------------------------------------------------------- finish

  double _accuracy() {
    final n = _botEvals.length;
    if (n < 2) return 0;
    double total = 0;
    for (int i = 1; i < n; i++) {
      total += (_botEvals[i] - _botEvals[i - 1]).clamp(0, 1000).toDouble();
    }
    final avg = total / (n - 1);
    final acc = 103.17 * exp(-0.004354 * avg) - 3.17;
    return acc.clamp(0.0, 100.0).toDouble();
  }

  Future<void> _finish(double score, String reason) async {
    if (_over) return;
    _over = true;
    _thinking = false;
    await Future<void>.delayed(Duration.zero); // never run inside a setState
    final acc = _accuracy();
    final info = pos.counting;
    final escape = reason == 'counting' &&
        info.attacker != null &&
        info.attacker != _userSide;
    final GameSummary summary;
    if (widget.casual && widget.tournament == null) {
      final e = widget.eco.user.elo;
      summary = GameSummary(score, reason, bot, e, e, 0, acc, const []);
    } else {
      summary = widget.eco.recordUserGame(
        opponent: bot,
        score: score,
        reason: reason,
        accuracy: acc,
        wasCountingEscape: escape,
        minutes: widget.minutes,
        tournamentId: widget.tournament?.tournamentId,
      );
    }
    final tn = widget.tournament;
    if (tn != null) widget.eco.reportTourneyGame(tn, score, _moves.length);
    unawaited(widget.eco.onGameFinished());
    if (!mounted) return;
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) _showSummary(summary);
  }

  String _reasonText(String r) {
    switch (r) {
      case 'checkmate':
        return t('ម៉ាត', 'Checkmate');
      case 'resign':
        return t('ចុះចាញ់', 'Resignation');
      case 'bot_resign':
        return t('គូប្រជែងចុះចាញ់', 'Opponent resigned');
      case 'timeout':
        return t('អស់ម៉ោង', 'Timeout');
      case 'stalemate':
        return t('អស់ផ្លូវដើរ', 'Stalemate');
      case 'counting':
        return t('ច្បាប់រាប់ (ឆាប់រាប់)', 'Counting rule');
      case 'agreement':
        return t('ព្រមព្រៀងស្មើ', 'Draw agreed');
      case 'insufficient':
        return t('កម្លាំងមិនគ្រប់គ្រាន់', 'Insufficient material');
      default:
        return t('ដើរដដែលៗ', 'Repetition');
    }
  }

  GameRecord _record(GameSummary s) {
    final me = widget.eco.user.name;
    final white = _userSide == Side.white ? me : bot.name;
    final black = _userSide == Side.black ? me : bot.name;
    final whiteWon = s.isWin == (_userSide == Side.white);
    final result = s.isDraw ? '1/2-1/2' : (whiteWon ? '1-0' : '0-1');
    return GameRecord(
      startFen: OukPosition.startFen,
      moves: _moves.map((m) => m.uci).toList(),
      whiteName: white,
      blackName: black,
      result: result,
      userIsWhite: _userSide == Side.white,
    );
  }

  void _showSummary(GameSummary s) {
    final Color banner = s.isWin
        ? const Color(0xFF2E7D32)
        : (s.isDraw ? const Color(0xFF616161) : const Color(0xFFC62828));
    final String title = s.isWin
        ? t('🏆 ជ័យជម្នះ!', '🏆 Victory!')
        : (s.isDraw ? t('🤝 ស្មើ', '🤝 Draw') : t('💔 បរាជ័យ', '💔 Defeat'));
    final Color eloColor = s.delta > 0
        ? const Color(0xFF2E7D32)
        : (s.delta < 0 ? const Color(0xFFC62828) : Colors.grey);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: banner, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                Text(_reasonText(s.reason),
                    style: const TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _avatarCol(widget.eco.user.name, 'U', Colors.brown),
              const Text('vs', style: TextStyle(fontSize: 16)),
              _avatarCol('${bot.flag} ${bot.name}', bot.name,
                  Colors.primaries[bot.avatar % Colors.primaries.length]),
            ]),
            const SizedBox(height: 12),
            Text(
              s.accuracy > 0
                  ? '${t('ភាពត្រឹមត្រូវ', 'Accuracy')}: ${s.accuracy.toStringAsFixed(1)}%'
                  : '${t('ភាពត្រឹមត្រូវ', 'Accuracy')}: —',
            ),
            const SizedBox(height: 6),
            widget.casual
                ? Text(t('ហ្គេមសាកល្បង (មិនប្តូរ Elo)', 'Casual game (no rating change)'),
                    style: const TextStyle(color: Colors.grey))
                : Text('Elo  ${s.eloLabel}',
                    style: TextStyle(
                        color: eloColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
            for (final a in s.newAchievements)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('🏅 ${t(a.titleKm, a.titleEn)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dctx);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameReviewScreen(record: _record(s)),
                    ),
                  );
                },
                icon: const Icon(Icons.analytics_outlined),
                label: Text(t('វិភាគអុកចត្រង្គខ្មែរ', 'Game review')),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(dctx);
                    Navigator.pop(context, false);
                  },
                  child: Text(t('ត្រឡប់', 'Back')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(dctx);
                    if (widget.tournament != null) {
                      Navigator.pop(context, true); // lobby starts the next game
                      return;
                    }
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GameScreen(
                          eco: widget.eco,
                          bot: bot,
                          minutes: widget.minutes,
                          casual: widget.casual,
                          userWhite: _userSide == Side.black,
                          showTitles: widget.showTitles,
                        ),
                      ),
                    );
                  },
                  child: Text(widget.tournament != null
                      ? t('ហ្គេមបន្ទាប់', 'Next game')
                      : t('លេងម្តងទៀត', 'Rematch')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _avatarCol(String label, String initialFrom, Color color) {
    return Column(children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: color,
        child: Text(_initial(initialFrom),
            style: const TextStyle(color: Colors.white, fontSize: 20)),
      ),
      const SizedBox(height: 4),
      SizedBox(
          width: 110,
          child: Text(label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis)),
    ]);
  }

  String _initial(String s) =>
      s.isEmpty ? '?' : String.fromCharCodes(s.runes.take(1));

  // ------------------------------------------------------------------- UI

  List<int> _capturedBy(Side by) {
    // Pieces of the opposite colour that are missing from the board.
    const initial = {kNeang: 1, kKol: 2, kSes: 2, kTouk: 2, kTrey: 8};
    final have = <int, int>{};
    for (int sq = 0; sq < 64; sq++) {
      final p = pos.pieceAt(sq);
      if (p != 0 && p.sign == by.opp.sign) {
        have[p.abs()] = (have[p.abs()] ?? 0) + 1;
      }
    }
    final out = <int>[];
    for (final type in [kTouk, kKol, kSes, kNeang, kTrey]) {
      final missing = initial[type]! - (have[type] ?? 0);
      for (int i = 0; i < missing; i++) {
        out.add(type);
      }
    }
    return out;
  }

  Widget _playerBar({
    required String name,
    required String flag,
    required int elo,
    required Color color,
    required Side side,
    BotPlayer? bot,
    String? title,
  }) {
    final captured = _capturedBy(side);
    final bal = pos.materialBalance;
    final adv = side == Side.white ? bal : -bal;
    final active = !_over && pos.turn == side && _moves.length >= 2;
    final ms = side == Side.white ? _whiteMs : _blackMs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(children: [
        bot != null
            ? BotAvatar(bot: bot, size: 40)
            : CircleAvatar(
                backgroundColor: color,
                child: Text(_initial(name),
                    style: const TextStyle(color: Colors.white)),
              ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (title != null) ...[
                TitleBadge(title: title),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text('$flag $name ($elo)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
            Row(children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final p in captured)
                      Align(
                        widthFactor: 0.62,
                        child: PieceImage(piece: side.opp.sign * p, size: 22),
                      ),
                  ]),
                ),
              ),
              if (adv > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('+$adv',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF263238) : const Color(0xFFCFD8DC),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _fmt(ms),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: active
                  ? (ms < 20000 ? const Color(0xFFFF8A80) : Colors.white)
                  : Colors.black87,
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flipped = _userSide == Side.black;
    final info = pos.counting;
    final botColor = Colors.primaries[bot.avatar % Colors.primaries.length];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.casual
            ? t('លេងសាកល្បង', 'Casual game')
            : t('ហ្គេមចំណាត់ថ្នាក់', 'Rated game')),
        actions: [
          if (_thinking)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          _playerBar(
            name: bot.name,
            flag: bot.flag,
            elo: bot.elo,
            color: botColor,
            side: _botSide,
            bot: bot,
            title: widget.showTitles ? bot.shownTitle : null,
          ),
          OukBoardWidget(
            pos: pos,
            flipped: flipped,
            selected: _selected,
            targets: _targets,
            last: _last,
            premove: _premove,
            arrows: _arrows,
            onTap: _onTap,
            canDrag: _canDrag,
            onDragStart: _onDragStart,
            onDragMove: _onDragMove,
            onArrow: (a) => setState(() {
              final i = _arrows.indexWhere((x) => x.from == a.from && x.to == a.to);
              if (i >= 0) {
                _arrows.removeAt(i);
              } else {
                _arrows.add(a);
              }
            }),
          ),
          _playerBar(
            name: widget.eco.user.name,
            flag: flagEmoji(widget.eco.user.countryCode),
            elo: widget.eco.user.cat(categoryForMinutes(widget.minutes)).rating.round(),
            color: Colors.brown,
            side: _userSide,
            title: widget.eco.user.title,
          ),
          if (info.active)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Chip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: Text(
                    '${t('ច្បាប់រាប់', 'Counting')} ${info.label}'
                    '${info.type == CountType.piece ? (info.attacker == _userSide ? ' ▲' : ' ▼') : ''}'),
              ),
            ),
          if (_chat != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('🤖 $_chat'),
            ),
          if (_engineError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                t('ម៉ាស៊ីនមិនដំណើរការ — bot ដើរចៃដន្យ',
                    'Engine unavailable — bot plays random moves'),
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(children: [
              if (widget.casual)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _undo,
                    icon: const Icon(Icons.undo),
                    label: Text(t('ដកថយ', 'Undo')),
                  ),
                ),
              if (widget.casual) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _over ? null : _offerDraw,
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(t('សុំស្មើ', 'Draw')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828)),
                  onPressed: _over ? null : _confirmResign,
                  icon: const Icon(Icons.flag),
                  label: Text(t('ចុះចាញ់', 'Resign')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
