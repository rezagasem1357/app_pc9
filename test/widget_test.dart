import 'package:flutter_test/flutter_test.dart';
import 'package:store_accounting_desktop/main.dart';

void main() {
  testWidgets('application starts', (WidgetTester tester) async {
    await tester.pumpWidget(const StoreAccountingApp());
    expect(find.byType(StoreAccountingApp), findsOneWidget);
  });
}
