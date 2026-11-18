import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

class ParsedMovement {
  final String action; // 'ENTRADA' o 'SALIDA'
  final double quantity;
  final String unit;
  final String productId;
  final String productName;
  final double confidence;

  ParsedMovement({
    required this.action,
    required this.quantity,
    required this.unit,
    required this.productId,
    required this.productName,
    required this.confidence,
  });
}

/// Motor NLP Heurístico 100% Offline en Dart (espejo de core_nlp/parser.py).
class RegionalNlpService {
  static const Map<String, double> _numberWords = {
    'cero': 0, 'un': 1, 'uno': 1, 'una': 1, 'dos': 2, 'tres': 3, 'cuatro': 4,
    'cinco': 5, 'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
    'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
    'dieciseis': 16, 'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19,
    'veinte': 20, 'veintiuno': 21, 'veintidos': 22, 'veintitres': 23,
    'veinticinco': 25, 'treinta': 30, 'cuarenta': 40, 'cincuenta': 50,
    'sesenta': 60, 'setenta': 70, 'ochenta': 80, 'noventa': 90, 'cien': 100,
    'ciento': 100, 'doscientos': 200, 'quinientos': 500, 'mil': 1000,
    'medio': 0.5, 'media': 0.5,
  };

  List<String> _units = [];
  List<String> _inKeywords = [];
  List<String> _outKeywords = [];
  List<Map<String, dynamic>> _baseProducts = [];
  List<Map<String, dynamic>> _products = [];
  bool _loaded = false;

  Future<void> loadCatalog() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/catalog.json');
    final Map<String, dynamic> data = jsonDecode(raw);
    _units = (data['units'] as List).map((e) => normalizeText(e.toString())).toList();
    _inKeywords = (data['intentions']['IN'] as List)
        .map((e) => normalizeText(e.toString()))
        .toList();
    _outKeywords = (data['intentions']['OUT'] as List)
        .map((e) => normalizeText(e.toString()))
        .toList();
    _baseProducts = List<Map<String, dynamic>>.from(data['products'] as List);
    _products = List<Map<String, dynamic>>.from(_baseProducts);
    _loaded = true;
  }

  /// Combina el catálogo regional base con los productos personalizados de la tienda activa.
  void setCustomProducts(List<Map<String, dynamic>> customProducts) {
    final merged = List<Map<String, dynamic>>.from(_baseProducts);
    for (final cp in customProducts) {
      final synRaw = cp['synonyms']?.toString() ?? '';
      final synList = synRaw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final entry = {
        'id': cp['id'].toString(),
        'name': cp['name'].toString(),
        'category': cp['category']?.toString() ?? 'Mi Tienda',
        'default_unit': cp['unit']?.toString() ?? 'unidades',
        'synonyms': synList.isEmpty ? [cp['name'].toString().toLowerCase()] : synList,
      };
      final idx = merged.indexWhere((p) => p['id'] == entry['id']);
      if (idx >= 0) {
        merged[idx] = entry;
      } else {
        merged.add(entry);
      }
    }
    _products = merged;
  }

  static String normalizeText(String input) {
    const accents = 'áéíóúüñÁÉÍÓÚÜÑ';
    const plain = 'aeiouunAEIOUUN';
    var out = input.toLowerCase().trim();
    for (int i = 0; i < accents.length; i++) {
      out = out.replaceAll(accents[i], plain[i]);
    }
    out = out.replaceAll(RegExp(r'[^a-z0-9\s\.,]'), ' ');
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final dp = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
    for (int i = 0; i <= a.length; i++) dp[i][0] = i;
    for (int j = 0; j <= b.length; j++) dp[0][j] = j;
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = min(
          min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }
    final maxLen = max(a.length, b.length);
    return 1.0 - (dp[a.length][b.length] / maxLen);
  }

  static double? _wordToNumber(String expr) {
    final clean = expr.trim();
    if (clean.isEmpty) return null;
    final direct = double.tryParse(clean);
    if (direct != null) return direct;

    final halfMatch = RegExp(r'^([a-z]+)\s+y\s+medi[ao]$').firstMatch(clean);
    if (halfMatch != null) {
      final base = _numberWords[halfMatch.group(1)!];
      if (base != null) return base + 0.5;
    }
    if (clean == 'media' || clean == 'medio') return 0.5;

    final tokens = clean.split(' ');
    for (final t in tokens) {
      if (!_numberWords.containsKey(t) && t != 'y' && int.tryParse(t) == null) {
        return null;
      }
    }
    double total = 0;
    double current = 0;
    bool found = false;
    for (final t in tokens) {
      if (t == 'y') continue;
      if (_numberWords.containsKey(t)) {
        final val = _numberWords[t]!;
        found = true;
        if (val == 1000) {
          current = (current == 0 ? 1 : current) * 1000;
          total += current;
          current = 0;
        } else if (val == 100 && current != 0) {
          current *= 100;
        } else {
          current += val;
        }
      } else {
        current += int.parse(t);
        found = true;
      }
    }
    total += current;
    return found ? total : null;
  }

  String _detectAction(String textNorm) {
    final words = textNorm.split(' ');
    for (final w in words) {
      if (_outKeywords.contains(w)) return 'SALIDA';
      if (_inKeywords.contains(w)) return 'ENTRADA';
    }
    for (final kw in _outKeywords) {
      if (RegExp('\\b${RegExp.escape(kw)}\\b').hasMatch(textNorm)) return 'SALIDA';
    }
    for (final kw in _inKeywords) {
      if (RegExp('\\b${RegExp.escape(kw)}\\b').hasMatch(textNorm)) return 'ENTRADA';
    }
    return 'ENTRADA';
  }

  Map<String, dynamic>? _findBestProduct(String query) {
    final cleanQuery = normalizeText(query);
    if (cleanQuery.length < 2) return null;

    Map<String, dynamic>? best;
    double highest = 0.0;

    for (final prod in _products) {
      final nameClean = normalizeText(prod['name'].toString());
      double sim = _similarity(cleanQuery, nameClean);
      if (cleanQuery.contains(nameClean) || nameClean.contains(cleanQuery)) {
        sim = max(sim, 0.85);
      }
      for (final syn in (prod['synonyms'] as List? ?? [])) {
        final synClean = normalizeText(syn.toString());
        double synSim = _similarity(cleanQuery, synClean);
        if (cleanQuery == synClean) {
          synSim = 1.0;
        } else if (cleanQuery.contains(synClean) || synClean.contains(cleanQuery)) {
          synSim = max(synSim, 0.90);
        }
        sim = max(sim, synSim);
      }
      if (sim > highest && sim >= 0.60) {
        highest = sim;
        best = {
          'product_id': prod['id'],
          'product_name': prod['name'],
          'default_unit': prod['default_unit'] ?? 'unidades',
          'confidence': double.parse(highest.toStringAsFixed(2)),
        };
      }
    }
    return best;
  }

  List<ParsedMovement> parsePhrase(String rawPhrase) {
    if (!_loaded) return [];
    var textNorm = normalizeText(rawPhrase);
    textNorm = textNorm.replaceAllMapped(
      RegExp(r'\b(un|una)\s+(venta|ventas|compra|compras|salida|salidas|entrada|entradas|despacho|despachos|ingreso|ingresos|pedido|pedidos)\b'),
      (m) => m.group(2)!,
    );

    final action = _detectAction(textNorm);
    final protectedText = textNorm.replaceAllMapped(
      RegExp(r'\b([a-z]+)\s+y\s+medi([ao])\b'),
      (m) => '${m.group(1)}_y_medi${m.group(2)}',
    );

    final clauses = protectedText.split(RegExp(r'\s+(?:y|tambien|con)\s+|,\s*'));
    final results = <ParsedMovement>[];
    String? lastUnit;

    final filterWords = <String>{
      ..._inKeywords,
      ..._outKeywords,
      'de', 'del', 'pa', 'para', 'en', 'por', 'favor', 'aqui',
      'se', 'me', 'le', 'nos', 'hice', 'anota', 'anotar',
      'apunta', 'apuntar', 'registro', 'registrar',
    };

    for (final rawClause in clauses) {
      final clause = rawClause.replaceAll('_y_', ' y ').trim();
      if (clause.isEmpty) continue;

      double? quantity;
      String? numStr;

      final digitMatch = RegExp(r'\b(\d+(?:\.\d+)?)\b').firstMatch(clause);
      if (digitMatch != null) {
        quantity = double.tryParse(digitMatch.group(1)!);
        numStr = digitMatch.group(1);
      } else {
        final words = clause.split(' ');
        outer:
        for (int i = 0; i < words.length; i++) {
          for (int j = words.length; j > i; j--) {
            final cand = words.sublist(i, j).join(' ');
            final val = _wordToNumber(cand);
            if (val != null) {
              quantity = val;
              numStr = cand;
              break outer;
            }
          }
        }
      }

      String? unit;
      String? unitStr;
      for (final u in _units) {
        final uMatch = RegExp('\\b${RegExp.escape(u)}\\b').firstMatch(clause);
        if (uMatch != null) {
          unit = u;
          unitStr = uMatch.group(0);
          lastUnit = u;
          break;
        }
      }

      var productQuery = clause;
      if (numStr != null) {
        productQuery = productQuery.replaceFirst(RegExp('\\b${RegExp.escape(numStr)}\\b'), ' ');
      }
      if (unitStr != null) {
        productQuery = productQuery.replaceFirst(RegExp('\\b${RegExp.escape(unitStr)}\\b'), ' ');
      }

      final tokens = productQuery
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty && !filterWords.contains(w))
          .toList();
      final matched = _findBestProduct(tokens.join(' '));
      if (matched != null) {
        results.add(
          ParsedMovement(
            action: action,
            quantity: quantity ?? 1.0,
            unit: unit ?? lastUnit ?? matched['default_unit'].toString(),
            productId: matched['product_id'].toString(),
            productName: matched['product_name'].toString(),
            confidence: matched['confidence'] as double,
          ),
        );
      }
    }

    return results;
  }
}
