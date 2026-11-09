import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-modal, dismissible guidance shown at the point where it is useful.
class ContextualTip extends StatefulWidget {
  final String id, message;
  const ContextualTip({super.key, required this.id, required this.message});
  @override
  State<ContextualTip> createState() => _ContextualTipState();
}

class _ContextualTipState extends State<ContextualTip> {
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _visible = !(prefs.getBool('tip_${widget.id}_v1') ?? false),
      );
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    await (await SharedPreferences.getInstance()).setBool(
      'tip_${widget.id}_v1',
      true,
    );
  }

  @override
  Widget build(BuildContext context) => !_visible
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.lightbulb_outline),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(widget.message),
                  ),
                ),
                IconButton(
                  tooltip: 'Ocultar consejo',
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        );
}
