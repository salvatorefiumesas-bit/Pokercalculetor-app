import 'package:flutter_test/flutter_test.dart';
import 'package:poker_gto_trainer/engine/cards.dart';
import 'package:poker_gto_trainer/engine/evaluator.dart';
import 'package:poker_gto_trainer/engine/probability.dart';

void main() {
  test('coppia in mano: tris o meglio al flop', () {
    final o = computeHandOdds(parseCards('7c7d'), []);
    final setOrBetter = o.next[HandEvaluator.trips] + o.next[HandEvaluator.fullHouse] + o.next[HandEvaluator.quads];
    // 11,76% di set (almeno un 7 sul flop) + i flop con tris sul board (full).
    expect(setOrBetter, closeTo(1 - 17296 / 19600 + 48 / 19600, 1e-9));
    expect(o.combos, 2118760); // C(50,5)
    expect(o.river.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
  });

  test('suited: colore al flop 0,84%, progetto colore 10,94%', () {
    final o = computeHandOdds(parseCards('AhKh'), []);
    expect(o.next[HandEvaluator.flush] + o.next[HandEvaluator.straightFlush], closeTo(0.0084, 0.0003));
    expect(o.flopDraws!.flushDraw, closeTo(0.1094, 0.0005));
  });

  test('outs: progetto colore al flop = 9 outs', () {
    final o = computeHandOdds(parseCards('AhKh'), parseCards('2h7h9c'));
    final flushOuts = o.outs.values.where((c) => c == HandEvaluator.flush).length;
    expect(flushOuts, 9);
    expect(o.current, HandEvaluator.highCard);
    expect(probTwoCards(9, 47), closeTo(0.3497, 0.0001));
  });

  test('outs: le carte che accoppiano il board non contano', () {
    final o = computeHandOdds(parseCards('8d7s'), parseCards('9d5s2h'));
    expect(o.outs.length, 10); // 4 sei (scala) + 3 otto + 3 sette (coppia)
  });

  test('river completo: probabilità 100% del punto attuale', () {
    final o = computeHandOdds(parseCards('AhKh'), parseCards('2h7h9cAs3d'));
    expect(o.current, HandEvaluator.onePair);
    expect(o.river[HandEvaluator.onePair], 1);
  });

  test('texture del flop', () {
    final t = computeFlopTexture();
    expect(t.rainbow, closeTo(0.3976, 0.0001));
    expect(t.twoTone, closeTo(0.5506, 0.0001));
    expect(t.monotone, closeTo(0.0518, 0.0001));
    expect(t.paired + t.trips, closeTo(0.1718, 0.0001));
  });
}
