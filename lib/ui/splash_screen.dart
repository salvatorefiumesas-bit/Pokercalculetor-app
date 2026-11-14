import 'package:material_ui/material_ui.dart';

/// Schermata d'avvio con il nome dell'autore.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();

  static const _gold = Color(0xFFE2B857);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    final fadeLate = CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 1, curve: Curves.easeOut));
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [Color(0xFF1B5E44), Color(0xFF0B1F17)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            FadeTransition(
              opacity: fade,
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Suit('♠', Colors.white),
                _Suit('♥', Color(0xFFE5484D)),
                _Suit('♦', Color(0xFFE5484D)),
                _Suit('♣', Colors.white),
              ]),
            ),
            const SizedBox(height: 28),
            FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(fade),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(
                    child: Text(
                      'ANTONIO VESCOVO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: fadeLate,
              child: Column(children: [
                Container(width: 64, height: 2, color: _gold),
                const SizedBox(height: 12),
                const Text(
                  'Professional Poker Player',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1.5,
                  ),
                ),
              ]),
            ),
            const Spacer(flex: 3),
            FadeTransition(
              opacity: fadeLate,
              child: const Column(children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                ),
                SizedBox(height: 14),
                Text('Poker GTO Trainer', style: TextStyle(color: Colors.white60, letterSpacing: 1)),
              ]),
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }
}

class _Suit extends StatelessWidget {
  const _Suit(this.symbol, this.color);

  final String symbol;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(symbol, style: TextStyle(fontSize: 34, color: color)),
    );
  }
}
