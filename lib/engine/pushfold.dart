import 'dart:typed_data';

import 'preflop_data.dart';

/// Tipo di ante del torneo.
enum AnteType {
  none('Nessuno'),
  bigBlindAnte('BB ante'),
  classic('Classico 12,5%');

  final String label;
  const AnteType(this.label);

  /// Ante totale (dead money) in big blind.
  double total(int players) => switch (this) {
        AnteType.none => 0,
        AnteType.bigBlindAnte => 1,
        AnteType.classic => 0.125 * players,
      };
}

const List<String> _fullTable = ['UTG', 'UTG+1', 'UTG+2', 'LJ', 'HJ', 'CO', 'BTN', 'SB', 'BB'];

/// Nomi delle posizioni in ordine di azione preflop.
List<String> positionNames(int players) {
  if (players == 2) return const ['SB', 'BB'];
  return _fullTable.sublist(9 - players);
}

/// Blind già messo da una posizione (in BB).
double blindPosted(int players, int pos) {
  if (pos == players - 1) return 1;
  if (pos == players - 2) return 0.5;
  return 0;
}

class PushFoldConfig {
  final int players;
  final int stack; // stack effettivo in BB
  final AnteType ante;
  final int pusher; // indice posizione di chi va all-in

  const PushFoldConfig({
    required this.players,
    required this.stack,
    required this.ante,
    required this.pusher,
  });

  String get key => '$players|$stack|${ante.name}|$pusher';
}

/// Equilibrio di Nash push/fold (chip EV) per uno spot "tutti foldano fino a
/// chi spinge", con i giocatori successivi che possono chiamare.
class PushFoldSolution {
  final PushFoldConfig config;

  /// Frequenza di all-in per ogni classe (0..1).
  final Float64List push;

  /// EV (in BB, rispetto a fold) dell'all-in per ogni classe.
  final Float64List pushEv;

  /// Per ogni posizione che può chiamare: frequenza di call per classe.
  final Map<int, Float64List> call;

  /// Per ogni posizione che può chiamare: EV del call (rispetto a fold).
  final Map<int, Float64List> callEv;

  /// Exploitability approssimata (BB) come misura di convergenza.
  final double exploitability;

  PushFoldSolution(this.config, this.push, this.pushEv, this.call, this.callEv, this.exploitability);
}

/// Risolve lo spot con fictitious play.
///
/// Semplificazioni (come le classiche tabelle push/fold): un solo caller
/// (niente overcall multiway), card removal considerato solo tra i due
/// giocatori coinvolti, valutazione in chip EV (no ICM).
PushFoldSolution solvePushFold(PushFoldConfig cfg, PreflopData data, {int iterations = 1000}) {
  final n = cfg.players;
  final s = cfg.stack.toDouble();
  final i = cfg.pusher;
  final pi = blindPosted(n, i);
  final dead = 1.5 + cfg.ante.total(n);
  final callers = [for (var j = i + 1; j < n; j++) j];

  final w = data.w;
  final ew = Float64List(169 * 169);
  final wRow = Float64List(169);
  for (var a = 0; a < 169; a++) {
    var t = 0.0;
    for (var b = 0; b < 169; b++) {
      ew[a * 169 + b] = w[a * 169 + b] * data.eq[a * 169 + b];
      t += w[a * 169 + b];
    }
    wRow[a] = t;
  }

  double potFor(int j) => 2 * s + dead - pi - blindPosted(n, j);

  final avgP = Float64List(169)..fillRange(0, 169, 0.5);
  final avgC = {for (final j in callers) j: Float64List(169)..fillRange(0, 169, 0.5)};
  final eqVsPush = Float64List(169);
  final hasPush = List<bool>.filled(169, false);

  // Equity di ogni mano del caller contro il range di push.
  void computeEqVsPush(Float64List p) {
    for (var b = 0; b < 169; b++) {
      var num = 0.0, den = 0.0;
      final row = b * 169;
      for (var a = 0; a < 169; a++) {
        final pa = p[a];
        if (pa == 0) continue;
        num += ew[row + a] * pa;
        den += w[row + a] * pa;
      }
      hasPush[b] = den > 0;
      eqVsPush[b] = den > 0 ? num / den : 0;
    }
  }

  double callEvOf(int j, int b) {
    if (!hasPush[b]) return 0;
    return eqVsPush[b] * potFor(j) - s + blindPosted(n, j);
  }

  double pushEvOf(int a, Map<int, Float64List> c) {
    var ev = 0.0, pNone = 1.0;
    final row = a * 169;
    for (final j in callers) {
      final cj = c[j]!;
      var cw = 0.0, ce = 0.0;
      for (var b = 0; b < 169; b++) {
        final x = cj[b];
        if (x == 0) continue;
        cw += w[row + b] * x;
        ce += ew[row + b] * x;
      }
      final pc = cw / wRow[a];
      if (cw > 0) {
        ev += pNone * pc * ((ce / cw) * potFor(j) - s + pi);
      }
      pNone *= 1 - pc;
    }
    // Tutti foldano: rispetto al fold (dove si perde il blind) si guadagna
    // l'intero piatto, blind proprio incluso.
    return ev + pNone * dead;
  }

  for (var t = 1; t <= iterations; t++) {
    // Best response simultanee contro le strategie medie.
    computeEqVsPush(avgP);
    final brC = <int, Float64List>{};
    for (final j in callers) {
      final br = Float64List(169);
      for (var b = 0; b < 169; b++) {
        br[b] = callEvOf(j, b) > 0 ? 1 : 0;
      }
      brC[j] = br;
    }
    final brP = Float64List(169);
    for (var a = 0; a < 169; a++) {
      brP[a] = pushEvOf(a, avgC) > 0 ? 1 : 0;
    }
    // Media pesata linearmente: converge più in fretta.
    final k = 2.0 / (t + 2);
    for (var a = 0; a < 169; a++) {
      avgP[a] += (brP[a] - avgP[a]) * k;
    }
    for (final j in callers) {
      final c = avgC[j]!, br = brC[j]!;
      for (var b = 0; b < 169; b++) {
        c[b] += (br[b] - c[b]) * k;
      }
    }
  }

  // Pulizia: frequenze molto vicine a 0/1 vengono arrotondate.
  double clean(double v) => v < 0.02 ? 0 : (v > 0.98 ? 1 : v);
  for (var a = 0; a < 169; a++) {
    avgP[a] = clean(avgP[a]);
  }
  for (final c in avgC.values) {
    for (var b = 0; b < 169; b++) {
      c[b] = clean(c[b]);
    }
  }

  // EV finali contro le strategie di equilibrio.
  final pushEv = Float64List(169);
  for (var a = 0; a < 169; a++) {
    pushEv[a] = pushEvOf(a, avgC);
  }
  computeEqVsPush(avgP);
  final callEv = <int, Float64List>{};
  for (final j in callers) {
    final ev = Float64List(169);
    for (var b = 0; b < 169; b++) {
      ev[b] = callEvOf(j, b);
    }
    callEv[j] = ev;
  }

  // Exploitability: guadagno medio (per mano) di una best response rispetto
  // alla strategia trovata, sommato sui giocatori.
  double gain(Float64List freq, Float64List ev) {
    var g = 0.0, tot = 0.0;
    for (var a = 0; a < 169; a++) {
      final weight = wRow[a];
      final cur = freq[a] * ev[a];
      final best = ev[a] > 0 ? ev[a] : 0.0;
      g += (best - cur) * weight;
      tot += weight;
    }
    return g / tot;
  }

  var expl = gain(avgP, pushEv);
  for (final j in callers) {
    expl += gain(avgC[j]!, callEv[j]!);
  }

  return PushFoldSolution(cfg, avgP, pushEv, avgC, callEv, expl);
}
