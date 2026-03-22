import 'package:flutter/material.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF06080D),
                  Color(0xFF0D1320),
                  Color(0xFF090C12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.22, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            top: -140,
            right: -90,
            child: _GlowBlob(
              color: const Color(0xFF8CE1FF).withValues(alpha: 0.28),
              size: 300,
            ),
          ),
          Positioned(
            top: 120,
            left: -110,
            child: _GlowBlob(
              color: const Color(0xFFD7DEFF).withValues(alpha: 0.16),
              size: 260,
            ),
          ),
          Positioned(
            bottom: -160,
            left: -80,
            child: _GlowBlob(
              color: const Color(0xFF7EF0D7).withValues(alpha: 0.14),
              size: 320,
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
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
