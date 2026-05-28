import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ios_theme.dart';

Future<Color?> showColorPicker(BuildContext context, {required Color initial}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ColorPickerSheet(initial: initial),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  const _ColorPickerSheet({required this.initial});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;
  late double _alpha;
  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _alpha = widget.initial.alpha / 255.0;
    _hexCtrl = TextEditingController(text: _toHex(widget.initial));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _currentColor => _hsv.toColor().withOpacity(_alpha);

  String _toHex(Color c) {
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${h(c.alpha)}${h(c.red)}${h(c.green)}${h(c.blue)}';
  }

  void _updateFromHex(String text) {
    var s = text.trim().toUpperCase().replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return;
    final n = int.tryParse(s, radix: 16);
    if (n == null) return;
    final c = Color(n);
    setState(() {
      _hsv = HSVColor.fromColor(c);
      _alpha = c.alpha / 255.0;
    });
  }

  void _syncHex() {
    _hexCtrl.text = _toHex(_currentColor);
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: c.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36, height: 5,
                decoration: BoxDecoration(
                  color: c.fill,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text('Отмена',
                        style: t.textStyles.body.copyWith(color: c.red)),
                  ),
                  const Spacer(),
                  Text('Выбор цвета', style: t.textStyles.headline),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(_currentColor),
                    child: Text('Готово',
                        style: t.textStyles.body.copyWith(
                            color: c.blue, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),

              
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 56,
                decoration: BoxDecoration(
                  color: _currentColor,
                  borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
                  border: Border.all(color: c.separator, width: 0.5),
                ),
              ),
              const SizedBox(height: 16),

              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SaturationValueBox(
                  hsv: _hsv,
                  onChanged: (h) {
                    setState(() => _hsv = h);
                    _syncHex();
                  },
                ),
              ),
              const SizedBox(height: 16),

              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _HueSlider(
                  hue: _hsv.hue,
                  onChanged: (h) {
                    setState(() => _hsv = _hsv.withHue(h));
                    _syncHex();
                  },
                ),
              ),
              const SizedBox(height: 12),

              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _AlphaSlider(
                  baseColor: _hsv.toColor(),
                  alpha: _alpha,
                  onChanged: (a) {
                    setState(() => _alpha = a);
                    _syncHex();
                  },
                ),
              ),
              const SizedBox(height: 16),

              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('HEX', style: t.textStyles.subheadline.copyWith(color: c.textSecondary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _hexCtrl,
                      onSubmitted: _updateFromHex,
                      onChanged: (v) {
                        if (v.length == 6 || v.length == 8) _updateFromHex(v);
                      },
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                        LengthLimitingTextInputFormatter(9),
                      ],
                      textCapitalization: TextCapitalization.characters,
                      style: t.textStyles.body.copyWith(
                        fontFamily: 'monospace',
                        color: c.textPrimary,
                      ),
                      decoration: BoxDecoration(
                        color: c.fill,
                        borderRadius: BorderRadius.circular(IosShapes.radiusField),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaturationValueBox extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _SaturationValueBox({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.2,
      child: LayoutBuilder(builder: (_, box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _handle(d.localPosition, box.maxWidth, box.maxHeight),
          onPanUpdate: (d) => _handle(d.localPosition, box.maxWidth, box.maxHeight),
          onTapDown: (d) => _handle(d.localPosition, box.maxWidth, box.maxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(IosShapes.radiusMedium),
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _SVPainter(hue: hsv.hue, s: hsv.saturation, v: hsv.value),
            ),
          ),
        );
      }),
    );
  }

  void _handle(Offset p, double w, double h) {
    final s = (p.dx / w).clamp(0.0, 1.0);
    final v = (1 - p.dy / h).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }
}

class _SVPainter extends CustomPainter {
  final double hue, s, v;
  _SVPainter({required this.hue, required this.s, required this.v});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    
    final huePaint = Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(rect, huePaint);
    
    final whiteGrad = Paint()
      ..shader = LinearGradient(colors: [Colors.white, Colors.white.withOpacity(0)]).createShader(rect);
    canvas.drawRect(rect, whiteGrad);
    
    final blackGrad = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
      ).createShader(rect);
    canvas.drawRect(rect, blackGrad);

    
    final cx = s * size.width;
    final cy = (1 - v) * size.height;
    final ring = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final shadow = Paint()..color = Colors.black26..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawCircle(Offset(cx, cy), 10, shadow);
    canvas.drawCircle(Offset(cx, cy), 10, ring);
  }

  @override
  bool shouldRepaint(_SVPainter old) => old.hue != hue || old.s != s || old.v != v;
}

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(builder: (_, box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _h(d.localPosition.dx, box.maxWidth),
          onPanUpdate: (d) => _h(d.localPosition.dx, box.maxWidth),
          onTapDown: (d) => _h(d.localPosition.dx, box.maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              size: Size(box.maxWidth, 28),
              painter: _HuePainter(hue: hue),
            ),
          ),
        );
      }),
    );
  }

  void _h(double x, double w) => onChanged((x / w * 360).clamp(0.0, 360.0));
}

class _HuePainter extends CustomPainter {
  final double hue;
  _HuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(colors: [
      Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
      Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
    ]).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
    final cx = hue / 360 * size.width;
    final ring = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final shadow = Paint()..color = Colors.black26..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawCircle(Offset(cx, size.height / 2), 11, shadow);
    canvas.drawCircle(Offset(cx, size.height / 2), 11, ring);
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

class _AlphaSlider extends StatelessWidget {
  final Color baseColor;
  final double alpha;
  final ValueChanged<double> onChanged;
  const _AlphaSlider({required this.baseColor, required this.alpha, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(builder: (_, box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _h(d.localPosition.dx, box.maxWidth),
          onPanUpdate: (d) => _h(d.localPosition.dx, box.maxWidth),
          onTapDown: (d) => _h(d.localPosition.dx, box.maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              size: Size(box.maxWidth, 28),
              painter: _AlphaPainter(base: baseColor, a: alpha),
            ),
          ),
        );
      }),
    );
  }

  void _h(double x, double w) => onChanged((x / w).clamp(0.0, 1.0));
}

class _AlphaPainter extends CustomPainter {
  final Color base;
  final double a;
  _AlphaPainter({required this.base, required this.a});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    
    final checker = Paint()..color = const Color(0xFFE0E0E0);
    canvas.drawRect(rect, Paint()..color = Colors.white);
    const cell = 6.0;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), checker);
        }
      }
    }
    
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [
      base.withOpacity(0), base.withOpacity(1),
    ]).createShader(rect));
    final cx = a * size.width;
    final ring = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final shadow = Paint()..color = Colors.black26..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawCircle(Offset(cx, size.height / 2), 11, shadow);
    canvas.drawCircle(Offset(cx, size.height / 2), 11, ring);
  }

  @override
  bool shouldRepaint(_AlphaPainter old) => old.a != a || old.base != base;
}
