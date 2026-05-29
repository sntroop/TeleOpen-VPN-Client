// lib/screens/add_subscription/parts.dart
//
// Вспомогательные виджеты экрана add_subscription_screen (вынесены из монолита).
part of '../add_subscription_screen.dart';

class _MethodButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;
  final IosThemeData t;
  final IosColors c;

  const _MethodButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.loading,
    required this.onTap,
    required this.t,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? c.blue.withValues(alpha: 0.12) : c.bgSecondary,
          borderRadius: IosShapes.continuous(IosShapes.radiusLarge),
          border: Border.all(
            color: selected ? c.blue.withValues(alpha: 0.6) : c.separator,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.blue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.blue),
                  )
                : Icon(icon, size: 18, color: c.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: t.textStyles.body
                        .copyWith(fontWeight: FontWeight.w600, color: c.textPrimary)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: t.textStyles.footnote.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          if (!loading)
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.chevron_right,
              size: 18,
              color: selected ? c.blue : c.textSecondary,
            ),
        ]),
      ),
    );
  }
}

// ── Баннер ошибки ─────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String error;
  final IosThemeData t;
  final IosColors c;

  const _ErrorBanner({required this.error, required this.t, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.red.withValues(alpha: 0.12),
        borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
      ),
      child: Row(children: [
        Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: c.red),
        const SizedBox(width: 8),
        Expanded(
            child: Text(error,
                style: t.textStyles.subheadline.copyWith(color: c.red))),
      ]),
    );
  }
}

// ── QR Scanner Page ───────────────────────────────────────────────────────────
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _detected = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканировать QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _ctrl.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _ctrl,
        onDetect: (capture) {
          if (_detected) return;
          final barcode = capture.barcodes.firstOrNull;
          final val = barcode?.rawValue;
          if (val != null && val.isNotEmpty) {
            _detected = true;
            Navigator.of(context).pop(val);
          }
        },
      ),
    );
  }
}
