import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poker_gto_trainer/engine/hand_class.dart';
import 'package:poker_gto_trainer/engine/preflop_data.dart';
import 'package:poker_gto_trainer/engine/preflop_solver.dart';
import 'package:poker_gto_trainer/engine/pushfold.dart';

void main() {
  final data = PreflopData.fromBytes(File('assets/preflop_equity.bin').readAsBytesSync().buffer.asByteData());

  FullPreflopSolution solve(int players, int stack, int opener) => solveFullPreflop(
        PushFoldConfig(players: players, stack: stack, ante: AnteType.bigBlindAnte, pusher: opener),
        data,
      );

  void expectNormalized(StrategyNode node) {
    for (var h = 0; h < 169; h++) {
      var s = 0.0;
      for (final f in node.freq) {
        s += f[h];
      }
      expect(s, closeTo(1, 1e-9));
    }
  }

  test('UTG 9-max 25bb: apre stretto, soprattutto col rilancio', () {
    final s = solve(9, 25, 0);
    final o = s.open;
    expect(o.actions, [PokerAction.fold, PokerAction.raise, PokerAction.allIn]);
    expectNormalized(o);
    final raise = o.percent(1), fold = o.percent(0);
    expect(raise, inInclusiveRange(10, 22));
    expect(fold, greaterThan(75));
    // AA rilancia sempre, 72o folda sempre.
    expect(o.freq[1][HandClass.pairIndex(12)], 1);
    expect(o.freq[0][HandClass.offsuitIndex(5, 0)], 1);
    // Solo il BB può fare call contro il rilancio.
    expect(s.vsRaise[8]!.actions, contains(PokerAction.call));
    expect(s.vsRaise[3]!.actions, isNot(contains(PokerAction.call)));
    expectNormalized(s.vsRaise[8]!);
  });

  test('stack corto: prevale l\'all-in', () {
    final s = solve(9, 6, 6); // BTN 6bb
    final jam = s.open.percent(2), raise = s.open.percent(1);
    expect(jam, greaterThan(raise));
  });

  test('BTN apre più largo di UTG', () {
    final utg = solve(9, 20, 0), btn = solve(9, 20, 6);
    expect(100 - btn.open.percent(0), greaterThan(100 - utg.open.percent(0) + 15));
  });

  test('SB vs BB: esistono limp e nodi dopo il limp', () {
    final s = solve(9, 20, 7);
    expect(s.open.actions, contains(PokerAction.limp));
    expect(s.vsLimp, isNotNull);
    expect(s.limpVsJam, isNotNull);
    expectNormalized(s.vsLimp!);
    expect(s.open.percent(s.open.indexOf(PokerAction.limp)), greaterThan(10));
  });

  test('EV coerenti: l\'azione con frequenza piena è la migliore', () {
    final s = solve(6, 15, 3);
    final o = s.open;
    for (var h = 0; h < 169; h++) {
      for (var k = 0; k < o.actions.length; k++) {
        if (o.freq[k][h] == 1) {
          expect(o.ev[k][h], greaterThanOrEqualTo(o.ev[o.bestAction(h)][h] - 0.05));
        }
      }
    }
  });
}
