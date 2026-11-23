// lib/widgets/dir_widgets.dart  -  shared pieces for the ranking and bot profiles
import 'package:flutter/material.dart';

import '../services/bot_directory.dart';
import '../ui/cc_theme.dart';
import 'bot_avatar.dart';

/// 10000 -> "10,000"
String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}

Color rankColor(int rank) =>
    rank == 1 ? ccGold : (rank == 2 ? ccSilver : (rank == 3 ? ccBronze : ccMuted));

/// "12 min ago" style text (Khmer or English).
String agoText(int ms, bool khmer) {
  final m = ms ~/ 60000;
  if (m < 60) return khmer ? '$m នាទីមុន' : '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return khmer ? '$h ម៉ោងមុន' : '${h}h ago';
  final d = h ~/ 24;
  return khmer ? '$d ថ្ងៃមុន' : '${d}d ago';
}

/// Avatar of a directory player (named bots keep their own picture).
class DirAvatar extends StatelessWidget {
  final DirBot bot;
  final double size;
  const DirAvatar(this.bot, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final e = bot.eco;
    if (e != null) return BotAvatar(bot: e, size: size);
    return SeedAvatar(seed: bot.faceSeed, size: size);
  }
}

/// One ranking row: rank, avatar, title badge, flag + username, rating.
class PlayerRow extends StatelessWidget {
  final int rank;
  final Widget avatar;
  final String? title;
  final String flag;
  final String name;
  final int rating;
  final bool highlight;
  final VoidCallback? onTap;

  const PlayerRow({
    super.key,
    required this.rank,
    required this.avatar,
    required this.title,
    required this.flag,
    required this.name,
    required this.rating,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 64,
        color: highlight ? const Color(0x2281B64C) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SizedBox(
            width: 58,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text('#${fmtInt(rank)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: rankColor(rank))),
            ),
          ),
          avatar,
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              if (title != null && title!.isNotEmpty) ...[
                TitleBadge(title: title!, fontSize: 11),
                const SizedBox(width: 6),
              ],
              Text(flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                        fontSize: 15)),
              ),
            ]),
          ),
          Text(fmtInt(rating),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
      ),
    );
  }
}
