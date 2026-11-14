/// Carte rappresentate come interi 0..51: rank * 4 + suit.
/// rank: 0 = '2' ... 12 = 'A'; suit: 0 = c, 1 = d, 2 = h, 3 = s.
library;

const String rankChars = '23456789TJQKA';
const String suitChars = 'cdhs';
const List<String> suitSymbols = ['♣', '♦', '♥', '♠'];

int makeCard(int rank, int suit) => rank * 4 + suit;
int rankOf(int card) => card >> 2;
int suitOf(int card) => card & 3;

String cardToString(int card) => rankChars[rankOf(card)] + suitChars[suitOf(card)];

int rankFromChar(String ch) {
  final r = rankChars.indexOf(ch.toUpperCase());
  if (r < 0) throw FormatException('Rank non valido: $ch');
  return r;
}

int parseCard(String s) {
  if (s.length != 2) throw FormatException('Carta non valida: $s');
  final r = rankFromChar(s[0]);
  final su = suitChars.indexOf(s[1].toLowerCase());
  if (su < 0) throw FormatException('Seme non valido: $s');
  return makeCard(r, su);
}

/// Legge una sequenza di carte tipo "Ah7c2d" o "Ah 7c 2d".
List<int> parseCards(String text) {
  final clean = text.replaceAll(RegExp(r'[\s,]'), '');
  if (clean.length % 2 != 0) throw FormatException('Carte non valide: $text');
  final out = <int>[];
  for (var i = 0; i < clean.length; i += 2) {
    final c = parseCard(clean.substring(i, i + 2));
    if (out.contains(c)) throw FormatException('Carta duplicata: ${cardToString(c)}');
    out.add(c);
  }
  return out;
}

int cardMask(int card) => 1 << card;
