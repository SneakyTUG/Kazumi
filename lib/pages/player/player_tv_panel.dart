import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/format.dart';

/// TV（遥控器）专用播放控制面板（bilibili 风格）。
///
/// 完全自管焦点：不依赖 Flutter 默认焦点遍历（在电视上不可控），
/// 用行列索引状态驱动高亮，方向键/确认键全部在本面板的按键处理器内消化。
/// 交互约定（对齐主流 TV 播放器）：
/// - 左右：同一行内移动焦点；上下：在顶栏/底栏之间切换；
/// - OK/Enter/Select：激活当前项；
/// - 返回键：不在此处理，交给播放页早期键处理器收起面板；
/// - 防自动隐藏的 PlayerPanelHold 由播放页（player_item）掌控，
///   本面板不自行 acquire，避免 hold 让返回键收不起面板。
class PlayerTvPanel extends StatefulWidget {
  const PlayerTvPanel({
    super.key,
    required this.playerController,
    required this.title,
    required this.onBack,
    required this.onPrevEpisode,
    required this.onNextEpisode,
    required this.setPlaybackSpeed,
    required this.handleDanmaku,
    required this.showDanmakuSettings,
    required this.showVideoInfo,
    required this.handleSuperResolutionChange,
    this.onToggleSidePanel,
    this.onHidePanel,
  });

  final PlayerController playerController;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onPrevEpisode;
  final VoidCallback onNextEpisode;
  final Future<void> Function(double) setPlaybackSpeed;
  final VoidCallback handleDanmaku;
  final VoidCallback showDanmakuSettings;
  final VoidCallback showVideoInfo;
  final Future<void> Function(SuperResolutionMode) handleSuperResolutionChange;
  final VoidCallback? onToggleSidePanel;
  // 收起本面板（TV 适配：5 秒空闲自动隐藏时由面板回调播放页）。
  final VoidCallback? onHidePanel;

  @override
  State<PlayerTvPanel> createState() => _PlayerTvPanelState();
}

class _PlayerTvPanelState extends State<PlayerTvPanel> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerTvPanel');
  int _row = 1; // 初始焦点落在底栏（播放键）
  int _col = 0;

  // TV 标准节奏：面板显示后若 5 秒内无按键则自动收起，露出干净画面；
  // 任意按键都会重置计时；有对话框/新路由覆盖时暂缓计时。
  static const Duration _idleTimeout = Duration(seconds: 5);
  Timer? _idleTimer;

  // 与 build 中渲染的项目一一对应的动作矩阵，build 内每次刷新。
  List<List<VoidCallback>> _actions = const [<VoidCallback>[], <VoidCallback>[]];

  @override
  void initState() {
    super.initState();
    // 双保险：autofocus + post-frame 强制请求，确保遥控器按键先到本面板。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdleTimeout);
  }

  void _onIdleTimeout() {
    if (!mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      // 设置对话框等覆盖层还在最上层：暂缓自动隐藏，等回来后重新计时。
      _restartIdleTimer();
      return;
    }
    widget.onHidePanel?.call();
  }

  int get _rowCount => 2;

  int _rowLength(int row) => row == 0
      ? 2
      : 8 + (widget.onToggleSidePanel != null ? 1 : 0);

  void _move(int dRow, int dCol) {
    final newRow = (_row + dRow).clamp(0, _rowCount - 1);
    var newCol = _col;
    if (dRow != 0) {
      newCol = _col.clamp(0, _rowLength(newRow) - 1);
    } else {
      newCol = (_col + dCol).clamp(0, _rowLength(newRow) - 1);
    }
    if (newRow == _row && newCol == _col) {
      return;
    }
    setState(() {
      _row = newRow;
      _col = newCol;
    });
  }

  void _activate() {
    final row = _actions[_row];
    if (_col < row.length) {
      row[_col]();
    }
  }

  void _cycleSpeed(int delta) {
    final list = defaultPlaySpeedList;
    final current = widget.playerController.playback.playerSpeed;
    final index = list.indexOf(current);
    final next = (index < 0 ? 0 : index + delta).clamp(0, list.length - 1);
    unawaited(widget.setPlaybackSpeed(list[next]));
  }

  void _cycleAspectRatio(int delta) {
    final values = PlayerAspectRatio.values;
    final current = widget.playerController.panel.aspectRatioMode;
    final next = (values.indexOf(current) + delta) % values.length;
    widget.playerController.panel.aspectRatioMode = values[next];
  }

  void _openSettings() {
    showTvPlayerSettingsDialog(
      context: context,
      playerController: widget.playerController,
      setPlaybackSpeed: widget.setPlaybackSpeed,
      handleDanmaku: widget.handleDanmaku,
      showDanmakuSettings: widget.showDanmakuSettings,
      showVideoInfo: widget.showVideoInfo,
      handleSuperResolutionChange: widget.handleSuperResolutionChange,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 面板期间有任意按键活动就重置自动隐藏计时。
    _restartIdleTimer();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _activate();
      }
      return KeyEventResult.handled;
    }
    // 返回键（goBack/escape）：不处理，交给播放页早期键处理器收起面板。
    return KeyEventResult.ignored;
  }

  /// 底栏动作定义：与渲染顺序一一对应。
  List<_TvPanelActionDef> _bottomDefs(bool playing) {
    final danmakuOn = widget.playerController.danmaku.danmakuOn;
    return <_TvPanelActionDef>[
      _TvPanelActionDef(
        icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        label: playing ? '暂停' : '播放',
        onTap: () => widget.playerController.playOrPause(),
      ),
      _TvPanelActionDef(
        icon: Icons.skip_previous_rounded,
        label: '上一集',
        onTap: widget.onPrevEpisode,
      ),
      _TvPanelActionDef(
        icon: Icons.skip_next_rounded,
        label: '下一集',
        onTap: widget.onNextEpisode,
      ),
      if (widget.onToggleSidePanel != null)
        _TvPanelActionDef(
          icon: Icons.menu_open_rounded,
          label: '选集',
          onTap: widget.onToggleSidePanel!,
        ),
      _TvPanelActionDef(
        icon: Icons.fast_rewind_rounded,
        label: '快退',
        onTap: () => widget.playerController.seeking.seekBy(
          Duration(
              seconds: -widget.playerController.playback.arrowKeySkipTime),
        ),
      ),
      _TvPanelActionDef(
        icon: Icons.fast_forward_rounded,
        label: '快进',
        onTap: () => widget.playerController.seeking.seekBy(
          Duration(seconds: widget.playerController.playback.arrowKeySkipTime),
        ),
      ),
      _TvPanelActionDef(
        icon: danmakuOn
            ? Icons.comment_rounded
            : Icons.comments_disabled_rounded,
        label: '弹幕',
        valueText: danmakuOn ? '开' : '关',
        active: danmakuOn,
        onTap: widget.handleDanmaku,
      ),
      _TvPanelActionDef(
        icon: Icons.speed_rounded,
        label: '倍速',
        valueText: '${widget.playerController.playback.playerSpeed}x',
        onTap: () => _cycleSpeed(1),
      ),
      _TvPanelActionDef(
        icon: Icons.aspect_ratio_rounded,
        label: '比例',
        valueText: widget.playerController.panel.aspectRatioMode.label,
        onTap: () => _cycleAspectRatio(1),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Observer(
        builder: (context) {
          final playing = widget.playerController.playback.playing;
          final defs = _bottomDefs(playing);

          _actions = [
            [widget.onBack, _openSettings],
            [for (final def in defs) def.onTap],
          ];

          final position = widget.playerController.playback.currentPosition;
          final duration = widget.playerController.playback.duration;
          final progress = duration > Duration.zero
              ? (position.inMilliseconds / duration.inMilliseconds)
                  .clamp(0.0, 1.0)
              : 0.0;

          return Stack(
            children: [
              // ── 顶栏：返回 + 标题 + 设置 ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.82),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                      child: Row(
                        children: [
                          _TvRoundButton(
                            icon: Icons.arrow_back_rounded,
                            focused: _row == 0 && _col == 0,
                            onTap: widget.onBack,
                          ),
                          const SizedBox(width: 16),
                          // bilibili 风格标题：粉色竖条 + 白色粗体
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: tvAccentColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          _TvRoundButton(
                            icon: Icons.settings_outlined,
                            focused: _row == 0 && _col == 1,
                            onTap: _openSettings,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // ── 底栏：进度条 + 控制按钮 ──
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.88),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 进度条行：当前时间 / 进度（带滑块圆点）/ 总时长
                          Row(
                            children: [
                              Text(
                                durationToString(position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _TvProgressBar(progress: progress),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                durationToString(duration),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // 控制按钮行
                          Row(
                            children: [
                              for (var i = 0; i < defs.length; i++)
                                Expanded(
                                  child: Center(
                                    child: _TvItem(
                                      icon: defs[i].icon,
                                      label: defs[i].label,
                                      valueText: defs[i].valueText,
                                      active: defs[i].active,
                                      focused: _row == 1 && _col == i,
                                      onTap: defs[i].onTap,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 底栏单个动作的定义（图标 + 文案 + 动作）。
class _TvPanelActionDef {
  const _TvPanelActionDef({
    required this.icon,
    required this.label,
    required this.onTap,
    this.valueText,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? valueText;
  // 是否处于激活状态（如弹幕已开启）：未聚焦时图标用强调色标示。
  final bool active;
}

/// TV 面板顶栏圆形按钮（返回/设置）。
class _TvRoundButton extends StatelessWidget {
  const _TvRoundButton({
    required this.icon,
    required this.focused,
    this.onTap,
  });

  final IconData icon;
  final bool focused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: focused
            ? tvAccentColor
            : Colors.white.withOpacity(0.14),
        shape: BoxShape.circle,
        border: Border.all(
          color: focused ? Colors.white.withOpacity(0.9) : Colors.transparent,
          width: 2,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: tvAccentColor.withOpacity(0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 3),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Icon(icon, size: 24, color: Colors.white),
      ),
    );
  }
}

/// bilibili 风格进度条：细轨道 + 强调色已播段 + 白色圆点滑块。
class _TvProgressBar extends StatelessWidget {
  const _TvProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const thumbSize = 12.0;
        final fillWidth = (width * progress).clamp(0.0, width);
        final thumbLeft = (fillWidth - thumbSize / 2).clamp(0.0, width - thumbSize);
        return SizedBox(
          height: 14,
          child: Stack(
            children: [
              // 轨道
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 已播放段
              Positioned(
                top: 5,
                left: 0,
                child: Container(
                  height: 4,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    color: tvAccentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 滑块圆点
              Positioned(
                left: thumbLeft,
                top: 1,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// TV 面板单个可聚焦项：bilibili 风格胶囊按钮。
/// 聚焦 = 强调色填充 + 白描边 + 发光；弹幕等激活态未聚焦时图标用强调色。
class _TvItem extends StatelessWidget {
  const _TvItem({
    required this.icon,
    required this.label,
    required this.focused,
    this.onTap,
    this.valueText,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool focused;
  final VoidCallback? onTap;
  final String? valueText;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final iconColor = focused
        ? Colors.white
        : active
            ? tvAccentColor
            : Colors.white.withOpacity(0.85);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: focused ? tvAccentColor : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: focused ? Colors.white.withOpacity(0.9) : Colors.transparent,
          width: 2,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: tvAccentColor.withOpacity(0.45),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: focused ? Colors.white : Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (valueText != null) ...[
                const SizedBox(width: 5),
                Text(
                  valueText!,
                  style: TextStyle(
                    color: focused
                        ? Colors.white.withOpacity(0.92)
                        : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// TV 设置对话框：单列表 + 左右键调值，OK 确认，返回关闭。
/// 同样自管焦点，不依赖 Flutter 焦点遍历。
class _TvPlayerSettingsDialog extends StatefulWidget {
  const _TvPlayerSettingsDialog({
    required this.playerController,
    required this.setPlaybackSpeed,
    required this.handleDanmaku,
    required this.showDanmakuSettings,
    required this.showVideoInfo,
    required this.handleSuperResolutionChange,
  });

  final PlayerController playerController;
  final Future<void> Function(double) setPlaybackSpeed;
  final VoidCallback handleDanmaku;
  final VoidCallback showDanmakuSettings;
  final VoidCallback showVideoInfo;
  final Future<void> Function(SuperResolutionMode) handleSuperResolutionChange;

  @override
  State<_TvPlayerSettingsDialog> createState() =>
      _TvPlayerSettingsDialogState();
}

class _TvPlayerSettingsDialogState extends State<_TvPlayerSettingsDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TvPlayerSettings');
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _adjustSpeed(int delta) {
    final list = defaultPlaySpeedList;
    final current = widget.playerController.playback.playerSpeed;
    final index = list.indexOf(current);
    final next = (index < 0 ? 0 : index + delta).clamp(0, list.length - 1);
    unawaited(widget.setPlaybackSpeed(list[next]));
  }

  void _cycleAspectRatio(int delta) {
    final values = PlayerAspectRatio.values;
    final current = widget.playerController.panel.aspectRatioMode;
    final next = (values.indexOf(current) + delta) % values.length;
    widget.playerController.panel.aspectRatioMode = values[next];
  }

  void _cycleSuperResolution(int delta) {
    final values = SuperResolutionMode.values;
    final current = widget.playerController.playback.superResolutionMode;
    final next = (values.indexOf(current) + delta) % values.length;
    unawaited(widget.handleSuperResolutionChange(values[next]));
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1).clamp(0, _rowKeys.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1).clamp(0, _rowKeys.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    final adjust = _adjusters[_index];
    if (key == LogicalKeyboardKey.arrowLeft && adjust != null) {
      adjust(-1);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.space) &&
        event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.arrowRight) {
        adjust?.call(1);
      } else {
        _activate(_index);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activate(int index) {
    final key = _rowKeys[index];
    switch (key) {
      case _TvSettingRowKey.speed:
        _adjustSpeed(1);
        break;
      case _TvSettingRowKey.aspectRatio:
        _cycleAspectRatio(1);
        break;
      case _TvSettingRowKey.superResolution:
        _cycleSuperResolution(1);
        break;
      case _TvSettingRowKey.danmaku:
        widget.handleDanmaku();
        break;
      case _TvSettingRowKey.danmakuSettings:
        Navigator.of(context).pop();
        widget.showDanmakuSettings();
        break;
      case _TvSettingRowKey.videoInfo:
        Navigator.of(context).pop();
        widget.showVideoInfo();
        break;
    }
  }

  static const List<_TvSettingRowKey> _rowKeys = <_TvSettingRowKey>[
    _TvSettingRowKey.speed,
    _TvSettingRowKey.aspectRatio,
    _TvSettingRowKey.superResolution,
    _TvSettingRowKey.danmaku,
    _TvSettingRowKey.danmakuSettings,
    _TvSettingRowKey.videoInfo,
  ];

  Map<_TvSettingRowKey, void Function(int)> get _adjusters => {
        _TvSettingRowKey.speed: _adjustSpeed,
        _TvSettingRowKey.aspectRatio: _cycleAspectRatio,
        _TvSettingRowKey.superResolution: _cycleSuperResolution,
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('播放设置'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Observer(
          builder: (context) {
            final playback = widget.playerController.playback;
            final rows = <Widget>[
              for (var i = 0; i < _rowKeys.length; i++)
                _TvSettingRowTile(
                  focused: _index == i,
                  title: switch (_rowKeys[i]) {
                    _TvSettingRowKey.speed => '倍速',
                    _TvSettingRowKey.aspectRatio => '画面比例',
                    _TvSettingRowKey.superResolution => '超分辨率',
                    _TvSettingRowKey.danmaku => '弹幕',
                    _TvSettingRowKey.danmakuSettings => '弹幕设置',
                    _TvSettingRowKey.videoInfo => '视频详情',
                  },
                  valueText: switch (_rowKeys[i]) {
                    _TvSettingRowKey.speed =>
                      '${playback.playerSpeed}x',
                    _TvSettingRowKey.aspectRatio =>
                      widget.playerController.panel.aspectRatioMode.label,
                    _TvSettingRowKey.superResolution =>
                      playback.superResolutionMode.label,
                    _TvSettingRowKey.danmaku =>
                      widget.playerController.danmaku.danmakuOn ? '开' : '关',
                    _ => null,
                  },
                  hasValue: switch (_rowKeys[i]) {
                    _TvSettingRowKey.danmakuSettings ||
                    _TvSettingRowKey.videoInfo =>
                      false,
                    _ => true,
                  },
                  onTap: () => _activate(i),
                ),
            ];
            return SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: row,
                    ),
                ],
              ),
            );
          },
        ),
      ),
      // actions 留空：TV 上返回键关闭即可。
      actions: const <Widget>[],
      // 提示条
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
  }
}

enum _TvSettingRowKey {
  speed,
  aspectRatio,
  superResolution,
  danmaku,
  danmakuSettings,
  videoInfo,
}

class _TvSettingRowTile extends StatelessWidget {
  const _TvSettingRowTile({
    required this.focused,
    required this.title,
    required this.valueText,
    required this.hasValue,
    this.onTap,
  });

  final bool focused;
  final String title;
  final String? valueText;
  final bool hasValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: focused ? tvAccentColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? Colors.white.withOpacity(0.9) : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        onTap: onTap,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
            color: focused ? Colors.white : colors.onSurface,
          ),
        ),
        trailing: hasValue
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: focused ? Colors.white70 : colors.outline,
                  ),
                  Text(
                    valueText ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: focused ? Colors.white : colors.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: focused ? Colors.white70 : colors.outline,
                  ),
                ],
              )
            : Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: focused ? Colors.white70 : colors.outline,
              ),
      ),
    );
  }
}

/// 打开 TV 播放设置对话框。
void showTvPlayerSettingsDialog({
  required BuildContext context,
  required PlayerController playerController,
  required Future<void> Function(double) setPlaybackSpeed,
  required VoidCallback handleDanmaku,
  required VoidCallback showDanmakuSettings,
  required VoidCallback showVideoInfo,
  required Future<void> Function(SuperResolutionMode) handleSuperResolutionChange,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => _TvPlayerSettingsDialog(
      playerController: playerController,
      setPlaybackSpeed: setPlaybackSpeed,
      handleDanmaku: handleDanmaku,
      showDanmakuSettings: showDanmakuSettings,
      showVideoInfo: showVideoInfo,
      handleSuperResolutionChange: handleSuperResolutionChange,
    ),
  );
}
