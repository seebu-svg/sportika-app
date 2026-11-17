import 'package:flutter/material.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Keeps large squads and the keyboard usable on compact Android screens.
class FutsalSheet extends StatelessWidget {
  const FutsalSheet({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: AppSheet(title: title, child: child),
    ),
  );
}
