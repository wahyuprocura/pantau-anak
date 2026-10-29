import 'package:flutter_test/flutter_test.dart';
import 'package:app_anak/main.dart';

void main() {
  testWidgets('App anak bisa dibangun', (WidgetTester tester) async {
    await tester.pumpWidget(const PantauAnakApp());
    expect(find.byType(PantauAnakApp), findsOneWidget);
  });
}
