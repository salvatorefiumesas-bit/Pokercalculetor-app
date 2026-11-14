import 'package:material_ui/material_ui.dart';

import '../engine/cards.dart';
import '../engine/hand_class.dart';
import '../engine/preflop_solver.dart';

const Color foldColor = Color(0xFF2A333D);
const Color pushColor = Color(0xFFE5484D);
const Color callColor = Color(0xFF30A46C);
const Color rangeColor = Color(0xFF3E9BF5);
const Color raiseColor = Color(0xFFF5A623);
const Color limpColor = Color(0xFF12A5C4);
const Color checkColor = Color(0xFF6B8AA6);

Color actionColor(PokerAction a) => switch (a) {
      PokerAction.fold => foldColor,
      PokerAction.check => checkColor,
      PokerAction.call => callColor,
      PokerAction.limp => limpColor,
      PokerAction.raise => raiseColor,
      PokerAction.allIn => pushColor,
    };

/// Strato della griglia: frequenze (169) e colore.
typedef GridLayer = ({List<double> values, Color color});

/// Strati per un nodo di strategia (il fold resta lo sfondo).
List<GridLayer> nodeLayers(StrategyNode node) => [
      for (var k = 0; k < node.actions.length; k++)
        if (node.actions[k] != PokerAction.fold) (values: node.freq[k], color: actionColor(node.actions[k])),
    ];

/// Griglia 13x13 delle mani preflop. Ogni cella è riempita in proporzione
/// alla frequenza (0..1).
class RangeGrid extends StatelessWidget {
  const RangeGrid({
    super.key,
    this.values,
    this.layers,
    this.color = pushColor,
    this.selected,
    this.onCellTap,
    this.onPaintStart,
    this.onPaintUpdate,
  });

  final List<double>? values;
  final List<GridLayer>? layers;
  final Color color;
  final int? selected;
  final ValueChanged<int>? onCellTap;
  final ValueChanged<int>? onPaintStart;
  final ValueChanged<int>? onPaintUpdate;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.maxWidth;
        int? cellAt(Offset p) {
          final cell = size / 13;
          final col = (p.dx / cell).floor(), row = (p.dy / cell).floor();
          if (col < 0 || col > 12 || row < 0 || row > 12) return null;
          return row * 13 + col;
        }

        return GestureDetector(
          onTapUp: onCellTap == null
              ? null
              : (d) {
                  final i = cellAt(d.localPosition);
                  if (i != null) onCellTap!(i);
                },
          onPanStart: onPaintStart == null
              ? null
              : (d) {
                  final i = cellAt(d.localPosition);
                  if (i != null) onPaintStart!(i);
                },
          onPanUpdate: onPaintUpdate == null
              ? null
              : (d) {
                  final i = cellAt(d.localPosition);
                  if (i != null) onPaintUpdate!(i);
                },
          child: CustomPaint(
            size: Size.square(size),
            painter: _GridPainter(layers ?? [(values: values ?? List.filled(169, 0.0), color: color)], selected),
          ),
        );
      }),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.layers, this.selected);

  final List<GridLayer> layers;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 13;
    final bg = Paint()..color = foldColor;
    final fills = [for (final l in layers) Paint()..color = l.color];
    final border = Paint()
      ..color = const Color(0xFF12171C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var idx = 0; idx < 169; idx++) {
      final r = Rect.fromLTWH((idx % 13) * cell, (idx ~/ 13) * cell, cell, cell);
      canvas.drawRect(r, bg);
      var x = r.left, v = 0.0;
      for (var l = 0; l < layers.length; l++) {
        final f = layers[l].values[idx].clamp(0.0, 1.0);
        if (f <= 0) continue;
        final wdt = r.width * f;
        canvas.drawRect(Rect.fromLTWH(x, r.top, wdt, r.height), fills[l]);
        x += wdt;
        v += f;
      }
      canvas.drawRect(r, border);
      final tp = TextPainter(
        text: TextSpan(
          text: HandClass.name(idx),
          style: TextStyle(
            color: v > 0 ? Colors.white : Colors.white54,
            fontSize: cell * 0.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cell);
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    }
    if (selected != null) {
      final s = selected!;
      final r = Rect.fromLTWH((s % 13) * cell, (s ~/ 13) * cell, cell, cell);
      canvas.drawRect(
        r.deflate(1),
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}

/// Carta da gioco (mazzo a 4 colori).
class PlayingCardView extends StatelessWidget {
  const PlayingCardView(this.card, {super.key, this.width = 64});

  final int card;
  final double width;

  static const _suitColors = [
    Color(0xFF1E8E3E), // fiori
    Color(0xFF1A73E8), // quadri
    Color(0xFFD93025), // cuori
    Color(0xFF202124), // picche
  ];

  @override
  Widget build(BuildContext context) {
    final color = _suitColors[suitOf(card)];
    return Container(
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.12),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black45, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            rankChars[rankOf(card)],
            style: TextStyle(color: color, fontSize: width * 0.5, fontWeight: FontWeight.bold, height: 1),
          ),
          Text(suitSymbols[suitOf(card)], style: TextStyle(color: color, fontSize: width * 0.42, height: 1.1)),
        ],
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot(this.color, this.label, {super.key});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label),
    ]);
  }
}

String fmtEv(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} BB';

String fmtPct(double v) => '${(v * 100).toStringAsFixed(0)}%';
