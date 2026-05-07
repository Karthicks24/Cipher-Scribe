import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/auth/set_password_page.dart'
    show kSecurityQuestions;
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:file_picker/file_picker.dart';
import 'dart:io';

enum VerificationLevel { standard, recoveryOnly }

class VerifyAuthPage extends StatefulWidget {
  final VerificationLevel level;

  const VerifyAuthPage({super.key, this.level = VerificationLevel.standard});

  @override
  State<VerifyAuthPage> createState() => _VerifyAuthPageState();
}

class _VerifyAuthPageState extends State<VerifyAuthPage>
    with TickerProviderStateMixin {
  final _storage = SecureStorageService();
  final _crypto = CryptoService();
  final _localAuth = LocalAuthentication();

  String _authMethod = 'pin';
  int _pinLength = 6;
  bool _isLoading = true;

  String _pin = '';
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _errorMessage = '';
  bool _isVerifying = false;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  // Recovery Phrase State (used if level == recoveryOnly or if they click forgot)
  final _phraseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim =
        Tween<double>(
            begin: 0,
            end: 24,
          ).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeCtrl)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _shakeCtrl.reverse();
            }
          });

    if (widget.level == VerificationLevel.standard) {
      _initCheck();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _initCheck() async {
    final method = await _storage.getAuthMethod();
    if (mounted) {
      setState(() {
        _authMethod = method ?? 'pin';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _passwordController.dispose();
    _phraseController.dispose();
    super.dispose();
  }

  void _onKeyPress(String val) {
    if (_pin.length < _pinLength) {
      setState(() => _pin += val);
      if (_pin.length == _pinLength) _verifyAuth(_pin);
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _verifyAuth(String candidate) async {
    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });

    try {
      final wrappedDekBytes = await _storage.getWrappedDEK();
      if (wrappedDekBytes == null) throw Exception('Vault Nuked');

      final salt = await _storage.getDeviceHardwareSalt();
      final kek = await _crypto.deriveKEK(pin: candidate, salt: salt);
      final dek = await _crypto.unwrapDEK(wrappedDekBytes, kek);

      // Legacy Support: Save DEK Hash if missing
      final storedHash = await _storage.getDekHash();
      if (storedHash == null) {
        await _storage.saveDekHash(dek);
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, dek);
      }
    } catch (e) {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _pin = '';
        _passwordController.clear();
        _errorMessage =
            'Incorrect ${_authMethod == 'pin' ? 'PIN' : 'password'}.';
      });
    }
  }

  Future<void> _verifyRecoveryPhrase() async {
    final phrase = _phraseController.text.trim();
    if (phrase.split(' ').length != 24) {
      setState(() => _errorMessage = 'Invalid 24-word recovery phrase.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });

    try {
      final dek = await _crypto.dekFromMnemonic(phrase);
      
      // Validate DEK Hash if exists
      final storedHash = await _storage.getDekHash();
      if (storedHash != null) {
        final candidateHash = sha256.convert(dek).toString();
        if (candidateHash != storedHash) {
          throw Exception('Incorrect recovery phrase for this vault.');
        }
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, dek);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = e.toString().contains('Incorrect') ? e.toString() : 'Invalid recovery phrase.';
      });
    }
  }

  Future<void> _importRecoveryPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.single.path == null) return;

    if (!mounted) return;
    setState(() => _isVerifying = true);

    try {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final document = syncfusion.PdfDocument(inputBytes: bytes);
      final text = syncfusion.PdfTextExtractor(document).extractText();
      document.dispose();

      // Extract 24 words from the text
      // We look for the words in the format "1. word" "2. word" etc.
      final phraseMatch = RegExp(r'\d+\.\s+([a-z]+)').allMatches(text);
      if (phraseMatch.length >= 24) {
        final words = phraseMatch.map((m) => m.group(1)!).toList().sublist(0, 24);
        _phraseController.text = words.join(' ');
      } else {
        // Fallback: look for DEK Hex
        final hexMatch = RegExp(r'([A-Fa-f0-9\s]{64,})').firstMatch(text);
        if (hexMatch != null) {
          final hex = hexMatch.group(1)!.replaceAll(RegExp(r'\s+'), '');
          if (hex.length == 64) {
             final dek = _crypto.hexDecode(hex);
             final mnemonic = _crypto.generateMnemonic(dek);
             _phraseController.text = mnemonic;
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = '';
        });
        if (_phraseController.text.split(' ').length == 24) {
           _verifyRecoveryPhrase();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Failed to parse PDF. Please type manually.';
      });
    }
  }

  Future<void> _showForgotPassword() async {
    final q1IdxStr = await _storage.readString('cs_security_q1');
    final q2IdxStr = await _storage.readString('cs_security_q2');
    final backupDekHex = await _storage.readString('cs_backup_wrapped_dek');

    if (q1IdxStr == null || q2IdxStr == null || backupDekHex == null) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Security questions not set up. You must use the Recovery Phrase flow.',
        );
      }
      return;
    }

    final q1Idx = int.parse(q1IdxStr);
    final q2Idx = int.parse(q2IdxStr);

    final ans1Ctrl = TextEditingController();
    final ans2Ctrl = TextEditingController();

    if (!mounted) return;

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkBackground
                  : AppColors.lightBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Security Questions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Answer these to verify your identity.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    kSecurityQuestions[q1Idx],
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: ans1Ctrl,
                    padding: const EdgeInsets.all(12),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    kSecurityQuestions[q2Idx],
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: ans2Ctrl,
                    padding: const EdgeInsets.all(12),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      child: const Text('Verify Answers'),
                      onPressed: () async {
                        Navigator.pop(context);
                        _verifySecurityQuestions(
                          ans1Ctrl.text.trim().toLowerCase(),
                          ans2Ctrl.text.trim().toLowerCase(),
                          backupDekHex,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: CupertinoButton(
                      child: const Text(
                        'Use Recovery Phrase instead',
                        style: TextStyle(fontSize: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          // Change level dynamically or push new page
                          Navigator.pushReplacement(
                            context,
                            CupertinoPageRoute(
                              builder: (context) => const VerifyAuthPage(
                                level: VerificationLevel.recoveryOnly,
                              ),
                            ),
                          ).then((val) {
                            if (val != null) {
                              Navigator.pop(context, val);
                            }
                          });
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _verifySecurityQuestions(
    String ans1,
    String ans2,
    String backupDekHex,
  ) async {
    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });
    try {
      final combinedAnswers = ans1 + ans2;
      final salt = await _storage.getDeviceHardwareSalt();
      final backupKek = await _crypto.deriveKEK(
        pin: combinedAnswers,
        salt: salt,
      );
      final dek = await _crypto.unwrapDEK(
        _crypto.hexDecode(backupDekHex),
        backupKek,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, dek);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Incorrect security answers.';
        });
        HapticFeedback.vibrate();
        _shakeCtrl.forward(from: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CupertinoActivityIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        appBar: CupertinoNavigationBar(
          backgroundColor:
              (isDark ? AppColors.darkBackground : AppColors.lightBackground)
                  .withValues(alpha: 0.9),
          middle: const Text('Verify Identity'),
        ),
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  _shakeAnim.value * (1 - (_shakeAnim.value / 24)),
                  0,
                ),
                child: child,
              );
            },
            child: widget.level == VerificationLevel.standard
                ? _buildStandardAuth(isDark)
                : _buildRecoveryAuth(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardAuth(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 52),
        const Icon(
          CupertinoIcons.lock_shield_fill,
          size: 48,
          color: AppColors.darkPrimary,
        ),
        const SizedBox(height: 20),
        Text(
          'Re-authentication Required',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter ${_authMethod == 'pin' ? 'PIN' : 'password'} to continue',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 36),
        if (_authMethod == 'pin')
          _buildPinDots()
        else
          _buildPasswordField(isDark),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _errorMessage.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )
              : const SizedBox(height: 20),
        ),
        const Spacer(),
        if (_isVerifying)
          const Padding(
            padding: EdgeInsets.only(bottom: 48),
            child: CupertinoActivityIndicator(),
          )
        else if (_authMethod == 'pin')
          _buildKeypad(isDark)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: CupertinoButton(
              color: AppColors.darkPrimary,
              borderRadius: BorderRadius.circular(14),
              onPressed: (_passwordController.text.length < 8)
                  ? null
                  : () => _verifyAuth(_passwordController.text),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'Verify',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: (_passwordController.text.length < 8)
                        ? Colors.white54
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        CupertinoButton(
          onPressed: _showForgotPassword,
          child: Text(
            'Forgot ${_authMethod == 'pin' ? 'PIN' : 'Password'}?',
            style: const TextStyle(color: AppColors.darkPrimary, fontSize: 14),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildRecoveryAuth(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Icon(
            CupertinoIcons.doc_text_fill,
            size: 48,
            color: AppColors.darkPrimary,
          ),
          const SizedBox(height: 20),
          Text(
            'Recovery Phrase',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your 24-word recovery phrase to continue.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 36),
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
              controller: _phraseController,
              maxLines: 5,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'word1 word2 word3 ... word24',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_errorMessage.isNotEmpty)
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          const Spacer(),
          if (!_isVerifying)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _importRecoveryPdf,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.darkPrimary),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.doc_text_viewfinder, size: 20),
                        SizedBox(width: 10),
                        Text('Import from Recovery PDF'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isVerifying)
            const Center(child: CupertinoActivityIndicator())
          else
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: AppColors.darkPrimary,
                borderRadius: BorderRadius.circular(14),
                onPressed: _verifyRecoveryPhrase,
                child: const Text(
                  'Verify',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- UI Helpers ---

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinLength, (i) {
        final active = i < _pin.length;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.darkPrimary : Colors.transparent,
            border: Border.all(color: AppColors.darkPrimary, width: 1.5),
          ),
        );
      }),
    );
  }

  Widget _buildPasswordField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                placeholder: 'Password',
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: const BoxDecoration(color: Colors.transparent),
                onChanged: (val) => setState(() {}),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              child: Icon(
                _obscurePassword
                    ? CupertinoIcons.eye_slash_fill
                    : CupertinoIcons.eye_fill,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(bool isDark) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keys
          .map(
            (row) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((key) => _keypadButton(key, isDark)).toList(),
            ),
          )
          .toList(),
    );
  }

  Widget _keypadButton(String key, bool isDark) {
    if (key == '') return const Expanded(child: SizedBox());
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.8,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: InkWell(
            onTap: () {
              if (key == '⌫') {
                HapticFeedback.mediumImpact();
                _onBackspace();
              } else {
                HapticFeedback.lightImpact();
                _onKeyPress(key);
              }
            },
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.blue.withValues(alpha: 0.3), // ripple
            highlightColor: Colors.blue.withValues(alpha: 0.1),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: key == '⌫'
                    ? Icon(
                        CupertinoIcons.delete_left,
                        color: isDark ? Colors.white70 : Colors.black87,
                        size: 24,
                      )
                    : Text(
                        key,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
