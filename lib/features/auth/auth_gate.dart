import 'package:cryptography/cryptography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/auth/set_password_page.dart';
import 'package:cipherscribe/features/vault/presentation/page/vault_page.dart';
import 'package:cipherscribe/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cipherscribe/features/vault/data/datasources/vault_local_datasource.dart';
import 'package:cipherscribe/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:cipherscribe/features/vault/domain/usecases/vault_usecases.dart';
import 'package:cipherscribe/core/database/database.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/features/auth/restore_vault_page.dart';
import 'package:cipherscribe/features/auth/set_password_page.dart'
    show kSecurityQuestions, SetPasswordPage;
import 'package:cipherscribe/core/utils/lifecycle_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthGate — entry router + unlock screen
// ─────────────────────────────────────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Services ──────────────────────────────────────────────────────────────
  final _storage = SecureStorageService();
  final _crypto = CryptoService();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true; // initial async check
  bool _isVerifying = false; // during password check
  bool _isFirstLaunch = true;
  bool _isNuked = false;
  String _errorMessage = '';
  Uint8List? _sessionDEK;

  // ── PIN State ─────────────────────────────────────────────────────────────
  String _pin = '';
  static const int _pinLength = 6;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _shakeCtrl;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _initCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lockApp();
    }
  }

  void _lockApp() {
    if (LifecycleManager.isIntentionalLeave) return;

    if (_sessionDEK != null) {
      _crypto.wipeRAM(_sessionDEK);
      _sessionDEK = null;
      if (mounted) {
        // Pop back to unlock screen if inside vault
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() {
          _pin = '';
          _errorMessage = 'Session expired for security.';
        });
      }
    }
  }

  String _authMethod = 'pin';
  final _passwordController = TextEditingController();

  Future<void> _initCheck() async {
    final setupDone = await _storage.isSetupComplete();
    final wrappedDek = await _storage.getWrappedDEK();
    final method = await _storage.getAuthMethod();

    if (mounted) {
      setState(() {
        _isFirstLaunch = !setupDone;
        _isNuked = setupDone && wrappedDek == null;
        _authMethod = method;
        _isLoading = false;
      });
      _fadeCtrl.forward();
      // if (!_isFirstLaunch && !_isNuked) _tryBiometrics();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_sessionDEK != null) _crypto.wipeRAM(_sessionDEK);
    _shakeCtrl.dispose();
    _fadeCtrl.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── PIN Unlock ────────────────────────────────────────────────────────────
  void _onKeyPress(String val) {
    if (_pin.length < _pinLength) {
      setState(() => _pin += val);
      if (_pin.length == _pinLength) _verifyAuth(_pin);
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty)
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
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

      if (mounted) {
        _sessionDEK = dek;
        await _storage.resetFailedAttempts();
        HapticFeedback.mediumImpact();
        _unlockVault(dek);
      }
    } catch (e) {
      final attempts = await _storage.incrementFailedAttempts();
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _isVerifying = false;
        _pin = '';
        _passwordController.clear();
        _errorMessage = attempts >= 10
            ? 'Vault Nuked: Too many failed attempts.'
            : 'Incorrect ${_authMethod == 'pin' ? 'PIN' : 'password'}. ${10 - attempts} attempts remaining.';
        if (attempts >= 10) _isNuked = true;
      });
    }
  }

  void _unlockVault(Uint8List dek) {
    final hexKey = _crypto.hexEncode(dek);
    final database = AppDatabase(hexKey); // SQLCipher encrypted with the DEK
    final dataSource = VaultLocalDataSourceImpl(
      database: database,
      cryptoService: _crypto,
    );
    final repository = VaultRepositoryImpl(dataSource);

    Navigator.of(context)
        .pushReplacement(
          CupertinoPageRoute(
            builder: (context) => BlocProvider<VaultBloc>(
              create: (_) => VaultBloc(
                getDocuments: GetDocumentsUseCase(repository),
                importDocument: ImportDocumentUseCase(repository),
                deleteDocument: DeleteDocumentUseCase(repository),
                renameDocument: RenameDocumentUseCase(repository),
                sessionKey: SecretKey(dek),
              )..add(LoadVaultDocuments()),
              child: const VaultPage(),
            ),
          ),
        )
        .then((_) {
          // When user returns from Vault (locks manually)
          _lockApp();
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: CupertinoActivityIndicator()),
      );
    if (_isFirstLaunch) return SetPasswordPage(onSetupComplete: _initCheck);
    if (_isNuked) return _buildRecoveryScreen();
    return _buildUnlockScreen();
  }

  Widget _buildRecoveryScreen() {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.xmark_shield_fill,
                color: Colors.red,
                size: 80,
              ),
              const SizedBox(height: 24),
              const Text(
                'Vault Wiped',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This vault was nuked due to security violations or failed PIN attempts. Access is only possible via your 24-word recovery phrase.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 40),
              CupertinoButton.filled(
                child: const Text('Restore from Recovery Phrase'),
                onPressed: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => RestoreVaultPage(
                        onRestoreComplete: () {
                          Navigator.pop(context);
                          _initCheck();
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        body: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                height:
                    MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
                child: Column(
                  children: [
                    const SizedBox(height: 52),
                    _buildLockIcon(isDark),
                    const SizedBox(height: 20),
                    Text(
                      'CipherScribe',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enter ${_authMethod == 'pin' ? 'PIN' : 'password'} to unlock vault',
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              child: Text(
                                _errorMessage,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
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
                          onPressed: () =>
                              _verifyAuth(_passwordController.text),
                          child: const SizedBox(
                            width: double.infinity,
                            child: Text(
                              'Unlock',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
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
                        style: const TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                    'Answer these to gain temporary access and reset your PIN/Password.',
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
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (context) => RestoreVaultPage(
                              onRestoreComplete: () {
                                Navigator.pop(context);
                                _initCheck();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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
        _sessionDEK = dek;
        await _storage.resetFailedAttempts();
        HapticFeedback.mediumImpact();

        // Wipe original PIN mapping so user is forced to set it again
        await _storage.deleteKey('cs_wrapped_dek');
        await _storage.deleteKey('cs_auth_method');
        await _storage.deleteKey('cs_setup_complete');

        // Push setup process to force them to create a new PIN and re-wrap the DEK
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(
            builder: (context) =>
                SetPasswordPage(onSetupComplete: _initCheck, importedDek: dek),
          ),
        );
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

  Widget _buildLockIcon(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkPrimary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        CupertinoIcons.lock_fill,
        color: AppColors.darkPrimary,
        size: 40,
      ),
    );
  }

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

  // Widget _keypadButton(String key, bool isDark) {
  //   if (key == '') return const SizedBox(width: 80, height: 80);
  //   return CupertinoButton(
  //     padding: EdgeInsets.zero,
  //     onPressed: () => key == '⌫' ? _onBackspace() : _onKeyPress(key),
  //     child: Container(
  //       width: 80,
  //       height: 80,
  //       margin: const EdgeInsets.all(8),
  //       decoration: BoxDecoration(
  //         color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
  //         borderRadius: BorderRadius.circular(16),
  //       ),
  //       child: Center(child: Text(key, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400, color: Colors.blue))),
  //     ),
  //   );
  // }

  Widget _keypadButton(String key, bool isDark) {
    if (key == '') return const Expanded(child: SizedBox());

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          // Visual feedback is key for UX
          onPressed: () => key == '⌫' ? _onBackspace() : _onKeyPress(key),
          child: Container(
            // We don't set a height here; we let the Column/Expanded handle it
            // OR we set a responsive height using MediaQuery
            height: 65, // A standard "Paytm" rectangular height
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
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _passwordController,
          obscureText: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, letterSpacing: 2),
          decoration: const InputDecoration(
            hintText: 'Password',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 16),
            hintStyle: TextStyle(letterSpacing: 0),
          ),
          onSubmitted: (val) => _verifyAuth(val),
        ),
      ),
    );
  }
}
