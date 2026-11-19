// lib/widgets/eval_graph_widget.dart
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/game_analyzer.dart';

/// Area chart of the evaluation (White's view) over the whole game.
/// Index i of [evalWhite] = position after i plies. Tap or drag to pick a move.
class EvalGraphWidget extends StatelessWidget {
  final List<int> evalWhite; // centipawns, White's view
  final int cursor; // selected position index
  final int middleStart; // cursor index where the middlegame starts (-1 none)
  final int endStart; // cursor index where the endgame starts (-1 none)
  final List<MoveClass?> classes; // class of the move leading to position i (i>=1)
  final ValueChanged<int> onSelect;
  final double height;
  final bool khmer;

  const EvalGraphWidget({
    super.key,
    required this.evalWhite,
    required this.cursor,
    required this.middleStart,
    required this.endStart,
    required this.onSelect,
    this.classes = const [],
    this.height = 150,
    this.khmer = true,
  });

  int _indexAt(double dx, double width) {
    final n = evalWhite.length;
    if (n <= 1) return 0;
    final i = (dx / width * (n - 1)).round();
    return i.clamp(0, n - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onSelect(_indexAt(d.localPosition.dx, w)),
        onHorizontalDragUpdate: (d) =>
            onSelect(_indexAt(d.localPosition.dx, w)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: w,
            height: height,
            child: CustomPaint(
              painter: _GraphPainter(
                evalWhite: evalWhite,
                cursor: cursor,
                middleStart: middleStart,
                endStart: endStart,
                classes: classes,
                khmer: khmer,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _GraphPainter extends CustomPainter {
  final List<int> evalWhite;
  final int cursor;
  final int middleStart;
  final int endStart;
  final List<MoveClass?> classes;
  final bool khmer;

  _GraphPainter({
    required this.evalWhite,
    required this.cursor,
    required this.middleStart,
    required this.endStart,
    required this.classes,
    required this.khmer,
  });

  // Map centipawns to 0..1 (1 = White winning) with the same S-curve as win %.
  double _y01(int cp) => winPercent(cp.clamp(-1500, 1500).toInt()) / 100.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final n = evalWhite.length;

    // Background (Black's territory).
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF2B2B2B));
    if (n < 2) return;

    double xOf(int i) => i / (n - 1) * w;
    double yOf(int i) => h - _y01(evalWhite[i]) * h;

    // White's area.
    final area = Path()..moveTo(0, h);
    for (int i = 0; i < n; i++) {
      area.lineTo(xOf(i), yOf(i));
    }
    area
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(area, Paint()..color = const Color(0xFFE8E8E8));

    // Outline of the curve.
    final line = Path()..moveTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) {
      line.lineTo(xOf(i), yOf(i));
    }
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF9E9E9E));

    // Dashed midline (equal position).
    _dashedLine(canvas, Offset(0, h / 2), Offset(w, h / 2),
        const Color(0x99FF8A65));

    // Phase dividers + labels.
    final bounds = <int>[0];
    if (middleStart > 0) bounds.add(middleStart);
    if (endStart > 0) bounds.add(endStart);
    bounds.add(n - 1);
    final names = [
      khmer ? 'បើក' : 'Opening',
      khmer ? 'កណ្ដាល' : 'Middle',
      khmer ? 'បញ្ចប់' : 'End',
    ];
    // Which labels exist depends on which boundaries exist.
    final labels = <String>[names[0]];
    if (middleStart > 0) labels.add(names[1]);
    if (endStart > 0) labels.add(names[2]);
    for (int k = 0; k < labels.length; k++) {
      final x0 = xOf(bounds[k]);
      final x1 = xOf(bounds[k + 1]);
      if (k > 0) {
        _dashedLine(canvas, Offset(x0, 0), Offset(x0, h), const Color(0x88FFFFFF));
      }
      final tp = TextPainter(
        text: TextSpan(
          text: labels[k],
          style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x0 + max(4.0, (x1 - x0 - tp.width) / 2), 4));
    }

    // Coloured dots for notable moves.
    for (int i = 1; i < n && i - 1 < classes.length + 1; i++) {
      final idx = i - 1;
      if (idx >= classes.length) break;
      final cl = classes[idx];
      if (cl == null) continue;
      if (cl == MoveClass.blunder ||
          cl == MoveClass.mistake ||
          cl == MoveClass.miss ||
          cl == MoveClass.brilliant ||
          cl == MoveClass.great) {
        canvas.drawCircle(Offset(xOf(i), yOf(i)), 3, Paint()..color = cl.color);
      }
    }

    // Selected position.
    final cs = cursor.clamp(0, n - 1).toInt();
    final cx = xOf(cs);
    canvas.drawLine(Offset(cx, 0), Offset(cx, h),
        Paint()..color = const Color(0x55FFFFFF)..strokeWidth = 1);
    canvas.drawCircle(Offset(cx, yOf(cs)), 6, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(cx, yOf(cs)),
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF81B64C));
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    double t = 0;
    while (t < len) {
      canvas.drawLine(a + dir * t, a + dir * min(t + 5, len), paint);
      t += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
