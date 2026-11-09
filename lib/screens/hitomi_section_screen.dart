import 'dart:async';

import 'package:flutter/material.dart';

import '../services/hitomi_service.dart';
import '../utils/preferences.dart';
import 'online_browser_screen.dart';

/// Apartado propio de galerías +18. No comparte la fuente del catálogo normal.
class HitomiSectionScreen extends StatefulWidget {
  const HitomiSectionScreen({super.key});

  @override
  State<HitomiSectionScreen> createState() => _HitomiSectionScreenState();
}

class _HitomiSectionScreenState extends State<HitomiSectionScreen> {
  final GlobalKey<OnlineBrowserScreenState> _browserKey =
      GlobalKey<OnlineBrowserScreenState>();
  String _language = HitomiService.defaultLanguage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLanguage());
  }

  Future<void> _loadLanguage() async {
    final stored = await PreferencesService.getHitomiLanguage();
    final code = stored != null && HitomiService.languages.containsKey(stored)
        ? stored
        : HitomiService.defaultLanguage;
    HitomiService.useLanguage(code);
    if (!mounted) return;
    setState(() {
      _language = code;
      _ready = true;
    });
  }

  Future<void> _setLanguage(String code) async {
    HitomiService.useLanguage(code);
    setState(() => _language = code);
    await PreferencesService.setHitomiLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('+18 Hitomi.la'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Idioma del catálogo',
            initialValue: _language,
            onSelected: (value) => unawaited(_setLanguage(value)),
            itemBuilder: (context) => [
              for (final entry in HitomiService.languages.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(HitomiService.languageLabel(_language)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Recargar catálogo',
            onPressed: _ready
                ? () => _browserKey.currentState?.refresh()
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _ready
            ? OnlineBrowserScreen(
                key: _browserKey,
                lockedSourceId: 'hitomi',
                catalogKey: _language,
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
