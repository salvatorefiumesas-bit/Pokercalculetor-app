import 'dart:isolate';

import 'package:material_ui/material_ui.dart';

import '../engine/cards.dart';
import '../engine/equity.dart';
import '../engine/range.dart';
import 'range_editor.dart';

/// Calcolatore di equity: mani specifiche o range, con board opzionale.
class EquityScreen extends StatefulWidget {
  const EquityScreen({super.key});

  @override
  State<EquityScreen> createState() => _EquityScreenState();
}

class _EquityScreenState extends State<EquityScreen> {
  final players = [TextEditingController(text: 'AhKh'), TextEditingController(text: 'QQ+, AKo')];
  final board = TextEditingController();
  EquityResult? result;
  String? error;
  bool running = false;

  static const _colors = [
    Color(0xFF3E9BF5), Color(0xFFE5484D), Color(0xFF30A46C),
    Color(0xFFF5A623), Color(0xFFAB4ABA), Color(0xFF12A594),
  ];

  @override
  void dispose() {
    for (final c in players) {
      c.dispose();
    }
    board.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    try {
      final boardCards = board.text.trim().isEmpty ? <int>[] : parseCards(board.text);
      if (boardCards.length > 5 || boardCards.length == 1 || boardCards.length == 2) {
        throw const FormatException('Il board deve avere 0, 3, 4 o 5 carte');
      }
      final parsed = <PlayerHand>[];
      for (var i = 0; i < players.length; i++) {
        try {
          parsed.add(PlayerHand.parse(players[i].text));
        } on FormatException catch (e) {
          throw FormatException('Giocatore ${i + 1}: ${e.message}');
        }
      }
      var boardMask = 0;
      for (final c in boardCards) {
        boardMask |= 1 << c;
      }
      // Carte specifiche: non devono sovrapporsi tra loro o col board.
      var specific = boardMask;
      for (var i = 0; i < parsed.length; i++) {
        final c = parsed[i].cards;
        if (c == null) continue;
        final m = (1 << c[0]) | (1 << c[1]);
        if ((specific & m) != 0) throw FormatException('Giocatore ${i + 1}: carta già usata');
        specific |= m;
      }
      final cards = <List<int>>[];
      final weights = <List<double>>[];
      for (var i = 0; i < parsed.length; i++) {
        final own = parsed[i].cards;
        final ownMask = own == null ? 0 : (1 << own[0]) | (1 << own[1]);
        final combos = parsed[i].combos(specific & ~ownMask);
        if (combos.weights.isEmpty) {
          throw FormatException('Giocatore ${i + 1}: nessuna combinazione possibile');
        }
        cards.add(combos.cards);
        weights.add(combos.weights);
      }
      setState(() {
        running = true;
        error = null;
      });
      final req = EquityRequest(playerCards: cards, playerWeights: weights, board: boardCards);
      final res = await Isolate.run(() => calculateEquity(req));
      if (!mounted) return;
      setState(() {
        result = res;
        running = false;
      });
    } on FormatException catch (e) {
      setState(() {
        error = e.message;
        result = null;
        running = false;
      });
    }
  }

  Future<void> _editRange(int i) async {
    final res = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => RangeEditorPage(initial: players[i].text)),
    );
    if (res != null) setState(() => players[i].text = res);
  }

  @override
  Widget build(BuildContext context) {
    final res = result;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var i = 0; i < players.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              CircleAvatar(radius: 14, backgroundColor: _colors[i], child: Text('${i + 1}')),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: players[i],
                  decoration: const InputDecoration(
                    labelText: 'Mano o range (es. AhKd oppure 22+, AJs+)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.grid_on), tooltip: 'Editor range', onPressed: () => _editRange(i)),
              if (players.length > 2)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    players.removeAt(i).dispose();
                    result = null;
                  }),
                ),
            ]),
          ),
        if (players.length < 6)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                players.add(TextEditingController());
                result = null;
              }),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi giocatore'),
            ),
          ),
        TextField(
          controller: board,
          decoration: const InputDecoration(
            labelText: 'Board (opzionale, es. Ah7c2d)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
          onPressed: running ? null : _calculate,
          icon: running
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.calculate),
          label: const Text('Calcola equity'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: const TextStyle(color: Color(0xFFFF6B6B))),
          ),
        if (res != null && res.equity.length == players.length) ...[
          const SizedBox(height: 16),
          for (var i = 0; i < res.equity.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 12, backgroundColor: _colors[i], child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(players[i].text, overflow: TextOverflow.ellipsis)),
                    Text('${(res.equity[i] * 100).toStringAsFixed(2)}%',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: res.equity[i],
                    color: _colors[i],
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text('Vince ${(res.win[i] * 100).toStringAsFixed(2)}% · Pareggia ${(res.tie[i] * 100).toStringAsFixed(2)}%',
                      style: const TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
            ),
          Text(
            res.exact ? 'Calcolo esatto (${res.samples} board)' : 'Monte Carlo (${res.samples} simulazioni)',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ],
    );
  }
}
