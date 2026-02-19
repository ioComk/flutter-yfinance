import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_yfinance/main.dart';

void main() {
  testWidgets('dashboard renders iOS shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());

    expect(find.text('Liquid Stocks'), findsOneWidget);
    expect(find.text('銘柄をダッシュボードに追加'), findsOneWidget);
    expect(find.text('編集'), findsOneWidget);
  });

  testWidgets('edit mode toggles from 編集 to 完了', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());
    await tester.tap(find.text('編集'));
    await tester.pump();

    expect(find.text('完了'), findsOneWidget);
    expect(find.text('編集'), findsNothing);
  });
}
