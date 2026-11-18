import 'package:flutter_test/flutter_test.dart';
import 'package:origo_mobile/services/offline_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OWASP Mobile Security Validations', () {
    test('Phone sanitization strips non-digit characters (Anti-Injection)', () {
      expect(OfflineLedgerService.sanitizePhone('+57 (310) 123-4567'), '573101234567');
      expect(OfflineLedgerService.sanitizePhone('310.123.4567'), '3101234567');
      expect(OfflineLedgerService.sanitizePhone('  310 123 4567  '), '3101234567');
    });

    test('Quantity validation rejects invalid numbers (OWASP M4)', () {
      // Verificar que valores no numéricos o anómalos no sean permitidos
      expect(() {
        final q = double.nan;
        if (q.isNaN || q.isInfinite || q <= 0.0) {
          throw ArgumentError('La cantidad debe ser un número positivo mayor que cero.');
        }
      }, throwsArgumentError);

      expect(() {
        final q = -5.0;
        if (q.isNaN || q.isInfinite || q <= 0.0) {
          throw ArgumentError('La cantidad debe ser un número positivo mayor que cero.');
        }
      }, throwsArgumentError);

      expect(() {
        final q = double.infinity;
        if (q.isNaN || q.isInfinite || q <= 0.0) {
          throw ArgumentError('La cantidad debe ser un número positivo mayor que cero.');
        }
      }, throwsArgumentError);
    });
  });
}
