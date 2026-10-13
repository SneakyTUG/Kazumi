import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';

typedef PlayerShortcutAction = FutureOr<void> Function();

class PlayerLongPressShortcutActions {
  const PlayerLongPressShortcutActions({
    required this.onRepeat,
    required this.onRelease,
  });

  final PlayerShortcutAction onRepeat;
  final PlayerShortcutAction onRelease;
}

/// Dispatches player shortcuts before focused controls handle the key event.
///
/// [focusScopeNode] must be attached to a stable ancestor of the player area.
/// Dialog routes and explicitly blocked overlay interactions keep their normal
/// key handling. Active long-press shortcuts are always released, even after
/// focus leaves the player or this widget is disposed.
class PlayerKeyboardShortcuts extends StatefulWidget {
  const PlayerKeyboardShortcuts({
    super.key,
    required this.focusScopeNode,
    required this.actions,
    this.longPressActions = const <String, PlayerLongPressShortcutActions>{},
    this.isBlocked,
    this.shortcuts,
    this.isPanelVisible,
    this.onPanelEscape,
    this.isMenuOpen,
    this.isSidePanelOpen,
    this.onSidePanelClose,
  });

  final FocusNode focusScopeNode;
  final Map<String, PlayerShortcutAction> actions;
  final Map<String, PlayerLongPressShortcutActions> longPressActions;
  final bool Function()? isBlocked;
  final Map<String, List<String>>? shortcuts;
  // 播放器控制面板（含进度条/按钮）是否可见。可见时应让出方向键与确认键，
  // 交给面板内的控件处理焦点遍历，否则早期键处理器会私吞方向键导致面板按钮选不到。
  final bool Function()? isPanelVisible;
  // 面板可见时按「返回/Back」应优先收起面板而非退出播放器。
  final VoidCallback? onPanelEscape;
  // 播放器内的 MenuAnchor 菜单（更多选项/倍速/比例等）是否打开。
  // 打开时 Back/Escape 必须放行给菜单自身处理（菜单内的按键处理器会关闭菜单），
  // 否则会被本处理器吞掉，遥控器无法用返回键关闭菜单。
  final bool Function()? isMenuOpen;
  // TV 适配：选集侧面板是否打开。打开时 Back/Escape 收起侧面板（而不是
  // 退出播放页），方向键/确认键交给侧面板内部控件，实现逐级返回。
  final bool Function()? isSidePanelOpen;
  final VoidCallback? onSidePanelClose;

  @override
  State<PlayerKeyboardShortcuts> createState() =>
      _PlayerKeyboardShortcutsState();
}

class _PlayerKeyboardShortcutsState extends State<PlayerKeyboardShortcuts> {
  late Map<String, List<String>> _shortcuts;
  final Map<LogicalKeyboardKey, PlayerLongPressShortcutActions>
      _activeLongPressKeys =
      <LogicalKeyboardKey, PlayerLongPressShortcutActions>{};
  // TV 适配：面板收起状态下按遥控器返回键，第一次只提示、2 秒内再按才退出，
  // 防止单次误触直接退出播放。设置对话框等覆盖层打开时不受影响（先关覆盖层）。
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    _shortcuts = widget.shortcuts ?? _loadShortcuts();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(PlayerKeyboardShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shortcuts != oldWidget.shortcuts) {
      _shortcuts = widget.shortcuts ?? _loadShortcuts();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    _releaseAllLongPressShortcuts();
    super.dispose();
  }

  Map<String, List<String>> _loadShortcuts() {
    // TV 适配：↑/↓ 曾默认映射音量调节，现改为不绑定（上下键留给面板/焦点导航）。
    // 旧默认值可能已被键盘设置页持久化，这里把「未修改过的旧默认」迁移为空绑定，
    // 避免改默认值后残留旧绑定。用户显式追加过其它键的（长度不符）则不动。
    const legacyVolumeKeys = <String, List<String>>{
      'volumeup': <String>['Arrow Up'],
      'volumedown': <String>['Arrow Down'],
    };
    final volumeOverrides = <String, List<String>>{};
    legacyVolumeKeys.forEach((action, legacyKeys) {
      final stored = GStorage.getStringListSettingByName('shortcut_$action');
      if (listEquals(stored, legacyKeys)) {
        volumeOverrides[action] = const <String>[];
        unawaited(GStorage.putStringListSettingByName(
          'shortcut_$action',
          const <String>[],
        ));
      }
    });
    return <String, List<String>>{
      for (final entry in defaultShortcuts.entries)
        entry.key: volumeOverrides[entry.key] ??
            GStorage.getStringListSettingByName(
              'shortcut_${entry.key}',
              defaultValue: entry.value,
            ),
    };
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      final longPressActions = _activeLongPressKeys.remove(event.logicalKey);
      if (longPressActions != null) {
        _invokeAction(longPressActions.onRelease);
        return KeyEventResult.handled;
      }
    }

    // 面板可见时：早期键处理器全面让位，把方向键/确认键交给面板内的焦点控件，
    // 否则箭头键会被播放器快捷键吃掉，电视遥控器无法在面板按钮间移动焦点。
    // 仅「返回/Back」例外——优先收起面板而不是退出播放页。
    // TV 适配：选集侧面板打开时全面让位——Back/Escape 收起侧面板，
    // 其余按键交给侧面板内部控件，保证「播放面板 → 选集 → 返回」逐级回退。
    if (widget.isSidePanelOpen?.call() ?? false) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack)) {
        widget.onSidePanelClose?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (widget.isPanelVisible?.call() ?? false) {
      // 菜单打开时全面让位：Back/Escape 由菜单内的按键处理器关闭菜单，
      // 方向键/确认键交给菜单项焦点遍历。
      if (widget.isMenuOpen?.call() ?? false) {
        return KeyEventResult.ignored;
      }
      // 有覆盖路由（对话框等）时全面让位，否则返回键会被这里吞掉，
      // TV 上将无法用返回键关闭对话框。
      if (widget.isBlocked?.call() ?? false) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack)) {
        widget.onPanelEscape?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // TV 适配：面板收起后按遥控器返回键（goBack）不直接退出播放，
    // 第一次提示、2 秒内再按一次才放行默认返回行为（退出播放/返回详情）。
    // 仅拦截 goBack，不拦截 Escape（避免影响桌面端退出全屏快捷键）。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.goBack) {
      final now = DateTime.now();
      final last = _lastBackPressAt;
      if (last == null ||
          now.difference(last) > const Duration(seconds: 2)) {
        _lastBackPressAt = now;
        KazumiDialog.showToast(message: '再按一次返回', context: context);
        return KeyEventResult.handled;
      }
      _lastBackPressAt = null;
      return KeyEventResult.ignored;
    }

    if (!_shouldHandleShortcut()) {
      return KeyEventResult.ignored;
    }

    final keyLabel = event.logicalKey.keyLabel.isNotEmpty
        ? event.logicalKey.keyLabel
        : event.logicalKey.debugName ?? '';
    final actionName = _findActionName(keyLabel);
    if (actionName == null) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      final action = widget.actions[actionName];
      if (action == null) {
        return KeyEventResult.ignored;
      }
      final longPressActions = widget.longPressActions[actionName];
      if (longPressActions != null) {
        _activeLongPressKeys[event.logicalKey] = longPressActions;
      }
      _invokeAction(action);
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
      final longPressActions = _activeLongPressKeys[event.logicalKey];
      if (longPressActions == null) {
        return KeyEventResult.ignored;
      }
      _invokeAction(longPressActions.onRepeat);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _shouldHandleShortcut() {
    if (widget.isBlocked?.call() ?? false) {
      return false;
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return false;
    }

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null ||
        (primaryFocus != widget.focusScopeNode &&
            !primaryFocus.ancestors.contains(widget.focusScopeNode))) {
      return false;
    }

    final focusContext = primaryFocus.context;
    if (focusContext == null) {
      return true;
    }
    return focusContext.widget is! EditableText &&
        focusContext.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  String? _findActionName(String keyLabel) {
    for (final entry in _shortcuts.entries) {
      if (entry.value.contains(keyLabel)) {
        return entry.key;
      }
    }
    return null;
  }

  void _releaseAllLongPressShortcuts() {
    final actions = _activeLongPressKeys.values.toSet();
    _activeLongPressKeys.clear();
    for (final action in actions) {
      _invokeAction(action.onRelease);
    }
  }

  void _invokeAction(PlayerShortcutAction action) {
    unawaited(_runAction(action));
  }

  Future<void> _runAction(PlayerShortcutAction action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'player keyboard shortcuts',
          context: ErrorDescription('while invoking a player shortcut'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
