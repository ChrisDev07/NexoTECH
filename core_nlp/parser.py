"""
Motor NLP Heurístico de Voz para NexoLlano (CREATIC Casanare)
Procesa lenguaje natural oral de comerciantes de Casanare sin conexión a internet.
Extrae intenciones, cantidades, unidades y busca productos con coincidencia difusa (Fuzzy Matching).
"""

import json
import os
import re
import unicodedata
from difflib import SequenceMatcher
from typing import List, Dict, Any, Optional

SPARSE_NUMBERS = {
    "cero": 0, "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
    "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
    "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
    "dieciseis": 16, "dieciséis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19,
    "veinte": 20, "veintiuno": 21, "veintidos": 22, "veintidós": 22, "veintitres": 23,
    "veinticinco": 25, "treinta": 30, "cuarenta": 40, "cincuenta": 50,
    "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
    "ciento": 100, "doscientos": 200, "quinientos": 500, "mil": 1000,
    "medio": 0.5, "media": 0.5
}

def normalize_text(text: str) -> str:
    """Normaliza texto eliminando tildes y caracteres especiales, manteniendo minúsculas."""
    text = text.lower().strip()
    text = ''.join(c for c in unicodedata.normalize('NFD', text) if unicodedata.category(c) != 'Mn')
    text = re.sub(r'[^a-z0-9\s\.,]', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()

def word_to_number(word_expr: str) -> Optional[float]:
    """Convierte expresiones numéricas orales o dígitos a flotante.
    Solo tiene éxito si TODAS las palabras forman parte de la expresión numérica."""
    expr = word_expr.strip()
    if not expr:
        return None
    if re.match(r'^\d+(\.\d+)?$', expr):
        return float(expr)
    
    # Manejo de "dos y media", "tres y medio"
    half_match = re.match(r'^([a-z]+)\s+y\s+medi[ao]$', expr)
    if half_match:
        base_word = half_match.group(1)
        if base_word in SPARSE_NUMBERS:
            return float(SPARSE_NUMBERS[base_word]) + 0.5

    # Manejo de "media" o "medio"
    if expr in ["media", "medio"]:
        return 0.5

    tokens = expr.split()
    # Todas las palabras deben ser números o 'y'
    for t in tokens:
        if t not in SPARSE_NUMBERS and t != 'y' and not re.match(r'^\d+$', t):
            return None

    total = 0
    current = 0
    found = False
    for t in tokens:
        if t == 'y':
            continue
        if t in SPARSE_NUMBERS:
            val = SPARSE_NUMBERS[t]
            found = True
            if val == 1000:
                current = (current if current != 0 else 1) * 1000
                total += current
                current = 0
            elif val == 100 and current != 0:
                current *= 100
            else:
                current += val
        elif re.match(r'^\d+$', t):
            current += int(t)
            found = True
    total += current
    return float(total) if found else None

class RegionalNLPParser:
    def __init__(self, catalog_path: Optional[str] = None):
        if catalog_path is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            catalog_path = os.path.join(base_dir, "catalog.json")
        with open(catalog_path, "r", encoding="utf-8") as f:
            self.catalog = json.load(f)
        
        self.units = [normalize_text(u) for u in self.catalog.get("units", [])]
        self.in_keywords = [normalize_text(k) for k in self.catalog["intentions"]["IN"]]
        self.out_keywords = [normalize_text(k) for k in self.catalog["intentions"]["OUT"]]
        self.products = self.catalog.get("products", [])

    def find_best_product(self, query: str) -> Optional[Dict[str, Any]]:
        """Búsqueda difusa (Fuzzy Matching) contra catálogo y sinónimos regionales."""
        clean_query = normalize_text(query)
        if not clean_query or len(clean_query) < 2:
            return None
        best_match = None
        highest_score = 0.0

        for prod in self.products:
            # Comparar con nombre oficial
            prod_name_clean = normalize_text(prod["name"])
            sim = SequenceMatcher(None, clean_query, prod_name_clean).ratio()
            
            # Substring match bonus
            if clean_query in prod_name_clean or prod_name_clean in clean_query:
                sim = max(sim, 0.85)

            # Comparar con sinónimos
            for syn in prod.get("synonyms", []):
                syn_clean = normalize_text(syn)
                syn_sim = SequenceMatcher(None, clean_query, syn_clean).ratio()
                if clean_query == syn_clean:
                    syn_sim = 1.0
                elif clean_query in syn_clean or syn_clean in clean_query:
                    syn_sim = max(syn_sim, 0.90)
                sim = max(sim, syn_sim)

            if sim > highest_score and sim >= 0.60:
                highest_score = sim
                best_match = {
                    "product_id": prod["id"],
                    "product_name": prod["name"],
                    "category": prod.get("category", "General"),
                    "default_unit": prod.get("default_unit", "unidades"),
                    "retail_price_cop": prod.get("retail_price_cop", 0),
                    "wholesale_price_cop": prod.get("wholesale_price_cop", 0),
                    "min_threshold": prod.get("min_threshold", 5),
                    "match_score": round(highest_score, 2)
                }

        return best_match

    def detect_action(self, text_norm: str) -> str:
        """Determina si es ENTRADA o SALIDA de mercancía."""
        words = text_norm.split()
        for w in words:
            if w in self.in_keywords:
                return "ENTRADA"
            if w in self.out_keywords:
                return "SALIDA"
        
        # Búsqueda por subcadena
        for kw in self.in_keywords:
            if re.search(r'\b' + re.escape(kw) + r'\b', text_norm):
                return "ENTRADA"
        for kw in self.out_keywords:
            if re.search(r'\b' + re.escape(kw) + r'\b', text_norm):
                return "SALIDA"
        
        return "ENTRADA"  # Predeterminado

    def parse_phrase(self, raw_phrase: str) -> List[Dict[str, Any]]:
        """
        Procesa una frase de voz y devuelve una lista de entidades estructuradas.
        Soporta oraciones compuestas con conectores ("y", "también").
        """
        text_norm = normalize_text(raw_phrase)
        action = self.detect_action(text_norm)

        # Proteger frases como "y media" o "y medio" para que no se separen por 'y'
        protected_text = re.sub(r'\b([a-z]+)\s+y\s+medi([ao])\b', r'\1_y_medi\2', text_norm)

        # Dividir por conectores de múltiples artículos (" y ", ", ", " tambien ")
        clauses = re.split(r'\s+(?:y|tambien|con)\s+|,\s*', protected_text)
        results = []

        last_known_unit = None

        for clause in clauses:
            clause = clause.replace('_y_', ' y ').strip()
            if not clause:
                continue

            # Buscar números (dígitos o palabras numéricas)
            quantity = None
            candidate_num_str = None

            # 1. Buscar dígitos
            digit_match = re.search(r'\b(\d+(\.\d+)?)\b', clause)
            if digit_match:
                quantity = float(digit_match.group(1))
                candidate_num_str = digit_match.group(1)
            else:
                # 2. Buscar palabras numéricas compuestas (ej: "veinticinco", "dos y media", "tres")
                words = clause.split()
                for i in range(len(words)):
                    for j in range(len(words), i, -1):
                        candidate = " ".join(words[i:j])
                        num_val = word_to_number(candidate)
                        if num_val is not None and (candidate in SPARSE_NUMBERS or "y media" in candidate):
                            quantity = num_val
                            candidate_num_str = candidate
                            break
                    if quantity is not None:
                        break

            # Buscar unidad de medida
            detected_unit = None
            detected_unit_str = None
            for u in self.units:
                u_match = re.search(r'\b' + re.escape(u) + r'\b', clause)
                if u_match:
                    detected_unit = u
                    detected_unit_str = u_match.group(0)
                    last_known_unit = u
                    break

            if not detected_unit:
                detected_unit = last_known_unit if last_known_unit else "unidades"

            # Extraer segmento de producto quitando números y unidades
            product_query = clause
            if candidate_num_str:
                product_query = re.sub(r'\b' + re.escape(candidate_num_str) + r'\b', ' ', product_query, count=1)
            if detected_unit_str:
                product_query = re.sub(r'\b' + re.escape(detected_unit_str) + r'\b', ' ', product_query, count=1)

            # Limpiar preposiciones, palabras de acción y muletillas
            filter_words = set(self.in_keywords + self.out_keywords + ["de", "del", "pa", "para", "en", "por", "favor", "aqui", "se", "me", "le", "nos"])
            tokens = [w for w in product_query.split() if w not in filter_words]
            clean_product_query = " ".join(tokens)

            matched_product = self.find_best_product(clean_product_query)

            if matched_product:
                results.append({
                    "raw_clause": clause,
                    "action": action,
                    "quantity": quantity if quantity is not None else 1.0,
                    "unit": detected_unit,
                    "product_id": matched_product["product_id"],
                    "product_name": matched_product["product_name"],
                    "category": matched_product["category"],
                    "retail_price_cop": matched_product["retail_price_cop"],
                    "wholesale_price_cop": matched_product["wholesale_price_cop"],
                    "min_threshold": matched_product["min_threshold"],
                    "confidence": matched_product["match_score"]
                })

        return results

if __name__ == "__main__":
    parser = RegionalNLPParser()
    test_phrases = [
        "llegaron 20 bultos de arroz casanare y 5 de sal",
        "vendí tres arrobas de papa pastusa",
        "descargaron diez bultos de cemento gris",
        "se llevaron dos y media arrobas de papa",
        "vendí cuatro cajas de aceite vegetal"
    ]
    print("=== DEMOSTRACIÓN DE PARSER NLP CASANAREÑO ===")
    for tp in test_phrases:
        print(f"\n🎙️ Frase: \"{tp}\"")
        res = parser.parse_phrase(tp)
        for r in res:
            print(f"  👉 Acción: {r['action']} | Cantidad: {r['quantity']} {r['unit']} | Producto: {r['product_name']} (Confianza: {r['confidence']*100}%)")
