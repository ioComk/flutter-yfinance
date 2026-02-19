import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_yfinance/main.dart';

void main() {
  testWidgets('dashboard renders', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());

    expect(find.text('Stocks Dashboard'), findsOneWidget);
    expect(find.text('銘柄追加'), findsOneWidget);
  });
}
