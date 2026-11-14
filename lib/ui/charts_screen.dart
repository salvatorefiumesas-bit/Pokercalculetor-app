import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../engine/hand_class.dart';
import '../engine/pushfold.dart';
import '../engine/range.dart';
import 'app_data.dart';
import 'widgets.dart';

/// Tabelle di Nash push/fold per tornei.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  int players = 9;
  int stack = 10;
  AnteType ante = AnteType.bigBlindAnte;
  bool callMode = false;
  int pusher = 0;
  int caller = 8;
  int? selected;
  PushFoldSolution? solution;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  PushFoldConfig get _cfg => PushFoldConfig(players: players, stack: stack, ante: ante, pusher: pusher);

  Future<void> _refresh() async {
    final cfg = _cfg;
    final hit = SolverCache.cached(cfg);
    if (hit != null) {
      setState(() {
        solution = hit;
        loading = false;
      });
      return;
    }
    setState(() => loading = true);
    final s = await SolverCache.solve(cfg);
    if (!mounted || s.config.key != _cfg.key) return;
    setState(() {
      solution = s;
      loading = false;
    });
  }

  void _setPlayers(int p) {
    players = p;
    pusher = pusher.clamp(0, p - 2);
    caller = p - 1;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final names = positionNames(players);
    final sol = solution;
    Float64List? freq, ev;
    if (sol != null && sol.config.key == _cfg.key) {
      freq = callMode ? sol.call[caller] : sol.push;
      ev = callMode ? sol.callEv[caller] : sol.pushEv;
    }
    final color = callMode ? callColor : pushColor;
    final actionName = callMode ? 'Call' : 'All-in';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
                  onChanged: (v) => _setPlayers(v!),
                ),
                const Spacer(),
                Text('Stack: $stack BB', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
              Slider(
                value: stack.toDouble(),
                min: 2,
                max: 25,
                divisions: 23,
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Apertura all-in')),
                  ButtonSegment(value: true, label: Text('Call vs all-in')),
                ],
                selected: {callMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  callMode = s.first;
                  if (caller <= pusher) caller = players - 1;
                }),
              ),
              const SizedBox(height: 8),
              Text(callMode ? 'Chi va all-in:' : 'La tua posizione:'),
              Wrap(spacing: 6, children: [
                for (var i = 0; i < players - 1; i++)
                  ChoiceChip(
                    label: Text(names[i]),
                    selected: pusher == i,
                    onSelected: (_) {
                      pusher = i;
                      if (caller <= pusher) caller = players - 1;
                      _refresh();
                    },
                  ),
              ]),
              if (callMode) ...[
                const SizedBox(height: 4),
                const Text('La tua posizione:'),
                Wrap(spacing: 6, children: [
                  for (var j = pusher + 1; j < players; j++)
                    ChoiceChip(
                      label: Text(names[j]),
                      selected: caller == j,
                      onSelected: (_) => setState(() => caller = j),
                    ),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          callMode
              ? '${names[pusher]} va all-in ($stack BB), tutti foldano fino a te in ${names[caller]}'
              : 'Tutti foldano fino a te in ${names[pusher]}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Stack(alignment: Alignment.center, children: [
          RangeGrid(
            values: freq ?? Float64List(169),
            color: color,
            selected: selected,
            onCellTap: (i) => setState(() => selected = i),
          ),
          if (loading || freq == null) const CircularProgressIndicator(),
        ]),
        const SizedBox(height: 8),
        if (freq != null) ...[
          Row(children: [
            LegendDot(color, actionName),
            const SizedBox(width: 16),
            const LegendDot(foldColor, 'Fold'),
            const Spacer(),
            Text('$actionName: ${HandRange(freq).percent.toStringAsFixed(1)}% delle mani',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          if (selected != null)
            Card(
              child: ListTile(
                title: Text(HandClass.name(selected!), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                subtitle: Text('$actionName ${fmtPct(freq[selected!])} · EV $actionName ${fmtEv(ev![selected!])} (vs fold)'),
              ),
            )
          else
            const Text('Tocca una mano per vedere frequenza ed EV.'),
          const SizedBox(height: 8),
          SelectableText(HandRange(freq).toString(), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
        const SizedBox(height: 12),
        const Text(
          'Equilibrio di Nash in chip EV: un solo caller, niente ICM. '
          'Ideale per stack corti (fino a ~20 BB).',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }
}
