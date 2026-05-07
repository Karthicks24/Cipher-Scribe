import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Customtextfield extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focus;
  final String? label;
  final bool isDark;
  final bool showText;
  final VoidCallback onToggleShow;
  final String? hint;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  const Customtextfield({
    super.key,
    required this.controller,
    this.focus,
    this.label,
    required this.isDark,
    required this.showText,
    required this.onToggleShow,
    this.hint,
    this.keyboardType = TextInputType.visiblePassword,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Text(
            label!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        if (label != null) const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focus,
            obscureText: !showText,
            keyboardType: TextInputType.visiblePassword,
            style: TextStyle(
              fontSize: 17,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffix: GestureDetector(
                onTap: onToggleShow,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    showText ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 18,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
            onSubmitted: onSubmitted,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

Widget buildPasswordField({
  required TextEditingController controller,
  required FocusNode focus,
  required String label,
  required bool isDark,
  required bool showText,
  required VoidCallback onToggleShow,
  String? hint,
  ValueChanged<String>? onSubmitted,
  ValueChanged<String>? onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: TextField(
          controller: controller,
          focusNode: focus,
          obscureText: !showText,
          keyboardType: TextInputType.visiblePassword,
          style: TextStyle(
            fontSize: 17,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            suffix: GestureDetector(
              onTap: onToggleShow,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  showText ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                  size: 18,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          onSubmitted: onSubmitted,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}


class PasswordStrengthIndicator extends StatelessWidget {
  final bool isDark;
  final double strength;
  final String label;
  final Color color;
  const PasswordStrengthIndicator({super.key, required this.isDark, required this.strength, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label.isEmpty ? 'Too Weak' : label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: label.isEmpty ? Colors.grey : color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}