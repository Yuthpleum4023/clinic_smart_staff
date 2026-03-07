import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebugOnly extends StatelessWidget {
  final Widget child;
  const DebugOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return child;
  }
}