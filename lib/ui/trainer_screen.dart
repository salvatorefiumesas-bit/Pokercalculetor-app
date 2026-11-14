import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../engine/hand_class.dart';
import '../engine/preflop_solver.dart';
import '../engine/pushfold.dart';
import 'app_data.dart';
import 'charts_screen.dart';
import 'situations.dart';
import 'widgets.dart';

enum TableSize {
  nine('9-max', 9),
  six('6-max', 6),
  hu('Heads-up', 2),
  random('Casuale', 0);

  final String label;
  final int players;
  const TableSize(this.label, this.players);
}

enum SpotType {
  open('Apertura'),
  response('Risposta'),
  mixed('Entrambi');

  final String label;
  const SpotType(this.label);
}

class _Spot {
  _Spot(this.cfg, this.node, this.cards, this.description);

  final PushFoldConfig cfg;
  final StrategyNode node;
  final List<int> cards;
  final String description;

  int get handClass => HandClass.ofCards(cards[0], cards[1]);
}

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  final _rnd = Random();
  bool full = true;
  TableSize tableSize = TableSize.nine;
  SpotType spotType = SpotType.mixed;
  RangeValues stackRange = const RangeValues(8, 25);
  AnteType ante = AnteType.bigBlindAnte;

  _Spot? spot;
  bool loading = false;
  int? answer;
  int hands = 0, correct = 0;
  double evLost = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _next();
  }

  /// Sceglie una mano (classe pesata per combinazioni e [weights]) e due carte.
  List<int> _dealHand(List<double>? weights) {
    final w = [for (var h = 0; h < 169; h++) (weights == null ? 1.0 : weights[h]) * HandClass.comboCount(h)];
    final total = w.fold(0.0, (a, b) => a + b);
    var cls = _rnd.nextInt(169);
    if (total > 0) {
      var x = _rnd.nextDouble() * total;
      for (var h = 0; h < 169; h++) {
        x -= w[h];
        if (x <= 0) {
          cls = h;
          break;
        }
      }
    }
    final combos = HandClass.combos(cls);
    final c = combos[_rnd.nextInt(combos.length)];
    return c[0] > c[1] ? c : [c[1], c[0]];
  }

  Future<_Spot> _makeSpot() async {
    final n = tableSize == TableSize.random ? 2 + _rnd.nextInt(8) : tableSize.players;
    final lo = max(stackRange.start.round(), full ? 5 : 2), hi = max(stackRange.end.round(), lo);
    final stack = lo + _rnd.nextInt(hi - lo + 1);
    final response = switch (spotType) {
      SpotType.open => false,
      SpotType.response => true,
      SpotType.mixed => _rnd.nextDouble() < 0.55,
    };
    var opener = _rnd.nextInt(n - 1);
    final names = positionNames(n);

    if (!full) {
      final cfg = PushFoldConfig(players: n, stack: stack, ante: ante, pusher: opener);
      final sol = await SolverCache.solve(cfg);
      if (!response) {
        return _Spot(cfg, sol.openNode, _dealHand(null), 'Tutti foldano fino a te in ${names[opener]}.');
      }
      final j = opener + 1 + _rnd.nextInt(n - 1 - opener);
      return _Spot(cfg, sol.callNode(j), _dealHand(null),
          '${names[opener]} va all-in per $stack BB. Tutti foldano fino a te in ${names[j]}.');
    }

    var sit = Situation.open;
    if (response) {
      final r = _rnd.nextDouble();
      sit = r < 0.4
          ? Situation.vsRaise
          : r < 0.6
              ? Situation.vsJam
              : r < 0.8
                  ? Situation.raiseVsJam
                  : r < 0.9
                      ? Situation.vsLimp
                      : Situation.limpVsJam;
    }
    if (sit.sbOnly) opener = n - 2;
    final cfg = PushFoldConfig(players: n, stack: stack, ante: ante, pusher: opener);
    final sol = await SolverCache.solveFull(cfg);
    final j = opener + 1 + _rnd.nextInt(n - 1 - opener);
    var node = nodeFor(sol, sit, j);
    if (!node.reachable) {
      sit = Situation.open;
      node = sol.open;
    }
    List<double>? weights;
    if (sit == Situation.raiseVsJam) weights = sol.open.freq[sol.open.indexOf(PokerAction.raise)];
    if (sit == Situation.limpVsJam) weights = sol.open.freq[sol.open.indexOf(PokerAction.limp)];
    return _Spot(cfg, node, _dealHand(weights), describeSituation(sol, sit, j));
  }

  Future<void> _next() async {
    final req = ++_request;
    setState(() {
      loading = true;
      answer = null;
    });
    final s = await _makeSpot();
    if (!mounted || req != _request) return;
    setState(() {
      spot = s;
      loading = false;
    });
  }

  double _loss(_Spot s, int k) {
    final h = s.handClass;
    return s.node.ev[s.node.bestAction(h)][h] - s.node.ev[k][h];
  }

  void _answer(int k) {
    final loss = _loss(spot!, k);
    setState(() {
      answer = k;
      hands++;
      if (loss < 0.05) correct++;
      evLost += loss;
    });
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void upd(VoidCallback f) {
          setSheet(f);
          setState(() {});
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Impostazioni trainer', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('Modello'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Preflop completo')),
                ButtonSegment(value: false, label: Text('Push/Fold')),
              ],
              selected: {full},
              showSelectedIcon: false,
              onSelectionChanged: (v) => upd(() => full = v.first),
            ),
            const SizedBox(height: 12),
            const Text('Tavolo'),
            SegmentedButton<TableSize>(
              segments: [for (final t in TableSize.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {tableSize},
              showSelectedIcon: false,
              onSelectionChanged: (v) => upd(() => tableSize = v.first),
            ),
            const SizedBox(height: 12),
            const Text('Tipo di spot'),
            SegmentedButton<SpotType>(
              segments: [for (final t in SpotType.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {spotType},
              showSelectedIcon: false,
              onSelectionChanged: (v) => upd(() => spotType = v.first),
            ),
            const SizedBox(height: 12),
            const Text('Ante'),
            SegmentedButton<AnteType>(
              segments: [for (final a in AnteType.values) ButtonSegment(value: a, label: Text(a.label))],
              selected: {ante},
              showSelectedIcon: false,
              onSelectionChanged: (v) => upd(() => ante = v.first),
            ),
            const SizedBox(height: 12),
            Text('Stack: ${stackRange.start.round()}–${stackRange.end.round()} BB'),
            RangeSlider(
              values: stackRange,
              min: 2,
              max: 30,
              divisions: 28,
              onChanged: (v) => upd(() => stackRange = v),
            ),
            Row(children: [
              TextButton(
                onPressed: () => upd(() {
                  hands = 0;
                  correct = 0;
                  evLost = 0;
                }),
                child: const Text('Azzera statistiche'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _next();
                },
                child: const Text('Applica'),
              ),
            ]),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = spot;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          _Stat('Mani', '$hands'),
          _Stat('Corrette', hands == 0 ? '–' : '${(correct / hands * 100).toStringAsFixed(0)}%'),
          _Stat('EV perso', '${evLost.toStringAsFixed(2)} BB'),
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.tune), tooltip: 'Impostazioni'),
        ]),
        const SizedBox(height: 8),
        if (s == null || loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Column(children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Calcolo della strategia…'),
            ]),
          )
        else ...[
          Card(
            color: const Color(0xFF0F3D2E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(
                  '${s.cfg.players} giocatori · stack ${s.cfg.stack} BB · ${s.cfg.ante.short}'
                  '${full ? '' : ' · push/fold'}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(s.description, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Chip(
                  label: Text('Sei in ${positionNames(s.cfg.players)[s.node.hero]}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  PlayingCardView(s.cards[0], width: 72),
                  const SizedBox(width: 10),
                  PlayingCardView(s.cards[1], width: 72),
                ]),
                const SizedBox(height: 8),
                Text(HandClass.name(s.handClass), style: theme.textTheme.titleLarge),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (answer == null)
            Row(children: [
              for (var k = 0; k < s.node.actions.length; k++) ...[
                if (k > 0) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: actionColor(s.node.actions[k]),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    onPressed: () => _answer(k),
                    child: Text(_buttonLabel(s, k), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ])
          else
            _Feedback(spot: s, answer: answer!, loss: _loss(s, answer!), onNext: _next),
        ],
      ],
    );
  }

  String _buttonLabel(_Spot s, int k) {
    final a = s.node.actions[k];
    if (a == PokerAction.raise && full) {
      final sol = SolverCache.cachedFull(s.cfg);
      if (sol != null) return 'Rilancio\n${fmtBb(sol.raiseSize)} BB';
    }
    return a.label;
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
      ]),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.spot, required this.answer, required this.loss, required this.onNext});

  final _Spot spot;
  final int answer;
  final double loss;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final node = spot.node;
    final h = spot.handClass;
    final ok = loss < 0.05;
    final mixed = node.freq.where((f) => f[h] > 0 && f[h] < 1).isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: ok ? const Color(0xFF1B4D2E) : const Color(0xFF5C1F22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ok ? '✓ Corretto' : '✗ Errore', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Hai scelto: ${node.actions[answer].label}'
                '${node.actions[answer] == node.actions[node.bestAction(h)] ? '' : ' · migliore: ${node.actions[node.bestAction(h)].label}'}'),
            if (mixed) const Text('Mano giocata con strategia mista.'),
            if (!ok) Text('EV perso: ${loss.toStringAsFixed(2)} BB', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
      HandInfoCard(node: node, hand: h),
      const SizedBox(height: 8),
      const Text('Strategia completa in questo spot:'),
      const SizedBox(height: 6),
      RangeGrid(layers: nodeLayers(node), selected: h),
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (var k = 0; k < node.actions.length; k++)
          LegendDot(actionColor(node.actions[k]), '${node.actions[k].label} ${node.percent(k).toStringAsFixed(1)}%'),
      ]),
      const SizedBox(height: 12),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: onNext,
        child: const Text('Prossima mano', style: TextStyle(fontSize: 18)),
      ),
    ]);
  }
}
