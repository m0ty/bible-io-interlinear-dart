import 'package:test/test.dart';

import '../example/independent_client.dart';

void main() {
  test('independent Latin/Spanish consumer works without Flutter or STEP data',
      () async {
    expect(await runIndependentExample(), ('verbum', 'palabra'));
  });
}
