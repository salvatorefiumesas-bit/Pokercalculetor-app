import 'package:flutter_test/flutter_test.dart';
import 'package:poker_gto_trainer/engine/cards.dart';
import 'package:poker_gto_trainer/engine/equity.dart';
import 'package:poker_gto_trainer/engine/hand_class.dart';
import 'package:poker_gto_trainer/engine/range.dart';

EquityResult eq(List<String> hands, [String board = '', int samples = 200000]) {
  final boardCards = board.isEmpty ? <int>[] : parseCards(board);
  var dead = 0;
  for (final c in boardCards) {
    dead |= 1 << c;
  }
  final parsed = hands.map(PlayerHand.parse).toList();
  for (final p in parsed) {
    if (p.cards != null) dead |= (1 << p.cards![0]) | (1 << p.cards![1]);
  }
  final cards = <List<int>>[], weights = <List<double>>[];
  for (final p in parsed) {
    final own = p.cards == null ? 0 : (1 << p.cards![0]) | (1 << p.cards![1]);
    final c = p.combos(dead & ~own);
    cards.add(c.cards);
    weights.add(c.weights);
  }
  return calculateEquity(EquityRequest(
      playerCards: cards, playerWeights: weights, board: boardCards, maxSamples: samples));
}

void main() {
  test('classi di mani', () {
    expect(HandClass.name(0), 'AA');
    expect(HandClass.name(1), 'AKs');
    expect(HandClass.name(13), 'AKo');
    expect(HandClass.name(168), '22');
    expect(HandClass.allCombos.length, 1326);
    var total = 0;
    for (var i = 0; i < 169; i++) {
      total += HandClass.combos(i).length;
      for (final c in HandClass.combos(i)) {
        expect(HandClass.ofCards(c[0], c[1]), i);
      }
    }
    expect(total, 1326);
  });

  test('parsing e formattazione range', () {
    final r = HandRange.parse('22+, A2s+, KTo+, QJs:0.5');
    expect(r.comboCount, closeTo(13 * 6 + 12 * 4 + 3 * 12 + 2, 1e-9));
    expect(r.toString(), '22+, A2s+, QJs:0.50, KTo+');
    final again = HandRange.parse(r.toString());
    expect(again.weights, r.weights);
    expect(HandRange.parse('JJ-88').comboCount, 24);
    expect(HandRange.parse('A5s-A2s').comboCount, 16);
    expect(HandRange.parse('AK').comboCount, 16);
    expect(HandRange.full().percent, closeTo(100, 1e-9));
  });

  test('equity mano vs mano preflop', () {
    final r = eq(['AsAh', 'KsKh']);
    expect(r.equity[0], closeTo(0.82, 0.01));
  });

  test('equity esatta su flop', () {
    final r = eq(['AhKh', 'QsQd'], '2h7h9c');
    expect(r.exact, isTrue);
    expect(r.samples, 990);
    expect(r.equity[0] + r.equity[1], closeTo(1, 1e-9));
    expect(r.equity[0], closeTo(0.56, 0.03));
  });

  test('equity range vs range', () {
    final r = eq(['AA', '22'], '', 100000);
    expect(r.equity[0], closeTo(0.82, 0.01));
  });
}
