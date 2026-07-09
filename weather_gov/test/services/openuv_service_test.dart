import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_gov/services/openuv_service.dart';

void main() {
  group('OpenUvService.fetchUvMaxForDate', () {
    test('returns null instead of hanging forever when a request never responds', () {
      fakeAsync((async) {
        final client = MockClient((_) => Future.delayed(
              const Duration(minutes: 10),
              () => http.Response('{"result": {"uv_max": 7}}', 200),
            ));
        final service = OpenUvService(client: client);

        int? result;
        bool resolved = false;
        service.fetchUvMaxForDate(38.9, -77.0, DateTime(2026, 4, 7)).then((r) {
          result = r;
          resolved = true;
        });

        async.elapse(const Duration(minutes: 2));

        expect(resolved, isTrue);
        expect(result, isNull);
      });
    });
  });
}
