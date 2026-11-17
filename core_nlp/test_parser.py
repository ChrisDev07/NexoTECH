"""
Suite de Pruebas Unitarias del Motor NLP Heurístico (CREATIC Casanare)
Valida la precisión en modismos y frases reales de tenderos del departamento.
"""

import unittest
from parser import RegionalNLPParser

class TestRegionalNLPParser(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parser = RegionalNLPParser()

    def test_single_item_in(self):
        res = self.parser.parse_phrase("llegaron 15 bultos de arroz casanare")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "ENTRADA")
        self.assertEqual(res[0]["quantity"], 15.0)
        self.assertEqual(res[0]["unit"], "bultos")
        self.assertEqual(res[0]["product_id"], "prod_arroz_casanare")

    def test_single_item_out(self):
        res = self.parser.parse_phrase("vendí 3 arrobas de papa pastusa")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "SALIDA")
        self.assertEqual(res[0]["quantity"], 3.0)
        self.assertEqual(res[0]["unit"], "arrobas")
        self.assertEqual(res[0]["product_id"], "prod_papa_pastusa")

    def test_compound_phrase_with_y(self):
        res = self.parser.parse_phrase("llegaron 20 bultos de arroz y 5 de sal marina")
        self.assertEqual(len(res), 2)
        self.assertEqual(res[0]["action"], "ENTRADA")
        self.assertEqual(res[0]["quantity"], 20.0)
        self.assertEqual(res[0]["product_id"], "prod_arroz_casanare")
        self.assertEqual(res[1]["action"], "ENTRADA")
        self.assertEqual(res[1]["quantity"], 5.0)
        self.assertEqual(res[1]["product_id"], "prod_sal_marina")

    def test_spoken_numbers(self):
        res = self.parser.parse_phrase("recibí veinticinco pacas de panela criolla")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["quantity"], 25.0)
        self.assertEqual(res[0]["product_id"], "prod_panela_criolla")

    def test_half_units(self):
        res = self.parser.parse_phrase("se llevaron dos y media arrobas de papa")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "SALIDA")
        self.assertEqual(res[0]["quantity"], 2.5)
        self.assertEqual(res[0]["product_id"], "prod_papa_pastusa")

    def test_agroinsumos_phrase(self):
        res = self.parser.parse_phrase("compré 10 bultos de abono triple 15")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "ENTRADA")
        self.assertEqual(res[0]["quantity"], 10.0)
        self.assertEqual(res[0]["product_id"], "prod_abono_triple15")

    def test_hardware_cemento(self):
        res = self.parser.parse_phrase("descargaron cincuenta bultos de cemento gris")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "ENTRADA")
        self.assertEqual(res[0]["quantity"], 50.0)
        self.assertEqual(res[0]["product_id"], "prod_cemento_gris")

    def test_oil_boxes(self):
        res = self.parser.parse_phrase("despaché seis cajas de aceite vegetal")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "SALIDA")
        self.assertEqual(res[0]["quantity"], 6.0)
        self.assertEqual(res[0]["product_id"], "prod_aceite_vegetal")

    def test_harina_pan(self):
        res = self.parser.parse_phrase("salieron ocho pacas de harina pan")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "SALIDA")
        self.assertEqual(res[0]["quantity"], 8.0)
        self.assertEqual(res[0]["product_id"], "prod_harina_pan")

    def test_fuzzy_matching_synonyms(self):
        res = self.parser.parse_phrase("llegaron 12 bultos de arrosito diana")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["product_id"], "prod_arroz_casanare")

    def test_venta_as_salida(self):
        res = self.parser.parse_phrase("venta de 3 bultos de arroz casanare")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "SALIDA")
        self.assertEqual(res[0]["quantity"], 3.0)
        self.assertEqual(res[0]["product_id"], "prod_arroz_casanare")

    def test_hice_una_venta(self):
        res = self.parser.parse_phrase("hice una venta de diez pacas de harina")
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["action"], "SALIDA")
        self.assertEqual(res[0]["quantity"], 10.0)
        self.assertEqual(res[0]["product_id"], "prod_harina_pan")

if __name__ == "__main__":
    unittest.main()
