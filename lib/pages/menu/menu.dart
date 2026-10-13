import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/utils/constants.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  final _railKey = GlobalKey<_TvRailState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;

  /// 桌面端靠鼠标，不需要抢初始焦点；TV/手机横屏才给侧边栏 autofocus。
  bool get _needsRailAutofocus => switch (defaultTargetPlatform) {
        TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS =>
          false,
        _ => true,
      };

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }

    // TV 适配：焦点在内容区时，返回键先回到侧边栏（TV 逐级返回习惯），
    // 而不是直接退出应用；焦点已在侧边栏时才走切 tab / 退出确认逻辑。
    if (_needsRailAutofocus &&
        (_railKey.currentState?.requestRailFocus() ?? false)) {
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: OrientationBuilder(
          builder: (context, orientation) {
            return orientation == Orientation.portrait
                ? _bottomMenu(context, _selectedIndex)
                : _sideMenu(context, _selectedIndex);
          },
        ),
      ),
    );
  }

  Widget _outlet(BuildContext context, {BorderRadius? borderRadius}) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _bottomMenu(BuildContext context, int selectedIndex) {
    return Scaffold(
      body: _outlet(context),
      bottomNavigationBar: NavigationBar(
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.home),
            icon: Icon(Icons.home_outlined),
            label: '推荐',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.timeline),
            icon: Icon(Icons.timeline_outlined),
            label: '时间表',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.favorite),
            icon: Icon(Icons.favorite_outlined),
            label: '追番',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }

  Widget _sideMenu(BuildContext context, int selectedIndex) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Row(
        children: [
          EmbeddedNativeControlArea(
            // TV 适配：自管焦点的侧边栏。Flutter 的 NavigationRail 目标在
            // 电视遥控器下焦点不可控（启动焦点落在内容区、rail 永远选不了），
            // 改为索引驱动 + 按键自处理，上下移动、OK 激活、左右交给遍历。
            child: _TvRail(
              key: _railKey,
              selectedIndex: selectedIndex,
              needsAutofocus: _needsRailAutofocus,
              onSearch: () => context.pushNamed('/search/'),
              onDestination: _selectDestination,
            ),
          ),
          Expanded(child: _outlet(context, borderRadius: borderRadius)),
        ],
      ),
    );
  }
}

/// TV（遥控器）专用侧边栏：自管焦点，不依赖 Flutter 默认焦点遍历。
/// 上下移动高亮、OK 激活（搜索/切 tab）、右键进入内容区；
/// 从内容区返回侧边栏由 Shell 的返回键处理（逐级返回）。
class _TvRail extends StatefulWidget {
  const _TvRail({
    super.key,
    required this.selectedIndex,
    required this.needsAutofocus,
    required this.onSearch,
    required this.onDestination,
  });

  final int selectedIndex;
  final bool needsAutofocus;
  final VoidCallback onSearch;
  final ValueChanged<int> onDestination;

  @override
  State<_TvRail> createState() => _TvRailState();
}

class _TvRailState extends State<_TvRail> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TvRail');
  // 0 = 搜索，1..4 = tab；初始高亮落在当前选中的 tab 上。
  late int _focusIndex = widget.selectedIndex + 1;

  @override
  void initState() {
    super.initState();
    // 双保险：autofocus + post-frame 强制请求。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.needsAutofocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Shell 返回键用：焦点不在侧边栏时把焦点交回侧边栏并高亮当前 tab。
  /// 已在侧边栏（或未挂载）时返回 false，由调用方继续走原返回逻辑。
  bool requestRailFocus() {
    if (_focusNode.hasFocus) {
      return false;
    }
    setState(() => _focusIndex = widget.selectedIndex + 1);
    _focusNode.requestFocus();
    return true;
  }

  void _activate(int index) {
    if (index == 0) {
      widget.onSearch();
      return;
    }
    widget.onDestination(index - 1);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusIndex = (_focusIndex - 1).clamp(0, 4));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusIndex = (_focusIndex + 1).clamp(0, 4));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // 进入内容区：显式向右做一次方向遍历，焦点迁到内容区第一个可聚焦控件。
      final ctx = _focusNode.context;
      if (ctx != null) {
        Actions.invoke(
            ctx, const DirectionalFocusIntent(TraversalDirection.right));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (event is KeyDownEvent) {
        _activate(_focusIndex);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const tabs = <({IconData icon, IconData selectedIcon, String label})>[
      (icon: Icons.home_outlined, selectedIcon: Icons.home, label: '推荐'),
      (icon: Icons.timeline_outlined, selectedIcon: Icons.timeline, label: '时间表'),
      (icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: '追番'),
      (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '我的'),
    ];
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.needsAutofocus,
      onKeyEvent: _handleKey,
      child: SizedBox(
        width: 184,
        child: Column(
          children: [
            const SizedBox(height: 22),
            // 品牌区：logo + 应用名
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tvAccentColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: tvAccentColor.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Kazumi',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _TvRailItem(
                      icon: i == widget.selectedIndex
                          ? tabs[i].selectedIcon
                          : tabs[i].icon,
                      label: tabs[i].label,
                      focused: _focusIndex == i + 1,
                      selected: i == widget.selectedIndex,
                      colors: colors,
                      onTap: () {
                        setState(() => _focusIndex = i + 1);
                        _activate(i + 1);
                      },
                    ),
                ],
              ),
            ),
            // 分隔线 + 底部搜索
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Divider(
                height: 1,
                thickness: 1,
                color: colors.onSurfaceVariant.withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 12),
            _TvRailItem(
              icon: Icons.search_rounded,
              label: '搜索',
              focused: _focusIndex == 0,
              selected: false,
              colors: colors,
              onTap: () {
                setState(() => _focusIndex = 0);
                _activate(0);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// TV 侧边栏导航项：横排胶囊样式（现代 TV 风格）。
/// 聚焦 = primary 填充胶囊 + 白描边 + 发光 + 轻微放大；
/// 选中 = primaryContainer 胶囊 + 左侧 primary 指示条。
class _TvRailItem extends StatelessWidget {
  const _TvRailItem({
    required this.icon,
    required this.label,
    required this.focused,
    required this.selected,
    required this.colors,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool focused;
  final bool selected;
  final ColorScheme colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final Color textColor;
    if (focused) {
      iconColor = colors.onPrimary;
      textColor = colors.onPrimary;
    } else if (selected) {
      iconColor = colors.primary;
      textColor = colors.primary;
    } else {
      iconColor = colors.onSurfaceVariant;
      textColor = colors.onSurfaceVariant;
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 14, top: 5, bottom: 5),
      child: Row(
        children: [
          // 选中指示条（未选中时收缩为 0 高度）
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 4,
            height: selected ? 22 : 0,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: AnimatedScale(
              scale: focused ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                height: 50,
                decoration: BoxDecoration(
                  color: focused
                      ? colors.primary
                      : selected
                          ? colors.primaryContainer
                          : colors.onSurfaceVariant.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: focused
                        ? colors.onPrimary.withOpacity(0.85)
                        : Colors.transparent,
                    width: 1.6,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: colors.primary.withOpacity(0.40),
                            blurRadius: 16,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(icon, size: 23, color: iconColor),
                        const SizedBox(width: 11),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: focused || selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
