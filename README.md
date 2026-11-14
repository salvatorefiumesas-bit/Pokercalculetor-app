# Poker GTO Trainer

App Android (Flutter) per studiare il poker da torneo con strategie di
equilibrio (GTO / Nash), calcolate direttamente sul telefono. Gratuita e
senza server.

## Funzioni

- **Tabelle di strategia**, due modelli:
  - **Preflop completo** (5–30 BB): apertura con fold / limp (SB) / rilancio /
    all-in, risposte al rilancio (fold / call / all-in), call contro l'all-in,
    rilancio seguito da all-in avversario, BB contro limp. Griglia a più
    colori con frequenze ed EV di ogni azione.
  - **Push/Fold** (2–30 BB): range di Nash di all-in e di call.
  Da 2 a 9 giocatori, ante nessuno / BB ante / classico.
- **Trainer**: l'app propone uno spot (posizione, stack, carte, azione
  degli avversari) con tutti e due i modelli. Scegli l'azione e ricevi subito
  il feedback: strategia di equilibrio, EV di ogni azione ed EV perso.
  Statistiche di sessione.
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
| Solver preflop completo (fictitious play) | `lib/engine/preflop_solver.dart` |

Il solver trova l'equilibrio di Nash in **chip EV** con queste
semplificazioni, le stesse delle classiche tabelle push/fold: un solo
caller (niente overcall multiway), card removal tra i due giocatori
coinvolti, niente ICM. Verifica: heads-up a 10 BB senza ante dà circa 58% di
push e 37% di call, in linea con i valori di riferimento.

Il **preflop completo** usa lo stesso metodo con un albero più ricco e
queste approssimazioni:

- rilancio d'apertura 2 BB (3 BB dallo SB, 2,5 BB in heads-up);
- contro un rilancio solo il BB può fare call, gli altri giocano all-in o
  fold (niente flat, squeeze o piatti multiway);
- quando si va al flop senza all-in, il piatto si divide con l'*equity
  realization*: ×1,1 in posizione, ×0,7 fuori posizione, corretta per la
  giocabilità della mano (coppie e suited realizzano di più, offsuit
  scollegate di meno).

Sono stime ragionevoli (es. 9 giocatori, 25 BB: UTG apre ~15%, BTN ~42%), non
l'output di un solver postflop completo.

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
