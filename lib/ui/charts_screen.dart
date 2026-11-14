import 'package:material_ui/material_ui.dart';

import '../engine/hand_class.dart';
import '../engine/preflop_solver.dart';
import '../engine/pushfold.dart';
import 'app_data.dart';
import 'situations.dart';
import 'widgets.dart';

/// Tabelle di strategia: preflop completo (rilancio/limp/call/all-in) oppure
/// push/fold classico.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  bool full = true;
  int players = 9;
  int stack = 20;
  AnteType ante = AnteType.bigBlindAnte;
  int opener = 0;
  int responder = 8;
  Situation situation = Situation.open;
  bool callMode = false; // solo push/fold
  int? selected;

  PushFoldSolution? pf;
  FullPreflopSolution? fullSol;
  bool loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  PushFoldConfig get _cfg => PushFoldConfig(players: players, stack: stack, ante: ante, pusher: opener);

  Future<void> _refresh() async {
    final req = ++_request;
    final cfg = _cfg;
    final hit = full ? SolverCache.cachedFull(cfg) : SolverCache.cached(cfg);
    if (hit == null) setState(() => loading = true);
    if (full) {
      final s = await SolverCache.solveFull(cfg);
      if (!mounted || req != _request) return;
      setState(() {
        fullSol = s;
        loading = false;
      });
    } else {
      final s = await SolverCache.solve(cfg);
      if (!mounted || req != _request) return;
      setState(() {
        pf = s;
        loading = false;
      });
    }
  }

  void _fixPositions() {
    opener = opener.clamp(0, players - 2);
    if (full && situation.sbOnly) opener = players - 2;
    if (responder <= opener || responder >= players) responder = players - 1;
  }

  StrategyNode? get _node {
    final key = _cfg.key;
    if (full) {
      final s = fullSol;
      if (s == null || s.config.key != key) return null;
      return nodeFor(s, situation, responder);
    }
    final s = pf;
    if (s == null || s.config.key != key) return null;
    return callMode ? s.callNode(responder) : s.openNode;
  }

  String get _description {
    final names = positionNames(players);
    if (full) {
      final s = fullSol;
      if (s == null || s.config.key != _cfg.key) return '';
      return describeSituation(s, situation, responder);
    }
    return callMode
        ? '${names[opener]} va all-in ($stack BB), tutti foldano fino a te in ${names[responder]}.'
        : 'Tutti foldano fino a te in ${names[opener]}.';
  }

  @override
  Widget build(BuildContext context) {
    final names = positionNames(players);
    final node = _node;
    final needsResponder = full ? situation.needsResponder : callMode;
    final minStack = full ? 5 : 2;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Preflop completo')),
            ButtonSegment(value: false, label: Text('Push/Fold')),
          ],
          selected: {full},
          showSelectedIcon: false,
          onSelectionChanged: (v) {
            full = v.first;
            if (stack < minStack) stack = 5;
            _fixPositions();
            _refresh();
          },
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Giocatori'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: players,
                  items: [for (var p = 2; p <= 9; p++) DropdownMenuItem(value: p, child: Text('$p'))],
                  onChanged: (v) {
                    players = v!;
                    _fixPositions();
                    _refresh();
                  },
                ),
                const Spacer(),
                Text('Stack: $stack BB', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
              Slider(
                value: stack.toDouble().clamp(minStack.toDouble(), 30),
                min: minStack.toDouble(),
                max: 30,
                divisions: 30 - minStack,
                label: '$stack BB',
                onChanged: (v) => setState(() => stack = v.round()),
                onChangeEnd: (_) => _refresh(),
              ),
              SegmentedButton<AnteType>(
                segments: [for (final a in AnteType.values) ButtonSegment(value: a, label: Text(a.label))],
                selected: {ante},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  ante = s.first;
                  _refresh();
                },
              ),
              const SizedBox(height: 12),
              if (full)
                DropdownButtonFormField<Situation>(
                  initialValue: situation,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Situazione', border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (final s in Situation.values)
                      DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    situation = v!;
                    final before = opener;
                    _fixPositions();
                    if (before != opener) {
                      _refresh();
                    } else {
                      setState(() {});
                    }
                  },
                )
              else
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Apertura all-in')),
                    ButtonSegment(value: true, label: Text('Call vs all-in')),
                  ],
                  selected: {callMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    callMode = s.first;
                    _fixPositions();
                  }),
                ),
              const SizedBox(height: 8),
              if (!(full && situation.sbOnly)) ...[
                Text(needsResponder ? 'Chi apre:' : 'La tua posizione:'),
                Wrap(spacing: 6, children: [
                  for (var i = 0; i < players - 1; i++)
                    ChoiceChip(
                      label: Text(names[i]),
                      selected: opener == i,
                      onSelected: (_) {
                        opener = i;
                        _fixPositions();
                        _refresh();
                      },
                    ),
                ]),
              ],
              if (needsResponder) ...[
                const SizedBox(height: 4),
                Text(full && situation == Situation.raiseVsJam ? 'Chi va all-in:' : 'La tua posizione:'),
                Wrap(spacing: 6, children: [
                  for (var j = opener + 1; j < players; j++)
                    ChoiceChip(
                      label: Text(names[j]),
                      selected: responder == j,
                      onSelected: (_) => setState(() => responder = j),
                    ),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(_description, style: Theme.of(context).textTheme.titleSmall),
        if (node != null && !node.reachable)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'All\'equilibrio questa situazione non capita mai: la tabella è solo indicativa.',
              style: TextStyle(color: Color(0xFFF5A623), fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
        Stack(alignment: Alignment.center, children: [
          RangeGrid(
            layers: node == null ? const [] : nodeLayers(node),
            selected: selected,
            onCellTap: (i) => setState(() => selected = i),
          ),
          if (loading || node == null) const CircularProgressIndicator(),
        ]),
        const SizedBox(height: 8),
        if (node != null) ...[
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (var k = 0; k < node.actions.length; k++)
              LegendDot(actionColor(node.actions[k]),
                  '${node.actions[k].label} ${node.percent(k).toStringAsFixed(1)}%'),
          ]),
          const SizedBox(height: 8),
          if (selected != null)
            HandInfoCard(node: node, hand: selected!)
          else
            const Text('Tocca una mano per vedere frequenze ed EV.'),
        ],
        const SizedBox(height: 12),
        Text(
          full
              ? 'Equilibrio approssimato in chip EV. Contro un rilancio solo il BB può fare call; '
                  'il gioco dopo il flop è stimato con l\'equity realization (in posizione ×1,1, '
                  'fuori posizione ×0,7, corretta per la giocabilità della mano). Rilancio: 2 BB, dallo SB 3 BB '
                  '(2,5 in heads-up).'
              : 'Equilibrio di Nash in chip EV: un solo caller, niente ICM. Ideale fino a ~15 BB.',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }
}

/// Dettaglio di una mano: frequenza ed EV di ogni azione.
class HandInfoCard extends StatelessWidget {
  const HandInfoCard({super.key, required this.node, required this.hand});

  final StrategyNode node;
  final int hand;

  @override
  Widget build(BuildContext context) {
    final best = node.bestAction(hand);
    final base = node.actions.first.label;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(HandClass.name(hand), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 6),
          for (var k = 0; k < node.actions.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: actionColor(node.actions[k]), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: Text(node.actions[k].label)),
                SizedBox(width: 56, child: Text(fmtPct(node.freq[k][hand]))),
                Text(k == 0 ? 'EV 0 (base)' : 'EV ${fmtEv(node.ev[k][hand])}',
                    style: TextStyle(fontWeight: k == best ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          const SizedBox(height: 4),
          Text('EV in BB rispetto a $base.', style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      ),
    );
  }
}
