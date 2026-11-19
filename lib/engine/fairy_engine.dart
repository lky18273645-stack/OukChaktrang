// lib/engine/fairy_engine.dart
//
// Thin UCI wrapper around the Fairy-Stockfish executable that the GitHub
// workflow ships as android/app/src/main/jniLibs/arm64-v8a/libfairystockfish.so.
// Android extracts it into nativeLibraryDir (see useLegacyPackaging), where it
// is allowed to execute. MainActivity exposes that directory over a channel.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class EngineEval {
  /// Centipawns from the SIDE TO MOVE's view (mate scores mapped to +-100000).
  final int cp;
  final int? mateIn;
  final String bestMove;
  const EngineEval(this.cp, this.mateIn, this.bestMove);
}

/// One principal variation (MultiPV line). cp is from the side to move's view.
class EngineLine {
  final int cp;
  final int? mate;
  final int depth;
  final List<String> pv; // UCI moves
  const EngineLine({
    required this.cp,
    required this.mate,
    required this.depth,
    required this.pv,
  });
}

class FairyEngine {
  static const MethodChannel _chan = MethodChannel('ouk/native');

  Process? _proc;
  final StreamController<String> _lines = StreamController<String>.broadcast();
  bool get running => _proc != null;

  static int get cores => Platform.numberOfProcessors;

  Future<void> start({bool useNnue = true}) async {
    if (_proc != null) return;
    final dir = await _chan.invokeMethod<String>('nativeLibDir');
    _proc = await Process.start('$dir/libfairystockfish.so', const []);
    _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_lines.add);
    _proc!.stderr.drain<void>();

    await _ask('uci', 'uciok');
    _send('setoption name UCI_Variant value cambodian');
    if (useNnue) {
      final path = await _installNnue();
      if (path != null) _send('setoption name EvalFile value $path');
    }
    await _ask('isready', 'readyok');
  }

  /// Copies assets/nnue/cambodian.nnue to app storage (if bundled).
  Future<String?> _installNnue() async {
    try {
      final data = await rootBundle.load('assets/nnue/cambodian.nnue');
      final docs = await getApplicationSupportDirectory();
      final f = File('${docs.path}/cambodian.nnue');
      if (!await f.exists() || await f.length() != data.lengthInBytes) {
        await f.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
      }
      return f.path;
    } catch (_) {
      return null; // not bundled -> classical evaluation
    }
  }

  void _send(String cmd) => _proc?.stdin.writeln(cmd);

  Future<String> _ask(String cmd, String until,
      {Duration timeout = const Duration(seconds: 20)}) {
    final f = _lines.stream
        .firstWhere((l) => l.startsWith(until))
        .timeout(timeout);
    _send(cmd);
    return f;
  }

  /// Set a UCI option and wait until the engine is ready again.
  Future<void> setOption(String name, Object value) async {
    _send('setoption name $name value $value');
    await _ask('isready', 'readyok');
  }

  /// Map a bot Elo (400..3000) to Fairy-Stockfish "Skill Level" 0..20.
  static int skillForElo(int elo) =>
      (((elo - 400) / 2600.0) * 20).round().clamp(0, 20).toInt();

  /// Analyse [fen] for [movetimeMs]; returns the best move and score.
  Future<EngineEval> analyse(String fen,
      {int movetimeMs = 300, int? botElo}) async {
    _send('setoption name MultiPV value 1');
    if (botElo != null) {
      _send('setoption name Skill Level value ${skillForElo(botElo)}');
    } else {
      _send('setoption name Skill Level value 20');
    }
    _send('position fen $fen');
    int cp = 0;
    int? mate;
    final done = Completer<String>();
    final sub = _lines.stream.listen((l) {
      if (l.startsWith('info') && l.contains(' score ')) {
        final m = RegExp(r'score (cp|mate) (-?\d+)').firstMatch(l);
        if (m != null) {
          final v = int.parse(m.group(2)!);
          if (m.group(1) == 'cp') {
            cp = v;
            mate = null;
          } else {
            mate = v;
            cp = v > 0 ? 100000 : -100000;
          }
        }
      } else if (l.startsWith('bestmove') && !done.isCompleted) {
        final parts = l.split(' ');
        done.complete(parts.length > 1 ? parts[1] : '');
      }
    });
    _send('go movetime $movetimeMs');
    final best =
        await done.future.timeout(Duration(milliseconds: movetimeMs + 15000));
    await sub.cancel();
    return EngineEval(cp, mate, best);
  }

  /// Full-strength MultiPV analysis (used by Game Review). Lines are sorted by
  /// rank (best first). Scores are from the side to move's view.
  Future<List<EngineLine>> analyseMulti(String fen,
      {int movetimeMs = 300, int multiPv = 2}) async {
    _send('setoption name Skill Level value 20');
    _send('setoption name MultiPV value $multiPv');
    _send('position fen $fen');
    final found = <int, EngineLine>{};
    final done = Completer<void>();
    final sub = _lines.stream.listen((l) {
      if (l.startsWith('info') && l.contains(' pv ') && l.contains(' score ')) {
        final sc = RegExp(r'score (cp|mate) (-?\d+)').firstMatch(l);
        if (sc == null) return;
        final mpv =
            int.tryParse(RegExp(r'multipv (\d+)').firstMatch(l)?.group(1) ?? '1') ??
                1;
        final dep =
            int.tryParse(RegExp(r' depth (\d+)').firstMatch(l)?.group(1) ?? '0') ??
                0;
        final v = int.parse(sc.group(2)!);
        final isMate = sc.group(1) == 'mate';
        final pv = l.substring(l.indexOf(' pv ') + 4).trim().split(' ');
        found[mpv] = EngineLine(
          cp: isMate ? (v > 0 ? 1 : -1) * (10000 - v.abs() * 10) : v,
          mate: isMate ? v : null,
          depth: dep,
          pv: pv,
        );
      } else if (l.startsWith('bestmove') && !done.isCompleted) {
        done.complete();
      }
    });
    _send('go movetime $movetimeMs');
    try {
      await done.future.timeout(Duration(milliseconds: movetimeMs + 15000));
    } finally {
      await sub.cancel();
      _send('setoption name MultiPV value 1');
    }
    final keys = found.keys.toList()..sort();
    return [for (final k in keys) found[k]!];
  }

  Future<void> dispose() async {
    _send('quit');
    _proc?.kill();
    _proc = null;
    await _lines.close();
  }
}
