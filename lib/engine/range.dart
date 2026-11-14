import 'dart:typed_data';

import 'cards.dart';
import 'hand_class.dart';

/// Un range preflop: un peso 0..1 per ciascuna delle 169 classi.
class HandRange {
  final Float64List weights;

  HandRange([Float64List? w]) : weights = w ?? Float64List(HandClass.count);

  HandRange.full() : weights = Float64List(HandClass.count)..fillRange(0, HandClass.count, 1);

  HandRange copy() => HandRange(Float64List.fromList(weights));

  double operator [](int idx) => weights[idx];
  void operator []=(int idx, double v) => weights[idx] = v;

  bool get isEmpty => weights.every((w) => w <= 0);

  /// Numero di combinazioni (pesate) nel range.
  double get comboCount {
    var s = 0.0;
    for (var i = 0; i < HandClass.count; i++) {
      s += weights[i] * HandClass.comboCount(i);
    }
    return s;
  }

  /// Percentuale delle 1326 combinazioni coperte dal range.
  double get percent => comboCount / 1326 * 100;

  /// Legge un range in notazione standard, es. "22+, A2s+, KTo+, QJs:0.5".
  static HandRange parse(String text) {
    final r = HandRange();
    final tokens = text
        .split(RegExp(r'[,\s]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    for (final raw in tokens) {
      var token = raw;
      var weight = 1.0;
      final colon = token.indexOf(':');
      if (colon >= 0) {
        weight = double.tryParse(token.substring(colon + 1)) ??
            (throw FormatException('Peso non valido: $raw'));
        if (weight > 1) weight /= 100; // accetta anche "AKs:50"
        token = token.substring(0, colon);
      }
      for (final idx in _expandToken(token)) {
        r.weights[idx] = weight.clamp(0.0, 1.0);
      }
    }
    return r;
  }

  static List<int> _expandToken(String token) {
    final t = token.trim();
    final dash = t.indexOf('-');
    if (dash > 0) {
      final a = _single(t.substring(0, dash));
      final b = _single(t.substring(dash + 1));
      if (a.kind != b.kind) throw FormatException('Intervallo non valido: $t');
      if (a.kind == 'p') {
        final lo = a.high < b.high ? a.high : b.high;
        final hi = a.high < b.high ? b.high : a.high;
        return [for (var r = lo; r <= hi; r++) HandClass.pairIndex(r)];
      }
      if (a.high != b.high) throw FormatException('Intervallo non valido: $t');
      final lo = a.low < b.low ? a.low : b.low;
      final hi = a.low < b.low ? b.low : a.low;
      return [for (var k = lo; k <= hi; k++) ..._indices(a.kind, a.high, k)];
    }
    final plus = t.endsWith('+');
    final h = _single(plus ? t.substring(0, t.length - 1) : t);
    if (!plus) {
      return h.kind == 'p'
          ? [HandClass.pairIndex(h.high)]
          : _indices(h.kind, h.high, h.low);
    }
    if (h.kind == 'p') {
      return [for (var r = h.high; r <= 12; r++) HandClass.pairIndex(r)];
    }
    return [for (var k = h.low; k < h.high; k++) ..._indices(h.kind, h.high, k)];
  }

  static List<int> _indices(String kind, int high, int low) {
    switch (kind) {
      case 's':
        return [HandClass.suitedIndex(high, low)];
      case 'o':
        return [HandClass.offsuitIndex(high, low)];
      default:
        return [HandClass.suitedIndex(high, low), HandClass.offsuitIndex(high, low)];
    }
  }

  static ({String kind, int high, int low}) _single(String s) {
    if (s.length < 2 || s.length > 3) throw FormatException('Mano non valida: $s');
    var a = rankFromChar(s[0]), b = rankFromChar(s[1]);
    if (a < b) {
      final t = a;
      a = b;
      b = t;
    }
    if (a == b) {
      if (s.length == 3) throw FormatException('Mano non valida: $s');
      return (kind: 'p', high: a, low: b);
    }
    if (s.length == 2) return (kind: 'b', high: a, low: b);
    final k = s[2].toLowerCase();
    if (k != 's' && k != 'o') throw FormatException('Mano non valida: $s');
    return (kind: k, high: a, low: b);
  }

  /// Converte il range in testo compatto.
  @override
  String toString() {
    final parts = <String>[];
    final w = weights;
    String fmtW(double v) => v >= 0.999 ? '' : ':${v.toStringAsFixed(2)}';

    // Coppie
    var r = 12;
    while (r >= 0) {
      final v = w[HandClass.pairIndex(r)];
      if (v <= 0) {
        r--;
        continue;
      }
      var end = r;
      while (end - 1 >= 0 && w[HandClass.pairIndex(end - 1)] == v) {
        end--;
      }
      final top = rankChars[r] * 2, bottom = rankChars[end] * 2;
      if (r == 12 && end < r) {
        parts.add('$bottom+${fmtW(v)}');
      } else if (end < r) {
        parts.add('$top-$bottom${fmtW(v)}');
      } else {
        parts.add('$top${fmtW(v)}');
      }
      r = end - 1;
    }

    // Suited e offsuit
    for (final kind in ['s', 'o']) {
      for (var h = 12; h >= 1; h--) {
        int idx(int low) => kind == 's'
            ? HandClass.suitedIndex(h, low)
            : HandClass.offsuitIndex(h, low);
        var k = h - 1;
        while (k >= 0) {
          final v = w[idx(k)];
          if (v <= 0) {
            k--;
            continue;
          }
          var end = k;
          while (end - 1 >= 0 && w[idx(end - 1)] == v) {
            end--;
          }
          final hc = rankChars[h];
          if (k == h - 1 && end < k) {
            parts.add('$hc${rankChars[end]}$kind+${fmtW(v)}');
          } else if (end < k) {
            parts.add('$hc${rankChars[k]}$kind-$hc${rankChars[end]}$kind${fmtW(v)}');
          } else {
            parts.add('$hc${rankChars[k]}$kind${fmtW(v)}');
          }
          k = end - 1;
        }
      }
    }
    return parts.join(', ');
  }
}

/// Input di un giocatore nel calcolatore: mano specifica o range.
class PlayerHand {
  final List<int>? cards;
  final HandRange? range;

  PlayerHand.cards(this.cards) : range = null;
  PlayerHand.range(this.range) : cards = null;

  static final RegExp _specific = RegExp(r'^([2-9TJQKA][cdhs]){2}$', caseSensitive: false);

  static PlayerHand parse(String text) {
    final t = text.replaceAll(' ', '');
    if (t.isEmpty) throw const FormatException('Inserisci una mano o un range');
    if (_specific.hasMatch(t)) {
      final c = parseCards(t);
      return PlayerHand.cards(c);
    }
    final r = HandRange.parse(text);
    if (r.isEmpty) throw FormatException('Range vuoto: $text');
    return PlayerHand.range(r);
  }

  /// Combinazioni pesate compatibili con le carte morte [deadMask].
  /// Restituisce coppie di liste: carte (2 per combo) e pesi.
  ({List<int> cards, List<double> weights}) combos(int deadMask) {
    final cs = <int>[];
    final ws = <double>[];
    if (cards != null) {
      final c = cards!;
      if ((deadMask & (1 << c[0])) == 0 && (deadMask & (1 << c[1])) == 0) {
        cs.addAll(c);
        ws.add(1);
      }
      return (cards: cs, weights: ws);
    }
    for (var i = 0; i < HandClass.count; i++) {
      final w = range!.weights[i];
      if (w <= 0) continue;
      for (final combo in HandClass.combos(i)) {
        if ((deadMask & (1 << combo[0])) != 0 || (deadMask & (1 << combo[1])) != 0) {
          continue;
        }
        cs.addAll(combo);
        ws.add(w);
      }
    }
    return (cards: cs, weights: ws);
  }
}
