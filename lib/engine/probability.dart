import 'dart:typed_data';

import 'evaluator.dart';

/// Probabilità dei punti per una mano (2 carte) e un board da 0 a 5 carte,
/// calcolate in modo esatto enumerando tutte le carte possibili.
class HandOdds {
  HandOdds({
    required this.boardSize,
    required this.current,
    required this.next,
    required this.river,
    required this.outs,
    required this.flopDraws,
    required this.combos,
  });

  final int boardSize;

  /// Punto attuale (categoria) se ci sono almeno 5 carte, altrimenti null.
  final int? current;

  /// Distribuzione della categoria alla prossima strada (flop, turn o
  /// river). Vuota se il board è completo.
  final Float64List next;

  /// Distribuzione della categoria finale al river.
  final Float64List river;

  /// Carte che migliorano la categoria alla prossima carta (solo da flop e
  /// turn): carta → nuova categoria.
  final Map<int, int> outs;

  /// Solo preflop: probabilità di progetti al flop.
  final FlopDraws? flopDraws;

  /// Numero di combinazioni enumerate per il river.
  final int combos;

  static const List<String> categoryNames = HandEvaluator.categoryNames;
}

class FlopDraws {
  const FlopDraws({
    required this.flushDraw,
    required this.straightDrawOpen,
    required this.gutshot,
    required this.pairOrBetter,
  });

  /// Progetto colore (4 carte dello stesso seme, colore non ancora fatto).
  final double flushDraw;

  /// Progetto scala bilaterale o doppio gutshot (8 outs di scala).
  final double straightDrawOpen;

  /// Scala a incastro (4 outs di scala).
  final double gutshot;

  /// Almeno una coppia al flop.
  final double pairOrBetter;
}

int _straightOuts(int rankMask) {
  // Numero di rank che, aggiunti, completano una scala non già presente.
  if (_hasStraight(rankMask)) return 0;
  var n = 0;
  for (var r = 0; r < 13; r++) {
    if ((rankMask >> r) & 1 == 1) continue;
    if (_hasStraight(rankMask | (1 << r))) n++;
  }
  return n;
}

bool _hasStraight(int m) {
  final mm = (m << 1) | ((m >> 12) & 1);
  for (var top = 13; top >= 4; top--) {
    if (((mm >> (top - 4)) & 31) == 31) return true;
  }
  return false;
}

/// Calcola le probabilità. [hand]: 2 carte; [board]: 0, 3, 4 o 5 carte.
HandOdds computeHandOdds(List<int> hand, List<int> board) {
  var dead = 0;
  for (final c in [...hand, ...board]) {
    dead |= 1 << c;
  }
  final deck = [for (var c = 0; c < 52; c++) if ((dead & (1 << c)) == 0) c];
  final cards = Int32List(7);
  cards[0] = hand[0];
  cards[1] = hand[1];
  for (var k = 0; k < board.length; k++) {
    cards[2 + k] = board[k];
  }
  final b = board.length;
  final total = 2 + b;
  final current = total >= 5 ? HandEvaluator.category(HandEvaluator.evaluate(cards, total)) : null;

  final river = Float64List(9);
  var riverCount = 0;
  final missing = 5 - b;

  // Distribuzione al river: enumerazione di tutte le carte mancanti.
  final idx = List.filled(missing, 0);
  void rec(int start, int depth) {
    if (depth == missing) {
      river[HandEvaluator.category(HandEvaluator.evaluate(cards, 7))] += 1;
      riverCount++;
      return;
    }
    for (var i = start; i <= deck.length - (missing - depth); i++) {
      idx[depth] = i;
      cards[2 + b + depth] = deck[i];
      rec(i + 1, depth + 1);
    }
  }

  if (missing > 0) {
    rec(0, 0);
    for (var k = 0; k < 9; k++) {
      river[k] /= riverCount;
    }
  } else {
    river[current!] = 1;
    riverCount = 1;
  }

  // Prossima strada.
  final next = Float64List(9);
  final outs = <int, int>{};
  FlopDraws? draws;
  if (b == 0) {
    var n = 0, fd = 0, oe = 0, gs = 0, pair = 0;
    for (var i = 0; i < deck.length; i++) {
      for (var j = i + 1; j < deck.length; j++) {
        for (var k = j + 1; k < deck.length; k++) {
          cards[2] = deck[i];
          cards[3] = deck[j];
          cards[4] = deck[k];
          final cat = HandEvaluator.category(HandEvaluator.evaluate(cards, 5));
          next[cat] += 1;
          n++;
          if (cat >= HandEvaluator.onePair) pair++;
          if (cat < HandEvaluator.flush) {
            // Progetto colore: 4 carte dello stesso seme, almeno una nostra.
            final suits = [0, 0, 0, 0];
            var rm = 0;
            for (var q = 0; q < 5; q++) {
              suits[cards[q] & 3]++;
              rm |= 1 << (cards[q] >> 2);
            }
            for (var s = 0; s < 4; s++) {
              if (suits[s] == 4 && ((cards[0] & 3) == s || (cards[1] & 3) == s)) {
                fd++;
                break;
              }
            }
            if (cat < HandEvaluator.straight) {
              final so = _straightOuts(rm);
              if (so >= 2) {
                oe++;
              } else if (so == 1) {
                gs++;
              }
            }
          }
        }
      }
    }
    for (var c = 0; c < 9; c++) {
      next[c] /= n;
    }
    draws = FlopDraws(
      flushDraw: fd / n,
      straightDrawOpen: oe / n,
      gutshot: gs / n,
      pairOrBetter: pair / n,
    );
  } else if (b == 3 || b == 4) {
    final boardOnly = Int32List(5);
    for (var k = 0; k < b; k++) {
      boardOnly[k] = board[k];
    }
    for (final c in deck) {
      cards[2 + b] = c;
      final cat = HandEvaluator.category(HandEvaluator.evaluate(cards, total + 1));
      next[cat] += 1;
      // Out = la carta migliora il tuo punto e il miglioramento non è solo
      // del board (es. una carta che accoppia il board dà la coppia a tutti).
      boardOnly[b] = c;
      final boardCat = HandEvaluator.category(HandEvaluator.evaluate(boardOnly, b + 1));
      if (cat > current! && cat > boardCat) outs[c] = cat;
    }
    for (var c = 0; c < 9; c++) {
      next[c] /= deck.length;
    }
  }

  return HandOdds(
    boardSize: b,
    current: current,
    next: next,
    river: river,
    outs: outs,
    flopDraws: draws,
    combos: riverCount,
  );
}

/// Probabilità di chiudere almeno uno degli [outs] (su [unseen] carte
/// sconosciute) con una carta o con due carte.
double probOneCard(int outs, int unseen) => outs / unseen;

double probTwoCards(int outs, int unseen) => 1 - ((unseen - outs) * (unseen - outs - 1)) / (unseen * (unseen - 1));

/// Texture del flop su tutti i 22.100 flop possibili.
class FlopTexture {
  const FlopTexture({
    required this.rainbow,
    required this.twoTone,
    required this.monotone,
    required this.paired,
    required this.trips,
    required this.straightPossible,
    required this.connected,
  });

  final double rainbow, twoTone, monotone, paired, trips, straightPossible, connected;
}

FlopTexture computeFlopTexture() {
  var n = 0, rb = 0, tt = 0, mono = 0, pr = 0, tr = 0, sp = 0, conn = 0;
  for (var a = 0; a < 52; a++) {
    for (var b = a + 1; b < 52; b++) {
      for (var c = b + 1; c < 52; c++) {
        n++;
        final sa = a & 3, sb = b & 3, sc = c & 3;
        final distinctSuits = {sa, sb, sc}.length;
        if (distinctSuits == 3) rb++;
        if (distinctSuits == 2) tt++;
        if (distinctSuits == 1) mono++;
        final ra = a >> 2, rbk = b >> 2, rc = c >> 2;
        final distinctRanks = {ra, rbk, rc}.length;
        if (distinctRanks == 2) pr++;
        if (distinctRanks == 1) tr++;
        if (distinctRanks == 3) {
          final m = (1 << ra) | (1 << rbk) | (1 << rc);
          // Scala possibile: due carte qualsiasi la completano.
          var possible = false;
          for (var x = 0; x < 13 && !possible; x++) {
            for (var y = x; y < 13 && !possible; y++) {
              if (_hasStraight(m | (1 << x) | (1 << y))) possible = true;
            }
          }
          if (possible) sp++;
          // Tre carte consecutive (asso anche basso).
          final mm = (m << 1) | ((m >> 12) & 1);
          for (var top = 13; top >= 2; top--) {
            if (((mm >> (top - 2)) & 7) == 7) {
              conn++;
              break;
            }
          }
        }
      }
    }
  }
  return FlopTexture(
    rainbow: rb / n,
    twoTone: tt / n,
    monotone: mono / n,
    paired: pr / n,
    trips: tr / n,
    straightPossible: sp / n,
    connected: conn / n,
  );
}
