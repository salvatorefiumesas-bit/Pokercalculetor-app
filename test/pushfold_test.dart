import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poker_gto_trainer/engine/hand_class.dart';
import 'package:poker_gto_trainer/engine/preflop_data.dart';
import 'package:poker_gto_trainer/engine/pushfold.dart';
import 'package:poker_gto_trainer/engine/range.dart';

void main() {
  final bytes = File('assets/preflop_equity.bin').readAsBytesSync();
  final data = PreflopData.fromBytes(bytes.buffer.asByteData());

  double pct(List<double> f) {
    var s = 0.0;
    for (var i = 0; i < 169; i++) {
      s += f[i] * HandClass.comboCount(i);
    }
    return s / 1326 * 100;
  }

  test('matrice equity coerente', () {
    final aa = HandClass.pairIndex(12);
    final kk = HandClass.pairIndex(11);
    final e = data.eq[aa * 169 + kk];
    expect(e, closeTo(0.82, 0.02));
    expect(data.eqVsRandom[aa], closeTo(0.852, 0.01));
  });

  test('heads-up 10bb senza ante: range di Nash noti', () {
    final sol = solvePushFold(
      const PushFoldConfig(players: 2, stack: 10, ante: AnteType.none, pusher: 0),
      data,
    );
    final push = pct(sol.push), call = pct(sol.call[1]!);
    // ignore: avoid_print
    print('HU 10bb: push ${push.toStringAsFixed(1)}%  call ${call.toStringAsFixed(1)}%  '
        'expl ${sol.exploitability.toStringAsFixed(4)}');
    expect(push, closeTo(58, 2));
    expect(call, closeTo(37, 2));
    expect(sol.push[HandClass.pairIndex(12)], 1);
    expect(sol.push[HandClass.offsuitIndex(5, 0)], 0); // 72o
  });

  test('9 giocatori, UTG 10bb, BB ante: range stretto', () {
    final sol = solvePushFold(
      const PushFoldConfig(players: 9, stack: 10, ante: AnteType.bigBlindAnte, pusher: 0),
      data,
    );
    final push = pct(sol.push);
    // ignore: avoid_print
    print('UTG 9-max 10bb: push ${push.toStringAsFixed(1)}%  '
        'BB call ${pct(sol.call[8]!).toStringAsFixed(1)}%  '
        'expl ${sol.exploitability.toStringAsFixed(4)}');
    // ignore: avoid_print
    print(HandRange(sol.push).toString());
    expect(push, inInclusiveRange(5, 20));
  });
}
