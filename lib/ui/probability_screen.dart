import 'dart:isolate';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../engine/cards.dart';
import '../engine/equity.dart';
import '../engine/evaluator.dart';
import '../engine/probability.dart';
import '../engine/range.dart';
import 'widgets.dart';

const _catNames = HandEvaluator.categoryNames;

String pctStr(double p) {
  if (p <= 0) return '0%';
  if (p < 0.0001) return '<0,01%';
  return '${(p * 100).toStringAsFixed(p < 0.1 ? 2 : 1).replaceAll('.', ',')}%';
}

String oneIn(double p) {
  if (p <= 0) return '–';
  final n = 1 / p;
  return '1 su ${n < 10 ? n.toStringAsFixed(1).replaceAll('.', ',') : n.round()}';
}

/// Sezione probabilità: calcolatore e tabelle di riferimento.
class ProbabilityScreen extends StatelessWidget {
  const ProbabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Calcolatore'), Tab(text: 'Tabelle')]),
        Expanded(child: TabBarView(children: [_OddsCalculator(), _ReferenceTables()])),
      ]),
    );
  }
}

// ───────────────────────────── Calcolatore ─────────────────────────────

class _OddsResult {
  _OddsResult(this.odds, this.equity);

  final HandOdds odds;
  final EquityResult equity;
}

// Funzioni top-level: la closure passata all'isolate non deve catturare lo
// stato dei widget (non inviabile ad un altro isolate).
Future<_OddsResult> _runOdds(List<int> hand, List<int> board, int opp) =>
    Isolate.run(() => _computeOdds(hand, board, opp));

_OddsResult _computeOdds(List<int> hand, List<int> board, int opp) {
  final odds = computeHandOdds(hand, board);
  var dead = 0;
  for (final c in [...hand, ...board]) {
    dead |= 1 << c;
  }
  final villain = PlayerHand.range(HandRange.full()).combos(dead);
  final eq = calculateEquity(EquityRequest(
    playerCards: [hand, for (var i = 0; i < opp; i++) villain.cards],
    playerWeights: [
      [1.0],
      for (var i = 0; i < opp; i++) villain.weights,
    ],
    board: board,
    maxSamples: 40000,
  ));
  return _OddsResult(odds, eq);
}

class _OddsCalculator extends StatefulWidget {
  const _OddsCalculator();

  @override
  State<_OddsCalculator> createState() => _OddsCalculatorState();
}

class _OddsCalculatorState extends State<_OddsCalculator> with AutomaticKeepAliveClientMixin {
  final List<int> picked = [];
  int opponents = 1;
  _OddsResult? result;
  bool running = false;
  int _req = 0;

  @override
  bool get wantKeepAlive => true;

  bool get _ready => picked.length == 2 || picked.length >= 5;

  void _toggle(int card) {
    setState(() {
      if (picked.contains(card)) {
        picked.remove(card);
      } else if (picked.length < 7) {
        picked.add(card);
      }
    });
    _compute();
  }

  void _random(int boardCards) {
    final rnd = Random();
    final deck = List.generate(52, (i) => i)..shuffle(rnd);
    setState(() {
      picked
        ..clear()
        ..addAll(deck.take(2 + boardCards));
    });
    _compute();
  }

  Future<void> _compute() async {
    final req = ++_req;
    if (!_ready) {
      setState(() => result = null);
      return;
    }
    setState(() => running = true);
    final hand = picked.sublist(0, 2);
    final board = picked.sublist(2);
    final opp = opponents;
    final res = await _runOdds(hand, board, opp);
    if (!mounted || req != _req) return;
    setState(() {
      result = res;
      running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final res = result;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Slots(picked: picked, onRemove: _toggle),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          ActionChip(label: const Text('Mano casuale'), onPressed: () => _random(0)),
          ActionChip(label: const Text('+ flop'), onPressed: () => _random(3)),
          ActionChip(label: const Text('+ turn'), onPressed: () => _random(4)),
          ActionChip(label: const Text('+ river'), onPressed: () => _random(5)),
          ActionChip(
            label: const Text('Azzera'),
            onPressed: () {
              setState(picked.clear);
              _compute();
            },
          ),
        ]),
        const SizedBox(height: 8),
        _DeckPicker(picked: picked, onTap: _toggle),
        const SizedBox(height: 4),
        Text(
          picked.length < 2
              ? 'Tocca le carte: prima le tue 2, poi il board.'
              : picked.length < 5
                  ? (picked.length == 2 ? '' : 'Completa il flop (3 carte) per vedere le probabilità.')
                  : '',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        Row(children: [
          const Text('Avversari (mani casuali):'),
          const Spacer(),
          DropdownButton<int>(
            value: opponents,
            items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
            onChanged: (v) {
              setState(() => opponents = v!);
              _compute();
            },
          ),
        ]),
        if (running && res == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (res != null && _ready) ...[
          if (running) const LinearProgressIndicator(),
          _ResultsView(res: res, opponents: opponents),
        ],
      ],
    );
  }
}

class _Slots extends StatelessWidget {
  const _Slots({required this.picked, required this.onRemove});

  final List<int> picked;
  final ValueChanged<int> onRemove;

  Widget _slot(int i) {
    final has = i < picked.length;
    return GestureDetector(
      onTap: has ? () => onRemove(picked[i]) : null,
      child: has
          ? PlayingCardView(picked[i], width: 40)
          : Container(
              width: 40,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget group(String label, List<int> idx) => Column(children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 4),
          Row(children: [
            for (final i in idx) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: _slot(i)),
          ]),
        ]);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        group('Mano', [0, 1]),
        const SizedBox(width: 10),
        group('Flop', [2, 3, 4]),
        const SizedBox(width: 10),
        group('Turn', [5]),
        const SizedBox(width: 10),
        group('River', [6]),
      ]),
    );
  }
}

class _DeckPicker extends StatelessWidget {
  const _DeckPicker({required this.picked, required this.onTap});

  final List<int> picked;
  final ValueChanged<int> onTap;

  static const _colors = [Color(0xFF1E8E3E), Color(0xFF1A73E8), Color(0xFFD93025), Color(0xFF202124)];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final suit in [3, 2, 1, 0])
        Row(children: [
          for (var r = 12; r >= 0; r--)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(1.5),
                child: Builder(builder: (context) {
                  final c = makeCard(r, suit);
                  final used = picked.contains(c);
                  return Material(
                    color: used ? Colors.white12 : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: () => onTap(c),
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 38,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(rankChars[r],
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    height: 1.1,
                                    color: used ? Colors.white38 : _colors[suit])),
                            Text(suitSymbols[suit],
                                style: TextStyle(fontSize: 12, height: 1, color: used ? Colors.white38 : _colors[suit])),
                          ]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ]),
    ]);
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.res, required this.opponents});

  final _OddsResult res;
  final int opponents;

  @override
  Widget build(BuildContext context) {
    final o = res.odds;
    final eq = res.equity;
    final nextLabel = switch (o.boardSize) {
      0 => 'Al flop',
      3 => 'Al turn',
      4 => 'Al river',
      _ => null,
    };
    final rows = [
      for (var c = 8; c >= 0; c--)
        if (o.river[c] > 0 || (nextLabel != null && o.next[c] > 0)) c,
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      if (o.current != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.style),
            title: Text('Ora hai: ${_catNames[o.current!]}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Equity contro $opponents ${opponents == 1 ? 'mano casuale' : 'mani casuali'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(children: [
              Text(pctStr(eq.equity[0]), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Vinci ${pctStr(eq.win[0])} · Pareggi ${pctStr(eq.tie[0])}',
                    style: const TextStyle(color: Colors.white70)),
              ),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: eq.equity[0], minHeight: 8, borderRadius: BorderRadius.circular(4)),
          ]),
        ),
      ),
      if (o.flopDraws != null) _FlopDrawsCard(d: o.flopDraws!),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Probabilità del punto finale', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
              children: [
                TableRow(children: [
                  const _H('Punto'),
                  _H(nextLabel ?? ''),
                  const _H('Al river'),
                ]),
                for (final c in rows)
                  TableRow(children: [
                    _C(_catNames[c], bold: c == o.current),
                    _C(nextLabel == null ? '' : pctStr(o.next[c])),
                    _C(pctStr(o.river[c]), sub: oneIn(o.river[c])),
                  ]),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Calcolo esatto su ${o.combos} combinazioni di board. Il punto conta anche le carte comuni.',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ]),
        ),
      ),
      if (o.boardSize == 3 || o.boardSize == 4) _OutsCard(o: o),
    ]);
  }
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600)),
      );
}

class _C extends StatelessWidget {
  const _C(this.text, {this.sub, this.bold = false});

  final String text;
  final String? sub;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
      );
}

class _FlopDrawsCard extends StatelessWidget {
  const _FlopDrawsCard({required this.d});

  final FlopDraws d;

  @override
  Widget build(BuildContext context) {
    Widget row(String l, double p) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(l)),
            Text(pctStr(p), style: const TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 80, child: Text('  ${oneIn(p)}', style: const TextStyle(fontSize: 11, color: Colors.white54))),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cosa ti dà il flop', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          row('Coppia o meglio', d.pairOrBetter),
          row('Progetto colore (4 carte)', d.flushDraw),
          row('Progetto scala bilaterale', d.straightDrawOpen),
          row('Scala a incastro (gutshot)', d.gutshot),
        ]),
      ),
    );
  }
}

class _OutsCard extends StatelessWidget {
  const _OutsCard({required this.o});

  final HandOdds o;

  @override
  Widget build(BuildContext context) {
    final unseen = 52 - 2 - o.boardSize;
    final n = o.outs.length;
    final byCat = <int, List<int>>{};
    o.outs.forEach((card, cat) => byCat.putIfAbsent(cat, () => []).add(card));
    final cats = byCat.keys.toList()..sort((a, b) => b - a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Outs: $n', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            o.boardSize == 3
                ? 'Al turn ${pctStr(probOneCard(n, unseen))} · entro il river ${pctStr(probTwoCards(n, unseen))}'
                : 'Al river ${pctStr(probOneCard(n, unseen))}',
          ),
          const SizedBox(height: 8),
          for (final c in cats) ...[
            Text('${_catNames[c]} (${byCat[c]!.length})', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final card in byCat[c]!..sort((a, b) => b - a)) PlayingCardView(card, width: 28),
            ]),
            const SizedBox(height: 8),
          ],
          const Text(
            'Outs = carte che migliorano il tuo punto, escluse quelle che migliorano solo il board '
            '(es. una carta che accoppia il board dà la coppia a tutti).',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────────── Tabelle ─────────────────────────────

class _RepHand {
  const _RepHand(this.label, this.cards);

  final String label;
  final String cards;
}

const _repHands = [
  _RepHand('Coppia (77)', '7c7d'),
  _RepHand('Suited connesse (T9s)', 'Th9h'),
  _RepHand('Suited (AKs)', 'AhKh'),
  _RepHand('Offsuit (AKo)', 'AhKd'),
];

class _TablesData {
  _TablesData(this.texture, this.hands);

  final FlopTexture texture;
  final List<HandOdds> hands;
}

_TablesData _computeTables() => _TablesData(
      computeFlopTexture(),
      [for (final h in _repHands) computeHandOdds(parseCards(h.cards), [])],
    );

class _ReferenceTables extends StatefulWidget {
  const _ReferenceTables();

  @override
  State<_ReferenceTables> createState() => _ReferenceTablesState();
}

class _ReferenceTablesState extends State<_ReferenceTables> with AutomaticKeepAliveClientMixin {
  static _TablesData? _cache;
  late final Future<_TablesData> _data =
      _cache != null ? Future.value(_cache) : Isolate.run(_computeTables).then((d) => _cache = d);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('Prima del flop: carte ricevute'),
        _PreflopTable(),
        _section('Outs: probabilità di chiudere il progetto'),
        const _OutsTable(),
        const _CommonDraws(),
        FutureBuilder<_TablesData>(
          future: _data,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Calcolo delle tabelle (milioni di board)…'),
                ]),
              );
            }
            final d = snap.data!;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _section('Dal preflop al river, per tipo di mano'),
              for (var i = 0; i < _repHands.length; i++) _HandDistribution(label: _repHands[i].label, o: d.hands[i]),
              _section('Com\'è il flop (tutti i 22.100 flop)'),
              _TextureTable(t: d.texture),
            ]);
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Tutti i valori sono calcolati in modo esatto dall\'app enumerando le carte possibili.',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );
}

Widget _probRow(String label, double p, {String? note}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label),
            if (note != null) Text(note, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ),
        Text(pctStr(p), style: const TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          width: 76,
          child: Text('  ${oneIn(p)}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ),
      ]),
    );

class _PreflopTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const t = 1326.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          _probRow('Una coppia specifica (es. AA)', 6 / t, note: '6 combinazioni su 1326'),
          _probRow('AA o KK', 12 / t),
          _probRow('QQ o meglio (QQ, KK, AA)', 18 / t),
          _probRow('Una coppia qualsiasi', 78 / t),
          _probRow('AK (suited o offsuit)', 16 / t),
          _probRow('AK suited', 4 / t),
          _probRow('Due carte dello stesso seme', 312 / t),
          _probRow('Due carte connesse (es. 98, A2)', 208 / t),
          _probRow('Suited connesse (es. 98s)', 52 / t),
          _probRow('Almeno un asso', 198 / t),
          _probRow('Due carte da T in su', 190 / t),
          // Almeno un avversario con AA quando hai KK: ogni avversario ha AA
          // con prob. 6/1225 (C(50,2) = 1225); con 8 avversari ≈ 1 - (1 - 6/1225)^8.
          _probRow('Hai KK: un avversario su 8 ha AA', 1 - pow(1 - 6 / 1225, 8).toDouble(),
              note: 'approssimazione, tavolo da 9'),
        ]),
      ),
    );
  }
}

class _OutsTable extends StatelessWidget {
  const _OutsTable();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(0.7)},
          children: [
            const TableRow(children: [_H('Outs'), _H('Turn'), _H('River'), _H('Flop→River')]),
            for (var n = 1; n <= 21; n++)
              TableRow(children: [
                _C('$n', bold: true),
                _C(pctStr(probOneCard(n, 47))),
                _C(pctStr(probOneCard(n, 46))),
                _C(pctStr(probTwoCards(n, 47))),
              ]),
          ],
        ),
      ),
    );
  }
}

class _CommonDraws extends StatelessWidget {
  const _CommonDraws();

  @override
  Widget build(BuildContext context) {
    const draws = [
      ('Progetto colore + bilaterale', 15),
      ('Progetto colore + gutshot', 12),
      ('Progetto colore', 9),
      ('Scala bilaterale', 8),
      ('Set → full o poker (dal flop)', 7),
      ('Due overcard (per fare coppia)', 6),
      ('Coppia + kicker → doppia o tris', 5),
      ('Scala a incastro (gutshot)', 4),
      ('Doppia coppia → full', 4),
      ('Coppia in mano → set', 2),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Progetti più comuni', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {0: FlexColumnWidth(2.2)},
            children: [
              const TableRow(children: [_H('Progetto'), _H('Outs'), _H('Flop→River')]),
              for (final d in draws)
                TableRow(children: [_C(d.$1), _C('${d.$2}'), _C(pctStr(probTwoCards(d.$2, 47)))]),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Regola del 2 e del 4: outs × 4 ≈ % dal flop al river, outs × 2 ≈ % con una carta.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ]),
      ),
    );
  }
}

class _HandDistribution extends StatelessWidget {
  const _HandDistribution({required this.label, required this.o});

  final String label;
  final HandOdds o;

  @override
  Widget build(BuildContext context) {
    final d = o.flopDraws!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            children: [
              const TableRow(children: [_H('Punto'), _H('Al flop'), _H('Al river')]),
              for (var c = 8; c >= 0; c--)
                if (o.river[c] > 0)
                  TableRow(children: [_C(_catNames[c]), _C(pctStr(o.next[c])), _C(pctStr(o.river[c]))]),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Al flop: progetto colore ${pctStr(d.flushDraw)} · bilaterale ${pctStr(d.straightDrawOpen)} · '
            'gutshot ${pctStr(d.gutshot)}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ]),
      ),
    );
  }
}

class _TextureTable extends StatelessWidget {
  const _TextureTable({required this.t});

  final FlopTexture t;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          _probRow('Rainbow (3 semi diversi)', t.rainbow),
          _probRow('Two-tone (2 carte dello stesso seme)', t.twoTone),
          _probRow('Monocolore (3 dello stesso seme)', t.monotone),
          _probRow('Board con coppia', t.paired),
          _probRow('Tris sul board', t.trips),
          _probRow('Tre carte consecutive (es. 789)', t.connected),
          _probRow('Scala possibile (con 2 carte)', t.straightPossible, note: 'flop senza coppie'),
        ]),
      ),
    );
  }
}
