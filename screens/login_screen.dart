import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ios_theme.dart';
import '../main.dart';
import '../models/market.dart';
import '../logic/market_api.dart';

const String kLoginBotUsername = 'TeleOpenLoginBot';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  String? _token;
  String? _error;
  bool _starting = false;
  Timer? _pollTimer;
  int _secondsLeft = 600; 
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      
      
      if (mounted) setState(() {});
      if (_token != null) _poll();
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final token = await MarketApi.authInit();
      if (!mounted) return;
      setState(() {
        _token = token;
        _secondsLeft = 600;
      });
      
      final url = Uri.parse('https://t.me/$kLoginBotUsername?start=$token');
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _error = 'Не удалось открыть Telegram');
      }
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось получить токен: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _countdown?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());

    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 600));
      if (_secondsLeft <= 0) {
        t.cancel();
        _pollTimer?.cancel();
        setState(() => _error = 'Ссылка для входа устарела. Попробуйте заново.');
      }
    });
  }

  Future<void> _poll() async {
    final token = _token;
    if (token == null) return;
    try {
      final result = await MarketApi.authPoll(token);
      if (result == null) return; 
      _pollTimer?.cancel();
      _countdown?.cancel();
      if (!mounted) return;
      
      MarketApi.setJwt(result.jwt);
      final appState = AppStateScope.of(context, listen: false);
      appState.setUser(result.user, jwt: result.jwt);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (e.status == 410 || e.status == 404) {
        _pollTimer?.cancel();
        _countdown?.cancel();
        if (mounted) {
          setState(() {
            _token = null;
            _error = 'Ссылка устарела. Нажмите «Войти через Telegram» ещё раз.';
          });
        }
      }
      
    } catch (_) {
      
    }
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = IosTheme.of(context);
    final c = t.colors;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SafeArea(
        child: Column(children: [
          
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(false),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(CupertinoIcons.chevron_back, size: 22, color: c.textPrimary),
                    Text(' Назад', style: t.textStyles.body.copyWith(color: c.textPrimary)),
                  ]),
                ),
              ),
              const Spacer(),
            ]),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),

                  
                  Container(
                    width: 96, height: 96,
                    margin: const EdgeInsets.only(bottom: 28),
                    decoration: BoxDecoration(
                      color: c.fill,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(CupertinoIcons.paperplane_fill, size: 44, color: c.textPrimary),
                  ),

                  Text('Войти через Telegram', style: t.textStyles.title1, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    _token == null
                        ? 'Откроется наш бот @$kLoginBotUsername. Нажмите «Start» - мы автоматически вернёмся в приложение.'
                        : 'Откройте Telegram и нажмите кнопку «Start» у бота. Ждём…',
                    style: t.textStyles.body.copyWith(color: c.textSecondary),
                    textAlign: TextAlign.center,
                  ),

                  if (_token != null) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        width: 22, height: 22,
                        child: CupertinoActivityIndicator(color: c.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'Истечёт через ${_formatTime(_secondsLeft)}',
                        style: t.textStyles.footnote.copyWith(color: c.textTertiary),
                      ),
                    ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.red.withValues(alpha: 0.12),
                        borderRadius: IosShapes.continuous(IosShapes.radiusMedium),
                      ),
                      child: Row(children: [
                        Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: c.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: t.textStyles.subheadline.copyWith(color: c.red))),
                      ]),
                    ),
                  ],

                  const Spacer(),

                  IosButton(
                    label: _token == null
                        ? 'Войти через Telegram'
                        : 'Открыть бот ещё раз',
                    style: IosButtonStyle.primary,
                    leadingIcon: CupertinoIcons.paperplane,
                    loading: _starting,
                    onPressed: _starting ? null : _start,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Telegram нужен только для подписи отзывов и публикации серверов в маркетплейс.',
                    style: t.textStyles.footnote.copyWith(color: c.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
