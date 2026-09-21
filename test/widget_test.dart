import 'package:log4app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Log4App shell', (WidgetTester tester) async {
    await tester.pumpWidget(const Log4App(serverVersion: '2.3.0'));

    expect(find.text('Log4App'), findsOneWidget);
    expect(find.text('V2.3.0'), findsOneWidget);
  });
}
