import 'package:flutter_test/flutter_test.dart';
import 'package:origo_mobile/services/nlp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NLP parses compound phrase with multiple products and sales', () async {
    final nlp = RegionalNlpService();
    await nlp.loadCatalog();

    final results = nlp.parsePhrase('Vendimos 5 bultos de papa y 5 bultos de harina');
    expect(results.length, 2);
    expect(results[0].action, 'SALIDA');
    expect(results[0].productId, 'prod_papa_pastusa');
    expect(results[0].quantity, 5.0);
    expect(results[0].unit, 'bultos');

    expect(results[1].action, 'SALIDA');
    expect(results[1].productId, 'prod_harina_pan');
    expect(results[1].quantity, 5.0);
    expect(results[1].unit, 'bultos');

    // Prueba 2: Reutilización de unidad o diferentes números en palabras
    final r2 = nlp.parsePhrase('Vendí dos bultos de arroz y tres de cemento');
    expect(r2.length, 2);
    expect(r2[0].quantity, 2.0);
    expect(r2[0].productId, 'prod_arroz_casanare');
    expect(r2[1].quantity, 3.0);
    expect(r2[1].productId, 'prod_cemento_gris');
  });
}
