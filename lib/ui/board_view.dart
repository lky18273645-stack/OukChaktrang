// lib/ui/board_view.dart

import 'package:flutter/material.dart';

import '../engine/ouk_rules.dart';
import 'app_state.dart';

class Arrow {
  final int from;
  final int to;
  const Arrow(this.from, this.to);
}

String pieceGlyph(int type) {
  switch (type) {
    case kKhun:
      return '\u265A';
    case kNeang:
      return '\u265B';
    case kKol:
      return '\u265D';
    case kSes:
      return '\u265E';
    case kTouk:
      return '\u265C';
    default:
      return '\u265F\uFE0E'; // text presentation, not emoji
  }
}

/// A chess glyph with an outline so both colours read on any square.
class PieceGlyph extends StatelessWidget {
  final int piece; // signed piece id
  final double size;
  const PieceGlyph({super.key, required this.piece, required this.size});

  @override
  Widget build(BuildContext context) {
    final white = piece > 0;
    final g = pieceGlyph(piece.abs());
    final fill = white ? Colors.white : const Color(0xFF1A1A1A);
    final outline = white ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8);
    return Stack(alignment: Alignment.center, children: [
      Text(g,
          style: TextStyle(
            fontSize: size,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.07
              ..color = outline,
          )),
      Text(g, style: TextStyle(fontSize: size, height: 1.0, color: fill)),
    ]);
  }
}

Rect _sqRect(int sq, double s, bool flipped) {
  final file = sq & 7;
  final rank = sq >> 3;
  final col = flipped ? 7 - file : file;
  final row = flipped ? rank : 7 - rank;
  return Rect.fromLTWH(col * s, row * s, s, s);
}

class BoardView extends StatefulWidget {
  final OukPosition pos;
  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final Move? last;
  final Move? premove;
  final List<Arrow> arrows;
  final void Function(int sq) onTap;
  final void Function(Arrow arrow) onArrow;

  const BoardView({
    super.key,
    required this.pos,
    required this.flipped,
    required this.selected,
    required this.targets,
    required this.last,
    required this.premove,
    required this.arrows,
    required this.onTap,
    required this.onArrow,
  });

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  int? _aStart;
  int? _aEnd;

  int? _sqAt(Offset p, double s) {
    final col = (p.dx / s).floor();
    final row = (p.dy / s).floor();
    if (col < 0 || col > 7 || row < 0 || row > 7) return null;
    final file = widget.flipped ? 7 - col : col;
    final rank = widget.flipped ? row : 7 - row;
    return rank * 8 + file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = currentBoardTheme;
    return LayoutBuilder(builder: (context, c) {
      final size = c.maxWidth.isFinite ? c.maxWidth : 360.0;
      final s = size / 8;

      final pieces = <Widget>[];
      for (int sq = 0; sq < 64; sq++) {
        final pc = widget.pos.pieceAt(sq);
        if (pc == 0) continue;
        final r = _sqRect(sq, s, widget.flipped);
        pieces.add(Positioned(
          left: r.left,
          top: r.top,
          width: s,
          height: s,
          child: IgnorePointer(
            child: Center(child: PieceGlyph(piece: pc, size: s * 0.78)),
          ),
        ));
      }

      Arrow? live;
      if (_aStart != null && _aEnd != null) live = Arrow(_aStart!, _aEnd!);

      return SizedBox(
        width: size,
        height: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final sq = _sqAt(d.localPosition, s);
            if (sq != null) widget.onTap(sq);
          },
          onLongPressStart: (d) {
            final sq = _sqAt(d.localPosition, s);
            setState(() {
              _aStart = sq;
              _aEnd = sq;
            });
          },
          onLongPressMoveUpdate: (d) {
            final sq = _sqAt(d.localPosition, s);
            if (sq != null && sq != _aEnd) setState(() => _aEnd = sq);
          },
          onLongPressEnd: (d) {
            final a = _aStart;
            final b = _aEnd;
            setState(() {
              _aStart = null;
              _aEnd = null;
            });
            if (a != null && b != null) widget.onArrow(Arrow(a, b));
          },
          child: Stack(children: [
            CustomPaint(
              size: Size(size, size),
              painter: _SquaresPainter(
                pos: widget.pos,
                flipped: widget.flipped,
                theme: theme,
                selected: widget.selected,
                targets: widget.targets,
                last: widget.last,
                premove: widget.premove,
              ),
            ),
            ...pieces,
            IgnorePointer(
              child: CustomPaint(
                size: Size(size, size),
                painter: _ArrowPainter(widget.arrows, live, widget.flipped),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _SquaresPainter extends CustomPainter {
  final OukPosition pos;
  final bool flipped;
  final BoardTheme theme;
  final int? selected;
  final Set<int> targets;
  final Move? last;
  final Move? premove;

  _SquaresPainter({
    required this.pos,
    required this.flipped,
    required this.theme,
    required this.selected,
    required this.targets,
    required this.last,
    required this.premove,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 8;
    final p = Paint();

    for (int sq = 0; sq < 64; sq++) {
      final dark = (((sq & 7) + (sq >> 3)) % 2 == 0);
      p.color = dark ? theme.dark : theme.light;
      canvas.drawRect(_sqRect(sq, s, flipped), p);
    }

    void tint(int sq, Color c) {
      p.color = c;
      canvas.drawRect(_sqRect(sq, s, flipped), p);
    }

    final lm = last;
    if (lm != null) {
      tint(lm.from, theme.lastMove);
      tint(lm.to, theme.lastMove);
    }
    final pm = premove;
    if (pm != null) {
      tint(pm.from, const Color(0x77E53935));
      tint(pm.to, const Color(0x77E53935));
    }
    final sel = selected;
    if (sel != null) tint(sel, theme.select);

    // King in check.
    if (pos.inCheck) {
      final ks = pos.kingSquare(pos.turn);
      if (ks >= 0) {
        final r = _sqRect(ks, s, flipped);
        final paint = Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xDDFF1744), Color(0x00FF1744)],
          ).createShader(r);
        canvas.drawRect(r, paint);
      }
    }

    // Legal move indicators.
    final dot = Paint()..color = const Color(0x55000000);
    final ring = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09;
    for (final sq in targets) {
      final c = _sqRect(sq, s, flipped).center;
      if (pos.pieceAt(sq) != 0) {
        canvas.drawCircle(c, s * 0.45, ring);
      } else {
        canvas.drawCircle(c, s * 0.16, dot);
      }
    }

    // Coordinates.
    void label(String text, Offset at, bool onDark) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: s * 0.2,
            fontWeight: FontWeight.bold,
            color: onDark ? theme.light : theme.dark,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    for (int col = 0; col < 8; col++) {
      final file = flipped ? 7 - col : col;
      final sq = flipped ? (7 * 8 + file) : file; // bottom-row square
      final dark = (((sq & 7) + (sq >> 3)) % 2 == 0);
      label(String.fromCharCode(97 + file),
          Offset(col * s + s * 0.78, 8 * s - s * 0.26), dark);
    }
    for (int row = 0; row < 8; row++) {
      final rank = flipped ? row : 7 - row;
      final file = flipped ? 7 : 0;
      final sq = rank * 8 + file;
      final dark = (((sq & 7) + (sq >> 3)) % 2 == 0);
      label('${rank + 1}', Offset(s * 0.06, row * s + s * 0.04), dark);
    }
  }

  @override
  bool shouldRepaint(covariant _SquaresPainter old) => true;
}

class _ArrowPainter extends CustomPainter {
  final List<Arrow> arrows;
  final Arrow? live;
  final bool flipped;
  _ArrowPainter(this.arrows, this.live, this.flipped);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 8;
    final all = <Arrow>[...arrows];
    if (live != null) all.add(live!);
    for (final a in all) {
      final from = _sqRect(a.from, s, flipped).center;
      final to = _sqRect(a.to, s, flipped).center;
      final color = const Color(0xCCF5A623);
      if (a.from == a.to) {
        canvas.drawCircle(
            from,
            s * 0.46,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.08);
        continue;
      }
      final d = to - from;
      final len = d.distance;
      final dir = d / len;
      final head = s * 0.42;
      final tip = to - dir * (s * 0.08);
      final base = tip - dir * head;
      final n = Offset(-dir.dy, dir.dx);
      canvas.drawLine(
          from + dir * (s * 0.22),
          base + dir * (head * 0.2),
          Paint()
            ..color = color
            ..strokeWidth = s * 0.16
            ..strokeCap = StrokeCap.butt);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + n.dx * head * 0.5, base.dy + n.dy * head * 0.5)
        ..lineTo(base.dx - n.dx * head * 0.5, base.dy - n.dy * head * 0.5)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => true;
}
