import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        'UniSend_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'UniSend logo',
      ),
    );
  }
}
