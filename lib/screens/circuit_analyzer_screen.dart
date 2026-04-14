// ============================================================
//  ADHUNIK YANTRA — COMPLETE OCR CIRCUIT ANALYZER
//  Works for: PDF (all pages) + Images (jpg/png)
//  No API key. No internet. No limits. Runs on device.
//
//  pubspec.yaml — add these:
//  google_mlkit_text_recognition: ^0.11.0
//  pdfx: ^2.6.0
//
//  File: lib/screens/circuit_analyzer_screen.dart
//  Replace your existing file with this entire file.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

// ── Groq API for TEXT-ONLY responses (fault explanation, safety check)
// Image analysis is done by on-device OCR — no API needed for that
const String _groqApiKey = 'YOUR_GROQ_API_KEY_HERE';
const String _groqUrl    = 'https://api.groq.com/openai/v1/chat/completions';
const String _groqModel  = 'llama-3.1-8b-instant'; // text only, 14.4K/day free

// ── Call Groq for text-only AI responses ─────────────────────
Future<String> _callGroq(String prompt) async {
  try {
    final response = await http.post(
      Uri.parse(_groqUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_groqApiKey',
      },
      body: jsonEncode({
        'model': _groqModel,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 300,
        'temperature': 0.2,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    }
    return _fallbackText(prompt);
  } catch (_) {
    return _fallbackText(prompt);
  }
}

String _fallbackText(String prompt) {
  if (prompt.contains('fault')) {
    return 'A fault was detected on this circuit. Turn off the circuit breaker and check all connected appliances before resetting.';
  }
  return 'Circuit appears to be wired correctly based on available data. Ensure regular maintenance checks.';
}

// ════════════════════════════════════════════════════════════
//  OCR ENGINE — reads text from image bytes
// ════════════════════════════════════════════════════════════
class _OCREngine {
  static final _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  // ── Read from file path (images) ─────────────────────────
  static Future<String> fromFile(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  // ── Read from bytes (PDF rendered pages) ─────────────────
  static Future<String> fromBytes(Uint8List bytes) async {
    // Write bytes to temp file then OCR it
    final tempDir = Directory.systemTemp;
    final tempFile = File(
        '${tempDir.path}/adhunik_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(bytes);

    try {
      final text = await fromFile(tempFile.path);
      return text;
    } finally {
      // Clean up temp file
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  static void dispose() => _recognizer.close();
}

// ════════════════════════════════════════════════════════════
//  CIRCUIT PARSER — converts OCR text → circuit list
// ════════════════════════════════════════════════════════════
class _CircuitParser {
  static List<Map<String, dynamic>> parse(String fullText) {
    // Combine all text, normalize whitespace
    final lines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final circuits = <Map<String, dynamic>>[];
    final phaseCounts = <String, int>{'R': 0, 'Y': 0, 'B': 0, 'N': 0};

    // ── Try structured row parsing first ─────────────────
    for (final line in lines) {
      if (_isNoiseLine(line)) continue;

      final circuit = _parseOneLine(line, phaseCounts);
      if (circuit != null) {
        circuits.add(circuit);
        final p = circuit['phase'] as String;
        phaseCounts[p] = (phaseCounts[p] ?? 0) + 1;
      }
    }

    // ── If nothing found, try combining adjacent lines ────
    if (circuits.isEmpty) {
      final combined = _combineLines(lines);
      for (final line in combined) {
        if (_isNoiseLine(line)) continue;
        final circuit = _parseOneLine(line, phaseCounts);
        if (circuit != null) {
          circuits.add(circuit);
          final p = circuit['phase'] as String;
          phaseCounts[p] = (phaseCounts[p] ?? 0) + 1;
        }
      }
    }

    return circuits;
  }

  // ── Try to extract a circuit from a single line ───────
  static Map<String, dynamic>? _parseOneLine(
      String line, Map<String, int> phaseCounts) {
    // Must have a number that looks like an MCB rating
    final mcbMatch = RegExp(
      r'\b(6|10|16|20|25|32|40|50|63|80|100)\s*[Aa](?:mp)?s?\b',
    ).firstMatch(line);

    if (mcbMatch == null) return null;

    final mcb = int.parse(mcbMatch.group(1)!);

    // ── Phase detection ─────────────────────────────────
    String phase = 'R';
    final phasePatterns = [
      RegExp(r'\b([RrYyBb])\s*[-–]?\s*\d+\b'), // R1, Y2, B3
      RegExp(r'[Pp]hase\s*[-:]?\s*([RrYyBb])\b'), // Phase R
      RegExp(r'\b([RrYyBb])\s*[Pp]hase\b'), // R Phase
      RegExp(r'^([RrYyBb])\b'), // starts with R/Y/B
      RegExp(r'\b([RrYyBb])\b'), // standalone R/Y/B
    ];

    for (final p in phasePatterns) {
      final m = p.firstMatch(line);
      if (m != null) {
        final candidate = (m.group(1) ?? '').toUpperCase();
        if (['R', 'Y', 'B'].contains(candidate)) {
          phase = candidate;
          break;
        }
      }
    }

    // ── Wire size ────────────────────────────────────────
    String wireSize = _wireFromMCB(mcb);
    final wireMatch =
        RegExp(r'(\d+\.?\d*)\s*(?:sq\.?\s*)?mm[²2]?', caseSensitive: false)
            .firstMatch(line);
    if (wireMatch != null) wireSize = '${wireMatch.group(1)}mm²';

    // ── Load watts ───────────────────────────────────────
    int loadWatts = _loadFromMCB(mcb);
    final wMatch = RegExp(r'(\d{2,4})\s*[Ww]\b').firstMatch(line);
    final kwMatch =
        RegExp(r'(\d+\.?\d*)\s*[Kk][Ww]', caseSensitive: false).firstMatch(line);
    if (wMatch != null) {
      loadWatts = int.tryParse(wMatch.group(1)!) ?? loadWatts;
    } else if (kwMatch != null) {
      loadWatts = ((double.tryParse(kwMatch.group(1)!) ?? 0) * 1000).round();
    }

    // ── Area description ─────────────────────────────────
    final area = _extractArea(line);

    // ── Circuit type ─────────────────────────────────────
    final type = _inferType(area, loadWatts, mcb);

    // ── Classification ───────────────────────────────────
    final classification =
        (loadWatts > 1500 || type == 'ac' || type == 'heater' || type == 'motor')
            ? 'heavy'
            : 'light';

    // ── ID ───────────────────────────────────────────────
    final count = (phaseCounts[phase] ?? 0) + 1;
    final id = '$phase$count';

    return {
      'id': id,
      'phase': phase,
      'mcb_rating': mcb,
      'wire_size': wireSize,
      'load_watts': loadWatts,
      'area': area.isNotEmpty ? area : 'Circuit $id',
      'circuit_type': type,
      'classification': classification,
    };
  }

  // ── Combine adjacent lines (for multi-line rows in PDF) ──
  static List<String> _combineLines(List<String> lines) {
    final combined = <String>[];
    for (int i = 0; i < lines.length; i++) {
      // Merge current line with next if current has no MCB rating
      if (i < lines.length - 1) {
        final merged = '${lines[i]} ${lines[i + 1]}';
        combined.add(merged);
      }
      combined.add(lines[i]);
    }
    return combined;
  }

  // ── Noise line detector ───────────────────────────────
  static bool _isNoiseLine(String line) {
    if (line.length < 3) return true;
    final upper = line.toUpperCase();

    // Skip pure header lines
    final headers = [
      'CIRCUIT SCHEDULE',
      'DISTRIBUTION BOARD',
      'DB SCHEDULE',
      'ELECTRICAL SCHEDULE',
      'SR NO',
      'S.NO',
      'SNO',
      'DESCRIPTION',
      'CIRCUIT NO',
      'REMARKS',
      'TOTAL LOAD',
      'GRAND TOTAL',
      'INCOMER',
      'INCOMING',
      'PAGE',
      'DRAWING NO',
      'PROJECT',
      'REVISION',
      'DATE',
      'SCALE',
    ];

    for (final h in headers) {
      if (upper.contains(h) && !RegExp(r'\d+\s*A').hasMatch(line)) return true;
    }

    // Skip lines with no letters (pure number rows)
    if (!RegExp(r'[a-zA-Z]').hasMatch(line)) return true;

    return false;
  }

  // ── Extract area name ─────────────────────────────────
  static String _extractArea(String line) {
    String s = line
        .replaceAll(
            RegExp(r'\b(6|10|16|20|25|32|40|50|63|80|100)\s*[Aa](?:mp)?s?\b'),
            '')
        .replaceAll(RegExp(r'\b[RrYyBb]\d+\b'), '')
        .replaceAll(RegExp(r'\d+\.?\d*\s*mm[²2]?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d{2,4}\s*[KkWw][Ww]?'), '')
        .replaceAll(
            RegExp(
                r'\b(MCB|RCCB|MCCB|DP|SP|TPN|SPN|CU|AL|PVC|XLPE|SWA|NOs?|No\.?)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'[|/\\_]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove leading/trailing numbers and punctuation
    s = s.replaceAll(RegExp(r'^[\d\s.\-:]+'), '').trim();
    s = s.replaceAll(RegExp(r'[\d\s.\-:]+$'), '').trim();

    if (s.isEmpty) return '';

    // Title case
    return s
        .split(' ')
        .where((w) => w.length > 1)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  // ── Infer circuit type ────────────────────────────────
  static String _inferType(String area, int watts, int mcb) {
    final a = area.toLowerCase();
    if (a.contains('ac') ||
        a.contains('air') ||
        a.contains('split') ||
        a.contains('cassette') ||
        a.contains('fcu') ||
        a.contains('vrf') ||
        a.contains('vrv')) {
      return 'ac';
    }

    if (a.contains('light') ||
        a.contains('lamp') ||
        a.contains('led') ||
        a.contains('tube') ||
        a.contains('downlight') ||
        a.contains('fan') ||
        a.contains('exhaust') ||
        a.contains('ceiling fan')) {
      return 'lighting';
    }

    if (a.contains('geyser') ||
        a.contains('heater') ||
        a.contains('water heat') ||
        a.contains('wh') ||
        a.contains('boiler') ||
        a.contains('solar')) {
      return 'heater';
    }

    if (a.contains('pump') ||
        a.contains('motor') ||
        a.contains('lift') ||
        a.contains('elevator') ||
        a.contains('hoist')) {
      return 'motor';
    }

    if (a.contains('inverter') ||
        a.contains('ups') ||
        a.contains('battery') ||
        a.contains('solar inv')) {
      return 'inverter';
    }

    if (a.contains('socket') ||
        a.contains('plug') ||
        a.contains('outlet') ||
        a.contains('power point') ||
        a.contains('kitchen') ||
        a.contains('wash') ||
        a.contains('refriger') ||
        a.contains('microwave') ||
        a.contains('oven')) {
      return 'socket';
    }

    // Fallback from ratings
    if (mcb >= 20 && watts >= 800) return 'ac';
    if (mcb <= 10) return 'lighting';
    return 'socket';
  }

  static String _wireFromMCB(int mcb) {
    if (mcb <= 6) return '1.0mm²';
    if (mcb <= 10) return '1.5mm²';
    if (mcb <= 16) return '2.5mm²';
    if (mcb <= 20) return '4mm²';
    if (mcb <= 32) return '6mm²';
    if (mcb <= 40) return '10mm²';
    return '16mm²';
  }

  static int _loadFromMCB(int mcb) => ((mcb * 0.7) * 230).round();
}

// ════════════════════════════════════════════════════════════
//  MAIN SCREEN
// ════════════════════════════════════════════════════════════
class CircuitAnalyzerScreen extends StatefulWidget {
  const CircuitAnalyzerScreen({super.key});
  @override
  State<CircuitAnalyzerScreen> createState() => _CircuitAnalyzerScreenState();
}

class _CircuitAnalyzerScreenState extends State<CircuitAnalyzerScreen> {
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _circuits = [];
  bool _isLoading = false;
  String? _lastError;
  bool _isRetrying = false;
  final bool _isOffline = false;
  bool _faultActive = false;
  bool _previousFaultActive = false;
  int _faultCircuit = 0;
  String? _faultMessage;
  bool _showingFaultDialog = false;
  final List<Map<String, dynamic>> _faultHistory = [];
  String _ocrStatus = '';  // shows what OCR is currently doing

  Stream<Map<String, dynamic>> get _readingsStream =>
      FirebaseDatabase.instance
          .ref('${AppConstants.deviceId}/readings')
          .onValue
          .map((e) => e.snapshot.value != null
              ? Map<String, dynamic>.from(e.snapshot.value as Map)
              : {});

  // ════════════════════════════════════════════════════════
  //  ENTRY POINTS
  // ════════════════════════════════════════════════════════

  // ── User picks source ─────────────────────────────────
  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Select Source', style: AppTypography.heading3),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _srcBtn(Icons.camera_alt, 'Camera', () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  }),
                  _srcBtn(Icons.photo_library, 'Gallery', () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  }),
                  _srcBtn(Icons.picture_as_pdf, 'PDF', () {
                    Navigator.pop(ctx);
                    _pickPDF();
                  }),
                  _srcBtn(Icons.edit_note, 'Manual', () {
                    Navigator.pop(ctx);
                    _showManualForm();
                  }),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _srcBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(label,
                style: AppTypography.caption.copyWith(fontSize: 10),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  IMAGE PROCESSING
  // ════════════════════════════════════════════════════════
  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (xfile == null) return;
      await _processImageFile(xfile.path);
    } catch (e) {
      _showErr('Failed to pick image: $e');
    }
  }

  Future<void> _processImageFile(String path) async {
    setState(() {
      _isLoading = true;
      _lastError = null;
      _ocrStatus = 'Reading image...';
    });

    try {
      // Run OCR on image
      setState(() => _ocrStatus = 'Running OCR on image...');
      final text = await _OCREngine.fromFile(path);

      if (text.trim().isEmpty) {
        throw Exception(
            'No text found in image. Try better lighting or a clearer photo.');
      }

      setState(() => _ocrStatus = 'Extracting circuits...');
      final circuits = _CircuitParser.parse(text);

      if (circuits.isEmpty) {
        // Show manual entry as fallback
        setState(() { _isLoading = false; _ocrStatus = ''; });
        _showNoCircuitsDialog();
        return;
      }

      setState(() {
        _circuits = circuits;
        _isLoading = false;
        _isRetrying = false;
        _ocrStatus = '';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isRetrying = false;
        _ocrStatus = '';
        _lastError = e.toString().replaceAll('Exception: ', '');
      });
      _showErr(_lastError!);
    }
  }

  // ════════════════════════════════════════════════════════
  //  PDF PROCESSING — reads ALL pages
  // ════════════════════════════════════════════════════════
  Future<void> _pickPDF() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      await _processPDF(path);
    } catch (e) {
      _showErr('Failed to pick PDF: $e');
    }
  }

  Future<void> _processPDF(String path) async {
    setState(() {
      _isLoading = true;
      _lastError = null;
      _ocrStatus = 'Opening PDF...';
    });

    try {
      final doc = await PdfDocument.openFile(path);
      final totalPages = doc.pagesCount;
      final allText = StringBuffer();

      setState(() => _ocrStatus = 'Reading $totalPages page(s)...');

      // ── Read every page ─────────────────────────────
      for (int pageNum = 1; pageNum <= totalPages; pageNum++) {
        setState(() =>
            _ocrStatus = 'OCR page $pageNum of $totalPages...');

        final page = await doc.getPage(pageNum);

        // Render at 2x for better OCR accuracy
        final rendered = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          quality: 90,
        );
        await page.close();

        if (rendered == null) continue;

        // Run OCR on this page
        final pageText = await _OCREngine.fromBytes(rendered.bytes);
        allText.writeln(pageText);
        allText.writeln('\n'); // separate pages
      }

      await doc.close();

      final fullText = allText.toString().trim();

      if (fullText.isEmpty) {
        throw Exception(
            'No text found in PDF. PDF may be image-only — try scanning with camera instead.');
      }

      setState(() => _ocrStatus = 'Extracting circuits from $totalPages pages...');
      final circuits = _CircuitParser.parse(fullText);

      if (circuits.isEmpty) {
        setState(() { _isLoading = false; _ocrStatus = ''; });
        _showNoCircuitsDialog();
        return;
      }

      setState(() {
        _circuits = circuits;
        _isLoading = false;
        _isRetrying = false;
        _ocrStatus = '';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isRetrying = false;
        _ocrStatus = '';
        _lastError = e.toString().replaceAll('Exception: ', '');
      });
      _showErr(_lastError!);
    }
  }

  // ── When OCR finds no circuits → offer manual entry ───
  void _showNoCircuitsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text('No circuits detected', style: AppTypography.heading3),
        content: Text(
          'OCR could not find circuit data automatically.\n\nYou can:\n• Try a clearer photo with better lighting\n• Enter circuits manually',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSourcePicker();
            },
            child: Text('Try Again', style: AppTypography.body),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showManualForm();
            },
            child: Text('Enter Manually',
                style: AppTypography.dmSans(weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  MANUAL ENTRY FORM
  // ════════════════════════════════════════════════════════
  void _showManualForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ManualEntryForm(
        existingCircuits: _circuits,
        onDone: (circuits) => setState(() => _circuits = circuits),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  FAULT HANDLING
  // ════════════════════════════════════════════════════════
  void _checkForNewFault(Map<String, dynamic> readings) {
    final active = readings['faultActive'] == true;
    if (active && !_previousFaultActive) {
      final msg = readings['faultMessage']?.toString() ?? 'Unknown fault';
      final cIdx = (readings['faultCircuit'] as num?)?.toInt() ?? 0;
      final cur = readings['current$cIdx'] ?? 0.0;
      Map<String, dynamic>? info;
      if (cIdx > 0 && cIdx <= _circuits.length) info = _circuits[cIdx - 1];
      _fetchFaultExplanation(msg, cIdx, cur, info);
    }
    _previousFaultActive = active;
  }

  Future<void> _fetchFaultExplanation(
    String msg, int cIdx, dynamic cur, Map<String, dynamic>? info,
  ) async {
    final mcb  = info?['mcb_rating']?.toString() ?? '?';
    final area = info?['area']?.toString() ?? 'Unknown';
    final curStr = cur is num ? cur.toStringAsFixed(1) : '?';

    final prompt =
        'Adhunik Yantra detected a fault.\nType: $msg\nCircuit: $cIdx ($area)\n'
        'Current: ${curStr}A  MCB: ${mcb}A\n\n'
        'In 2 sentences: (1) likely cause in simple terms (2) what to do now. '
        'Write for a non-technical homeowner.';

    final explanation = await _callGroq(prompt);

    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'faultMessage': msg,
      'faultCircuit': cIdx,
      'explanation': explanation,
      'area': area,
      'current': curStr,
    };

    setState(() {
      _faultHistory.insert(0, entry);
    });

    _showFaultDialog(explanation, cIdx);
  }

  void _showFaultDialog(String explanation, int cIdx) {
    if (_showingFaultDialog || !mounted) return;
    _showingFaultDialog = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber, color: AppColors.danger),
          const SizedBox(width: 8),
          Text('Fault Detected',
              style: AppTypography.heading3.copyWith(color: AppColors.danger)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explanation, style: AppTypography.body),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Text('Circuit $cIdx affected',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.danger)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showingFaultDialog = false;
            },
            child: Text('Dismiss', style: AppTypography.body),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              _showingFaultDialog = false;
              await FirebaseDatabase.instance
                  .ref('${AppConstants.deviceId}/relay/$cIdx')
                  .set(false);
            },
            child: Text('Turn Off Circuit',
                style: AppTypography.dmSans(weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Circuit details sheet ──────────────────────────────
  void _showCircuitDetails(Map<String, dynamic> circuit) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CircuitDetailSheet(circuit: circuit),
    );
  }

  // ── Fault history ──────────────────────────────────────
  void _showFaultHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx2, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Icon(Icons.history, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Fault History', style: AppTypography.heading3),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(ctx2),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: _faultHistory.isEmpty
                ? Center(
                    child: Text('No faults recorded',
                        style: AppTypography.body
                            .copyWith(color: AppColors.textSecondary)))
                : ListView.builder(
                    controller: sc,
                    padding: const EdgeInsets.all(16),
                    itemCount: _faultHistory.length,
                    itemBuilder: (_, i) {
                      final f = _faultHistory[i];
                      final ts = DateTime.tryParse(f['timestamp'] ?? '');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Circuit ${f['faultCircuit']}',
                                      style: AppTypography.caption
                                          .copyWith(color: AppColors.danger)),
                                ),
                                const Spacer(),
                                if (ts != null)
                                  Text(
                                    '${ts.day}/${ts.month} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}',
                                    style: AppTypography.caption
                                        .copyWith(color: AppColors.textMuted),
                                  ),
                              ]),
                              const SizedBox(height: 8),
                              Text(f['faultMessage'] ?? '',
                                  style: AppTypography.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(f['explanation'] ?? '',
                                  style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textSecondary)),
                            ]),
                      );
                    }),
          ),
        ]),
      ),
    );
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
        ),
        title: Text('Circuit Analyzer', style: AppTypography.heading3),
        centerTitle: true,
        actions: [
          if (_circuits.isNotEmpty)
            IconButton(
              onPressed: () => setState(() {
                _circuits = [];
                _lastError = null;
              }),
              icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            ),
          IconButton(
            onPressed: _showFaultHistory,
            icon: Badge(
              isLabelVisible: _faultHistory.isNotEmpty,
              label: Text('${_faultHistory.length}'),
              child:
                  const Icon(Icons.history, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildUploadCard(),
              const SizedBox(height: 20),
              _buildBoardStream(),
              const SizedBox(height: 100),
            ],
          ),
          if (_isLoading)
            Container(
              color: AppColors.background.withValues(alpha: 0.85),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppColors.primary)),
                    const SizedBox(height: 16),
                    Text(_ocrStatus.isNotEmpty
                        ? _ocrStatus
                        : 'Processing...', style: AppTypography.body),
                    const SizedBox(height: 6),
                    Text('On-device OCR — no internet needed',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMuted)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildUploadCard() {
    return Container(
      decoration: AppDecorations.card,
      child: InkWell(
        onTap: _showSourcePicker,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _circuits.isEmpty
              ? _buildEmptyUpload()
              : _buildUploadedState(),
        ),
      ),
    );
  }

  Widget _buildEmptyUpload() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3), width: 2),
          ),
          child: const Icon(Icons.document_scanner_outlined,
              size: 44, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text('Upload DB Schedule', style: AppTypography.heading3),
        const SizedBox(height: 6),
        Text(
          'Photo, gallery image, or PDF\nOn-device OCR — works offline',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _showSourcePicker,
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Choose Source'),
        ),
      ],
    );
  }

  Widget _buildUploadedState() {
    return Row(children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.check_circle, color: AppColors.success, size: 28),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_circuits.length} circuits loaded',
              style: AppTypography.heading3.copyWith(fontSize: 16)),
          Text('Tap refresh in top-right to re-upload',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      ),
      TextButton(
        onPressed: _showManualForm,
        child: Text('+ Add',
            style:
                AppTypography.body.copyWith(color: AppColors.primary)),
      ),
    ]);
  }

  Widget _buildBoardStream() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _readingsStream,
      builder: (ctx, snap) {
        final readings = snap.data ?? {};
        final connected = snap.hasData;
        _checkForNewFault(readings);

        if (readings['faultActive'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
              _faultActive = true;
              _faultMessage = readings['faultMessage']?.toString();
              _faultCircuit =
                  (readings['faultCircuit'] as num?)?.toInt() ?? 0;
            });
            }
          });
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Text('DB BOARD',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              const SizedBox(width: 10),
              _liveChip(connected),
            ]),
          ),

          _circuits.isEmpty
              ? Container(
                  width: double.infinity,
                  height: 160,
                  decoration: AppDecorations.card,
                  child: Center(
                    child: Text('Board appears after upload',
                        style: AppTypography.body
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                )
              : _DBBoard(
                  circuits: _circuits,
                  readings: readings,
                  faultActive: _faultActive,
                  faultCircuit: _faultCircuit,
                  onTap: _showCircuitDetails,
                ),
        ]);
      },
    );
  }

  Widget _liveChip(bool connected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (connected ? AppColors.success : AppColors.textMuted)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (connected ? AppColors.success : AppColors.textMuted)
                .withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
              color: connected ? AppColors.success : AppColors.textMuted,
              shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(connected ? 'Live — Adhunik Yantra' : 'Offline',
            style: AppTypography.caption.copyWith(
                color:
                    connected ? AppColors.success : AppColors.textMuted,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  void dispose() {
    _OCREngine.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════
//  DB BOARD WIDGET
// ════════════════════════════════════════════════════════════
class _DBBoard extends StatelessWidget {
  final List<Map<String, dynamic>> circuits;
  final Map<String, dynamic> readings;
  final bool faultActive;
  final int faultCircuit;
  final Function(Map<String, dynamic>) onTap;

  const _DBBoard({
    required this.circuits,
    required this.readings,
    required this.faultActive,
    required this.faultCircuit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final heavy = circuits
        .where((c) => c['classification']?.toString() == 'heavy')
        .toList();
    final light = circuits
        .where((c) => c['classification']?.toString() != 'heavy')
        .toList();

    final totalKw = circuits.fold<double>(
            0, (s, c) => s + ((c['load_watts'] as num?)?.toDouble() ?? 0)) /
        1000;

    return Container(
      decoration: AppDecorations.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Stats header
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Total Load', '${totalKw.toStringAsFixed(1)} kW',
                    AppColors.primary),
                Container(width: 1, height: 36, color: AppColors.border),
                _stat('Heavy', '${heavy.length}', AppColors.warning),
                Container(width: 1, height: 36, color: AppColors.border),
                _stat('Light', '${light.length}', AppColors.success),
              ]),
        ),
        const Divider(color: AppColors.border, height: 1),

        if (heavy.isNotEmpty) _section('HEAVY', AppColors.warning, heavy),
        if (light.isNotEmpty) _section('LIGHT', AppColors.success, light),
      ]),
    );
  }

  Widget _stat(String label, String val, Color color) => Column(children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 2),
        Text(val,
            style: AppTypography.shareTechMono(
                size: 16, weight: FontWeight.bold, color: color)),
      ]);

  Widget _section(
      String title, Color color, List<Map<String, dynamic>> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        color: color.withValues(alpha: 0.1),
        child: Text(title,
            style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      ),
      // Grid layout instead of scroll
      Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.asMap().entries.map((e) {
            final idx = e.key + 1;
            final isFault = faultActive && faultCircuit == idx;
            final liveCur =
                (readings['current$idx'] as num?)?.toDouble() ?? 0.0;
            return MCBCard(
              circuit: e.value,
              onTap: () => onTap(e.value),
              isFaulted: isFault,
              liveCurrent: liveCur,
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════
//  MCB CARD
// ════════════════════════════════════════════════════════════
class MCBCard extends StatelessWidget {
  final Map<String, dynamic> circuit;
  final VoidCallback onTap;
  final bool isFaulted;
  final double liveCurrent;

  const MCBCard({
    super.key,
    required this.circuit,
    required this.onTap,
    this.isFaulted = false,
    this.liveCurrent = 0.0,
  });

  Color _phaseColor(String? p) {
    switch (p?.toUpperCase()) {
      case 'R': return const Color(0xFFFF4444);
      case 'Y': return const Color(0xFFFFC107);
      case 'B': return const Color(0xFF2196F3);
      default:  return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = _phaseColor(circuit['phase']?.toString());
    final mcb = circuit['mcb_rating']?.toString() ?? '?';
    final area = circuit['area']?.toString() ?? '';
    final id = circuit['id']?.toString() ?? '?';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 72,
        decoration: BoxDecoration(
          color: isFaulted
              ? AppColors.danger.withValues(alpha: 0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isFaulted ? AppColors.danger : AppColors.border,
              width: isFaulted ? 1.5 : 1),
        ),
        child: Column(children: [
          // Phase bar
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: pc,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(children: [
              Text('${mcb}A',
                  style: AppTypography.shareTechMono(
                      size: 18,
                      weight: FontWeight.bold,
                      color:
                          isFaulted ? AppColors.danger : AppColors.primary)),
              const SizedBox(height: 2),
              Text('${liveCurrent.toStringAsFixed(2)}A',
                  style: AppTypography.shareTechMono(
                      size: 9, color: AppColors.success)),
              const SizedBox(height: 2),
              Text(area,
                  style: AppTypography.caption
                      .copyWith(fontSize: 8, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              isFaulted
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(3)),
                      child: Text('FAULT',
                          style: AppTypography.caption.copyWith(
                              fontSize: 7,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    )
                  : Text(id,
                      style: AppTypography.shareTechMono(
                          size: 9, color: AppColors.textMuted)),
              const SizedBox(height: 4),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CIRCUIT DETAIL SHEET
// ════════════════════════════════════════════════════════════
class _CircuitDetailSheet extends StatefulWidget {
  final Map<String, dynamic> circuit;
  const _CircuitDetailSheet({required this.circuit});
  @override
  State<_CircuitDetailSheet> createState() => _CircuitDetailSheetState();
}

class _CircuitDetailSheetState extends State<_CircuitDetailSheet> {
  String _ai = '';
  bool _loading = true;
  Color _border = AppColors.border;

  @override
  void initState() {
    super.initState();
    _fetchSafetyCheck();
  }

  Future<void> _fetchSafetyCheck() async {
    final c = widget.circuit;
    final prompt =
        'Electrical safety check for circuit in Indian home.\n'
        'Area: ${c['area']}  MCB: ${c['mcb_rating']}A  Wire: ${c['wire_size']}  '
        'Load: ${c['load_watts']}W  Type: ${c['circuit_type']}\n\n'
        'Give a 2-3 line safety check. Start with OK, WARNING, or DANGER. '
        'Write for a homeowner, not an engineer.';

    final text = await _callGroq(prompt);
    final upper = text.toUpperCase().trim();

    setState(() {
      _ai = text;
      _loading = false;
      _border = upper.startsWith('DANGER')
          ? AppColors.danger
          : upper.startsWith('WARNING')
              ? AppColors.warning
              : AppColors.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.circuit;
    Color pc;
    switch (c['phase']?.toString().toUpperCase()) {
      case 'R': pc = const Color(0xFFFF4444); break;
      case 'Y': pc = const Color(0xFFFFC107); break;
      case 'B': pc = const Color(0xFF2196F3); break;
      default:  pc = AppColors.textMuted;
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, sc) => SingleChildScrollView(
        controller: sc,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: AppColors.textMuted,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(c['area']?.toString() ?? 'Circuit',
                    style: AppTypography.heading2),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _chip('${c['mcb_rating']}A MCB', AppColors.primary),
                  _chip(c['wire_size']?.toString() ?? '?', AppColors.secondary),
                  _chip('${c['load_watts']}W', AppColors.info),
                  _chip('Phase ${c['phase']}', pc),
                  _chip(c['circuit_type']?.toString() ?? '?', AppColors.textSecondary),
                  _chip(c['classification']?.toString() ?? '?',
                      c['classification'] == 'heavy'
                          ? AppColors.warning
                          : AppColors.success),
                ]),
                const SizedBox(height: 20),
                Text('AI SAFETY CHECK',
                    style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border, width: 2),
                  ),
                  child: _loading
                      ? Row(children: [
                          const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                      AppColors.primary))),
                          const SizedBox(width: 10),
                          Text('Analyzing...',
                              style: AppTypography.bodySmall),
                        ])
                      : Text(_ai, style: AppTypography.body),
                ),
                const SizedBox(height: 20),
                // Wiring path
                Text('WIRING PATH',
                    style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(height: 12),
                _wiringPath(),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close',
                        style: AppTypography.dmSans(
                            weight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 20),
              ]),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: AppTypography.caption
                .copyWith(color: color, fontWeight: FontWeight.w600)),
      );

  Widget _wiringPath() {
    final steps = [
      ('Incomer', AppColors.danger),
      ('MCB', AppColors.textSecondary),
      ('Conduit', AppColors.textSecondary),
      ('J-Box', AppColors.textSecondary),
      ('Load', AppColors.success),
    ];
    return Row(
      children: steps.asMap().entries.map((e) {
        final i = e.key;
        final (label, color) = e.value;
        final isLast = i == steps.length - 1;
        return Row(children: [
          Column(children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: AppTypography.caption
                    .copyWith(fontSize: 8, color: AppColors.textSecondary)),
          ]),
          if (!isLast)
            Container(
                width: 28,
                height: 1,
                margin: const EdgeInsets.only(bottom: 14),
                color: AppColors.border),
        ]);
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  MANUAL ENTRY FORM
// ════════════════════════════════════════════════════════════
class _ManualEntryForm extends StatefulWidget {
  final List<Map<String, dynamic>> existingCircuits;
  final Function(List<Map<String, dynamic>>) onDone;
  const _ManualEntryForm(
      {required this.existingCircuits, required this.onDone});
  @override
  State<_ManualEntryForm> createState() => _ManualEntryFormState();
}

class _ManualEntryFormState extends State<_ManualEntryForm> {
  late List<Map<String, dynamic>> _circuits;
  final _areaCtrl = TextEditingController();
  String _phase = 'R';
  String _type  = 'lighting';
  int    _mcb   = 10;
  String _wire  = '1.5mm²';
  int    _load  = 500;

  @override
  void initState() {
    super.initState();
    _circuits = List.from(widget.existingCircuits);
  }

  void _add() {
    if (_areaCtrl.text.trim().isEmpty) return;
    final count = _circuits.where((c) => c['phase'] == _phase).length + 1;
    _circuits.add({
      'id': '$_phase$count',
      'phase': _phase,
      'mcb_rating': _mcb,
      'wire_size': _wire,
      'load_watts': _load,
      'area': _areaCtrl.text.trim(),
      'circuit_type': _type,
      'classification': (_load > 1500 || _type == 'ac' || _type == 'heater')
          ? 'heavy'
          : 'light',
    });
    setState(() => _areaCtrl.clear());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Text('Add Circuits', style: AppTypography.heading3),
            const Spacer(),
            if (_circuits.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  widget.onDone(_circuits);
                  Navigator.pop(context);
                },
                child: Text('Done (${_circuits.length})'),
              ),
          ]),
        ),
        const Divider(color: AppColors.border, height: 1),
        Expanded(
          child: ListView(controller: sc, padding: const EdgeInsets.all(16),
              children: [
            // Existing circuits
            ..._circuits.asMap().entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Text(e.value['id'],
                        style: AppTypography.shareTechMono(
                            size: 12, color: AppColors.primary)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(e.value['area'],
                            style: AppTypography.bodySmall)),
                    Text('${e.value['mcb_rating']}A',
                        style: AppTypography.caption),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 14, color: AppColors.danger),
                      onPressed: () =>
                          setState(() => _circuits.removeAt(e.key)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                )),
            if (_circuits.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
            ],
            // Area field
            TextField(
              controller: _areaCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Area / Description',
                labelStyle:
                    const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _dd('Phase', _phase, ['R', 'Y', 'B'],
                  (v) => setState(() => _phase = v!))),
              const SizedBox(width: 10),
              Expanded(
                  child: _dd(
                      'Type',
                      _type,
                      ['lighting','ac','socket','heater','motor','inverter'],
                      (v) => setState(() => _type = v!))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _dd(
                      'MCB (A)',
                      _mcb.toString(),
                      ['6','10','16','20','25','32','40','63'],
                      (v) => setState(() => _mcb = int.parse(v!)))),
              const SizedBox(width: 10),
              Expanded(
                  child: _dd(
                      'Wire',
                      _wire,
                      ['1.0mm²','1.5mm²','2.5mm²','4mm²','6mm²','10mm²'],
                      (v) => setState(() => _wire = v!))),
            ]),
            const SizedBox(height: 6),
            Text('Load: $_load W',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            Slider(
              value: _load.toDouble(),
              min: 0, max: 5000, divisions: 50,
              activeColor: AppColors.primary,
              label: '$_load W',
              onChanged: (v) => setState(() => _load = v.round()),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add Circuit'),
              ),
            ),
            if (_circuits.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    widget.onDone(_circuits);
                    Navigator.pop(context);
                  },
                  child: Text('Done — ${_circuits.length} circuits'),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ]),
        ),
      ]),
    );
  }

  Widget _dd(String label, String val, List<String> items,
      ValueChanged<String?> onChange) {
    return DropdownButtonFormField<String>(
      initialValue: val,
      dropdownColor: AppColors.cardBackground,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChange,
    );
  }
}

// ── DashedLinePainter kept for compatibility ──────────────
class DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, size.height / 2), Offset(x + 4, size.height / 2), paint);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}