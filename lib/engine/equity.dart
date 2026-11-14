import 'dart:typed_data';

import 'evaluator.dart';
import 'rng.dart';

/// Richiesta di calcolo equity (serializzabile verso un isolate).
class EquityRequest {
  /// Per ogni giocatore: carte delle combinazioni (2 per combo) e pesi.
  final List<List<int>> playerCards;
  final List<List<double>> playerWeights;
  final List<int> board;
  final int maxSamples;

  const EquityRequest({
    required this.playerCards,
    required this.playerWeights,
    required this.board,
    this.maxSamples = 200000,
  });
}

class EquityResult {
  final List<double> equity;
  final List<double> win;
  final List<double> tie;
  final int samples;
  final bool exact;

  const EquityResult(this.equity, this.win, this.tie, this.samples, this.exact);
}

int _choose(int n, int k) {
  if (k < 0 || k > n) return 0;
  var r = 1;
  for (var i = 0; i < k; i++) {
    r = r * (n - i) ~/ (i + 1);
  }
  return r;
}

/// Calcola l'equity di 2..N giocatori. Enumerazione esatta quando possibile,
/// altrimenti Monte Carlo.
EquityResult calculateEquity(EquityRequest req) {
  final n = req.playerCards.length;
  final board = req.board;
  var boardMask = 0;
  for (final c in board) {
    boardMask |= 1 << c;
  }
  final missing = 5 - board.length;

  final allSingle = req.playerWeights.every((w) => w.length == 1);
  final eq = Float64List(n), win = Float64List(n), tie = Float64List(n);
  final hands = List.generate(n, (_) => Int32List(7));
  for (final h in hands) {
    for (var k = 0; k < board.length; k++) {
      h[k + 2] = board[k];
    }
  }
  final values = Int32List(n);

  void score(double weight) {
    var best = -1, cnt = 0;
    for (var p = 0; p < n; p++) {
      final v = HandEvaluator.evaluate(hands[p], 7);
      values[p] = v;
      if (v > best) {
        best = v;
        cnt = 1;
      } else if (v == best) {
        cnt++;
      }
    }
    for (var p = 0; p < n; p++) {
      if (values[p] == best) {
        eq[p] += weight / cnt;
        if (cnt == 1) {
          win[p] += weight;
        } else {
          tie[p] += weight;
        }
      }
    }
  }

  if (allSingle) {
    var dead = boardMask;
    for (var p = 0; p < n; p++) {
      final c = req.playerCards[p];
      hands[p][0] = c[0];
      hands[p][1] = c[1];
      dead |= (1 << c[0]) | (1 << c[1]);
    }
    final deck = [for (var c = 0; c < 52; c++) if ((dead & (1 << c)) == 0) c];
    if (_choose(deck.length, missing) <= req.maxSamples) {
      var total = 0;
      final idx = List.filled(missing, 0);
      void rec(int start, int depth) {
        if (depth == missing) {
          for (var p = 0; p < n; p++) {
            for (var k = 0; k < missing; k++) {
              hands[p][2 + board.length + k] = deck[idx[k]];
            }
          }
          score(1);
          total++;
          return;
        }
        for (var i = start; i <= deck.length - (missing - depth); i++) {
          idx[depth] = i;
          rec(i + 1, depth + 1);
        }
      }

      rec(0, 0);
      return _result(eq, win, tie, total, true);
    }
  }

  // Monte Carlo
  final rng = FastRng();
  final cum = <Float64List>[];
  for (final w in req.playerWeights) {
    final c = Float64List(w.length);
    var s = 0.0;
    for (var i = 0; i < w.length; i++) {
      s += w[i];
      c[i] = s;
    }
    cum.add(c);
  }
  int pick(int p) {
    final c = cum[p];
    final x = rng.nextDouble() * c[c.length - 1];
    var lo = 0, hi = c.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (c[mid] > x) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  var samples = 0, attempts = 0;
  final maxAttempts = req.maxSamples * 50;
  while (samples < req.maxSamples && attempts < maxAttempts) {
    attempts++;
    var used = boardMask;
    var ok = true;
    for (var p = 0; p < n; p++) {
      final i = pick(p);
      final c1 = req.playerCards[p][2 * i], c2 = req.playerCards[p][2 * i + 1];
      final m = (1 << c1) | (1 << c2);
      if ((used & m) != 0) {
        ok = false;
        break;
      }
      used |= m;
      hands[p][0] = c1;
      hands[p][1] = c2;
    }
    if (!ok) continue;
    for (var k = 0; k < missing; k++) {
      int c;
      do {
        c = rng.nextInt(52);
      } while ((used & (1 << c)) != 0);
      used |= 1 << c;
      for (var p = 0; p < n; p++) {
        hands[p][2 + board.length + k] = c;
      }
    }
    score(1);
    samples++;
  }
  return _result(eq, win, tie, samples, false);
}

EquityResult _result(Float64List eq, Float64List win, Float64List tie, int total, bool exact) {
  final t = total == 0 ? 1 : total;
  return EquityResult(
    [for (final v in eq) v / t],
    [for (final v in win) v / t],
    [for (final v in tie) v / t],
    total,
    exact,
  );
}
