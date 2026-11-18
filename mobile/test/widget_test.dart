import 'package:flutter_test/flutter_test.dart';
import 'package:origo_mobile/main.dart';

void main() {
  testWidgets('Origo app renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OrigoApp());
    expect(find.text('🌾 ORIGO'), findsOneWidget);
  });
}
