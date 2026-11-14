import 'dart:isolate';

import 'package:flutter/services.dart';

import '../engine/preflop_data.dart';
import '../engine/pushfold.dart';

/// Dati condivisi dell'app e cache delle soluzioni.
class AppData {
  AppData._();

  static late PreflopData preflop;

  static Future<void> load() async {
    final bytes = await rootBundle.load('assets/preflop_equity.bin');
    preflop = await Isolate.run(() => PreflopData.fromBytes(bytes));
  }
}

class SolverCache {
  SolverCache._();

  static final Map<String, PushFoldSolution> _cache = {};
  static final Map<String, Future<PushFoldSolution>> _pending = {};

  static PushFoldSolution? cached(PushFoldConfig cfg) => _cache[cfg.key];

  static Future<PushFoldSolution> solve(PushFoldConfig cfg) {
    final key = cfg.key;
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final pending = _pending[key];
    if (pending != null) return pending;
    final data = AppData.preflop;
    final f = Isolate.run(() => solvePushFold(cfg, data, iterations: 500)).then((s) {
      _cache[key] = s;
      _pending.remove(key);
      return s;
    });
    _pending[key] = f;
    return f;
  }
}
