import 'dart:typed_data';

import 'preflop_data.dart';
import 'pushfold.dart';

/// Azioni possibili in un nodo preflop.
enum PokerAction {
  fold('Fold'),
  check('Check'),
  call('Call'),
  limp('Limp'),
  raise('Rilancio'),
  allIn('All-in');

  final String label;
  const PokerAction(this.label);
}

/// Un punto di decisione: per ogni azione, frequenza ed EV per ciascuna delle
/// 169 classi di mani. Gli EV sono in BB, relativi alla prima azione (fold o
/// check), quindi la prima azione ha sempre EV 0.
class StrategyNode {
  StrategyNode(this.hero, this.actions, this.freq, this.ev, {this.reachable = true});

  final int hero;
  final List<PokerAction> actions;
  final List<Float64List> freq;
  final List<Float64List> ev;
  final bool reachable;

  int indexOf(PokerAction a) => actions.indexOf(a);

  /// Percentuale di mani (combo) che sceglie l'azione [k].
  double percent(int k) {
    final f = freq[k];
    var s = 0.0;
    for (var h = 0; h < 169; h++) {
      s += f[h] * _combos(h);
    }
    return s / 1326 * 100;
  }

  int bestAction(int hand) {
    var best = 0;
    for (var k = 1; k < actions.length; k++) {
      if (ev[k][hand] > ev[best][hand]) best = k;
    }
    return best;
  }

  static int _combos(int idx) {
    final i = idx ~/ 13, j = idx % 13;
    return i == j ? 6 : (i < j ? 4 : 12);
  }
}

/// Soluzione preflop completa per uno spot "tutti foldano fino all'opener".
class FullPreflopSolution {
  FullPreflopSolution({
    required this.config,
    required this.raiseSize,
    required this.open,
    required this.vsRaise,
    required this.vsJam,
    required this.raiseVsJam,
    this.vsLimp,
    this.limpVsJam,
  });

  final PushFoldConfig config;

  /// Dimensione del rilancio d'apertura (totale, in BB).
  final double raiseSize;

  /// Decisione dell'opener: fold / (limp) / rilancio / all-in.
  final StrategyNode open;

  /// Per ogni posizione successiva: risposta al rilancio (fold/call/all-in).
  final Map<int, StrategyNode> vsRaise;

  /// Per ogni posizione successiva: risposta all'all-in d'apertura.
  final Map<int, StrategyNode> vsJam;

  /// L'opener ha rilanciato e la posizione j va all-in: call o fold.
  final Map<int, StrategyNode> raiseVsJam;

  /// Solo se l'opener è lo SB: il BB contro il limp (check / all-in).
  final StrategyNode? vsLimp;

  /// Solo se l'opener è lo SB: limp, il BB va all-in: call o fold.
  final StrategyNode? limpVsJam;
}

/// Giocabilità postflop di ogni classe (moltiplicatore dell'equity
/// realization): coppie e mani suited/connesse realizzano più equity delle
/// mani offsuit scollegate.
final Float64List playability = _buildPlayability();

Float64List _buildPlayability() {
  final p = Float64List(169);
  for (var idx = 0; idx < 169; idx++) {
    final i = idx ~/ 13, j = idx % 13;
    if (i == j) {
      final rank = 12 - i;
      p[idx] = rank >= 5 ? 1.0 : 0.95; // coppie piccole un po' meno
      continue;
    }
    final high = 12 - (i < j ? i : j), low = 12 - (i < j ? j : i);
    final suited = i < j;
    final gap = high - low - 1;
    var v = suited ? 1.0 : 0.82;
    v -= (suited ? 0.03 : 0.05) * (gap > 4 ? 4 : gap);
    if (high >= 8) v += 0.05; // carta alta T+
    if (low >= 8) v += 0.04; // due carte alte
    if (!suited && high < 8) v -= 0.06; // offsuit senza carte alte
    p[idx] = v;
  }
  return p;
}

/// Dimensione standard del rilancio d'apertura.
double openRaiseSize(int players, int opener, int stack) {
  final isSB = opener == players - 2;
  final r = isSB ? (players == 2 ? 2.5 : 3.0) : 2.0;
  return r < stack / 2 ? r : stack / 2;
}

/// Risolve il preflop con rilancio, limp (dallo SB), call e all-in.
///
/// Modello:
/// - un solo avversario risponde (niente squeeze né multiway), come nelle
///   tabelle push/fold;
/// - contro un rilancio si può foldare, chiamare o andare all-in;
/// - se si arriva al flop, il piatto viene diviso con l'equity realization:
///   chi è in posizione realizza la sua equity al [ipRealization], chi è
///   fuori posizione all'[oopRealization], moltiplicati per la [playability]
///   della mano;
/// - chip EV (niente ICM). Equilibrio con fictitious play.
FullPreflopSolution solveFullPreflop(
  PushFoldConfig cfg,
  PreflopData data, {
  int iterations = 300,
  double ipRealization = 1.1,
  double oopRealization = 0.7,
}) {
  final n = cfg.players;
  final s = cfg.stack.toDouble();
  final i = cfg.pusher;
  final ante = cfg.ante.total(n);
  final isSB = i == n - 2;
  final pI = blindPosted(n, i);
  final r = openRaiseSize(n, i, cfg.stack);
  final m = n - 1 - i; // numero di avversari dopo l'opener
  const nn = 169 * 169;

  // Matrici pesate per il card removal.
  final w = data.w;
  final ew = Float64List(nn), shIp = Float64List(nn), shOop = Float64List(nn);
  final ri = ipRealization, ro = oopRealization;
  final play = playability;
  for (var x = 0; x < nn; x++) {
    final e = data.eq[x].toDouble(), wx = w[x];
    final pa = play[x ~/ 169], pb = play[x % 169];
    ew[x] = wx * e;
    final hIp = e * ri * pa, vOop = (1 - e) * ro * pb;
    shIp[x] = wx * (hIp / (hIp + vOop));
    final hOop = e * ro * pa, vIp = (1 - e) * ri * pb;
    shOop[x] = wx * (hOop / (hOop + vIp));
  }
  final wRow = Float64List(169);
  for (var a = 0; a < 169; a++) {
    var t = 0.0;
    for (var b = 0; b < 169; b++) {
      t += w[a * 169 + b];
    }
    wRow[a] = t;
  }

  // Ordine d'azione postflop: SB, BB, poi gli altri. In heads-up lo SB è il
  // bottone e agisce per ultimo.
  int postRank(int k) => k >= n - 2 ? k - (n - 2) : k + 2;
  bool openerIp(int j) => n == 2 ? true : postRank(i) > postRank(j);

  final allFold = 1.5 + ante - pI;
  final dead = List<double>.generate(m, (k) => 1.5 + ante - pI - blindPosted(n, i + 1 + k));
  final potCall = List<double>.generate(m, (k) => 2 * r + dead[k]);
  final potJam = List<double>.generate(m, (k) => 2 * s + dead[k]);
  final opIp = List<bool>.generate(m, (k) => openerIp(i + 1 + k));
  // Contro un rilancio solo il BB può fare call; gli altri giocano all-in o
  // fold (come nelle tabelle short-stack: niente flat che non chiude l'azione).
  final canCall = List<bool>.generate(m, (k) => i + 1 + k == n - 1);

  Float64List vec(double v) => Float64List(169)..fillRange(0, 169, v);

  // Strategie medie.
  final oF = vec(isSB ? 0.25 : 1 / 3), oL = vec(isSB ? 0.25 : 0);
  final oR = vec(isSB ? 0.25 : 1 / 3), oJ = vec(isSB ? 0.25 : 1 / 3);
  final oC = List.generate(m, (_) => vec(0.5)); // opener: call vs all-in dopo rilancio
  final oLC = vec(0.5); // SB: call vs all-in dopo limp
  final rF = List.generate(m, (_) => vec(1 / 3));
  final rC = List.generate(m, (_) => vec(1 / 3));
  final rJ = List.generate(m, (_) => vec(1 / 3));
  final pC = List.generate(m, (_) => vec(0.5)); // call vs all-in d'apertura
  final bbJ = vec(0.5); // BB: all-in vs limp

  // Buffer per gli EV.
  final evOF = vec(-pI), evOL = vec(0), evOR = vec(0), evOJ = vec(0);
  final evOC = List.generate(m, (_) => vec(0)); // call - fold, dopo rilancio
  final evOLC = vec(0); // call - fold, dopo limp
  final evRC = List.generate(m, (_) => vec(0)); // vs rilancio: call - fold
  final evRJ = List.generate(m, (_) => vec(0)); // vs rilancio: all-in - fold
  final evPC = List.generate(m, (_) => vec(0)); // vs all-in: call - fold
  final evBJ = vec(0); // vs limp: all-in - check
  final reachRaise = List<bool>.filled(m, true);
  final reachJamAfterRaise = List<bool>.filled(m, true);
  final reachJam = List<bool>.filled(m, true);
  var reachLimp = isSB, reachLimpJam = isSB;

  void computeOpenerEvs() {
    final swPC = Float64List(m), sePC = Float64List(m), swRC = Float64List(m);
    final shRC = Float64List(m), swRJ = Float64List(m), seRJ = Float64List(m);
    final swRF = Float64List(m);
    for (var a = 0; a < 169; a++) {
      final row = a * 169, wr = wRow[a];
      for (var k = 0; k < m; k++) {
        final pc = pC[k], rc = rC[k], rj = rJ[k], rf = rF[k];
        final sh = opIp[k] ? shIp : shOop;
        var s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, s5 = 0.0, s6 = 0.0, s7 = 0.0;
        for (var b = 0; b < 169; b++) {
          final x = row + b, wx = w[x], ex = ew[x];
          final vpc = pc[b], vrc = rc[b], vrj = rj[b];
          s1 += wx * vpc;
          s2 += ex * vpc;
          s3 += wx * vrc;
          s4 += sh[x] * vrc;
          s5 += wx * vrj;
          s6 += ex * vrj;
          s7 += wx * rf[b];
        }
        swPC[k] = s1;
        sePC[k] = s2;
        swRC[k] = s3;
        shRC[k] = s4;
        swRJ[k] = s5;
        seRJ[k] = s6;
        swRF[k] = s7;
      }
      // All-in d'apertura.
      var pNone = 1.0, ev = 0.0;
      for (var k = 0; k < m; k++) {
        ev += pNone * (sePC[k] * potJam[k] - swPC[k] * s) / wr;
        pNone *= 1 - swPC[k] / wr;
      }
      evOJ[a] = ev + pNone * allFold;

      // Rilancio.
      pNone = 1.0;
      ev = 0.0;
      for (var k = 0; k < m; k++) {
        final callPart = (shRC[k] * potCall[k] - swRC[k] * r) / wr;
        final jCall = (seRJ[k] * potJam[k] - swRJ[k] * s) / wr;
        final jFold = -r * swRJ[k] / wr;
        evOC[k][a] = swRJ[k] > 0 ? (jCall - jFold) * wr / swRJ[k] : 0;
        ev += pNone * (callPart + (jCall > jFold ? jCall : jFold));
        pNone *= swRF[k] / wr;
      }
      evOR[a] = ev + pNone * allFold;
    }

    // Limp (solo SB contro BB).
    if (isSB) {
      final bbIp = n != 2; // in heads-up il BB è fuori posizione
      final sh = bbIp ? shOop : shIp; // prospettiva dello SB
      final potLimp = 2 + ante, potLJ = 2 * s + ante;
      for (var a = 0; a < 169; a++) {
        final row = a * 169, wr = wRow[a];
        var swChk = 0.0, shChk = 0.0, swJ = 0.0, seJ = 0.0;
        for (var b = 0; b < 169; b++) {
          final x = row + b, j = bbJ[b], c = 1 - j;
          swChk += w[x] * c;
          shChk += sh[x] * c;
          swJ += w[x] * j;
          seJ += ew[x] * j;
        }
        final chk = (shChk * potLimp - swChk * 1) / wr;
        final jCall = (seJ * potLJ - swJ * s) / wr;
        final jFold = -1 * swJ / wr;
        evOLC[a] = swJ > 0 ? (jCall - jFold) * wr / swJ : 0;
        evOL[a] = chk + (jCall > jFold ? jCall : jFold);
      }
    }
  }

  void computeResponderEvs() {
    final pjK = List<double>.generate(m, (k) => blindPosted(n, i + 1 + k));
    for (var b = 0; b < 169; b++) {
      final row = b * 169;
      var swX = 0.0, shIpX = 0.0, shOopX = 0.0, swJ = 0.0, seJ = 0.0;
      for (var a = 0; a < 169; a++) {
        final x = row + a, wx = w[x], vr = oR[a], vj = oJ[a];
        swX += wx * vr;
        shIpX += shIp[x] * vr;
        shOopX += shOop[x] * vr;
        swJ += wx * vj;
        seJ += ew[x] * vj;
      }
      for (var k = 0; k < m; k++) {
        final pj = pjK[k];
        // Contro l'all-in d'apertura.
        evPC[k][b] = swJ > 0 ? (seJ * potJam[k] - swJ * s) / swJ + pj : 0;
        // Contro il rilancio.
        if (swX <= 0) {
          evRC[k][b] = 0;
          evRJ[k][b] = 0;
          continue;
        }
        final shX = opIp[k] ? shOopX : shIpX; // prospettiva del responder
        evRC[k][b] = (shX * potCall[k] - swX * r) / swX + pj;
        final c = oC[k];
        var swY = 0.0, seY = 0.0;
        for (var a = 0; a < 169; a++) {
          final y = oR[a] * c[a];
          if (y == 0) continue;
          swY += w[row + a] * y;
          seY += ew[row + a] * y;
        }
        evRJ[k][b] = (seY * potJam[k] - swY * s + (swX - swY) * (r + dead[k])) / swX + pj;
      }
    }

    if (isSB) {
      final bbIp = n != 2;
      final sh = bbIp ? shIp : shOop; // prospettiva del BB
      final potLimp = 2 + ante, potLJ = 2 * s + ante;
      for (var b = 0; b < 169; b++) {
        final row = b * 169;
        var swX = 0.0, shX = 0.0, swY = 0.0, seY = 0.0;
        for (var a = 0; a < 169; a++) {
          final x = row + a, vl = oL[a];
          if (vl == 0) continue;
          swX += w[x] * vl;
          shX += sh[x] * vl;
          final y = vl * oLC[a];
          swY += w[x] * y;
          seY += ew[x] * y;
        }
        if (swX <= 0) {
          evBJ[b] = 0;
          continue;
        }
        final chk = (shX * potLimp - swX * 1) / swX;
        final jam = (seY * potLJ - swY * s + (swX - swY) * (1 + ante)) / swX;
        evBJ[b] = jam - chk;
      }
    }
  }

  for (var t = 1; t <= iterations; t++) {
    computeOpenerEvs();
    computeResponderEvs();
    final k2 = 2.0 / (t + 2);
    void upd(Float64List avg, bool chosen, int h) {
      avg[h] += ((chosen ? 1.0 : 0.0) - avg[h]) * k2;
    }

    for (var h = 0; h < 169; h++) {
      // Opener: argmax tra fold / limp / rilancio / all-in.
      var best = 0;
      var bestEv = evOF[h];
      if (isSB && evOL[h] > bestEv) {
        best = 1;
        bestEv = evOL[h];
      }
      if (evOR[h] > bestEv) {
        best = 2;
        bestEv = evOR[h];
      }
      if (evOJ[h] > bestEv) best = 3;
      upd(oF, best == 0, h);
      if (isSB) upd(oL, best == 1, h);
      upd(oR, best == 2, h);
      upd(oJ, best == 3, h);
      for (var k = 0; k < m; k++) {
        upd(oC[k], evOC[k][h] > 0, h);
        upd(pC[k], evPC[k][h] > 0, h);
        final c = canCall[k] ? evRC[k][h] : double.negativeInfinity, j = evRJ[k][h];
        final bk = (c <= 0 && j <= 0) ? 0 : (c >= j ? 1 : 2);
        upd(rF[k], bk == 0, h);
        upd(rC[k], bk == 1, h);
        upd(rJ[k], bk == 2, h);
      }
      if (isSB) {
        upd(oLC, evOLC[h] > 0, h);
        upd(bbJ, evBJ[h] > 0, h);
      }
    }
  }

  // EV finali contro le strategie medie.
  computeOpenerEvs();
  computeResponderEvs();

  // Raggiungibilità dei nodi.
  bool any(Float64List v) => v.any((x) => x > 0.001);
  for (var k = 0; k < m; k++) {
    reachRaise[k] = any(oR);
    reachJam[k] = any(oJ);
    reachJamAfterRaise[k] = any(oR) && any(rJ[k]);
  }
  reachLimp = isSB && any(oL);
  reachLimpJam = reachLimp && any(bbJ);

  // Pulizia frequenze (sotto il 2% → 0) e normalizzazione.
  List<Float64List> clean(List<Float64List> fs) {
    final out = [for (final f in fs) Float64List.fromList(f)];
    for (var h = 0; h < 169; h++) {
      var tot = 0.0;
      for (final f in out) {
        if (f[h] < 0.02) f[h] = 0;
        tot += f[h];
      }
      if (tot <= 0) {
        out[0][h] = 1;
        continue;
      }
      for (final f in out) {
        f[h] /= tot;
      }
    }
    return out;
  }

  Float64List minus(Float64List a, Float64List b) =>
      Float64List.fromList([for (var h = 0; h < 169; h++) a[h] - b[h]]);
  Float64List one(Float64List v) => Float64List.fromList([for (final x in v) 1 - x]);

  final open = isSB
      ? StrategyNode(
          i,
          const [PokerAction.fold, PokerAction.limp, PokerAction.raise, PokerAction.allIn],
          clean([oF, oL, oR, oJ]),
          [vec(0), minus(evOL, evOF), minus(evOR, evOF), minus(evOJ, evOF)],
        )
      : StrategyNode(
          i,
          const [PokerAction.fold, PokerAction.raise, PokerAction.allIn],
          clean([oF, oR, oJ]),
          [vec(0), minus(evOR, evOF), minus(evOJ, evOF)],
        );

  final vsRaise = <int, StrategyNode>{};
  final vsJam = <int, StrategyNode>{};
  final raiseVsJam = <int, StrategyNode>{};
  for (var k = 0; k < m; k++) {
    final j = i + 1 + k;
    vsRaise[j] = canCall[k]
        ? StrategyNode(
            j,
            const [PokerAction.fold, PokerAction.call, PokerAction.allIn],
            clean([rF[k], rC[k], rJ[k]]),
            [vec(0), evRC[k], evRJ[k]],
            reachable: reachRaise[k],
          )
        : StrategyNode(
            j,
            const [PokerAction.fold, PokerAction.allIn],
            clean([rF[k], rJ[k]]),
            [vec(0), evRJ[k]],
            reachable: reachRaise[k],
          );
    vsJam[j] = StrategyNode(
      j,
      const [PokerAction.fold, PokerAction.call],
      clean([one(pC[k]), pC[k]]),
      [vec(0), evPC[k]],
      reachable: reachJam[k],
    );
    raiseVsJam[j] = StrategyNode(
      i,
      const [PokerAction.fold, PokerAction.call],
      clean([one(oC[k]), oC[k]]),
      [vec(0), evOC[k]],
      reachable: reachJamAfterRaise[k],
    );
  }

  return FullPreflopSolution(
    config: cfg,
    raiseSize: r,
    open: open,
    vsRaise: vsRaise,
    vsJam: vsJam,
    raiseVsJam: raiseVsJam,
    vsLimp: isSB
        ? StrategyNode(
            n - 1,
            const [PokerAction.check, PokerAction.allIn],
            clean([one(bbJ), bbJ]),
            [vec(0), evBJ],
            reachable: reachLimp,
          )
        : null,
    limpVsJam: isSB
        ? StrategyNode(
            i,
            const [PokerAction.fold, PokerAction.call],
            clean([one(oLC), oLC]),
            [vec(0), evOLC],
            reachable: reachLimpJam,
          )
        : null,
  );
}
