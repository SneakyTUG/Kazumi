import 'package:flutter/material.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';

class UpdateSourceStep extends StatelessWidget {
  const UpdateSourceStep({
    super.key,
    required this.useGithubUpdate,
    required this.onChanged,
  });

  final bool useGithubUpdate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => OnboardingStepLayout(
        leading: const OnboardingStepIcon(
          icon: Icons.system_update_rounded,
          shape: OnboardingIconShape.cookie,
        ),
        title: '以你的方式更新',
        subtitle: '选择适合你的更新来源，让 Kazumi 保持最新。',
        // No RadioGroup here on purpose: its Shortcuts.manager maps the four
        // arrow keys to radio selection, so once a radio has focus the D-pad
        // can never reach the focus traversal system and the bottom bar
        // "继续" button becomes unreachable on a TV remote. RadioListTile
        // takes groupValue/onChanged directly and keeps normal traversal.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OptionCard(
              icon: Icons.rocket_launch_rounded,
              title: 'GitHub',
              description: '在应用内检查并获取新版本，适合大多数用户。',
              value: true,
              groupValue: useGithubUpdate,
              onChanged: onChanged,
              recommended: true,
            ),
            const SizedBox(height: 12),
            _OptionCard(
              icon: Icons.storefront_rounded,
              title: 'F-Droid',
              description: '由 F-Droid 商店管理更新，应用内不再自动检查。',
              value: false,
              groupValue: useGithubUpdate,
              onChanged: onChanged,
            ),
            const OnboardingHint(text: '之后也可以在 关于 → 自动检查更新 中修改。'),
          ],
        ),
      );
}

class _OptionCard extends StatefulWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.recommended = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool groupValue;
  final ValueChanged<bool> onChanged;
  final bool recommended;

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'UpdateSourceOption');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = widget.value == widget.groupValue;
    final foreground =
        selected ? colors.onSecondaryContainer : colors.onSurface;
    // D-pad focus needs a visible affordance at TV viewing distance.
    final borderColor = _focused
        ? colors.primary
        : selected
            ? colors.secondary
            : Colors.transparent;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubicEmphasized,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color:
            selected ? colors.secondaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(selected ? 20 : 28),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: RadioListTile<bool>(
          value: widget.value,
          groupValue: widget.groupValue,
          onChanged: (bool? selected) {
            if (selected != null) widget.onChanged(selected);
          },
          focusNode: _focusNode,
          controlAffinity: ListTileControlAffinity.trailing,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          secondary: Icon(widget.icon, size: 28, color: foreground),
          title: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: foreground, fontWeight: FontWeight.w700)),
              if (widget.recommended)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: ShapeDecoration(
                      color: colors.tertiaryContainer,
                      shape: const StadiumBorder()),
                  child: Text('推荐',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: colors.onTertiaryContainer)),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected ? foreground : colors.onSurfaceVariant,
                  height: 1.5,
                )),
          ),
        ),
      ),
    );
  }
}
