// Genera assets/preflop_equity.bin: equity all-in preflop di ogni classe di
// mani contro ogni altra (169 x 169, Float32 little-endian).
//
// Uso:  dart run tool/gen_preflop_equity.dart [campioni_per_coppia]
// (consigliato compilarlo: dart compile exe tool/gen_preflop_equity.dart)
import 'dart:io';
import 'dart:typed_data';

import 'package:poker_gto_trainer/engine/evaluator.dart';
import 'package:poker_gto_trainer/engine/hand_class.dart';
import 'package:poker_gto_trainer/engine/rng.dart';

void main(List<String> args) {
  final samples = args.isNotEmpty ? int.parse(args[0]) : 50000;
  final rng = FastRng(20261114);
  final eq = Float32List(169 * 169);
  final combos = [for (var i = 0; i < 169; i++) HandClass.combos(i)];
  final h1 = Int32List(7), h2 = Int32List(7);
  final sw = Stopwatch()..start();

  for (var a = 0; a < 169; a++) {
    eq[a * 169 + a] = 0.5;
    for (var b = a + 1; b < 169; b++) {
      var score = 0.0;
      var done = 0;
      while (done < samples) {
        final ca = combos[a][rng.nextInt(combos[a].length)];
        final cb = combos[b][rng.nextInt(combos[b].length)];
        final ma = (1 << ca[0]) | (1 << ca[1]);
        final mb = (1 << cb[0]) | (1 << cb[1]);
        if ((ma & mb) != 0) continue;
        var used = ma | mb;
        h1[0] = ca[0];
        h1[1] = ca[1];
        h2[0] = cb[0];
        h2[1] = cb[1];
        for (var k = 2; k < 7; k++) {
          int c;
          do {
            c = rng.nextInt(52);
          } while ((used & (1 << c)) != 0);
          used |= 1 << c;
          h1[k] = c;
          h2[k] = c;
        }
        final v1 = HandEvaluator.evaluate(h1, 7), v2 = HandEvaluator.evaluate(h2, 7);
        if (v1 > v2) {
          score += 1;
        } else if (v1 == v2) {
          score += 0.5;
        }
        done++;
      }
      final e = score / samples;
      eq[a * 169 + b] = e;
      eq[b * 169 + a] = 1 - e;
    }
    stderr.write('\r${a + 1}/169  ${sw.elapsed.inSeconds}s');
  }
  stderr.writeln();
  final out = File('assets/preflop_equity.bin');
  out.writeAsBytesSync(eq.buffer.asUint8List());
  stdout.writeln('Scritto ${out.path} (${out.lengthSync()} byte) in ${sw.elapsed.inSeconds}s');
}
