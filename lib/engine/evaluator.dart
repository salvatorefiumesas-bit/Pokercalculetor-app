import 'dart:typed_data';

/// Valutatore di mani da 5 a 7 carte basato su maschere di bit e tabelle.
///
/// Restituisce un intero: più alto = mano migliore.
/// Categoria nei bit 20+: 0 carta alta, 1 coppia, 2 doppia coppia, 3 tris,
/// 4 scala, 5 colore, 6 full, 7 poker, 8 scala colore.
class HandEvaluator {
  HandEvaluator._();

  static const int highCard = 0;
  static const int onePair = 1;
  static const int twoPair = 2;
  static const int trips = 3;
  static const int straight = 4;
  static const int flush = 5;
  static const int fullHouse = 6;
  static const int quads = 7;
  static const int straightFlush = 8;

  static const List<String> categoryNames = [
    'Carta alta', 'Coppia', 'Doppia coppia', 'Tris', 'Scala',
    'Colore', 'Full', 'Poker', 'Scala colore',
  ];

  static final Uint8List _popcount = _buildPopcount();
  static final Int8List _straightHigh = _buildStraights();
  static final Int32List _top5 = _buildTop5();
  static final Int32List _counts = Int32List(13);

  static Uint8List _buildPopcount() {
    final t = Uint8List(8192);
    for (var m = 1; m < 8192; m++) {
      t[m] = t[m >> 1] + (m & 1);
    }
    return t;
  }

  static Int8List _buildStraights() {
    final t = Int8List(8192);
    for (var m = 0; m < 8192; m++) {
      final mm = (m << 1) | ((m >> 12) & 1); // asso anche come carta bassa
      var high = -1;
      for (var top = 13; top >= 4; top--) {
        if (((mm >> (top - 4)) & 31) == 31) {
          high = top - 1;
          break;
        }
      }
      t[m] = high;
    }
    return t;
  }

  static Int32List _buildTop5() {
    final t = Int32List(8192);
    for (var m = 0; m < 8192; m++) {
      var code = 0, taken = 0;
      for (var r = 12; r >= 0 && taken < 5; r--) {
        if ((m >> r) & 1 == 1) {
          code = (code << 4) | r;
          taken++;
        }
      }
      while (taken < 5) {
        code <<= 4;
        taken++;
      }
      t[m] = code;
    }
    return t;
  }

  static int category(int value) => value >> 20;

  /// Valuta le prime [n] carte di [cards] (default: tutte).
  static int evaluate(List<int> cards, [int? n]) {
    final len = n ?? cards.length;
    final counts = _counts;
    for (var r = 0; r < 13; r++) {
      counts[r] = 0;
    }
    var s0 = 0, s1 = 0, s2 = 0, s3 = 0, rm = 0;
    for (var k = 0; k < len; k++) {
      final c = cards[k];
      final r = c >> 2;
      final bit = 1 << r;
      switch (c & 3) {
        case 0:
          s0 |= bit;
        case 1:
          s1 |= bit;
        case 2:
          s2 |= bit;
        default:
          s3 |= bit;
      }
      counts[r]++;
      rm |= bit;
    }

    final pc = _popcount;
    var fm = 0;
    if (pc[s0] >= 5) {
      fm = s0;
    } else if (pc[s1] >= 5) {
      fm = s1;
    } else if (pc[s2] >= 5) {
      fm = s2;
    } else if (pc[s3] >= 5) {
      fm = s3;
    }
    if (fm != 0) {
      final sf = _straightHigh[fm];
      if (sf >= 0) return (straightFlush << 20) | sf;
      return (flush << 20) | _top5[fm];
    }

    var quad = -1, trip = -1, trip2 = -1, p1 = -1, p2 = -1;
    for (var r = 12; r >= 0; r--) {
      switch (counts[r]) {
        case 4:
          quad = r;
        case 3:
          if (trip < 0) {
            trip = r;
          } else if (trip2 < 0) {
            trip2 = r;
          }
        case 2:
          if (p1 < 0) {
            p1 = r;
          } else if (p2 < 0) {
            p2 = r;
          }
      }
    }

    if (quad >= 0) {
      return (quads << 20) | (quad << 4) | (_top5[rm & ~(1 << quad)] >> 16);
    }
    if (trip >= 0 && (trip2 >= 0 || p1 >= 0)) {
      final pairRank = trip2 > p1 ? trip2 : p1;
      return (fullHouse << 20) | (trip << 4) | pairRank;
    }
    final st = _straightHigh[rm];
    if (st >= 0) return (straight << 20) | st;
    if (trip >= 0) {
      return (trips << 20) | (trip << 8) | (_top5[rm & ~(1 << trip)] >> 12);
    }
    if (p2 >= 0) {
      return (twoPair << 20) |
          (p1 << 8) |
          (p2 << 4) |
          (_top5[rm & ~(1 << p1) & ~(1 << p2)] >> 16);
    }
    if (p1 >= 0) {
      return (onePair << 20) | (p1 << 12) | (_top5[rm & ~(1 << p1)] >> 8);
    }
    return _top5[rm];
  }
}
