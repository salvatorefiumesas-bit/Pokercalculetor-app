import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../engine/hand_class.dart';
import '../engine/pushfold.dart';
import 'app_data.dart';
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
  push('All-in'),
  call('Call'),
  mixed('Entrambi');

  final String label;
  const SpotType(this.label);
}

class _Spot {
  _Spot(this.cfg, this.hero, this.cards, this.isCall);

  final PushFoldConfig cfg;
  final int hero; // posizione dell'eroe
  final List<int> cards;
  final bool isCall;

  int get handClass => HandClass.ofCards(cards[0], cards[1]);
}

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  final _rnd = Random();
  TableSize tableSize = TableSize.nine;
  SpotType spotType = SpotType.mixed;
  RangeValues stackRange = const RangeValues(4, 18);
  AnteType ante = AnteType.bigBlindAnte;

  _Spot? spot;
  PushFoldSolution? solution;
  bool? answeredAggressive;
  int hands = 0, correct = 0;
  double evLost = 0;

  @override
  void initState() {
    super.initState();
    _next();
  }

  _Spot _makeSpot() {
    final n = tableSize == TableSize.random ? 2 + _rnd.nextInt(8) : tableSize.players;
    final stack = stackRange.start.round() + _rnd.nextInt(stackRange.end.round() - stackRange.start.round() + 1);
    final isCall = switch (spotType) {
      SpotType.push => false,
      SpotType.call => true,
      SpotType.mixed => _rnd.nextBool(),
    };
    final pusher = _rnd.nextInt(n - 1);
    final hero = isCall ? pusher + 1 + _rnd.nextInt(n - 1 - pusher) : pusher;
    final c1 = _rnd.nextInt(52);
    int c2;
    do {
      c2 = _rnd.nextInt(52);
    } while (c2 == c1);
    final cards = c1 > c2 ? [c1, c2] : [c2, c1];
    return _Spot(PushFoldConfig(players: n, stack: stack, ante: ante, pusher: pusher), hero, cards, isCall);
  }

  Future<void> _next() async {
    final s = _makeSpot();
    setState(() {
      spot = s;
      solution = SolverCache.cached(s.cfg);
      answeredAggressive = null;
    });
    if (solution == null) {
      final sol = await SolverCache.solve(s.cfg);
      if (!mounted || spot != s) return;
      setState(() => solution = sol);
    }
  }

  double _ev(PushFoldSolution sol, _Spot s) =>
      s.isCall ? sol.callEv[s.hero]![s.handClass] : sol.pushEv[s.handClass];

  double _freq(PushFoldSolution sol, _Spot s) =>
      s.isCall ? sol.call[s.hero]![s.handClass] : sol.push[s.handClass];

  void _answer(bool aggressive) {
    final s = spot!, sol = solution!;
    final ev = _ev(sol, s);
    final best = max(ev, 0.0);
    final chosen = aggressive ? ev : 0.0;
    final loss = best - chosen;
    setState(() {
      answeredAggressive = aggressive;
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Impostazioni trainer', style: Theme.of(ctx).textTheme.titleLarge),
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
              max: 25,
              divisions: 23,
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
    if (s == null) return const Center(child: CircularProgressIndicator());
    final names = positionNames(s.cfg.players);
    final sol = solution;
    final answered = answeredAggressive != null;
    final aggressiveLabel = s.isCall ? 'Call' : 'All-in';
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
        Card(
          color: const Color(0xFF0F3D2E),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text('${s.cfg.players} giocatori · stack ${s.cfg.stack} BB · ante ${s.cfg.ante.label.toLowerCase()}',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                s.isCall
                    ? '${names[s.cfg.pusher]} va all-in per ${s.cfg.stack} BB.\nTutti foldano fino a te.'
                    : 'Tutti foldano fino a te.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Chip(label: Text('Sei in ${names[s.hero]}', style: const TextStyle(fontWeight: FontWeight.bold))),
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
        if (sol == null)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (!answered)
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: foldColor, minimumSize: const Size(0, 56)),
                onPressed: () => _answer(false),
                child: const Text('Fold', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: s.isCall ? callColor : pushColor, minimumSize: const Size(0, 56)),
                onPressed: () => _answer(true),
                child: Text(aggressiveLabel, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ])
        else
          _Feedback(
            spot: s,
            solution: sol,
            aggressive: answeredAggressive!,
            ev: _ev(sol, s),
            freq: _freq(sol, s),
            label: aggressiveLabel,
            onNext: _next,
          ),
      ],
    );
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
  const _Feedback({
    required this.spot,
    required this.solution,
    required this.aggressive,
    required this.ev,
    required this.freq,
    required this.label,
    required this.onNext,
  });

  final _Spot spot;
  final PushFoldSolution solution;
  final bool aggressive;
  final double ev;
  final double freq;
  final String label;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final best = max(ev, 0.0);
    final loss = best - (aggressive ? ev : 0.0);
    final ok = loss < 0.05;
    final mixed = freq > 0 && freq < 1;
    final range = spot.isCall ? solution.call[spot.hero]! : solution.push;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: ok ? const Color(0xFF1B4D2E) : const Color(0xFF5C1F22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ok ? '✓ Corretto' : '✗ Errore',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Hai scelto: ${aggressive ? label : 'Fold'}'),
            Text('Strategia Nash: $label ${fmtPct(freq)} · Fold ${fmtPct(1 - freq)}'
                '${mixed ? ' (strategia mista)' : ''}'),
            Text('EV $label: ${fmtEv(ev)} · EV Fold: ${fmtEv(0)}'),
            if (!ok) Text('EV perso: ${loss.toStringAsFixed(2)} BB', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Text('Range di $label in questo spot (${(_pct(range)).toStringAsFixed(1)}%)'),
      const SizedBox(height: 6),
      RangeGrid(values: range, color: spot.isCall ? callColor : pushColor, selected: spot.handClass),
      const SizedBox(height: 12),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: onNext,
        child: const Text('Prossima mano', style: TextStyle(fontSize: 18)),
      ),
    ]);
  }

  static double _pct(List<double> f) {
    var s = 0.0;
    for (var i = 0; i < 169; i++) {
      s += f[i] * HandClass.comboCount(i);
    }
    return s / 1326 * 100;
  }
}
