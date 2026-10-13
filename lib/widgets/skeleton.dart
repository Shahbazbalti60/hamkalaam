import 'package:flutter/material.dart';

/// A soft pulsing grey rounded box — the building block of loading
/// "skeletons" (placeholders that look like the content about to appear).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A list of pulsing placeholder cards, shown while a screen's data is
/// loading. Replaces a blank screen / lone spinner.
class SkeletonList extends StatefulWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 78,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _pulse =
      Tween<double>(begin: 0.45, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulse,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: widget.itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return Container(
            height: widget.itemHeight,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                const SkeletonBox(width: 46, height: 46, radius: 23),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 140, height: 12),
                      SizedBox(height: 8),
                      SkeletonBox(width: 200, height: 10),
                      SizedBox(height: 8),
                      SkeletonBox(width: 90, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
