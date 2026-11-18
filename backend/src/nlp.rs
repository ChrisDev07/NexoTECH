//! Motor NLP Heurístico de Voz en Rust para Origo (CREATIC Casanare).
//! Procesa lenguaje natural oral de comerciantes de Casanare 100% local (sin LLM externo).

use crate::models::{round2, Catalog, CatalogProduct, ParsedEntity};
use regex::Regex;
use std::collections::{HashMap, HashSet};
use unicode_normalization::UnicodeNormalization;

const EMBEDDED_CATALOG_JSON: &str = include_str!("../../core_nlp/catalog.json");

fn sparse_number(word: &str) -> Option<f64> {
    match word {
        "cero" => Some(0.0),
        "un" | "uno" | "una" => Some(1.0),
        "dos" => Some(2.0),
        "tres" => Some(3.0),
        "cuatro" => Some(4.0),
        "cinco" => Some(5.0),
        "seis" => Some(6.0),
        "siete" => Some(7.0),
        "ocho" => Some(8.0),
        "nueve" => Some(9.0),
        "diez" => Some(10.0),
        "once" => Some(11.0),
        "doce" => Some(12.0),
        "trece" => Some(13.0),
        "catorce" => Some(14.0),
        "quince" => Some(15.0),
        "dieciseis" => Some(16.0),
        "diecisiete" => Some(17.0),
        "dieciocho" => Some(18.0),
        "diecinueve" => Some(19.0),
        "veinte" => Some(20.0),
        "veintiuno" => Some(21.0),
        "veintidos" => Some(22.0),
        "veintitres" => Some(23.0),
        "veinticuatro" => Some(24.0),
        "veinticinco" => Some(25.0),
        "treinta" => Some(30.0),
        "cuarenta" => Some(40.0),
        "cincuenta" => Some(50.0),
        "sesenta" => Some(60.0),
        "setenta" => Some(70.0),
        "ochenta" => Some(80.0),
        "noventa" => Some(90.0),
        "cien" | "ciento" => Some(100.0),
        "doscientos" => Some(200.0),
        "quinientos" => Some(500.0),
        "mil" => Some(1000.0),
        "medio" | "media" => Some(0.5),
        _ => None,
    }
}

/// Normaliza texto eliminando tildes y símbolos especiales, manteniendo minúsculas.
pub fn normalize_text(text: &str) -> String {
    let lowered = text.to_lowercase();
    let mut cleaned = String::with_capacity(lowered.len());
    for ch in lowered.nfd() {
        // Filtrar marcas combinantes diacríticas (tildes)
        if ('\u{0300}'..='\u{036f}').contains(&ch) {
            continue;
        }
        if ch.is_ascii_alphanumeric() || ch == ' ' || ch == '.' || ch == ',' {
            cleaned.push(ch);
        } else {
            cleaned.push(' ');
        }
    }
    cleaned.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Convierte expresiones numéricas orales o dígitos a flotante.
/// Solo tiene éxito si TODAS las palabras forman parte de la expresión numérica.
pub fn word_to_number(word_expr: &str) -> Option<f64> {
    let expr = word_expr.trim();
    if expr.is_empty() {
        return None;
    }
    if let Ok(n) = expr.parse::<f64>() {
        if expr.chars().all(|c| c.is_ascii_digit() || c == '.') {
            return Some(n);
        }
    }

    let tokens: Vec<&str> = expr.split_whitespace().collect();
    if tokens.len() == 3 && tokens[1] == "y" && (tokens[2] == "media" || tokens[2] == "medio") {
        if let Some(base) = sparse_number(tokens[0]) {
            return Some(base + 0.5);
        }
    }

    if expr == "media" || expr == "medio" {
        return Some(0.5);
    }

    for &t in &tokens {
        if sparse_number(t).is_none() && t != "y" && !t.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
    }

    let mut total = 0.0;
    let mut current = 0.0;
    let mut found = false;

    for &t in &tokens {
        if t == "y" {
            continue;
        }
        if let Some(val) = sparse_number(t) {
            found = true;
            if (val - 1000.0).abs() < f64::EPSILON {
                current = if current != 0.0 { current } else { 1.0 } * 1000.0;
                total += current;
                current = 0.0;
            } else if (val - 100.0).abs() < f64::EPSILON && current != 0.0 {
                current *= 100.0;
            } else {
                current += val;
            }
        } else if let Ok(v) = t.parse::<f64>() {
            current += v;
            found = true;
        }
    }

    total += current;
    if found {
        Some(total)
    } else {
        None
    }
}

/// Similitud normalizada basada en distancia de Levenshtein (0.0 a 1.0).
fn string_similarity(a: &str, b: &str) -> f64 {
    if a == b {
        return 1.0;
    }
    let a_chars: Vec<char> = a.chars().collect();
    let b_chars: Vec<char> = b.chars().collect();
    let m = a_chars.len();
    let n = b_chars.len();
    if m == 0 || n == 0 {
        return 0.0;
    }

    let mut dp = vec![vec![0usize; n + 1]; m + 1];
    for (i, row) in dp.iter_mut().enumerate().take(m + 1) {
        row[0] = i;
    }
    for (j, cell) in dp[0].iter_mut().enumerate().take(n + 1) {
        *cell = j;
    }
    for i in 1..=m {
        for j in 1..=n {
            let cost = usize::from(a_chars[i - 1] != b_chars[j - 1]);
            dp[i][j] = (dp[i - 1][j] + 1)
                .min(dp[i][j - 1] + 1)
                .min(dp[i - 1][j - 1] + cost);
        }
    }
    let max_len = m.max(n) as f64;
    1.0 - (dp[m][n] as f64 / max_len)
}

pub struct RegionalNlpParser {
    pub catalog: Catalog,
    units: Vec<String>,
    in_keywords: Vec<String>,
    out_keywords: Vec<String>,
    filter_words: HashSet<String>,
    article_action_re: Regex,
    half_protect_re: Regex,
    clause_split_re: Regex,
    digit_re: Regex,
    unit_regexes: HashMap<String, Regex>,
}

impl RegionalNlpParser {
    pub fn from_embedded() -> Self {
        let catalog: Catalog =
            serde_json::from_str(EMBEDDED_CATALOG_JSON).expect("Catálogo JSON embebido inválido");
        Self::new(catalog)
    }

    pub fn new(catalog: Catalog) -> Self {
        let units: Vec<String> = catalog.units.iter().map(|u| normalize_text(u)).collect();
        let in_keywords: Vec<String> = catalog
            .intentions
            .get("IN")
            .cloned()
            .unwrap_or_default()
            .iter()
            .map(|k| normalize_text(k))
            .collect();
        let out_keywords: Vec<String> = catalog
            .intentions
            .get("OUT")
            .cloned()
            .unwrap_or_default()
            .iter()
            .map(|k| normalize_text(k))
            .collect();

        let mut filter_words: HashSet<String> = HashSet::new();
        for k in in_keywords.iter().chain(out_keywords.iter()) {
            filter_words.insert(k.clone());
        }
        for w in [
            "de",
            "del",
            "pa",
            "para",
            "en",
            "por",
            "favor",
            "aqui",
            "se",
            "me",
            "le",
            "nos",
            "hice",
            "anota",
            "anotar",
            "apunta",
            "apuntar",
            "registro",
            "registrar",
        ] {
            filter_words.insert(w.to_string());
        }

        let mut unit_regexes = HashMap::new();
        for u in &units {
            if let Ok(re) = Regex::new(&format!(r"\b{}\b", regex::escape(u))) {
                unit_regexes.insert(u.clone(), re);
            }
        }

        Self {
            catalog,
            units,
            in_keywords,
            out_keywords,
            filter_words,
            article_action_re: Regex::new(
                r"\b(un|una)\s+(venta|ventas|compra|compras|salida|salidas|entrada|entradas|despacho|despachos|ingreso|ingresos|pedido|pedidos)\b",
            )
            .unwrap(),
            half_protect_re: Regex::new(r"\b([a-z]+)\s+y\s+medi([ao])\b").unwrap(),
            clause_split_re: Regex::new(r"\s+(?:y|tambien|con)\s+|,\s*").unwrap(),
            digit_re: Regex::new(r"\b(\d+(?:\.\d+)?)\b").unwrap(),
            unit_regexes,
        }
    }

    pub fn find_best_product<'a>(
        &'a self,
        query: &str,
        extra_products: &'a [CatalogProduct],
    ) -> Option<(&'a CatalogProduct, f64)> {
        let clean_query = normalize_text(query);
        if clean_query.len() < 2 {
            return None;
        }

        let mut best: Option<(&CatalogProduct, f64)> = None;
        let mut highest_score = 0.0;

        for prod in self.catalog.products.iter().chain(extra_products.iter()) {
            let prod_name_clean = normalize_text(&prod.name);
            let mut sim = string_similarity(&clean_query, &prod_name_clean);

            if prod_name_clean.contains(&clean_query) || clean_query.contains(&prod_name_clean) {
                sim = sim.max(0.85);
            }

            for syn in &prod.synonyms {
                let syn_clean = normalize_text(syn);
                let mut syn_sim = string_similarity(&clean_query, &syn_clean);
                if clean_query == syn_clean {
                    syn_sim = 1.0;
                } else if syn_clean.contains(&clean_query) || clean_query.contains(&syn_clean) {
                    syn_sim = syn_sim.max(0.90);
                }
                sim = sim.max(syn_sim);
            }

            if sim > highest_score && sim >= 0.60 {
                highest_score = sim;
                best = Some((prod, round2(highest_score)));
            }
        }

        best
    }

    pub fn detect_action_in_clause(&self, text_norm: &str) -> Option<&'static str> {
        for w in text_norm.split_whitespace() {
            if self.in_keywords.iter().any(|k| k == w) {
                return Some("ENTRADA");
            }
            if self.out_keywords.iter().any(|k| k == w) {
                return Some("SALIDA");
            }
        }
        for kw in &self.in_keywords {
            if let Ok(re) = Regex::new(&format!(r"\b{}\b", regex::escape(kw))) {
                if re.is_match(text_norm) {
                    return Some("ENTRADA");
                }
            }
        }
        for kw in &self.out_keywords {
            if let Ok(re) = Regex::new(&format!(r"\b{}\b", regex::escape(kw))) {
                if re.is_match(text_norm) {
                    return Some("SALIDA");
                }
            }
        }
        None
    }

    pub fn detect_action(&self, text_norm: &str) -> &'static str {
        self.detect_action_in_clause(text_norm).unwrap_or("ENTRADA")
    }

    pub fn parse_phrase(&self, raw_phrase: &str) -> Vec<ParsedEntity> {
        self.parse_phrase_with_extra_products(raw_phrase, &[])
    }

    pub fn parse_phrase_with_extra_products(
        &self,
        raw_phrase: &str,
        extra_products: &[CatalogProduct],
    ) -> Vec<ParsedEntity> {
        let mut text_norm = normalize_text(raw_phrase);
        text_norm = self
            .article_action_re
            .replace_all(&text_norm, "$2")
            .to_string();
        let default_action = self.detect_action(&text_norm);
        let mut current_action = default_action;

        let protected_text = self
            .half_protect_re
            .replace_all(&text_norm, "${1}_y_medi${2}")
            .to_string();

        let mut results = Vec::new();
        let mut last_known_unit: Option<String> = None;

        for raw_clause in self.clause_split_re.split(&protected_text) {
            let clause = raw_clause.replace("_y_", " y ").trim().to_string();
            if clause.is_empty() {
                continue;
            }

            if let Some(act) = self.detect_action_in_clause(&clause) {
                current_action = act;
            }

            let mut quantity: Option<f64> = None;
            let mut candidate_num_str: Option<String> = None;

            if let Some(cap) = self.digit_re.captures(&clause) {
                if let Some(m) = cap.get(1) {
                    if let Ok(v) = m.as_str().parse::<f64>() {
                        quantity = Some(v);
                        candidate_num_str = Some(m.as_str().to_string());
                    }
                }
            } else {
                let words: Vec<&str> = clause.split_whitespace().collect();
                'outer: for i in 0..words.len() {
                    for j in (i + 1..=words.len()).rev() {
                        let candidate = words[i..j].join(" ");
                        if let Some(num_val) = word_to_number(&candidate) {
                            if sparse_number(&candidate).is_some()
                                || candidate.contains("y media")
                                || candidate.contains("y medio")
                            {
                                quantity = Some(num_val);
                                candidate_num_str = Some(candidate);
                                break 'outer;
                            }
                        }
                    }
                }
            }

            let mut detected_unit: Option<String> = None;
            let mut detected_unit_str: Option<String> = None;
            for u in &self.units {
                if let Some(re) = self.unit_regexes.get(u) {
                    if let Some(m) = re.find(&clause) {
                        detected_unit = Some(u.clone());
                        detected_unit_str = Some(m.as_str().to_string());
                        last_known_unit = Some(u.clone());
                        break;
                    }
                }
            }

            let final_unit = detected_unit
                .or_else(|| last_known_unit.clone())
                .unwrap_or_else(|| "unidades".to_string());

            let mut product_query = clause.clone();
            if let Some(num_str) = candidate_num_str {
                if let Ok(re) = Regex::new(&format!(r"\b{}\b", regex::escape(&num_str))) {
                    product_query = re.replace(&product_query, " ").to_string();
                }
            }
            if let Some(unit_str) = detected_unit_str {
                if let Ok(re) = Regex::new(&format!(r"\b{}\b", regex::escape(&unit_str))) {
                    product_query = re.replace(&product_query, " ").to_string();
                }
            }

            let clean_product_query = product_query
                .split_whitespace()
                .filter(|w| !self.filter_words.contains(*w))
                .collect::<Vec<_>>()
                .join(" ");

            if let Some((prod, score)) =
                self.find_best_product(&clean_product_query, extra_products)
            {
                results.push(ParsedEntity {
                    raw_clause: clause,
                    action: current_action.to_string(),
                    quantity: quantity.unwrap_or(1.0),
                    unit: final_unit,
                    product_id: prod.id.clone(),
                    product_name: prod.name.clone(),
                    category: prod.category.clone(),
                    retail_price_cop: prod.retail_price_cop,
                    wholesale_price_cop: prod.wholesale_price_cop,
                    min_threshold: prod.min_threshold,
                    confidence: score,
                });
            }
        }

        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parser() -> RegionalNlpParser {
        RegionalNlpParser::from_embedded()
    }

    #[test]
    fn test_single_item_in() {
        let res = parser().parse_phrase("Llegaron 20 bultos de arroz casanareño");
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].action, "ENTRADA");
        assert_eq!(res[0].quantity, 20.0);
        assert_eq!(res[0].unit, "bultos");
        assert_eq!(res[0].product_id, "prod_arroz_casanare");
    }

    #[test]
    fn test_single_item_out() {
        let res = parser().parse_phrase("Vendí 3 arrobas de papa pastusa");
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].action, "SALIDA");
        assert_eq!(res[0].quantity, 3.0);
        assert_eq!(res[0].unit, "arrobas");
        assert_eq!(res[0].product_id, "prod_papa_pastusa");
    }

    #[test]
    fn test_venta_as_salida() {
        let res = parser().parse_phrase("venta de 1 bultos de arroz casanareño");
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].action, "SALIDA");
        assert_eq!(res[0].quantity, 1.0);
        assert_eq!(res[0].product_id, "prod_arroz_casanare");
    }

    #[test]
    fn test_hice_una_venta() {
        let res = parser().parse_phrase("hice una venta de diez bultos de arroz casanareño");
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].action, "SALIDA");
        assert_eq!(res[0].quantity, 10.0);
        assert_eq!(res[0].product_id, "prod_arroz_casanare");
    }

    #[test]
    fn test_compound_phrase_with_y() {
        let res = parser().parse_phrase("Descargaron 15 bultos de arroz y 5 de sal marina");
        assert_eq!(res.len(), 2);
        assert_eq!(res[0].product_id, "prod_arroz_casanare");
        assert_eq!(res[0].quantity, 15.0);
        assert_eq!(res[1].product_id, "prod_sal_marina");
        assert_eq!(res[1].quantity, 5.0);
        assert_eq!(res[1].unit, "bultos");
    }

    #[test]
    fn test_compound_mixed_actions() {
        let res = parser().parse_phrase("Vendí 5 bultos de papa y compré 10 bultos de arroz");
        assert_eq!(res.len(), 2);
        assert_eq!(res[0].action, "SALIDA");
        assert_eq!(res[0].product_id, "prod_papa_pastusa");
        assert_eq!(res[0].quantity, 5.0);
        assert_eq!(res[0].unit, "bultos");

        assert_eq!(res[1].action, "ENTRADA");
        assert_eq!(res[1].product_id, "prod_arroz_casanare");
        assert_eq!(res[1].quantity, 10.0);
        assert_eq!(res[1].unit, "bultos");
    }

    #[test]
    fn test_spoken_numbers_and_half_units() {
        let p = parser();
        let r1 = p.parse_phrase("Se llevaron veinticinco pacas de panela criolla");
        assert_eq!(r1.len(), 1);
        assert_eq!(r1[0].action, "SALIDA");
        assert_eq!(r1[0].quantity, 25.0);
        assert_eq!(r1[0].product_id, "prod_panela_criolla");

        let r2 = p.parse_phrase("Vendí dos y media arrobas de papa");
        assert_eq!(r2.len(), 1);
        assert_eq!(r2[0].quantity, 2.5);
        assert_eq!(r2[0].product_id, "prod_papa_pastusa");
    }

    #[test]
    fn test_fuzzy_synonyms_agro_hardware_oil_harina() {
        let p = parser();
        let r_arros = p.parse_phrase("Llegaron 10 bultos de arrosito");
        assert_eq!(r_arros[0].product_id, "prod_arroz_casanare");

        let r_abono = p.parse_phrase("Entraron 8 bultos de triple 15");
        assert_eq!(r_abono[0].product_id, "prod_abono_triple15");

        let r_cem = p.parse_phrase("Despaché 12 bultos de cemento argos");
        assert_eq!(r_cem[0].action, "SALIDA");
        assert_eq!(r_cem[0].product_id, "prod_cemento_gris");

        let r_oil = p.parse_phrase("Recibí cuatro cajas de aceite premier");
        assert_eq!(r_oil[0].product_id, "prod_aceite_vegetal");
        assert_eq!(r_oil[0].quantity, 4.0);

        let r_har = p.parse_phrase("Salieron 6 pacas de harina pan");
        assert_eq!(r_har[0].action, "SALIDA");
        assert_eq!(r_har[0].product_id, "prod_harina_pan");
    }
}
