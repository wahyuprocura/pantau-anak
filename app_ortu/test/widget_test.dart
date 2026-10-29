import 'package:flutter_test/flutter_test.dart';
import 'package:app_ortu/main.dart';

void main() {
  testWidgets('App ortu bisa dibangun', (WidgetTester tester) async {
    await tester.pumpWidget(const PantauOrtuApp());
    expect(find.text('Pantau Anak'), findsWidgets);
  });
}
