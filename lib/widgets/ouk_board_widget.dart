// lib/widgets/ouk_board_widget.dart
//
// Ouk Chaktrang board that renders YOUR artwork:
//   assets/images/board/board.png            (full 8x8 board)
//   assets/images/pieces/{w,b}_{khun,neang,kol,ses,touk,trey}.png
//
// Layers (bottom -> top):
//   board.png -> tints (last move / premove / selection / check glow)
//   -> piece sprites (animated) -> legal-move dots -> arrows + classification badge
//   -> dragged piece
// If an image is missing the widget falls back to painted squares / glyph pieces,
// so the app never breaks.

import 'package:flutter/material.dart';

import '../engine/ouk_rules.dart';
import '../ui/app_state.dart';
import '../ui/board_view.dart' show Arrow, PieceGlyph;

const String kBoardAsset = 'assets/images/board/board.png';

/// If board.png has an outer frame/border, set this to the fraction of the image
/// width that the frame takes on EACH side (e.g. 0.03 = 3 %). 0 = squares fill
/// the whole image.
const double kBoardInset = 0.0;

String pieceAsset(int piece) {
  final side = piece > 0 ? 'w' : 'b';
  String name;
  switch (piece.abs()) {
    case kKhun:
      name = 'khun';
      break;
    case kNeang:
      name = 'neang';
      break;
    case kKol:
      name = 'kol';
      break;
    case kSes:
      name = 'ses';
      break;
    case kTouk:
      name = 'touk';
      break;
    default:
      name = 'trey';
  }
  return 'assets/images/pieces/${side}_$name.png';
}

ImageProvider pieceProvider(int piece) =>
    ResizeImage(AssetImage(pieceAsset(piece)), width: 192);

ImageProvider get boardProvider =>
    ResizeImage(AssetImage(kBoardAsset), width: 1200);

/// A piece sprite (also used for the captured-pieces row).
class PieceImage extends StatelessWidget {
  final int piece; // signed piece id
  final double size;
  const PieceImage({super.key, required this.piece, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image(
        image: pieceProvider(piece),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (c, e, s) => Center(
          child: PieceGlyph(piece: piece, size: size * 0.85),
        ),
      ),
    );
  }
}

class _Geo {
  final double off; // frame offset
  final double s; // square size
  final bool flipped;
  const _Geo(this.off, this.s, this.flipped);

  Rect rect(int sq) {
    final file = sq & 7;
    final rank = sq >> 3;
    final col = flipped ? 7 - file : file;
    final row = flipped ? rank : 7 - rank;
    return Rect.fromLTWH(off + col * s, off + row * s, s, s);
  }

  int? sqAt(Offset p) {
    final x = p.dx - off;
    final y = p.dy - off;
    if (x < 0 || y < 0) return null;
    final col = (x / s).floor();
    final row = (y / s).floor();
    if (col > 7 || row > 7) return null;
    final file = flipped ? 7 - col : col;
    final rank = flipped ? row : 7 - row;
    return rank * 8 + file;
  }
}

class _Sprite {
  final int id;
  int piece;
  int sq;
  _Sprite(this.id, this.piece, this.sq);
}

class OukBoardWidget extends StatefulWidget {
  final OukPosition pos;
  final bool flipped;
  final int? selected;
  final Set<int> targets; // legal-move dots
  final Move? last;
  final Move? premove;
  final List<Arrow> arrows;
  final void Function(int sq) onTap;
  final void Function(Arrow arrow) onArrow;

  /// Drag & drop (optional). [canDrag] decides which pieces may be picked up.
  final bool Function(int sq)? canDrag;
  final void Function(int sq)? onDragStart;
  final void Function(int from, int to)? onDragMove;

  /// Move classification badge (game review).
  final int? badgeSquare;
  final String? badgeText;
  final Color? badgeColor;

  final double inset;

  const OukBoardWidget({
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
    this.canDrag,
    this.onDragStart,
    this.onDragMove,
    this.badgeSquare,
    this.badgeText,
    this.badgeColor,
    this.inset = kBoardInset,
  });

  @override
  State<OukBoardWidget> createState() => _OukBoardWidgetState();
}

class _OukBoardWidgetState extends State<OukBoardWidget> {
  List<_Sprite> _sprites = [];
  int _nextId = 0;

  int? _dragSq;
  Offset? _dragPos;
  bool _instant = false;

  int? _aStart;
  int? _aEnd;

  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _sprites = _fromBoard(widget.pos);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final p in const [kKhun, kNeang, kKol, kSes, kTouk, kTrey]) {
      for (final sg in const [1, -1]) {
        precacheImage(pieceProvider(p * sg), context, onError: (e, s) {});
      }
    }
    precacheImage(boardProvider, context, onError: (e, s) {});
  }

  List<_Sprite> _fromBoard(OukPosition pos) {
    final out = <_Sprite>[];
    for (int sq = 0; sq < 64; sq++) {
      final p = pos.pieceAt(sq);
      if (p != 0) out.add(_Sprite(_nextId++, p, sq));
    }
    return out;
  }

  @override
  void didUpdateWidget(covariant OukBoardWidget old) {
    super.didUpdateWidget(old);
    if (identical(old.pos, widget.pos)) return;

    final oldB = [for (int i = 0; i < 64; i++) old.pos.pieceAt(i)];
    final newB = [for (int i = 0; i < 64; i++) widget.pos.pieceAt(i)];
    final changed = <int>[];
    for (int i = 0; i < 64; i++) {
      if (oldB[i] != newB[i]) changed.add(i);
    }
    int from = -1;
    int to = -1;
    for (final i in changed) {
      if (oldB[i] != 0 && newB[i] == 0) from = i;
    }
    for (final i in changed) {
      if (newB[i] != 0 && i != from) to = i;
    }
    final single = changed.length == 2 &&
        from >= 0 &&
        to >= 0 &&
        (newB[to] == oldB[from] ||
            (newB[to].abs() == kNeang && oldB[from].abs() == kTrey));
    if (single) {
      try {
        _sprites.removeWhere((s) => s.sq == to);
        final mover = _sprites.firstWhere((s) => s.sq == from);
        mover.sq = to;
        mover.piece = newB[to];
      } catch (_) {
        _sprites = _fromBoard(widget.pos);
      }
    } else {
      _sprites = _fromBoard(widget.pos);
    }
    if (_instant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _instant = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = currentBoardTheme;
    return LayoutBuilder(builder: (context, c) {
      final size = c.maxWidth.isFinite ? c.maxWidth : 360.0;
      final off = size * widget.inset;
      final s = (size - 2 * off) / 8;
      final geo = _Geo(off, s, widget.flipped);
      final dur = _instant ? Duration.zero : const Duration(milliseconds: 150);

      // ---- sprites
      final sprites = <Widget>[];
      for (final sp in _sprites) {
        final r = geo.rect(sp.sq);
        final ghost = _dragSq == sp.sq;
        sprites.add(AnimatedPositioned(
          key: ValueKey(sp.id),
          duration: dur,
          curve: Curves.easeOutCubic,
          left: r.left,
          top: r.top,
          width: s,
          height: s,
          child: IgnorePointer(
            child: Opacity(
              opacity: ghost ? 0.3 : 1.0,
              child: Padding(
                padding: EdgeInsets.all(s * 0.06),
                child: PieceImage(piece: sp.piece, size: s * 0.88),
              ),
            ),
          ),
        ));
      }

      // ---- piece being dragged (top-most)
      Widget? dragged;
      final ds = _dragSq;
      final dp = _dragPos;
      if (ds != null && dp != null) {
        final piece = widget.pos.pieceAt(ds);
        if (piece != 0) {
          final big = s * 1.15;
          dragged = Positioned(
            left: dp.dx - big / 2,
            top: dp.dy - big * 0.75, // lifted above the finger
            width: big,
            height: big,
            child: IgnorePointer(child: PieceImage(piece: piece, size: big)),
          );
        }
      }

      Arrow? live;
      if (_aStart != null && _aEnd != null) live = Arrow(_aStart!, _aEnd!);

      final checkSq =
          widget.pos.inCheck ? widget.pos.kingSquare(widget.pos.turn) : -1;
      final dragOver = (dp != null) ? geo.sqAt(dp) : null;

      return SizedBox(
        width: size,
        height: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final sq = geo.sqAt(d.localPosition);
            if (sq != null) widget.onTap(sq);
          },
          // ---- drag & drop
          onPanStart: (d) {
            final can = widget.canDrag;
            if (can == null) return;
            final sq = geo.sqAt(d.localPosition);
            if (sq == null || widget.pos.pieceAt(sq) == 0 || !can(sq)) return;
            setState(() {
              _dragSq = sq;
              _dragPos = d.localPosition;
            });
            widget.onDragStart?.call(sq);
          },
          onPanUpdate: (d) {
            if (_dragSq == null) return;
            setState(() => _dragPos = d.localPosition);
          },
          onPanEnd: (d) {
            final from = _dragSq;
            final pos = _dragPos;
            if (from == null) return;
            setState(() {
              _dragSq = null;
              _dragPos = null;
            });
            final to = pos == null ? null : geo.sqAt(pos);
            if (to != null && to != from) {
              _instant = true; // dropped piece is already there: no slide
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _instant = false);
              });
              widget.onDragMove?.call(from, to);
            }
          },
          onPanCancel: () {
            if (_dragSq != null) {
              setState(() {
                _dragSq = null;
                _dragPos = null;
              });
            }
          },
          // ---- arrows: press & hold, then drag
          onLongPressStart: (d) {
            final sq = geo.sqAt(d.localPosition);
            setState(() {
              _aStart = sq;
              _aEnd = sq;
            });
          },
          onLongPressMoveUpdate: (d) {
            final sq = geo.sqAt(d.localPosition);
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
          child: Stack(clipBehavior: Clip.none, children: [
            // 1) board artwork
            Positioned.fill(
              child: IgnorePointer(
                child: Image(
                  image: boardProvider,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (c, e, st) => CustomPaint(
                    painter: _FallbackBoardPainter(geo, theme),
                  ),
                ),
              ),
            ),
            // 2) translucent tints (artwork stays visible)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TintPainter(
                    geo: geo,
                    last: widget.last,
                    premove: widget.premove,
                    selected: widget.selected,
                    checkSq: checkSq,
                    dragOver: dragOver,
                    lastColor: theme.lastMove,
                    selectColor: theme.select,
                  ),
                ),
              ),
            ),
            // 3) pieces
            ...sprites,
            // 4) legal-move dots / capture rings
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DotsPainter(geo, widget.pos, widget.targets),
                ),
              ),
            ),
            // 5) arrows + badge
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OverlayPainter(
                    geo: geo,
                    arrows: widget.arrows,
                    live: live,
                    badgeSq: widget.badgeSquare,
                    badgeText: widget.badgeText,
                    badgeColor: widget.badgeColor,
                  ),
                ),
              ),
            ),
            // 6) dragged piece
            if (dragged != null) dragged,
          ]),
        ),
      );
    });
  }
}

// -----------------------------------------------------------------------------
// Painters
// -----------------------------------------------------------------------------

class _FallbackBoardPainter extends CustomPainter {
  final _Geo geo;
  final BoardTheme theme;
  _FallbackBoardPainter(this.geo, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (int sq = 0; sq < 64; sq++) {
      final dark = (((sq & 7) + (sq >> 3)) % 2 == 0);
      p.color = dark ? theme.dark : theme.light;
      canvas.drawRect(geo.rect(sq), p);
    }
  }

  @override
  bool shouldRepaint(covariant _FallbackBoardPainter old) => true;
}

class _TintPainter extends CustomPainter {
  final _Geo geo;
  final Move? last;
  final Move? premove;
  final int? selected;
  final int checkSq;
  final int? dragOver;
  final Color lastColor;
  final Color selectColor;

  _TintPainter({
    required this.geo,
    required this.last,
    required this.premove,
    required this.selected,
    required this.checkSq,
    required this.dragOver,
    required this.lastColor,
    required this.selectColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    void tint(int sq, Color c) {
      p.color = c;
      canvas.drawRect(geo.rect(sq), p);
    }

    final lm = last;
    if (lm != null) {
      tint(lm.from, lastColor);
      tint(lm.to, lastColor);
    }
    final pm = premove;
    if (pm != null) {
      tint(pm.from, const Color(0x66E53935));
      tint(pm.to, const Color(0x66E53935));
    }
    final sel = selected;
    if (sel != null) tint(sel, selectColor);

    final dov = dragOver;
    if (dov != null) {
      final r = geo.rect(dov);
      canvas.drawRect(
          r.deflate(geo.s * 0.04),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = geo.s * 0.07
            ..color = const Color(0xCCFFFFFF));
    }

    // Red glow under the Khun in check.
    if (checkSq >= 0) {
      final r = geo.rect(checkSq);
      final glow = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xEEFF1744), Color(0x00FF1744)],
          stops: [0.25, 1.0],
        ).createShader(r.inflate(geo.s * 0.15));
      canvas.drawCircle(r.center, geo.s * 0.65, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _TintPainter old) => true;
}

class _DotsPainter extends CustomPainter {
  final _Geo geo;
  final OukPosition pos;
  final Set<int> targets;
  _DotsPainter(this.geo, this.pos, this.targets);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0xAA2E7D32);
    final halo = Paint()..color = const Color(0x66FFFFFF);
    final ring = Paint()
      ..color = const Color(0xCC2E7D32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = geo.s * 0.09;
    for (final sq in targets) {
      final c = geo.rect(sq).center;
      if (pos.pieceAt(sq) != 0) {
        canvas.drawCircle(c, geo.s * 0.45, ring);
      } else {
        canvas.drawCircle(c, geo.s * 0.2, halo);
        canvas.drawCircle(c, geo.s * 0.15, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => true;
}

class _OverlayPainter extends CustomPainter {
  final _Geo geo;
  final List<Arrow> arrows;
  final Arrow? live;
  final int? badgeSq;
  final String? badgeText;
  final Color? badgeColor;

  _OverlayPainter({
    required this.geo,
    required this.arrows,
    required this.live,
    required this.badgeSq,
    required this.badgeText,
    required this.badgeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = geo.s;
    final all = <Arrow>[...arrows];
    if (live != null) all.add(live!);
    for (final a in all) {
      final from = geo.rect(a.from).center;
      final to = geo.rect(a.to).center;
      final color = a.color ?? const Color(0xCCF5A623);
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

    // Move-classification badge on the destination square (top-right corner).
    final bs = badgeSq;
    final bt = badgeText;
    if (bs != null && bt != null) {
      final r = geo.rect(bs);
      final c = Offset(r.right - s * 0.17, r.top + s * 0.17);
      canvas.drawCircle(c, s * 0.21, Paint()..color = Colors.white);
      canvas.drawCircle(c, s * 0.18, Paint()..color = badgeColor ?? Colors.grey);
      final tp = TextPainter(
        text: TextSpan(
          text: bt,
          style: TextStyle(
              fontSize: s * 0.2,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}
