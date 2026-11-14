/// Generatore pseudo-casuale xorshift veloce (64 bit, solo piattaforme native).
class FastRng {
  int _s;

  FastRng([int? seed]) : _s = (seed ?? DateTime.now().microsecondsSinceEpoch) | 1;

  int nextInt(int max) {
    var x = _s;
    x ^= x << 13;
    x ^= x >>> 7;
    x ^= x << 17;
    _s = x;
    return (x >>> 1) % max;
  }

  double nextDouble() => nextInt(1 << 30) / (1 << 30);
}
