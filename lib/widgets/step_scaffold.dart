import 'package:flutter/material.dart';

import '../theme.dart';

/// The backbone of every wizard screen: app bar with back, big title + subtitle,
/// scrollable body, and a pinned bottom CTA above the safe area. Keeps all
/// screens visually identical.
class StepScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? bottom; // usually a PrimaryButton
  final Widget? secondary; // optional TextButton under the CTA
  final bool showBack;
  final List<Widget>? actions;

  const StepScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.bottom,
    this.secondary,
    this.showBack = true,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.headlineMedium),
                  if (subtitle != null) ...[Gap.hSm, Text(subtitle!, style: t.bodyLarge)],
                ],
              ),
            ),
            Gap.hLg,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: body,
              ),
            ),
            if (bottom != null || secondary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
                child: Column(
                  children: [
                    if (bottom != null) bottom!,
                    if (secondary != null) ...[Gap.hSm, secondary!],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
