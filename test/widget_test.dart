import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:poker_gto_trainer/ui/widgets.dart';

void main() {
  testWidgets('la griglia dei range si disegna e riceve i tocchi', (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: RangeGrid(values: List.filled(169, 0.5), onCellTap: (i) => tapped = i),
        ),
      ),
    ));
    expect(find.byType(RangeGrid), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    expect(tapped, 0);
  });
}
