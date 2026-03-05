import 'package:flutter/material.dart';

import '../../core/splash_tokens.g.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, required this.showSlogan});

  final bool showSlogan;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with SingleTickerProviderStateMixin {
  static const Color backgroundColor = SplashTokens.backgroundColor;
  static const Color primaryColor = SplashTokens.brandColor;
  static const String _logoAsset = SplashTokens.logoAsset;
  static const String _sloganText = '让记录，自然流动';
  static const int _typewriterMsPerChar = 160;

  late final List<int> _sloganRunes = _sloganText.runes.toList();
  AnimationController? _typewriterController;

  @override
  void initState() {
    super.initState();
    if (widget.showSlogan) {
      _startTypewriter();
    }
  }

  @override
  void didUpdateWidget(StartupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSlogan && !oldWidget.showSlogan) {
      _startTypewriter();
    } else if (!widget.showSlogan && oldWidget.showSlogan) {
      _typewriterController?.dispose();
      _typewriterController = null;
    }
  }

  @override
  void dispose() {
    _typewriterController?.dispose();
    super.dispose();
  }

  void _startTypewriter() {
    _typewriterController?.dispose();
    final durationMs = _sloganRunes.length * _typewriterMsPerChar;
    _typewriterController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..addListener(() {
        if (!mounted) return;
        setState(() {});
      });
    _typewriterController?.forward();
  }

  String _currentSloganText() {
    if (!widget.showSlogan) return '';
    final controller = _typewriterController;
    if (controller == null) return _sloganText;
    final total = _sloganRunes.length;
    var count = (total * controller.value).floor();
    if (count < 0) count = 0;
    if (count > total) count = total;
    if (count == 0) return '';
    return String.fromCharCodes(_sloganRunes.sublist(0, count));
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortestSide / 375).clamp(0.85, 1.1).toDouble();
    final logoSize = 96 * scale;
    final sloganSize = 14 * scale;
    final memoFlowSize =
        (sloganSize - (2 * scale)).clamp(10.0, sloganSize);
    final sloganPadding = 48 * scale;
    final textGap = 6 * scale;

    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: logoSize,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox.square(
                  dimension: logoSize,
                  child: Image.asset(
                    _logoAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: sloganPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showSlogan)
                    Text(
                      _currentSloganText(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: primaryColor.withValues(alpha: 0.85),
                        fontSize: sloganSize,
                        letterSpacing: 1.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  SizedBox(height: widget.showSlogan ? textGap : 0),
                  Text(
                    'MemoFlow',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: memoFlowSize,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
