import 'package:flutter/material.dart';

class TranslationAttribution extends StatelessWidget {
  const TranslationAttribution({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Traducción automática con Google Translate',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Traducido por ',
              style: TextStyle(color: Colors.black87, fontSize: 12),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/google_logo.png', width: 42, height: 16),
                const Flexible(
                  child: Text(
                    ' Translate',
                    style: TextStyle(color: Colors.black87, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
