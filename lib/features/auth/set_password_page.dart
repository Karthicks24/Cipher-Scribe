import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';

/// ─── Security question bank ───────────────────────────────────────────────
const List<String> kSecurityQuestions = [
  "What was the name of your first pet?",
  "What city were you born in?",
  "What is your mother's maiden name?",
  "What was the make of your first car?",
  "What was the name of your elementary school?",
  "What is the name of the street you grew up on?",
  "What is your oldest sibling's middle name?",
  "What was your childhood nickname?",
];

/// ─── Onboarding step model ────────────────────────────────────────────────
enum _SetupStep { password, questions, confirm }

class SetPasswordPage extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetPasswordPage({super.key, required this.onSetupComplete});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _answer1Controller = TextEditingController();
  final _answer2Controller = TextEditingController();

  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _answer1Focus = FocusNode();
  final _answer2Focus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────────
  _SetupStep _step = _SetupStep.password;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String _errorMessage = '';

  String _selectedQuestion1 = kSecurityQuestions[0];
  String _selectedQuestion2 = kSecurityQuestions[1];

  // ── Password strength ─────────────────────────────────────────────────────
  double _strength = 0;
  String _strengthLabel = '';
  Color _strengthColor = Colors.transparent;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _fadeCtrl.forward();
    _slideCtrl.forward();

    _passwordController.addListener(_evaluateStrength);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _answer1Controller.dispose();
    _answer2Controller.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _answer1Focus.dispose();
    _answer2Focus.dispose();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Password Strength ─────────────────────────────────────────────────────
  void _evaluateStrength() {
    final pw = _passwordController.text;
    double score = 0;
    if (pw.length >= 8) score += 0.25;
    if (pw.length >= 12) score += 0.15;
    if (pw.contains(RegExp(r'[A-Z]'))) score += 0.2;
    if (pw.contains(RegExp(r'[0-9]'))) score += 0.2;
    if (pw.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score += 0.2;

    String label;
    Color color;
    if (score < 0.35) {
      label = 'Weak';
      color = AppColors.darkError;
    } else if (score < 0.65) {
      label = 'Fair';
      color = AppColors.darkWarning;
    } else if (score < 0.85) {
      label = 'Strong';
      color = AppColors.darkSecondary;
    } else {
      label = 'Very Strong';
      color = AppColors.darkSuccess;
    }

    setState(() {
      _strength = score.clamp(0.0, 1.0);
      _strengthLabel = pw.isEmpty ? '' : label;
      _strengthColor = color;
      _errorMessage = '';
    });
  }

  // ── Step transitions ──────────────────────────────────────────────────────
  Future<void> _animateTransition(VoidCallback onDone) async {
    await _fadeCtrl.reverse();
    await _slideCtrl.reverse();
    onDone();
    _fadeCtrl.forward();
    _slideCtrl.forward();
  }

  void _goToQuestions() {
    final pw = _passwordController.text;
    if (pw.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirmController.text) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }
    _animateTransition(() => setState(() {
          _step = _SetupStep.questions;
          _errorMessage = '';
        }));
  }

  void _goToConfirm() {
    if (_answer1Controller.text.trim().isEmpty ||
        _answer2Controller.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please answer both security questions.');
      return;
    }
    _animateTransition(() => setState(() {
          _step = _SetupStep.confirm;
          _errorMessage = '';
        }));
  }

  Future<void> _saveSetup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final storage = SecureStorageService();
      // Hash-like storage: store password hash + questions/answers
      await storage.savePassword(_passwordController.text);
      await storage.saveSecurityQuestions(
        q1: _selectedQuestion1,
        a1: _answer1Controller.text.trim().toLowerCase(),
        q2: _selectedQuestion2,
        a2: _answer2Controller.text.trim().toLowerCase(),
      );
      await storage.markSetupComplete();

      if (mounted) {
        HapticFeedback.heavyImpact();
        widget.onSetupComplete();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save credentials. Please try again.';
        _isLoading = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final primary =
        isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: _buildBody(isDark, primary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark, Color primary) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildHeader(isDark),
                const SizedBox(height: 32),
                _buildStepIndicator(isDark, primary),
                const SizedBox(height: 36),
                _buildStepContent(isDark, primary),
                const SizedBox(height: 24),
                if (_errorMessage.isNotEmpty) _buildErrorBanner(isDark),
                const SizedBox(height: 16),
                _buildPrimaryButton(isDark, primary),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    final labels = [
      ('Create Password', 'Secure your vault with a master password.'),
      ('Security Questions', 'These help you recover your account.'),
      ('All Set', 'Review and finalize your security setup.'),
    ];
    final idx = _step.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shield icon with glow
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.darkPrimary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.darkPrimary.withValues(alpha: 0.35), width: 1),
          ),
          child: Icon(
            idx == 2 ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.lock_shield_fill,
            color: AppColors.darkPrimary,
            size: 28,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          labels[idx].$1,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: isDark ? AppColors.darkTitleText : AppColors.lightTitleText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          labels[idx].$2,
          style: TextStyle(
            fontSize: 15,
            color: isDark
                ? AppColors.darkDescriptionText
                : AppColors.lightDescriptionText,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ── Step Indicator ────────────────────────────────────────────────────────
  Widget _buildStepIndicator(bool isDark, Color primary) {
    return Row(
      children: List.generate(3, (i) {
        final active = i == _step.index;
        final done = i < _step.index;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: done || active
                  ? primary
                  : (isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider),
            ),
          ),
        );
      }),
    );
  }

  // ── Step Content ──────────────────────────────────────────────────────────
  Widget _buildStepContent(bool isDark, Color primary) {
    switch (_step) {
      case _SetupStep.password:
        return _buildPasswordStep(isDark, primary);
      case _SetupStep.questions:
        return _buildQuestionsStep(isDark, primary);
      case _SetupStep.confirm:
        return _buildConfirmStep(isDark, primary);
    }
  }

  // ── Step 1: Password ──────────────────────────────────────────────────────
  Widget _buildPasswordStep(bool isDark, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iosField(
          controller: _passwordController,
          focus: _passwordFocus,
          nextFocus: _confirmFocus,
          label: 'Master Password',
          hint: 'At least 8 characters',
          obscure: _obscurePassword,
          isDark: isDark,
          primary: primary,
          suffix: _eyeToggle(
              isDark, _obscurePassword, () => setState(() => _obscurePassword = !_obscurePassword)),
        ),
        const SizedBox(height: 14),
        // Strength bar
        if (_passwordController.text.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _strength,
                    minHeight: 4,
                    backgroundColor: isDark
                        ? AppColors.darkDivider
                        : AppColors.lightDivider,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_strengthColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _strengthLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _strengthColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        _iosField(
          controller: _confirmController,
          focus: _confirmFocus,
          label: 'Confirm Password',
          hint: 'Re-enter your password',
          obscure: _obscureConfirm,
          isDark: isDark,
          primary: primary,
          suffix: _eyeToggle(
              isDark, _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _goToQuestions(),
        ),
        const SizedBox(height: 20),
        _tipCard(
          isDark: isDark,
          icon: CupertinoIcons.shield_lefthalf_fill,
          text:
              'Use a mix of uppercase, numbers, and symbols for maximum security.',
        ),
      ],
    );
  }

  // ── Step 2: Security Questions ────────────────────────────────────────────
  Widget _buildQuestionsStep(bool isDark, Color primary) {
    return Column(
      children: [
        _questionDropdown(
          isDark: isDark,
          primary: primary,
          label: 'Question 1',
          selected: _selectedQuestion1,
          questions: kSecurityQuestions
              .where((q) => q != _selectedQuestion2)
              .toList(),
          onChanged: (val) => setState(() => _selectedQuestion1 = val!),
        ),
        const SizedBox(height: 12),
        _iosField(
          controller: _answer1Controller,
          focus: _answer1Focus,
          nextFocus: _answer2Focus,
          label: 'Your Answer',
          hint: 'Answer (case-insensitive)',
          isDark: isDark,
          primary: primary,
        ),
        const SizedBox(height: 24),
        _questionDropdown(
          isDark: isDark,
          primary: primary,
          label: 'Question 2',
          selected: _selectedQuestion2,
          questions: kSecurityQuestions
              .where((q) => q != _selectedQuestion1)
              .toList(),
          onChanged: (val) => setState(() => _selectedQuestion2 = val!),
        ),
        const SizedBox(height: 12),
        _iosField(
          controller: _answer2Controller,
          focus: _answer2Focus,
          label: 'Your Answer',
          hint: 'Answer (case-insensitive)',
          isDark: isDark,
          primary: primary,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _goToConfirm(),
        ),
        const SizedBox(height: 20),
        _tipCard(
          isDark: isDark,
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          text:
              'Your answers are stored encrypted. They are used only for account recovery.',
        ),
      ],
    );
  }

  // ── Step 3: Confirm ───────────────────────────────────────────────────────
  Widget _buildConfirmStep(bool isDark, Color primary) {
    return Column(
      children: [
        _reviewRow(
          isDark: isDark,
          icon: CupertinoIcons.lock_fill,
          label: 'Master Password',
          value: '•' * _passwordController.text.length.clamp(0, 20),
        ),
        _divider(isDark),
        _reviewRow(
          isDark: isDark,
          icon: CupertinoIcons.question_circle_fill,
          label: 'Security Question 1',
          value: _selectedQuestion1,
        ),
        _divider(isDark),
        _reviewRow(
          isDark: isDark,
          icon: CupertinoIcons.question_circle_fill,
          label: 'Security Question 2',
          value: _selectedQuestion2,
        ),
        const SizedBox(height: 24),
        _tipCard(
          isDark: isDark,
          icon: CupertinoIcons.info_circle_fill,
          text:
              'Once confirmed, your password cannot be recovered — only reset via security questions.',
        ),
      ],
    );
  }

  // ── Primary Button ────────────────────────────────────────────────────────
  Widget _buildPrimaryButton(bool isDark, Color primary) {
    final labels = ['Continue', 'Continue', 'Create Vault'];
    final actions = [_goToQuestions, _goToConfirm, _saveSetup];

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: _isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                  color: primary, radius: 13))
          : CupertinoButton(
              color: primary,
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              onPressed: actions[_step.index],
              child: Text(
                labels[_step.index],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  // ── Error Banner ──────────────────────────────────────────────────────────
  Widget _buildErrorBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkError.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkError.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.xmark_circle_fill,
              color: AppColors.darkError, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.darkError,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────
  Widget _iosField({
    required TextEditingController controller,
    required FocusNode focus,
    FocusNode? nextFocus,
    required String label,
    required String hint,
    required bool isDark,
    required Color primary,
    bool obscure = false,
    Widget? suffix,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final bodyText = isDark ? AppColors.darkBodyText : AppColors.lightBodyText;
    final desc = isDark ? AppColors.darkDescriptionText : AppColors.lightDescriptionText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: desc,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focus.hasFocus
                  ? primary.withValues(alpha: 0.6)
                  : (isDark ? AppColors.darkDivider : AppColors.lightDivider),
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focus,
            obscureText: obscure,
            textInputAction: textInputAction,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w400, color: bodyText),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: desc, fontSize: 15),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: suffix,
            ),
            onSubmitted: onSubmitted ??
                (_) {
                  if (nextFocus != null) {
                    FocusScope.of(context).requestFocus(nextFocus);
                  }
                },
          ),
        ),
      ],
    );
  }

  Widget _questionDropdown({
    required bool isDark,
    required Color primary,
    required String label,
    required String selected,
    required List<String> questions,
    required ValueChanged<String?> onChanged,
  }) {
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final bodyText = isDark ? AppColors.darkBodyText : AppColors.lightBodyText;
    final desc = isDark ? AppColors.darkDescriptionText : AppColors.lightDescriptionText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: desc,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppColors.darkDivider : AppColors.lightDivider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: questions.contains(selected) ? selected : questions.first,
              isExpanded: true,
              dropdownColor: card,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                  color: bodyText),
              icon: Icon(CupertinoIcons.chevron_down,
                  size: 14, color: desc),
              items: questions
                  .map((q) => DropdownMenuItem(
                      value: q,
                      child: Text(q,
                          maxLines: 2, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewRow({
    required bool isDark,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final bodyText = isDark ? AppColors.darkBodyText : AppColors.lightBodyText;
    final desc = isDark ? AppColors.darkDescriptionText : AppColors.lightDescriptionText;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: desc,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        color: bodyText,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(bool isDark) => Divider(
        height: 1,
        color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
        indent: 48,
      );

  Widget _tipCard({
    required bool isDark,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkPrimary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 16,
              color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark
                    ? AppColors.darkDescriptionText
                    : AppColors.lightDescriptionText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eyeToggle(bool isDark, bool obscure, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Icon(
          obscure
              ? CupertinoIcons.eye_slash_fill
              : CupertinoIcons.eye_fill,
          size: 18,
          color: isDark
              ? AppColors.darkDescriptionText
              : AppColors.lightDescriptionText,
        ),
      ),
    );
  }
}
