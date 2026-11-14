import 'cards.dart';

/// Le 169 classi di mani preflop, disposte nella classica griglia 13x13.
///
/// Riga/colonna 0 = Asso, 12 = Due. Sulla diagonale le coppie, sopra le
/// mani suited, sotto le offsuit. Indice = riga * 13 + colonna.
class HandClass {
  HandClass._();

  static const int count = 169;

  static int rankAt(int gridPos) => 12 - gridPos;

  static bool isPair(int idx) => idx ~/ 13 == idx % 13;
  static bool isSuited(int idx) => idx ~/ 13 < idx % 13;
  static bool isOffsuit(int idx) => idx ~/ 13 > idx % 13;

  static int highRank(int idx) {
    final i = idx ~/ 13, j = idx % 13;
    return rankAt(i < j ? i : j);
  }

  static int lowRank(int idx) {
    final i = idx ~/ 13, j = idx % 13;
    return rankAt(i < j ? j : i);
  }

  static int pairIndex(int rank) => (12 - rank) * 14;

  static int suitedIndex(int high, int low) => (12 - high) * 13 + (12 - low);

  static int offsuitIndex(int high, int low) => (12 - low) * 13 + (12 - high);

  static String name(int idx) {
    final h = rankChars[highRank(idx)], l = rankChars[lowRank(idx)];
    if (isPair(idx)) return '$h$l';
    return isSuited(idx) ? '$h${l}s' : '$h${l}o';
  }

  static int comboCount(int idx) => isPair(idx) ? 6 : (isSuited(idx) ? 4 : 12);

  /// Classe di una combinazione specifica di due carte.
  static int ofCards(int c1, int c2) {
    var r1 = rankOf(c1), r2 = rankOf(c2);
    if (r1 < r2) {
      final t = r1;
      r1 = r2;
      r2 = t;
    }
    if (r1 == r2) return pairIndex(r1);
    if (suitOf(c1) == suitOf(c2)) return suitedIndex(r1, r2);
    return offsuitIndex(r1, r2);
  }

  /// Tutte le combinazioni (coppie di carte) di una classe.
  static List<List<int>> combos(int idx) {
    final h = highRank(idx), l = lowRank(idx);
    final out = <List<int>>[];
    if (isPair(idx)) {
      for (var a = 0; a < 4; a++) {
        for (var b = a + 1; b < 4; b++) {
          out.add([makeCard(h, a), makeCard(h, b)]);
        }
      }
    } else if (isSuited(idx)) {
      for (var s = 0; s < 4; s++) {
        out.add([makeCard(h, s), makeCard(l, s)]);
      }
    } else {
      for (var a = 0; a < 4; a++) {
        for (var b = 0; b < 4; b++) {
          if (a != b) out.add([makeCard(h, a), makeCard(l, b)]);
        }
      }
    }
    return out;
  }

  /// Le 1326 combinazioni preflop: [c1, c2, classe].
  static final List<List<int>> allCombos = _buildAll();

  static List<List<int>> _buildAll() {
    final out = <List<int>>[];
    for (var a = 0; a < 52; a++) {
      for (var b = a + 1; b < 52; b++) {
        out.add([b, a, ofCards(a, b)]);
      }
    }
    return out;
  }
}
