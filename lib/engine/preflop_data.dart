import 'dart:typed_data';

import 'hand_class.dart';

/// Dati preflop precalcolati usati dal solver push/fold.
class PreflopData {
  /// eq[a*169+b] = equity all-in della classe a contro la classe b.
  final Float32List eq;

  /// w[a*169+b] = numero di coppie di combinazioni compatibili (senza carte
  /// in comune) tra la classe a e la classe b. Gestisce il card removal.
  final Float64List w;

  /// Equity di ogni classe contro una mano casuale.
  final Float64List eqVsRandom;

  PreflopData._(this.eq, this.w, this.eqVsRandom);

  factory PreflopData.fromBytes(ByteData bytes) {
    final eq = Float32List(169 * 169);
    for (var i = 0; i < eq.length; i++) {
      eq[i] = bytes.getFloat32(i * 4, Endian.little);
    }
    final w = computeComboWeights();
    final vr = Float64List(169);
    for (var a = 0; a < 169; a++) {
      var num = 0.0, den = 0.0;
      for (var b = 0; b < 169; b++) {
        num += w[a * 169 + b] * eq[a * 169 + b];
        den += w[a * 169 + b];
      }
      vr[a] = num / den;
    }
    return PreflopData._(eq, w, vr);
  }

  static Float64List computeComboWeights() {
    final w = Float64List(169 * 169);
    final all = HandClass.allCombos;
    final masks = [for (final c in all) (1 << c[0]) | (1 << c[1])];
    for (var i = 0; i < all.length; i++) {
      final mi = masks[i];
      final row = all[i][2] * 169;
      for (var j = 0; j < all.length; j++) {
        if ((mi & masks[j]) == 0) w[row + all[j][2]] += 1;
      }
    }
    return w;
  }

  /// Classi ordinate dalla più forte alla più debole (equity vs mano casuale).
  List<int> get strengthOrder {
    final order = List.generate(169, (i) => i);
    order.sort((a, b) => eqVsRandom[b].compareTo(eqVsRandom[a]));
    return order;
  }
}
