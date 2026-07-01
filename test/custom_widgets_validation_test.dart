import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';

void main() {
  group('validate() custom-widget stubbing', () {
    // A top-level reference to a host custom widget the manifest did NOT declare
    // fails validation as "undefined".
    test('undeclared custom widget at top level fails', () async {
      final bundler = Bundler();
      expect(
        () => bundler.validate('let x = RatingStars({})'),
        throwsA(isA<BundlerException>()),
      );
    });

    // Declaring it in customWidgets stubs it, so validation passes.
    test('declared custom widget validates', () async {
      final bundler = Bundler();
      await bundler.validate('let x = RatingStars({})',
          customWidgets: ['RatingStars']);
      // reaching here (no throw) is the assertion
    });
  });
}
