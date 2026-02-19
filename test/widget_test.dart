import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_yfinance/main.dart';

void main() {
  testWidgets('dashboard renders iOS shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());

    expect(find.text('Liquid Stocks'), findsOneWidget);
    expect(find.text('銘柄をダッシュボードに追加'), findsOneWidget);
  });
}
