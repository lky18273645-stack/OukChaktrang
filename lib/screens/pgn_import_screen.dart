// lib/screens/pgn_import_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pgn_import.dart';
import '../ui/app_state.dart';
import 'game_review_screen.dart';

class PgnImportScreen extends StatefulWidget {
  const PgnImportScreen({super.key});

  @override
  State<PgnImportScreen> createState() => _PgnImportScreenState();
}

class _PgnImportScreenState extends State<PgnImportScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) {
      setState(() => _ctrl.text = d!.text!);
    }
  }

  void _analyse() {
    final res = parsePgn(_ctrl.text);
    final rec = res.record;
    if (rec == null) {
      setState(() => _message =
          '${t('មិនអាចអានបាន', 'Could not read the PGN')}: ${res.error ?? ''}');
      return;
    }
    setState(() => _message = res.error == null
        ? null
        : '${t('អានបានតែ', 'Read only')} ${res.parsedPlies} ${t('ការដើរ', 'plies')}. ${res.error}');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameReviewScreen(record: rec)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.km,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(title: Text(t('នាំចូល PGN', 'Import PGN'))),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          Text(
            t('បិទភ្ជាប់ PGN របស់អុកចត្រង្គខ្មែរ (ឧ. ពី PyChess)',
                'Paste a Cambodian chess PGN (e.g. from PyChess)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[Variant "Cambodian"]\n\n1. e4 d5 2. Me3 c5 ...',
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
                label: Text(t('បិទភ្ជាប់', 'Paste')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _analyse,
                icon: const Icon(Icons.analytics_outlined),
                label: Text(t('វិភាគ', 'Analyse')),
              ),
            ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_message!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
        ]),
      ),
    );
  }
}
