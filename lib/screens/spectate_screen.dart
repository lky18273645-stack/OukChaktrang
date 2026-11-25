// lib/screens/spectate_screen.dart
//
// Watch an ongoing tournament game. Offline there is no real live feed, so the
// two players are simulated by Fairy-Stockfish at their ratings. The moves are
// NOT the moves behind the recorded tournament result.

import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/fairy_engine.dart';
import '../engine/ouk_rules.dart';
import '../services/tournament_engine.dart';
import '../ui/app_state.dart';
import '../ui/cc_theme.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/ouk_board_widget.dart';

class SpectateScreen extends StatefulWidget {
  final TnPlayer white;
  final TnPlayer black;
  const SpectateScreen({super.key, required this.white, required this.black});

  @override
  State<SpectateScreen> createState() => _SpectateScreenState();
}

class _SpectateScreenState extends State<SpectateScreen> {
  final FairyEngine _engine = FairyEngine();
  final Random _rng = Random();
  OukPosition _pos = OukPosition.start();
  Move? _last;
  bool _stop = false;
  bool _over = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _stop = true;
    _engine.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      await _engine.start();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    while (!_stop && mounted && !_pos.isGameOver && _pos.fullmove < 100) {
      final p = _pos.turn == Side.white ? widget.white : widget.black;
      Move? m;
      try {
        final ev = await _engine.analyse(_pos.toFen(),
            movetimeMs: 70, botElo: p.rating.clamp(400, 3200).toInt());
        m = _pos.findLegal(ev.bestMove);
      } catch (_) {}
      if (_stop || !mounted) return;
      final legal = _pos.legalMoves();
      if (legal.isEmpty) break;
      m ??= legal[_rng.nextInt(legal.length)];
      setState(() {
        _pos = _pos.makeMove(m!);
        _last = m;
      });
      await Future.delayed(Duration(milliseconds: 600 + _rng.nextInt(700)));
    }
    if (mounted) setState(() => _over = true);
  }

  Widget _bar(TnPlayer p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          if (p.title != null && p.title!.isNotEmpty) ...[
            TitleBadge(title: p.title!, fontSize: 11),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text('${p.flag} ${p.name} (${p.rating})',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ccTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('កំពុងមើល', 'Spectating')),
          actions: [
            if (!_over && _error == null)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                    child: Text('● LIVE',
                        style: TextStyle(color: ccRed, fontWeight: FontWeight.bold))),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            _bar(widget.black),
            OukBoardWidget(
              pos: _pos,
              flipped: false,
              selected: null,
              targets: const {},
              last: _last,
              premove: null,
              arrows: const [],
              onTap: (_) {},
              onArrow: (_) {},
            ),
            _bar(widget.white),
            if (_over)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(t('ហ្គេមក្លែងធ្វើបានចប់', 'Simulated game finished'),
                    style: const TextStyle(color: ccMuted)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(t('ម៉ាស៊ីនមិនដំណើរការ', 'Engine unavailable'),
                    style: const TextStyle(color: ccRed)),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                t('ការមើលជាការក្លែងធ្វើដោយម៉ាស៊ីន មិនមែនជាកំណត់ត្រាពិតនៃការប្រកួតនេះទេ។',
                    'Simulated by the engine at both ratings; not the recorded game.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: ccMuted, fontSize: 11),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
