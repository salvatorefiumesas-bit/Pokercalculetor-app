import 'package:flutter_test/flutter_test.dart';
import 'package:poker_gto_trainer/engine/cards.dart';
import 'package:poker_gto_trainer/engine/evaluator.dart';

int ev(String s) => HandEvaluator.evaluate(parseCards(s));
int cat(String s) => HandEvaluator.category(ev(s));

void main() {
  test('categorie riconosciute', () {
    expect(cat('AsKsQsJsTs2c3d'), HandEvaluator.straightFlush);
    expect(cat('As2s3s4s5s9cKd'), HandEvaluator.straightFlush);
    expect(cat('AsAcAdAh2c3d4h'), HandEvaluator.quads);
    expect(cat('KsKcKdQhQc2d3h'), HandEvaluator.fullHouse);
    expect(cat('KsKcKdQhQcQd3h'), HandEvaluator.fullHouse);
    expect(cat('As9s7s4s2sKdKc'), HandEvaluator.flush);
    expect(cat('Ah2c3d4s5h9cJd'), HandEvaluator.straight);
    expect(cat('TcJdQhKsAc2d3h'), HandEvaluator.straight);
    expect(cat('7c7d7h2s9cJdKh'), HandEvaluator.trips);
    expect(cat('7c7d9h9s2cJdKh'), HandEvaluator.twoPair);
    expect(cat('7c7d9h3s2cJdKh'), HandEvaluator.onePair);
    expect(cat('7c4d9h3s2cJdKh'), HandEvaluator.highCard);
  });

  test('confronti corretti', () {
    expect(ev('AsAcKdKh2c3d4h') > ev('AsAcQdQh2c3d4h'), isTrue);
    expect(ev('6h2c3d4s5h9cJd') > ev('Ah2c3d4s5h9cJd'), isTrue); // 6-high > wheel
    expect(ev('KsKcKdQhQc2d3h') < ev('KsKcKdAhAc2d3h'), isTrue);
    expect(ev('7c7d9h9s2cJdKh') > ev('7c7d9h9s2cJdQh'), isTrue); // kicker
    expect(ev('7c7d9h9s5c5dKh') == ev('7c7d9h9s2cJdKh'), isTrue); // terza coppia non conta
    expect(ev('AcAd2h3s4cJdKh') > ev('AcAd2h3s4cJdQh'), isTrue);
    // Pareggio: board che gioca
    expect(ev('2c3dAsKsQsJsTs'), ev('4h5hAsKsQsJsTs'));
  });
}
