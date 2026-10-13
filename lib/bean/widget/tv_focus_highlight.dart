import 'package:flutter/material.dart';

/// 给 TV（遥控器）界面里的可聚焦条目统一加「十英尺」焦点反馈。
///
/// 包裹层自身不参与焦点遍历（canRequestFocus/skipTraversal 均关闭），只监听
/// 内部可聚焦控件是否拿到焦点，因此嵌套控件（如卡片里的开关按钮）也能让整条
/// 目高亮，并且自动滚动到可视区域——避免遥控器选中看不见的条目。
///
/// 仅在非桌面端启用（桌面端有鼠标，不需要占用视觉的焦点框）。
class TvFocusHighlight extends StatefulWidget {
  const TvFocusHighlight({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.enabled = true,
    this.scale = 1.02,
    this.onFocusChange,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;
  final double scale;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvFocusHighlight> createState() => _TvFocusHighlightState();
}

class _TvFocusHighlightState extends State<TvFocusHighlight> {
  static const Duration _animationDuration = Duration(milliseconds: 140);
  bool _hasFocus = false;

  void _handleFocusChange(bool hasFocus) {
    if (_hasFocus == hasFocus) {
      return;
    }
    setState(() => _hasFocus = hasFocus);
    widget.onFocusChange?.call(hasFocus);
    if (!hasFocus) {
      return;
    }
    // 选中项滚入视野：长列表用遥控器往下走时不会跑出屏幕。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasFocus) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: _animationDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final colors = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: _handleFocusChange,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _hasFocus ? 1.0 : 0.0),
        duration: _animationDuration,
        curve: Curves.easeOutCubic,
        builder: (context, progress, child) => Transform.scale(
          scale: 1 + (widget.scale - 1) * progress,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: colors.primary.withOpacity(0.35 + 0.65 * progress),
                width: 3,
              ),
            ),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
