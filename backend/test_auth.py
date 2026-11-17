"""
Pruebas Unitarias del Módulo de Autenticación Segura y Habeas Data (Ley 1581 de 2012).
"""

import unittest
from auth import AuthManager, hash_pin, verify_pin


class TestAuthSecurity(unittest.TestCase):
    def setUp(self):
        self.auth = AuthManager(":memory:")

    def test_pbkdf2_unique_salt_and_verification(self):
        salt1, hash1 = hash_pin("4567")
        salt2, hash2 = hash_pin("4567")
        self.assertNotEqual(salt1, salt2)
        self.assertNotEqual(hash1, hash2)
        self.assertTrue(verify_pin("4567", salt1, hash1))
        self.assertFalse(verify_pin("0000", salt1, hash1))

    def test_register_requires_habeas_data_consent(self):
        result, err = self.auth.register_user(
            phone="3209998877",
            pin="5678",
            owner_name="Doña Martha",
            business_name="Agroinsumos Aguazul",
            zone="Centro, Aguazul",
            habeas_data_accepted=False
        )
        self.assertIsNone(result)
        self.assertIn("Ley 1581", err)

    def test_register_login_and_session_lifecycle(self):
        result, err = self.auth.register_user(
            phone="320-999-8877",
            pin="5678",
            owner_name="Doña Martha",
            business_name="Agroinsumos Aguazul",
            zone="Centro, Aguazul",
            habeas_data_accepted=True
        )
        self.assertIsNone(err)
        self.assertIsNotNone(result)
        token = result["token"]
        user = result["user"]
        self.assertEqual(user["owner_name"], "Doña Martha")
        self.assertEqual(user["business_name"], "Agroinsumos Aguazul")
        # Nunca exponer secretos en la respuesta
        self.assertNotIn("pin_hash", user)
        self.assertNotIn("pin_salt", user)

        # Validar sesión activa
        session_user = self.auth.get_session_user(token)
        self.assertIsNotNone(session_user)
        self.assertEqual(session_user["phone"], "3209998877")

        # Login con clave correcta e incorrecta
        login_ok, err_ok = self.auth.login("3209998877", "5678")
        self.assertIsNone(err_ok)
        self.assertIsNotNone(login_ok["token"])

        login_bad, err_bad = self.auth.login("3209998877", "9999")
        self.assertIsNone(login_bad)
        self.assertIsNotNone(err_bad)

        # Cerrar sesión invalida el token
        self.auth.logout(token)
        self.assertIsNone(self.auth.get_session_user(token))

    def test_demo_account_seeded(self):
        res, err = self.auth.login("3101234567", "1234")
        self.assertIsNone(err)
        self.assertEqual(res["user"]["id"], "tienda_demo")
        self.assertEqual(res["user"]["owner_name"], "Don Pedro")


if __name__ == "__main__":
    unittest.main()
