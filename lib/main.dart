// lib/main.dart  (Step-1 smoke-test shell; real screens come in Step 2)
import 'package:flutter/material.dart';

import 'engine/fairy_engine.dart';
import 'engine/ouk_rules.dart';
import 'services/virtual_ecosystem.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final eco = await VirtualEcosystem.load();
  await eco.onAppOpen();
  runApp(OukApp(eco));
}

class OukApp extends StatelessWidget {
  final VirtualEcosystem eco;
  const OukApp(this.eco, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OukChaktrang.com',
        theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
        home: HomeTest(eco),
      );
}

class HomeTest extends StatefulWidget {
  final VirtualEcosystem eco;
  const HomeTest(this.eco, {super.key});
  @override
  State<HomeTest> createState() => _HomeTestState();
}

class _HomeTestState extends State<HomeTest> {
  String log = '';

  Future<void> _selfTest() async {
    final pos = OukPosition.start();
    final sb = StringBuffer()
      ..writeln('Legal moves at start: ${pos.legalMoves().length}')
      ..writeln('perft(2): ${pos.perft(2)}');
    try {
      final eng = FairyEngine();
      await eng.start();
      final ev = await eng.analyse(pos.toFen(), movetimeMs: 500);
      sb.writeln('Fairy-Stockfish: best ${ev.bestMove}, cp ${ev.cp}');
      await eng.dispose();
    } catch (e) {
      sb.writeln('Engine error: $e');
    }
    setState(() => log = sb.toString());
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.eco.leaderboard(limit: 10);
    return Scaffold(
      appBar: AppBar(title: const Text('OukChaktrang.com')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        FilledButton(onPressed: _selfTest, child: const Text('Run rules + engine self-test')),
        if (log.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(log)),
        const Divider(),
        const Text('Leaderboard (live simulation)', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final e in top)
          ListTile(
            dense: true,
            leading: Text('#${e.rank}'),
            title: Text('${e.flag} ${e.name}'),
            trailing: Text('${e.elo}'),
          ),
      ]),
    );
  }
}
