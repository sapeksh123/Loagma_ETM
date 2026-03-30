import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────
// Theme constants
// ─────────────────────────────────────────────
class _CalcTheme {
  static const dialogBg = Color(0xFFF0EAD8);
  static const btnBg = Color(0xFFF5F0E8);
  static const shadowDark = Color(0xFFD4C9B0);
  static const shadowLight = Color(0xFFFAF8F2);
  static const textPrimary = Color(0xFF5A4A2A);
  static const textSecondary = Color(0xFF8A7A5A);
  static const accent = Color(0xFFB8962E);
  static const accentDark = Color(0xFFA8882A);
}

// ─────────────────────────────────────────────
// Button config
// ─────────────────────────────────────────────
enum _BtnType { number, operator, equals, special }

class _BtnConfig {
  final String label;
  final String value;
  final _BtnType type;

  const _BtnConfig(this.label, this.value, this.type);
}

const _buttons = [
  [
    _BtnConfig('7', '7', _BtnType.number),
    _BtnConfig('8', '8', _BtnType.number),
    _BtnConfig('9', '9', _BtnType.number),
    _BtnConfig('÷', '/', _BtnType.operator),
  ],
  [
    _BtnConfig('4', '4', _BtnType.number),
    _BtnConfig('5', '5', _BtnType.number),
    _BtnConfig('6', '6', _BtnType.number),
    _BtnConfig('×', '*', _BtnType.operator),
  ],
  [
    _BtnConfig('1', '1', _BtnType.number),
    _BtnConfig('2', '2', _BtnType.number),
    _BtnConfig('3', '3', _BtnType.number),
    _BtnConfig('−', '-', _BtnType.operator),
  ],
  [
    _BtnConfig('0', '0', _BtnType.number),
    _BtnConfig('.', '.', _BtnType.number),
    _BtnConfig('=', '=', _BtnType.equals),
    _BtnConfig('+', '+', _BtnType.operator),
  ],
];

// ─────────────────────────────────────────────
// Main widget
// ─────────────────────────────────────────────
class CalculatorDialog extends StatefulWidget {
  const CalculatorDialog({super.key});

  static Future<double?> show(BuildContext context) {
    return showDialog<double>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CalculatorDialog(),
    );
  }

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  String _expression = '';
  String _result = '';
  bool _justCalculated = false;

  // ── Input handling ──────────────────────────

  void _onNumber(String value) {
    setState(() {
      if (_justCalculated) {
        _expression = '';
        _result = '';
        _justCalculated = false;
      }
      _expression += value;
    });
  }

  void _onOperator(String value) {
    setState(() {
      if (_justCalculated) {
        _expression = _result;
        _result = '';
        _justCalculated = false;
      }
      _expression += value;
    });
  }

  void _onEquals() {
    if (_expression.isEmpty) return;
    setState(() {
      try {
        final res = _evaluate(_expression);
        _result = _formatResult(res);
        _justCalculated = true;
      } catch (_) {
        _result = 'Error';
      }
    });
  }

  void _onClear() {
    setState(() {
      _expression = '';
      _result = '';
      _justCalculated = false;
    });
  }

  void _onBackspace() {
    setState(() {
      if (_justCalculated) {
        _onClear();
        return;
      }
      if (_expression.isNotEmpty) {
        _expression = _expression.substring(0, _expression.length - 1);
      }
    });
  }

  void _onCopy() {
    final value = _result.isNotEmpty && _result != 'Error' ? _result : _expression;
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        backgroundColor: _CalcTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  // ── Evaluation ──────────────────────────────

  double _evaluate(String exp) {
    final tokens = _tokenize(exp);
    return _evaluateTokens(tokens);
  }

  List<dynamic> _tokenize(String exp) {
    final tokens = <dynamic>[];
    String num = '';
    for (int i = 0; i < exp.length; i++) {
      final c = exp[i];
      if ('0123456789.'.contains(c)) {
        num += c;
      } else if ('+-*/'.contains(c)) {
        if (num.isNotEmpty) {
          tokens.add(double.parse(num));
          num = '';
        }
        tokens.add(c);
      }
    }
    if (num.isNotEmpty) tokens.add(double.parse(num));
    return tokens;
  }

  /// Respects operator precedence (* / before + -)
  double _evaluateTokens(List<dynamic> tokens) {
    final t = List<dynamic>.from(tokens);
    // First pass: * and /
    for (int i = 1; i < t.length; i += 2) {
      if (t[i] == '*' || t[i] == '/') {
        final val = t[i] == '*'
            ? (t[i - 1] as double) * (t[i + 1] as double)
            : (t[i - 1] as double) / (t[i + 1] as double);
        t.replaceRange(i - 1, i + 2, [val]);
        i -= 2;
      }
    }
    // Second pass: + and -
    double result = t[0] as double;
    for (int i = 1; i < t.length; i += 2) {
      final next = t[i + 1] as double;
      if (t[i] == '+') result += next;
      if (t[i] == '-') result -= next;
    }
    return result;
  }

  String _formatResult(double value) {
    if (!value.isFinite) return 'Error';
    // Remove trailing zeros for whole numbers
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return double.parse(value.toStringAsPrecision(10)).toString();
  }

  // ── Display expression ──────────────────────

  String get _displayExpression =>
      _expression.replaceAll('*', '×').replaceAll('/', '÷').replaceAll('-', '−');

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _CalcTheme.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildDisplay(),
            const SizedBox(height: 16),
            _buildGrid(),
            const SizedBox(height: 12),
            _buildBottomRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Calculator',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _CalcTheme.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
        _NeuButton(
          onTap: () => Navigator.of(context).pop(),
          type: _BtnType.special,
          size: 36,
          child: const Icon(Icons.close, size: 16, color: _CalcTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      constraints: const BoxConstraints(minHeight: 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _displayExpression,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _CalcTheme.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _result,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: _CalcTheme.accent,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return Column(
      children: _buttons.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: row.asMap().entries.map((entry) {
              final i = entry.key;
              final btn = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: _buildCalcButton(btn),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalcButton(_BtnConfig cfg) {
    return _NeuButton(
      onTap: () {
        switch (cfg.type) {
          case _BtnType.number:
            _onNumber(cfg.value);
            break;
          case _BtnType.operator:
            _onOperator(cfg.value);
            break;
          case _BtnType.equals:
            _onEquals();
            break;
          case _BtnType.special:
            break;
        }
      },
      type: cfg.type,
      child: Text(
        cfg.label,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: cfg.type == _BtnType.operator
              ? _CalcTheme.accent
              : cfg.type == _BtnType.equals
                  ? Colors.white
                  : _CalcTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildBottomRow() {
    return Row(
      children: [
        Expanded(
          child: _NeuButton(
            onTap: _onClear,
            type: _BtnType.special,
            child: const Text(
              'C',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _CalcTheme.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _NeuButton(
            onTap: _onBackspace,
            type: _BtnType.special,
            child: const Icon(Icons.backspace_outlined, size: 22, color: _CalcTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _NeuButton(
            onTap: _onCopy,
            type: _BtnType.special,
            child: const Text(
              'Copy',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _CalcTheme.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: SizedBox()),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Neumorphic button
// ─────────────────────────────────────────────
class _NeuButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final _BtnType type;
  final double size;

  const _NeuButton({
    required this.onTap,
    required this.child,
    required this.type,
    this.size = 60,
  });

  @override
  State<_NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<_NeuButton> {
  bool _pressed = false;

  BoxDecoration get _decoration {
    if (widget.type == _BtnType.equals) {
      return BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC8A830), _CalcTheme.accentDark],
        ),
        boxShadow: _pressed
            ? [
                const BoxShadow(
                  color: Color(0xFFD4C9B0),
                  offset: Offset(1, 1),
                  blurRadius: 4,
                ),
              ]
            : [
                const BoxShadow(
                  color: Color(0xFFD4C9B0),
                  offset: Offset(4, 4),
                  blurRadius: 10,
                ),
                const BoxShadow(
                  color: _CalcTheme.shadowLight,
                  offset: Offset(-2, -2),
                  blurRadius: 6,
                ),
              ],
      );
    }

    return BoxDecoration(
      shape: BoxShape.circle,
      color: _CalcTheme.btnBg,
      boxShadow: _pressed
          ? [
              const BoxShadow(
                color: Color(0xFFD4C9B0),
                offset: Offset(1, 1),
                blurRadius: 4,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.5),
                offset: const Offset(-1, -1),
                blurRadius: 3,
              ),
            ]
          : [
              const BoxShadow(
                color: Color(0xFFD4C9B0),
                offset: Offset(4, 4),
                blurRadius: 10,
              ),
              const BoxShadow(
                color: _CalcTheme.shadowLight,
                offset: Offset(-2, -2),
                blurRadius: 6,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.5),
                offset: const Offset(0, 1),
                blurRadius: 0,
              ),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.size,
        height: widget.size,
        decoration: _decoration,
        transform: _pressed
            ? (Matrix4.identity()..scale(0.96))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Center(child: widget.child),
      ),
    );
  }
}