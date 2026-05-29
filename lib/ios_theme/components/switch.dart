// lib/ios_theme/components/switch.dart
// IosSwitch (тумблер с фирменной «полоской I» в ON). part of ios_theme.

part of '../../ios_theme.dart';

// ─── 5.2 IosSwitch (с белой полоской «I» в положении ON) ────────────────────

class IosSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const IosSwitch({super.key, required this.value, required this.onChanged});

  @override
  State<IosSwitch> createState() => _IosSwitchState();
}

class _IosSwitchState extends State<IosSwitch> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this, duration: IosDurations.fast, lowerBound: 0, upperBound: 1,
  );

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press.forward(),
      onTapUp:   (_) => _press.reverse(),
      onTapCancel: () => _press.reverse(),
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, _) {
          final pressed = _press.value;
          final thumbWidth = 28 + pressed * 6; // удлинение при нажатии — фирменная iOS-фишка
          return AnimatedContainer(
            duration: IosDurations.normal,
            curve: IosDurations.spring,
            width: 52, height: 32,
            decoration: BoxDecoration(
              color: widget.value ? c.green : (t.brightness == Brightness.dark ? c.fillSecondary : const Color(0xFFE9E9EA)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: IosDurations.normal,
                  curve: IosDurations.spring,
                  alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: IosDurations.fast,
                      width: thumbWidth, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4, offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 1, offset: const Offset(0, 3), spreadRadius: 0.5,
                          ),
                        ],
                      ),
                      // Маленькая «полоска I» внутри кружка как на скрине Figma
                      child: widget.value
                          ? Center(
                              child: Container(
                                width: 2.5, height: 11,
                                decoration: BoxDecoration(
                                  color: c.green.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
