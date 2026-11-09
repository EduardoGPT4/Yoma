import 'package:flutter/material.dart';

import '../utils/preferences.dart';

class OnboardingFlow {
  static Future<void> showIfNeeded(BuildContext context) async {
    final completed = await PreferencesService.getOnboardingCompleted();
    if (!context.mounted || completed) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const _OnboardingDialog();
      },
    );
  }
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.auto_stories_outlined,
      title: 'Tu próxima lectura',
      body:
          'Busca un manga en Inicio, guárdalo con el corazón y continúa desde Biblioteca. Puedes leer online o descargar para después.',
    ),
    _OnboardingPageData(
      icon: Icons.help_outline,
      title: 'A tu ritmo',
      body:
          'Encontrarás consejos al usar cada apartado. Los ajustes del lector están dentro del capítulo y puedes conectar MyAnimeList desde Perfil.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await PreferencesService.setOnboardingCompleted(true);
    await PreferencesService.setWelcomeNoticeSeen(true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _next() async {
    if (_page >= _pages.length - 1) {
      await _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      content: SizedBox(
        width: 360,
        height: MediaQuery.sizeOf(context).height.clamp(240.0, 520.0) * .6,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          page.icon,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: theme.colorScheme.onSurface.withAlpha(190),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) {
                final active = index == _page;
                return Container(
                  width: active ? 18 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha(50),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _finish, child: const Text('Saltar')),
        FilledButton(
          onPressed: _next,
          child: Text(_page >= _pages.length - 1 ? 'Empezar' : 'Siguiente'),
        ),
      ],
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
  });
}
