import 'package:material_ui/material_ui.dart';

import '../engine/hand_class.dart';
import '../engine/range.dart';
import 'app_data.dart';
import 'widgets.dart';

/// Editor di range: trascina sulla griglia per aggiungere o togliere mani.
/// Restituisce il range in formato testo.
class RangeEditorPage extends StatefulWidget {
  const RangeEditorPage({super.key, required this.initial});

  final String initial;

  @override
  State<RangeEditorPage> createState() => _RangeEditorPageState();
}

class _RangeEditorPageState extends State<RangeEditorPage> {
  late HandRange range;
  late final TextEditingController text;
  bool painting = true;
  double topPercent = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    try {
      range = HandRange.parse(widget.initial);
    } catch (_) {
      range = HandRange();
    }
    text = TextEditingController(text: range.toString());
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void _sync() {
    text.text = range.toString();
    error = null;
  }

  void _setTop(double pct) {
    final r = HandRange();
    var combos = 0.0;
    for (final idx in AppData.preflop.strengthOrder) {
      if (combos / 1326 * 100 >= pct) break;
      r[idx] = 1;
      combos += HandClass.comboCount(idx);
    }
    setState(() {
      range = r;
      topPercent = pct;
      _sync();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor range'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, range.toString()),
            child: const Text('Usa range'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          RangeGrid(
            values: range.weights,
            color: rangeColor,
            onPaintStart: (i) => setState(() {
              painting = range[i] <= 0;
              range[i] = painting ? 1 : 0;
              _sync();
            }),
            onPaintUpdate: (i) => setState(() {
              range[i] = painting ? 1 : 0;
              _sync();
            }),
            onCellTap: (i) => setState(() {
              range[i] = range[i] > 0 ? 0 : 1;
              _sync();
            }),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('${range.percent.toStringAsFixed(1)}% · ${range.comboCount.toStringAsFixed(0)} combo',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () => _setTop(0), child: const Text('Svuota')),
            TextButton(onPressed: () => _setTop(100), child: const Text('Tutto')),
          ]),
          Text('Top ${topPercent.round()}% delle mani'),
          Slider(
            value: topPercent,
            min: 0,
            max: 100,
            divisions: 100,
            label: '${topPercent.round()}%',
            onChanged: _setTop,
          ),
          TextField(
            controller: text,
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(
              labelText: 'Range (es. 22+, A2s+, KTo+)',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
            onChanged: (v) {
              try {
                final r = HandRange.parse(v);
                setState(() {
                  range = r;
                  error = null;
                });
              } on FormatException catch (e) {
                setState(() => error = e.message);
              }
            },
          ),
          const SizedBox(height: 8),
          const Text('Trascina sulla griglia per aggiungere o togliere mani.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
