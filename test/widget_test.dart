import 'package:android_log_center/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Android Log Center shell', (WidgetTester tester) async {
    await tester.pumpWidget(const AndroidLogCenterApp());

    expect(find.text('Android Log Center'), findsOneWidget);
  });
}
