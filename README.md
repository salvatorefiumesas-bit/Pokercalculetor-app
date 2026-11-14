# Poker GTO Trainer

App Android (Flutter) per studiare il poker da torneo con strategie di
equilibrio (GTO / Nash), calcolate direttamente sul telefono. Gratuita e
senza server.

## Funzioni

- **Tabelle Nash push/fold**: range di all-in e di call per 2–9 giocatori,
  stack da 2 a 25 BB, ante nessuno / BB ante / classico. Tocca una mano per
  vederne frequenza ed EV.
- **Trainer**: l'app propone uno spot (posizione, stack, carte). Scegli
  All-in / Call / Fold e ricevi subito il feedback: strategia Nash, EV di
  ogni azione e EV perso. Statistiche di sessione.
- **Calcolatore di equity**: da 2 a 6 giocatori, mani specifiche (`AhKd`) o
  range (`22+, A2s+, KTo+`), con board opzionale. Calcolo esatto quando
  possibile, altrimenti Monte Carlo.
- **Editor di range**: griglia 13×13 da "dipingere" col dito, slider "Top X%".

## Come funziona

| Componente | File |
|---|---|
| Valutatore di mani 7 carte (tabelle di bit) | `lib/engine/evaluator.dart` |
| Equity esatta / Monte Carlo | `lib/engine/equity.dart` |
| Matrice equity preflop 169×169 precalcolata | `assets/preflop_equity.bin`, generata da `tool/gen_preflop_equity.dart` |
| Solver push/fold (fictitious play) | `lib/engine/pushfold.dart` |

Il solver trova l'equilibrio di Nash in **chip EV** con queste
semplificazioni, le stesse delle classiche tabelle push/fold: un solo
caller (niente overcall multiway), card removal tra i due giocatori
coinvolti, niente ICM. Verifica: heads-up a 10 BB senza ante dà circa 58% di
push e 37% di call, in linea con i valori di riferimento.

Per rigenerare la matrice di equity (circa 7 minuti):

```bash
dart compile exe tool/gen_preflop_equity.dart -o gen
./gen 100000
```

## Build

Ogni push su GitHub avvia la action **Build APK Android**: analisi, test e
compilazione. L'APK si scarica dalla pagina della run, nella sezione
*Artifacts*. Creando un tag `v1.0.0`, l'APK viene allegato anche a una
Release.

In locale:

```bash
flutter pub get
flutter test
flutter build apk --release
```

## Uso responsabile

L'app è pensata per lo **studio lontano dal tavolo**. Usare strumenti di
assistenza durante il gioco (RTA) è vietato dalle sale online, PokerStars
compresa.

## Prossimi passi

- ICM per bolla e tavolo finale
- Solver postflop (Rust + `flutter_rust_bridge`)
- Import delle hand history di PokerStars per l'analisi post-sessione
