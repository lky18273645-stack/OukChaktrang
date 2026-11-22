// lib/widgets/bot_avatar.dart
//
// Original cartoon avatars drawn with Canvas (no image files needed).
// Every bot gets a unique face from its avatar number + name.

import 'package:flutter/material.dart';

import '../services/virtual_ecosystem.dart';

const List<Color> _skins = [
  Color(0xFFF1C27D), Color(0xFFE0AC69), Color(0xFFC68642),
  Color(0xFF8D5524), Color(0xFFFFDBAC), Color(0xFFD2A679),
];
const List<Color> _hairs = [
  Color(0xFF2B1B10), Color(0xFF5A3825), Color(0xFF121212),
  Color(0xFFB5651D), Color(0xFF8A8A8A), Color(0xFF6B3E26),
];
const List<Color> _shirts = [
  Color(0xFF3F7CAC), Color(0xFFB8433A), Color(0xFF4C9A6A), Color(0xFFD9A441),
  Color(0xFF7A5BA6), Color(0xFFEEEEEE), Color(0xFF2F4858),
];

class BotAvatar extends StatelessWidget {
  final BotPlayer bot;
  final double size;
  final bool rounded;
  final bool showTag; // small GM / seed tag in the corner (off by default)

  const BotAvatar({
    super.key,
    required this.bot,
    this.size = 56,
    this.rounded = true,
    this.showTag = false,
  });

  bool get _isEngine => bot.id.startsWith('engine_');

  int _seedOf() =>
      bot.avatar * 7 + bot.name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xFFFF);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(rounded ? size * 0.12 : 0);
    if (_isEngine) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          width: size,
          height: size,
          color: const Color(0xFF3A3835),
          alignment: Alignment.center,
          child: Stack(alignment: Alignment.center, children: [
            Icon(Icons.memory, size: size * 0.8, color: const Color(0xFF6B6967)),
            Text('${bot.avatar}',
                style: TextStyle(
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ]),
        ),
      );
    }
    if (bot.isFixed) {
      // Optional picture you provide: assets/images/avatars/<bot id>.png
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(fit: StackFit.expand, children: [
            Image(
              image: ResizeImage(
                  AssetImage('assets/images/avatars/${bot.id}.png'),
                  width: 256),
              fit: BoxFit.cover,
              errorBuilder: (c, e, st) =>
                  CustomPaint(painter: _FacePainter(_seedOf())),
            ),
            if (showTag)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: size * 0.07, vertical: size * 0.02),
                color: const Color(0xFFD4A017),
                child: Text(bot.seed > 0 ? '★${bot.seed}' : (bot.shownTitle ?? 'GM'),
                    style: TextStyle(
                        fontSize: size * 0.16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
              ),
            ),
          ]),
        ),
      );
    }
    final seed =
        bot.avatar * 7 + bot.name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xFFFF);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _FacePainter(seed)),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  final int seed;
  _FacePainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final skin = _skins[seed % _skins.length];
    final hair = _hairs[(seed ~/ 3) % _hairs.length];
    final shirt = _shirts[(seed ~/ 5) % _shirts.length];
    final hairStyle = (seed ~/ 2) % 5; // 0 short 1 long 2 cap 3 bald 4 bun
    final beard = seed % 7 == 0;

    canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = const Color(0xFF3A3835));

    // shoulders
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.14, s * 0.74, s * 0.72, s * 0.5),
        topLeft: Radius.circular(s * 0.28),
        topRight: Radius.circular(s * 0.28),
      ),
      Paint()..color = shirt,
    );
    // neck
    canvas.drawRect(Rect.fromLTWH(s * 0.43, s * 0.60, s * 0.14, s * 0.18),
        Paint()..color = skin);

    final head = Offset(s * 0.5, s * 0.44);
    final hr = s * 0.2;

    // long hair behind the head
    if (hairStyle == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.27, s * 0.2, s * 0.46, s * 0.55),
            Radius.circular(s * 0.2)),
        Paint()..color = hair,
      );
    }
    // bun
    if (hairStyle == 4) {
      canvas.drawCircle(Offset(s * 0.5, s * 0.17), s * 0.08, Paint()..color = hair);
    }

    canvas.drawCircle(head, hr, Paint()..color = skin);

    // hair on top
    final hairPaint = Paint()..color = hair;
    if (hairStyle == 0 || hairStyle == 1 || hairStyle == 4) {
      canvas.drawArc(Rect.fromCircle(center: head, radius: hr * 1.04), 3.1416,
          3.1416, true, hairPaint);
    } else if (hairStyle == 2) {
      canvas.drawArc(Rect.fromCircle(center: head, radius: hr * 1.06), 3.1416,
          3.1416, true, Paint()..color = const Color(0xFF2F4858));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.46, s * 0.27, s * 0.34, s * 0.05),
            Radius.circular(s * 0.02)),
        Paint()..color = const Color(0xFF2F4858),
      );
    }

    // beard
    if (beard) {
      canvas.drawArc(
        Rect.fromCircle(center: head, radius: hr * 1.02),
        0.2,
        2.74,
        true,
        Paint()..color = hair,
      );
      canvas.drawCircle(Offset(s * 0.5, s * 0.5), hr * 0.55, Paint()..color = skin);
    }

    // eyes
    final eye = Paint()..color = const Color(0xFF222222);
    canvas.drawCircle(Offset(s * 0.43, s * 0.43), s * 0.018, eye);
    canvas.drawCircle(Offset(s * 0.57, s * 0.43), s * 0.018, eye);
    // smile
    canvas.drawArc(
      Rect.fromCenter(center: Offset(s * 0.5, s * 0.5), width: s * 0.14, height: s * 0.09),
      0.2,
      2.7,
      false,
      Paint()
        ..color = const Color(0xFF8B2E2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) => old.seed != seed;
}


/// Red title badge (GM, IM, FM, CM, NM, WGM, WIM, WFM, WCM).
class TitleBadge extends StatelessWidget {
  final String title;
  final double fontSize;
  const TitleBadge({super.key, required this.title, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.45, vertical: fontSize * 0.12),
      decoration: BoxDecoration(
        color: const Color(0xFFB33430),
        borderRadius: BorderRadius.circular(fontSize * 0.3),
      ),
      child: Text(title,
          style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              height: 1.1)),
    );
  }
}
