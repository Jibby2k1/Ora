import 'package:flutter/material.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark
        ? const [
            Color(0xFF0B0D12),
            Color(0xFF101521),
            Color(0xFF0B0F14),
          ]
        : const [
            Color(0xFFF6F9FF),
            Color(0xFFEAF1FB),
            Color(0xFFF3F6FC),
          ];
    final glowPrimary = isDark ? const Color(0xFF7AC4FF) : const Color(0xFF2563EB);
    final glowSecondary = isDark ? const Color(0xFFB6C2FF) : const Color(0xFF93B2FF);
    return Positioned.fill(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -80,
            child: _GlowBlob(
              color: glowPrimary.withOpacity(isDark ? 0.22 : 0.18),
              size: 260,
            ),
          ),
          Positioned(
            bottom: -140,
            left: -80,
            child: _GlowBlob(
              color: glowSecondary.withOpacity(isDark ? 0.16 : 0.12),
              size: 280,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}
