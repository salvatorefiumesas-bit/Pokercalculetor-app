import 'package:material_ui/material_ui.dart';

import 'ui/app_data.dart';
import 'ui/charts_screen.dart';
import 'ui/equity_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/trainer_screen.dart';
import 'ui/updater.dart';

void main() {
  runApp(const PokerGtoApp());
}

class PokerGtoApp extends StatelessWidget {
  const PokerGtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Poker GTO Trainer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F9D6B), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF12171C),
        useMaterial3: true,
      ),
      home: const _Loader(),
    );
  }
}

class _Loader extends StatefulWidget {
  const _Loader();

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  // Lo splash resta visibile almeno 2,5 secondi.
  late final Future<void> _loading = Future.wait([
    AppData.load(),
    Future<void>.delayed(const Duration(milliseconds: 2500)),
  ]);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('Errore di caricamento: ${snap.error}')));
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: snap.connectionState != ConnectionState.done ? const SplashScreen() : const HomeShell(),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    // Controllo aggiornamenti dopo il primo frame della schermata principale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Updater.checkForUpdate(context);
    });
  }

  static const _titles = ['Tabelle di strategia', 'Trainer', 'Calcolatore equity'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[tab])),
      body: SafeArea(
        child: IndexedStack(
          index: tab,
          children: const [ChartsScreen(), TrainerScreen(), EquityScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Tabelle'),
          NavigationDestination(icon: Icon(Icons.school), label: 'Trainer'),
          NavigationDestination(icon: Icon(Icons.percent), label: 'Equity'),
        ],
      ),
    );
  }
}
