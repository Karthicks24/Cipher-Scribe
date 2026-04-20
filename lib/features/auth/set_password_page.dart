import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/services/recovery_service.dart';
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
enum _SetupStep { choose, securityQuestions, mnemonic, confirm }

class SetPasswordPage extends StatefulWidget {
  final VoidCallback onSetupComplete;
  final Uint8List? importedDek;

  const SetPasswordPage({super.key, required this.onSetupComplete, this.importedDek});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final _storage = SecureStorageService();
  final _crypto = CryptoService();
  final _recovery = RecoveryService();

  // ── Controllers ──────────────────────────────────────────────────────────
  final _credentialController = TextEditingController();
  final _confirmController = TextEditingController();
  final _credentialFocus = FocusNode();
  final _confirmFocus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────────
  _SetupStep _step = _SetupStep.choose;
  bool _usePin = true;

  // ── PIN entry state ────────────────────────────────────────────────────────
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirmingPin = false; // false = entering, true = confirming

  Uint8List? _generatedDEK;
  String _mnemonic = '';
  bool _isLoading = false;
  String _errorMessage = '';
  bool _pdfSaved = false;
  bool _showConfirmPass = false;
  bool _showPass = false;

  // ── Security Questions State ────────────────────────────────────────────────
  int? _question1Index;
  int? _question2Index;
  final _answer1Controller = TextEditingController();
  final _answer2Controller = TextEditingController();

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _fadeCtrl.forward();
    _slideCtrl.forward();
    _generateInitialKeys();
  }

  Future<void> _generateInitialKeys() async {
    final dek = widget.importedDek ?? await _crypto.generateDEK();
    final mnemonic = _crypto.generateMnemonic(dek);
    if (mounted) {
      setState(() {
        _generatedDEK = dek;
        _mnemonic = mnemonic;
      });
    }
  }

  @override
  void dispose() {
    _credentialController.dispose();
    _confirmController.dispose();
    _answer1Controller.dispose();
    _answer2Controller.dispose();
    _credentialFocus.dispose();
    _confirmFocus.dispose();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Transitions ───────────────────────────────────────────────────────────
  Future<void> _animateTransition(VoidCallback onDone) async {
    await _fadeCtrl.reverse();
    onDone();
    _fadeCtrl.forward();
  }

  // ── PIN keypad logic ──────────────────────────────────────────────────────
  void _onPinKey(String digit) {
    setState(() => _errorMessage = '');
    if (!_isConfirmingPin) {
      if (_pin.length < 6) {
        _pin += digit;
        if (_pin.length == 6) setState(() {});
      }
    } else {
      if (_confirmPin.length < 6) {
        _confirmPin += digit;
        if (_confirmPin.length == 6) {
          // Auto-validate when confirm is full
          _validateAndProceed();
        }
      }
    }
    setState(() {});
  }

  void _onPinBackspace() {
    if (!_isConfirmingPin) {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
    } else {
      if (_confirmPin.isNotEmpty) setState(() => _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1));
    }
  }

  void _validateAndProceed() {
    if (_usePin) {
      if (!_isConfirmingPin) {
        if (_pin.length < 6) {
          setState(() => _errorMessage = 'Enter a 6-digit PIN.');
          return;
        }
        setState(() { _isConfirmingPin = true; _errorMessage = ''; });
      } else {
        if (_pin != _confirmPin) {
          setState(() {
            _errorMessage = 'PINs do not match. Try again.';
            _confirmPin = '';
          });
          return;
        }
        _animateTransition(() => setState(() {
          _errorMessage = '';
          _step = _SetupStep.securityQuestions;
        }));
      }
    } else {
      final pass = _credentialController.text;
      final confirm = _confirmController.text;
      if (_getPasswordStrength(pass) == 0) {
        setState(() => _errorMessage = 'Password is too weak.');
        return;
      }
      if (pass.length < 8) {
        setState(() => _errorMessage = 'Password must be at least 8 characters.');
        return;
      }
      if (pass != confirm) {
        setState(() => _errorMessage = 'Passwords do not match.');
        return;
      }
      _animateTransition(() => setState(() {
        _errorMessage = '';
        _step = _SetupStep.securityQuestions;
      }));
    }
  }

  int _getPasswordStrength(String pass) {
    if (pass.isEmpty) return 0; // None
    int strength = 0;
    if (pass.length >= 8) strength++;
    if (RegExp(r'[A-Z]').hasMatch(pass) && RegExp(r'[a-z]').hasMatch(pass)) strength++;
    if (RegExp(r'[0-9]').hasMatch(pass) || RegExp(r'[!@#\$&*~]').hasMatch(pass)) strength++;
    return strength; // 1 = Poor, 2 = Good, 3 = Great
  }

  String _getStrengthText(int strength) {
    switch (strength) {
      case 1: return 'Weak';
      case 2: return 'Good';
      case 3: return 'Great';
      default: return '';
    }
  }

  Color _getStrengthColor(int strength) {
    switch (strength) {
      case 1: return Colors.orange;
      case 2: return Colors.blue;
      case 3: return Colors.green;
      default: return Colors.transparent;
    }
  }

  Future<void> _saveRecoveryPdf() async {
    if (_generatedDEK == null) return;
    setState(() => _isLoading = true);
    try {
      await _recovery.generateAndSaveRecoveryPdf(
        mnemonic: _mnemonic,
        dekHex: _crypto.hexEncode(_generatedDEK!),
      );
      if (mounted) setState(() { _pdfSaved = true; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Failed to generate PDF: $e'; });
    }
  }

  void _goToConfirm() {
    if (!_pdfSaved) {
      setState(() => _errorMessage = 'Please save your Recovery PDF first.');
      return;
    }
    _animateTransition(() => setState(() => _step = _SetupStep.confirm));
  }

  Future<void> _finalizeSetup() async {
    if (_generatedDEK == null) return;
    setState(() { _isLoading = true; _errorMessage = ''; });

    try {
      final credential = _usePin ? _pin : _credentialController.text;
      final salt = await _storage.getDeviceHardwareSalt();

      // Save auth method FIRST
      await _storage.setAuthMethod(_usePin ? 'pin' : 'password');

      // 1. Primary wrap: PIN/Password
      final kek = await _crypto.deriveKEK(pin: credential, salt: salt);
      final wrappedDek = await _crypto.wrapDEK(_generatedDEK!, kek);

      // 2. Secondary wrap: Security Questions
      final combinedAnswers = _answer1Controller.text.trim().toLowerCase() + _answer2Controller.text.trim().toLowerCase();
      final backupKek = await _crypto.deriveKEK(pin: combinedAnswers, salt: salt);
      final backupWrappedDek = await _crypto.wrapDEK(_generatedDEK!, backupKek);

      await _storage.saveWrappedDEK(wrappedDek);
      await _storage.writeString('cs_backup_wrapped_dek', _crypto.hexEncode(Uint8List.fromList(backupWrappedDek)));
      
      // Save Question Indexes so we can ask them later
      await _storage.writeString('cs_security_q1', _question1Index.toString());
      await _storage.writeString('cs_security_q2', _question2Index.toString());

      await _storage.markSetupComplete();

      // Wipe DEK from RAM
      _crypto.wipeRAM(_generatedDEK);

      if (mounted) {
        HapticFeedback.mediumImpact();
        widget.onSetupComplete();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Encryption failure. Please try again.';
        _isLoading = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: _buildStepContent(isDark, primary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(bool isDark, Color primary) {
    switch (_step) {
      case _SetupStep.choose:
        return _buildChooseStep(isDark, primary);
      case _SetupStep.securityQuestions:
        return _buildSecurityQuestionsStep(isDark, primary);
      case _SetupStep.mnemonic:
        return _buildMnemonicStep(isDark, primary);
      case _SetupStep.confirm:
        return _buildConfirmStep(isDark, primary);
    }
  }

  // ── STEP 1: Choose Auth Method ────────────────────────────────────────────
  Widget _buildChooseStep(bool isDark, Color primary) {
    return Column(
      children: [
        // ── Header ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.shield_lefthalf_fill, color: primary, size: 44),
              const SizedBox(height: 14),
              Text(
                _isConfirmingPin ? 'Confirm Your PIN' : (_usePin ? 'Create a PIN' : 'Create a Password'),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                _isConfirmingPin 
                  ? 'Enter your PIN one more time to verify.' 
                  : (_usePin ? 'Choose a 6-digit PIN to protect your vault.' : 'Choose a strong password to protect your vault.'),
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54),
              ),
              const SizedBox(height: 20),

              // ── Step progress bar ───────────────────────────────────────
              _buildStepIndicator(isDark, primary, 0),
              const SizedBox(height: 20),

              // ── Toggle (only shown on first PIN entry) ─────────────────
              if (!_isConfirmingPin) _buildAuthToggle(isDark, primary),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Input Area ────────────────────────────────────────────────────
        if (_usePin) ...[
          _buildPinDots(
            isDark, 
            primary, 
            current: _isConfirmingPin ? _confirmPin : _pin,
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _errorMessage.isNotEmpty
              ? _buildErrorBanner()
              : const SizedBox(height: 44),
          ),
          const Spacer(),
          _buildKeypad(isDark, primary),
          const SizedBox(height: 32),
        ] else ...[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  _buildPasswordField(
                    controller: _credentialController,
                    focus: _credentialFocus,
                    label: 'Vault Password',
                    isDark: isDark,
                    showText: _showPass,
                    onToggleShow: () => setState(() => _showPass = !_showPass),
                    hint: 'Min. 8 characters',
                    onSubmitted: (_) => FocusScope.of(context).requestFocus(_confirmFocus),
                  ),
                  const SizedBox(height: 16),
                  _buildPasswordField(
                    controller: _confirmController,
                    focus: _confirmFocus,
                    label: 'Confirm Password',
                    isDark: isDark,
                    showText: _showConfirmPass,
                    onToggleShow: () => setState(() => _showConfirmPass = !_showConfirmPass),
                    hint: 'Re-enter password',
                    onSubmitted: (_) => _validateAndProceed(),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _credentialController,
                    builder: (context, value, _) {
                      final strength = _getPasswordStrength(value.text);
                      return Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: strength == 0 ? 0 : strength / 3,
                                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor(strength)),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _getStrengthText(strength).isEmpty ? 'Too Weak' : _getStrengthText(strength),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _getStrengthColor(strength)),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage.isNotEmpty) _buildErrorBanner(),
                  const SizedBox(height: 24),
                  _infoCard(
                    CupertinoIcons.info, 
                    'Your password derives a unique key. We never store it — only an encrypted form of your vault key.',
                    isDark,
                  ),
                  const SizedBox(height: 32),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _credentialController,
                    builder: (context, value, child) {
                      final strength = _getPasswordStrength(value.text);
                      return _buildPrimaryButton(
                        label: 'Continue',
                        primary: strength > 0 ? primary : Colors.grey,
                        onTap: strength > 0 ? _validateAndProceed : null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── STEP 1.5: Security Questions ──────────────────────────────────────────
  Widget _buildSecurityQuestionsStep(bool isDark, Color primary) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.person_3_fill, color: primary, size: 44),
              const SizedBox(height: 14),
              Text('Security Questions', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 6),
              Text('In case you forget your ${_usePin ? 'PIN' : 'password'}, these answers will help you regain block-level access to your vault.', style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 20),
              // We reuse 0 for indicator visually, or just make it 0.5? Let's just use 0.
              _buildStepIndicator(isDark, primary, 0),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuestionPicker(1, _question1Index, (idx) {
                  setState(() => _question1Index = idx);
                }, isDark),
                const SizedBox(height: 12),
                if (_question1Index != null)
                  _buildAnswerField(_answer1Controller, isDark),
                const SizedBox(height: 24),

                _buildQuestionPicker(2, _question2Index, (idx) {
                  setState(() => _question2Index = idx);
                }, isDark),
                const SizedBox(height: 12),
                if (_question2Index != null)
                  _buildAnswerField(_answer2Controller, isDark),

                const SizedBox(height: 24),
                if (_errorMessage.isNotEmpty) _buildErrorBanner(),
                const SizedBox(height: 32),
                _buildPrimaryButton(
                  label: 'Save & Continue',
                  primary: (_question1Index != null && _question2Index != null && _answer1Controller.text.trim().isNotEmpty && _answer2Controller.text.trim().isNotEmpty) ? primary : Colors.grey,
                  onTap: () {
                    if (_question1Index == null || _question2Index == null) {
                      setState(() => _errorMessage = 'Please select both questions.');
                      return;
                    }
                    if (_question1Index == _question2Index) {
                      setState(() => _errorMessage = 'Please select two distinct questions.');
                      return;
                    }
                    if (_answer1Controller.text.trim().isEmpty || _answer2Controller.text.trim().isEmpty) {
                      setState(() => _errorMessage = 'Please answer both questions.');
                      return;
                    }
                    _animateTransition(() => setState(() {
                      _errorMessage = '';
                      _step = _SetupStep.mnemonic;
                    }));
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionPicker(int number, int? selectedIndex, ValueChanged<int> onChanged, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Question $number', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: selectedIndex,
              hint: Text('Select a security question', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
              dropdownColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
              items: List.generate(kSecurityQuestions.length, (i) {
                return DropdownMenuItem<int>(
                  value: i,
                  child: Text(kSecurityQuestions[i], style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                );
              }),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerField(TextEditingController controller, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Your answer...',
          hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ── STEP 2: Mnemonic ──────────────────────────────────────────────────────
  Widget _buildMnemonicStep(bool isDark, Color primary) {
    final words = _mnemonic.isEmpty ? List.filled(24, '...') : _mnemonic.split(' ');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.doc_text_fill, color: primary, size: 44),
              const SizedBox(height: 14),
              Text('Recovery Phrase', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 6),
              Text('These 24 words are the only way to restore your vault. Save your PDF before continuing.', style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 20),
              _buildStepIndicator(isDark, primary, 1),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 2.4, crossAxisSpacing: 6, mainAxisSpacing: 6,
              ),
              itemCount: words.length,
              itemBuilder: (context, i) => Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text('${i + 1}. ${words[i]}', 
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, 
                      color: isDark ? Colors.white : Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
          child: Column(
            children: [
              if (_errorMessage.isNotEmpty) ...[
                _buildErrorBanner(),
                const SizedBox(height: 8),
              ],
              _buildSavePdfButton(isDark, primary),
              const SizedBox(height: 12),
              _buildPrimaryButton(
                label: 'I Have Saved My PDF',
                primary: _pdfSaved ? primary : Colors.grey,
                onTap: _pdfSaved ? _goToConfirm : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  // ── STEP 3: Confirm & Secure ──────────────────────────────────────────────
  Widget _buildConfirmStep(bool isDark, Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Icon(CupertinoIcons.checkmark_shield_fill, color: Colors.green, size: 44),
          const SizedBox(height: 14),
          Text('Final Secure Check', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 6),
          Text('Review your setup before locking the vault.', style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 20),
          _buildStepIndicator(isDark, primary, 2),
          const SizedBox(height: 32),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green, size: 72),
                const SizedBox(height: 24),
                Text(
                  'Vault Architecture Ready',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your Master Key (DEK) is ready to be locked with your ${_usePin ? 'PIN' : 'password'}. '
                  'Your Recovery PDF is your backup — keep it safe offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(height: 32),
                _infoCard(CupertinoIcons.lock_shield, 'After this step, only your ${_usePin ? 'PIN' : 'password'} or recovery phrase can unlock your vault. We have no access.', isDark),
              ],
            ),
          ),
          if (_errorMessage.isNotEmpty) ...[
            _buildErrorBanner(),
            const SizedBox(height: 12),
          ],
          _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : _buildPrimaryButton(label: 'Create Vault', primary: primary, onTap: _finalizeSetup),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Reusable Widgets ──────────────────────────────────────────────────────
  Widget _buildStepIndicator(bool isDark, Color primary, int currentStep) {
    return Row(
      children: List.generate(3, (i) => Expanded(
        child: Container(
          height: 3,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: i <= currentStep ? primary : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black12),
          ),
        ),
      )),
    );
  }

  Widget _buildAuthToggle(bool isDark, Color primary) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleOption(label: '6-Digit PIN', icon: CupertinoIcons.number, active: _usePin, isDark: isDark, primary: primary, onTap: () {
            setState(() { _usePin = true; _pin = ''; _confirmPin = ''; _isConfirmingPin = false; _errorMessage = ''; });
          })),
          Expanded(child: _toggleOption(label: 'Password', icon: CupertinoIcons.keyboard, active: !_usePin, isDark: isDark, primary: primary, onTap: () {
            setState(() { _usePin = false; _credentialController.clear(); _confirmController.clear(); _errorMessage = ''; });
          })),
        ],
      ),
    );
  }

  Widget _toggleOption({required String label, required IconData icon, required bool active, required bool isDark, required Color primary, required VoidCallback onTap}) {
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
            Icon(icon, size: 16, color: active ? Colors.white : (isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, 
              color: active ? Colors.white : (isDark ? Colors.white54 : Colors.black54))),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDots(bool isDark, Color primary, {required String current}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < current.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? primary : Colors.transparent,
            border: Border.all(color: filled ? primary : (isDark ? Colors.white38 : Colors.black26), width: 1.5),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad(bool isDark, Color primary) {
    const keys = [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']];
    return Column(
      children: keys.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((key) {
          if (key == '') return const SizedBox(width: 88, height: 88);
          final isDelete = key == '⌫';
          return GestureDetector(
            onTap: () => isDelete ? _onPinBackspace() : _onPinKey(key),
            child: Container(
              width: 88,
              height: 88,
              margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: isDelete
                  ? Icon(CupertinoIcons.delete_left, color: isDark ? Colors.white70 : Colors.black54, size: 22)
                  : Text(key, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w400, color: isDark ? Colors.white : Colors.black87)),
              ),
            ),
          );
        }).toList(),
      )).toList(),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    required bool isDark,
    required bool showText,
    required VoidCallback onToggleShow,
    String? hint,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
          ),
          child: TextField(
            controller: controller,
            focusNode: focus,
            obscureText: !showText,
            keyboardType: TextInputType.visiblePassword,
            style: TextStyle(fontSize: 17, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffix: GestureDetector(
                onTap: onToggleShow,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(showText ? CupertinoIcons.eye_slash : CupertinoIcons.eye, 
                    size: 18, color: Colors.grey),
                ),
              ),
            ),
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }

  Widget _buildSavePdfButton(bool isDark, Color primary) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: _isLoading ? null : _saveRecoveryPdf,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _pdfSaved ? Colors.green.withValues(alpha: 0.1) : primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _pdfSaved ? Colors.green : primary, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const CupertinoActivityIndicator()
            else ...[
              Icon(_pdfSaved ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.doc_text_viewfinder, 
                size: 18, color: _pdfSaved ? Colors.green : primary),
              const SizedBox(width: 10),
              Text(
                _pdfSaved ? 'Recovery PDF Saved ✓' : 'Save Recovery PDF',
                style: TextStyle(fontWeight: FontWeight.bold, 
                  color: _pdfSaved ? Colors.green : primary, fontSize: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({required String label, required Color primary, VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: CupertinoButton(
        color: primary,
        borderRadius: BorderRadius.circular(14),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
      ),
    );
  }

  Widget _infoCard(IconData icon, String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.darkPrimary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.exclamationmark_circle, color: Colors.red, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    );
  }
}
