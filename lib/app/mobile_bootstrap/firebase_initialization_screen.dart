import 'package:flutter/material.dart';

class FirebaseInitializationScreen extends StatelessWidget {
  const FirebaseInitializationScreen({
    super.key,
    this.title = 'Setting up your workspace',
    this.subtitle = 'Loading company profile, permissions, and mobile UI…',
    this.status,
    this.error,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final String? status;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F4),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFD8DED4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.06),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF5F7F55), size: 30),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF0F140F),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error == null ? subtitle : 'We could not finish setup. Please check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5F675E),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (error == null) ...[
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF5F7F55)),
                    ),
                    if (status != null && status!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        status!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8B9288),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ] else ...[
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry setup'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5F7F55),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(148, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC85F55),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
