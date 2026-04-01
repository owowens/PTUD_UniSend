import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.radius = 44,
    this.iconSize = 44,
    this.icon = Icons.person,
  });

  final double radius;
  final double iconSize;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      child: Icon(icon, size: iconSize, color: colorScheme.onPrimaryContainer),
    );
  }
}
