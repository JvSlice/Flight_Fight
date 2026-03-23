import 'package:flutter/material.dart';

class TouchControls extends StatelessWidget {
  final bool visible;
  final VoidCallback onLeftDown;
  final VoidCallback onLeftUp;
  final VoidCallback onRightDown;
  final VoidCallback onRightUp;
  final VoidCallback onUpDown;
  final VoidCallback onUpUp;
  final VoidCallback onDownDown;
  final VoidCallback onDownUp;
  final VoidCallback onFire;

  const TouchControls({
    super.key,
    required this.visible,
    required this.onLeftDown,
    required this.onLeftUp,
    required this.onRightDown,
    required this.onRightUp,
    required this.onUpDown,
    required this.onUpUp,
    required this.onDownDown,
    required this.onDownUp,
    required this.onFire,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    children: [
                      _holdButton(
                        alignment: const Alignment(0, -1),
                        label: '▲',
                        onDown: onUpDown,
                        onUp: onUpUp,
                      ),
                      _holdButton(
                        alignment: const Alignment(-1, 0),
                        label: '◀',
                        onDown: onLeftDown,
                        onUp: onLeftUp,
                      ),
                      _holdButton(
                        alignment: const Alignment(1, 0),
                        label: '▶',
                        onDown: onRightDown,
                        onUp: onRightUp,
                      ),
                      _holdButton(
                        alignment: const Alignment(0, 1),
                        label: '▼',
                        onDown: onDownDown,
                        onUp: onDownUp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: onFire,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x33FFC857),
                      border: Border.all(
                        color: const Color(0xAAFFC857),
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'FIRE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _holdButton({
    required Alignment alignment,
    required String label,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return Align(
      alignment: alignment,
      child: Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onUp(),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x2288AAFF),
            border: Border.all(color: const Color(0x8888AAFF)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
