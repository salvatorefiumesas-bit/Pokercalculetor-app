import '../engine/preflop_solver.dart';
import '../engine/pushfold.dart';

/// Situazioni del preflop completo.
enum Situation {
  open('Apertura'),
  vsRaise('Contro rilancio'),
  vsJam('Contro all-in'),
  raiseVsJam('Rilancio → all-in avversario'),
  vsLimp('BB contro limp'),
  limpVsJam('Limp → all-in del BB');

  final String label;
  const Situation(this.label);

  /// Serve scegliere anche la posizione dell'avversario che risponde.
  bool get needsResponder => this == vsRaise || this == vsJam || this == raiseVsJam;

  /// Esiste solo quando l'opener è lo small blind.
  bool get sbOnly => this == vsLimp || this == limpVsJam;
}

StrategyNode nodeFor(FullPreflopSolution s, Situation sit, int responder) => switch (sit) {
      Situation.open => s.open,
      Situation.vsRaise => s.vsRaise[responder]!,
      Situation.vsJam => s.vsJam[responder]!,
      Situation.raiseVsJam => s.raiseVsJam[responder]!,
      Situation.vsLimp => s.vsLimp!,
      Situation.limpVsJam => s.limpVsJam!,
    };

String fmtBb(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Descrizione testuale della situazione, dal punto di vista dell'eroe.
String describeSituation(FullPreflopSolution s, Situation sit, int responder) {
  final cfg = s.config;
  final names = positionNames(cfg.players);
  final op = names[cfg.pusher];
  final r = fmtBb(s.raiseSize);
  return switch (sit) {
    Situation.open => 'Tutti foldano fino a te in $op.',
    Situation.vsRaise => '$op rilancia a $r BB. Tutti foldano fino a te in ${names[responder]}.',
    Situation.vsJam => '$op va all-in (${cfg.stack} BB). Tutti foldano fino a te in ${names[responder]}.',
    Situation.raiseVsJam => 'Hai rilanciato a $r BB da $op. ${names[responder]} va all-in, gli altri foldano.',
    Situation.vsLimp => 'Lo SB fa limp. Sei in BB.',
    Situation.limpVsJam => 'Hai fatto limp dallo SB. Il BB va all-in.',
  };
}
