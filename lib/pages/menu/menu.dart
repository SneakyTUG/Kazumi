import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/router.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
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
/// 上下移动高亮、OK 激活（搜索/切 tab）、左右方向交给默认焦点遍历
/// （右进内容区 / 从内容区最左侧控件左移回来）。
class _TvRail extends StatefulWidget {
  const _TvRail({
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
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (event is KeyDownEvent) {
        _activate(_focusIndex);
      }
      return KeyEventResult.handled;
    }
    // 左/右：交给默认焦点遍历（右侧进内容区；内容区最左侧控件左移可回 rail）。
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = const <({IconData icon, IconData selectedIcon, String label})>[
      (icon: Icons.search_rounded, selectedIcon: Icons.search_rounded, label: '搜索'),
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
        width: 116,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              _TvRailItem(
                icon: i == widget.selectedIndex + 1
                    ? items[i].selectedIcon
                    : items[i].icon,
                label: items[i].label,
                focused: _focusIndex == i,
                selected: i == widget.selectedIndex + 1,
                colors: colors,
                onTap: () {
                  setState(() => _focusIndex = i);
                  _activate(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: focused
            ? colors.primary.withOpacity(0.18)
            : selected
                ? colors.secondaryContainer
                : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? colors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: selected
                    ? colors.primary
                    : focused
                        ? colors.primary
                        : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? colors.primary
                      : focused
                          ? colors.primary
                          : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
