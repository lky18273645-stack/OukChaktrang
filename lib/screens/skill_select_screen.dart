// lib/screens/skill_select_screen.dart
//
// First launch: choose a starting level. The rating starts at the chosen value
// with Rating Deviation 350, so the first games adjust it quickly.

import 'package:flutter/material.dart';

import '../services/glicko.dart';
import '../services/virtual_ecosystem.dart';
import '../ui/app_state.dart';

class SkillSelectScreen extends StatelessWidget {
  final VirtualEcosystem eco;
  final VoidCallback onDone;
  const SkillSelectScreen(this.eco, {super.key, required this.onDone});

  String _blurb(SkillLevel l) {
    switch (l) {
      case SkillLevel.newPlayer:
        return t('ទើបចេះច្បាប់ ឬមិនទាន់ចេះ', 'Just learning the rules');
      case SkillLevel.beginner:
        return t('ចេះច្បាប់ ហើយលេងបានខ្លះៗ', 'Know the rules, play a little');
      case SkillLevel.intermediate:
        return t('លេងញឹកញាប់ ស្គាល់យុទ្ធសាស្ត្រមូលដ្ឋាន', 'Play often, know basic tactics');
      case SkillLevel.advanced:
        return t('ស្គាល់ការបើក និងការរាប់ច្បាស់', 'Solid openings and counting rules');
      case SkillLevel.expert:
        return t('ប្រកួតប្រជែងជាប្រចាំ', 'Regular competitive player');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.km,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(title: Text(t('ជ្រើសកម្រិតរបស់អ្នក', 'Choose your level'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            t('កម្រិតនេះកំណត់ Elo ចាប់ផ្តើម។ ការលេងដំបូងៗនឹងកែតម្រូវវាលឿន។',
                'This sets your starting rating. Your first games adjust it quickly.'),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 14),
          for (final level in SkillLevel.values)
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(t(level.km, level.en),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                subtitle: Text(_blurb(level)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${level.rating}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(t(getPlayerTier(level.rating).km,
                            getPlayerTier(level.rating).en),
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                onTap: () {
                  eco.setStartingLevel(level);
                  onDone();
                },
              ),
            ),
        ]),
      ),
    );
  }
}
