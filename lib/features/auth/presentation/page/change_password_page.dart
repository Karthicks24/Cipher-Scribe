import 'dart:io';
import 'package:cipherscribe/features/auth/presentation/widgets/CustomTextField.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/auth/presentation/page/update_security_questions_page.dart';

/// A streamlined page for changing the Master PIN or Password.
///
/// Unlike [SetPasswordPage], this is used for existing vaults and skips onboarding UI.
class ChangePasswordPage extends StatefulWidget {
  final Uint8List importedDek;

  const ChangePasswordPage({super.key, required this.importedDek});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _storage = SecureStorageService();
  final _crypto = CryptoService();

  // State
  bool _usePin = true;
  int _pinLength = 6;
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirmingPin = false;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showPass = false;
  bool _showConfirmPass = false;
  bool _isLoading = false;
  String _errorMessage = '';

  double _strength = 0;
  String _strengthLabel = '';
  Color _strengthColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _loadCurrentAuthMethod();
  }

  Future<void> _loadCurrentAuthMethod() async {
    final method = await _storage.getAuthMethod();
    if (mounted) {
      setState(() => _usePin = method == 'pin');
    }
  }

  void _onPinKey(String digit) {
    if (digit == '✓') {
      HapticFeedback.lightImpact();
      _validateAndProceed();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = '';
      if (!_isConfirmingPin) {
        if (_pin.length < 6) _pin += digit;
      } else {
        if (_confirmPin.length < 6) _confirmPin += digit;
      }
    });
  }

  void _onPinBackspace() {
    HapticFeedback.mediumImpact();
    setState(() {
      if (!_isConfirmingPin) {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else {
        if (_confirmPin.isNotEmpty)
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      }
    });
  }

  void _validateAndProceed() {
    if (_usePin) {
      if (!_isConfirmingPin) {
        if (_pin.length < 6) {
          setState(() => _errorMessage = 'Enter a 6-digit PIN.');
          return;
        }
        setState(() {
          _isConfirmingPin = true;
          _errorMessage = '';
        });
      } else {
        if (_pin != _confirmPin) {
          setState(() {
            _errorMessage = 'PINs do not match. Try again.';
            _confirmPin = '';
          });
          return;
        }
        _finalizeChange();
      }
    } else {
      final pass = _passwordController.text;
      final confirm = _confirmController.text;
      if (pass.length < 8) {
        setState(
          () => _errorMessage = 'Password must be at least 8 characters.',
        );
        return;
      }
      if (pass != confirm) {
        setState(() => _errorMessage = 'Passwords do not match.');
        return;
      }
      _finalizeChange();
    }
  }

  Future<void> _finalizeChange() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final credential = _usePin ? _pin : _passwordController.text;
      final salt = await _storage.getDeviceHardwareSalt();

      // 1. Derive KEK and Wrap DEK
      final kek = await _crypto.deriveKEK(pin: credential, salt: salt);
      final wrappedDek = await _crypto.wrapDEK(widget.importedDek, kek);

      // 2. Save
      await _storage.setAuthMethod(_usePin ? 'pin' : 'password');
      await _storage.saveWrappedDEK(wrappedDek);

      // Also ensure DEK hash is saved for validation
      await _storage.saveDekHash(widget.importedDek);

      if (mounted) {
        HapticFeedback.mediumImpact();
        _showSecurityQuestionsDialog();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to update password.';
      });
    }
  }

  void _showSecurityQuestionsDialog() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Update Security Questions?'),
        content: const Text(
          'Would you also like to update your security questions for recovery?',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Skip'),
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Pop ChangePasswordPage
            },
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Update'),
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pushReplacement(
                context,
                CupertinoPageRoute(
                  builder: (context) => UpdateSecurityQuestionsPage(
                    importedDek: widget.importedDek,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

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

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: CupertinoNavigationBar(
          backgroundColor:
              (isDark ? AppColors.darkBackground : AppColors.lightBackground)
                  .withValues(alpha: 0.9),
          middle: const Text('Change Password'),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          spacing: 16,
                          children: [
                            Icon(
                              CupertinoIcons.shield_lefthalf_fill,
                              color: primary,
                              size: 44,
                            ),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Set New PIN or Password',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isConfirmingPin
                              ? 'Please confirm your new PIN.'
                              : 'Choose a new method to protect your vault.',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isConfirmingPin) _buildAuthToggle(isDark, primary),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _usePin
                        ? _buildPinEntry(isDark, primary)
                        : _buildPasswordEntry(isDark, primary),
                  ),
                ],
              ),
              if (_isLoading)
                Container(
                  color: (isDark ? Colors.black : Colors.white)
                      .withValues(alpha: 0.7),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkBackground
                                : AppColors.lightBackground,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const CupertinoActivityIndicator(radius: 14),
                              const SizedBox(height: 20),
                              Text(
                                'Securing Vault...',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Recrypting keys with new credentials',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: 200,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: const LinearProgressIndicator(
                                    minHeight: 4,
                                    backgroundColor: Colors.transparent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthToggle(bool isDark, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toggleOption(
              label: '6-Digit PIN',
              icon: CupertinoIcons.number,
              active: _usePin,
              isDark: isDark,
              primary: primary,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  _usePin = true;
                  _pin = '';
                  _confirmPin = '';
                  _isConfirmingPin = false;
                  _errorMessage = '';
                });
              },
            ),
          ),
          Expanded(
            child: _toggleOption(
              label: 'Password',
              icon: CupertinoIcons.keyboard,
              active: !_usePin,
              isDark: isDark,
              primary: primary,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  _usePin = false;
                  _passwordController.clear();
                  _confirmController.clear();
                  _errorMessage = '';
                  _strength = 0;
                  _strengthLabel = '';
                  _strengthColor = Colors.transparent;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleOption({
    required String label,
    required IconData icon,
    required bool active,
    required bool isDark,
    required Color primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? Colors.white
                  : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active
                    ? Colors.white
                    : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinEntry(bool isDark, Color primary) {
    final current = _isConfirmingPin ? _confirmPin : _pin;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _pinLength,
            (i) => Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < current.length ? primary : Colors.transparent,
                border: Border.all(
                  color: i < current.length
                      ? primary
                      : (isDark ? Colors.white38 : Colors.black26),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _errorMessage.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : const SizedBox(height: 44),
        ),
        const Spacer(flex: 2),
        _buildKeypad(isDark, primary),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildPasswordEntry(bool isDark, Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Customtextfield(
            controller: _passwordController,
            label: 'New Password',
            hint: 'Min. 8 characters',
            isDark: isDark,
            onChanged: (_) => _evaluateStrength(),
            showText: _showPass,
            onToggleShow: () => setState(() => _showPass = !_showPass),
          ),
          const SizedBox(height: 16),
          Customtextfield(
            controller: _confirmController,
            label: 'Confirm New Password',
            hint: 'Re-enter password',
            isDark: isDark,
            onChanged: (_) => _evaluateStrength(),
            showText: _showConfirmPass,
            onToggleShow: () =>
                setState(() => _showConfirmPass = !_showConfirmPass),
          ),
          const SizedBox(height: 16),
          PasswordStrengthIndicator(
            isDark: isDark,
            strength: _strength,
            label: _strengthLabel,
            color: _strengthColor,
          ),
          const SizedBox(height: 16),
          if (_errorMessage.isNotEmpty)
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 32),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _passwordController,
            builder: (context, value, child) {
              final strength = _strength;
              return _buildPrimaryButton(
                label: 'Change Password',
                primary: strength > 0 ? primary : Colors.grey,
                onTap: strength > 0 ? _validateAndProceed : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad(bool isDark, Color primary) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['✓', '0', '⌫'],
    ];
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: keys
            .map(
              (row) => Row(
                children: row
                    .map(
                      (key) => Expanded(
                        child: AspectRatio(
                          aspectRatio: 1.8,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: InkWell(
                              onTap: _isLoading
                                  ? null
                                  : () {
                                      if (key == '⌫') {
                                        _onPinBackspace();
                                      } else {
                                        _onPinKey(key);
                                      }
                                    },
                              borderRadius: BorderRadius.circular(16),
                              splashColor: Colors.blue.withValues(
                                alpha: 0.3,
                              ),
                              highlightColor: Colors.blue.withValues(
                                alpha: 0.1,
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: key == '⌫'
                                      ? Icon(
                                          CupertinoIcons.delete_left,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                          size: 22,
                                        )
                                      : (key == '✓'
                                          ? Icon(
                                              CupertinoIcons.checkmark_alt,
                                              color: isDark
                                                  ? AppColors.darkPrimary
                                                  : Colors.black54,
                                              size: 26,
                                            )
                                          : Text(
                                              key,
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w400,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            )),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required Color primary,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: CupertinoButton(
        color: primary,
        borderRadius: BorderRadius.circular(14),
        onPressed: _isLoading ? null : onTap,
        child: _isLoading
            ? const CupertinoActivityIndicator(color: Colors.white)
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              )
      ));
  }
}
