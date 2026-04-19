import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/auth_service.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/auth/set_password_page.dart';
import 'package:cipherscribe/features/vault/vault_page.dart';
import 'package:cipherscribe/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cipherscribe/features/vault/data/datasources/vault_local_datasource.dart';
import 'package:cipherscribe/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:cipherscribe/features/vault/domain/usecases/vault_usecases.dart';
import 'package:cipherscribe/core/database/database.dart';
import 'package:cipherscribe/services/crypto_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthGate — entry router + unlock screen
// ─────────────────────────────────────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final _authService = AuthService();
  final _storage = SecureStorageService();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;           // initial async check
  bool _isVerifying = false;        // during password check
  bool _isFirstLaunch = true;
  bool _obscurePassword = true;
  String _errorMessage = '';
  int _failedAttempts = 0;

  // ── Controllers ──────────────────────────────────────────────────────────
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _initCheck();
  }

  Future<void> _initCheck() async {
    final setupDone = await _storage.isSetupComplete();
    if (!mounted) return;
    setState(() {
      _isFirstLaunch = !setupDone;
      _isLoading = false;
    });
    _fadeCtrl.forward();

    // Auto-trigger biometrics for returning users
    if (!_isFirstLaunch) {
      _tryBiometrics();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    _shakeCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Biometrics ────────────────────────────────────────────────────────────
  Future<void> _tryBiometrics() async {
    final canCheck = await _authService.canCheckBiometrics();
    if (!canCheck || !mounted) return;
    final success =
        await _authService.authenticateWithBiometrics('Unlock CipherScribe');
    if (success && mounted) _unlockVault();
  }

  // ── Password unlock ───────────────────────────────────────────────────────
  Future<void> _verifyPassword() async {
    final pw = _passwordController.text;
    if (pw.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });

    final ok = await _storage.verifyPassword(pw);

    if (!mounted) return;

    if (ok) {
      HapticFeedback.heavyImpact();
      _unlockVault();
    } else {
      _failedAttempts++;
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _isVerifying = false;
        _passwordController.clear();
        _errorMessage = _failedAttempts >= 5
            ? 'Too many attempts. Use biometrics or contact support.'
            : 'Incorrect password. ${5 - _failedAttempts} attempt(s) remaining.';
      });
    }
  }

  // ── Navigate to Vault ─────────────────────────────────────────────────────
  void _unlockVault() {
    final cryptoService = CryptoService();
    final database = AppDatabase('dummy_session_db_password');
    final dataSource = VaultLocalDataSourceImpl(
      database: database,
      cryptoService: cryptoService,
    );
    final repository = VaultRepositoryImpl(dataSource);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => BlocProvider<VaultBloc>(
          create: (_) => VaultBloc(
            getDocuments: GetDocumentsUseCase(repository),
            importDocument: ImportDocumentUseCase(repository),
          )..add(LoadVaultDocuments()),
          child: const VaultPage(),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Loading indicator while checking setup state
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(
          child: CupertinoActivityIndicator(color: AppColors.darkPrimary),
        ),
      );
    }

    // First-launch → setup flow
    if (_isFirstLaunch) {
      return SetPasswordPage(
        onSetupComplete: () {
          setState(() => _isFirstLaunch = false);
          _fadeCtrl.forward(from: 0);
          _tryBiometrics();
        },
      );
    }

    // Returning user → unlock screen
    return _buildUnlockScreen();
  }

  Widget _buildUnlockScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

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
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          const SizedBox(height: 64),
                          _buildLockIcon(isDark, primary),
                          const SizedBox(height: 28),
                          _buildTitle(isDark),
                          const SizedBox(height: 48),
                          _buildPasswordField(isDark, primary),
                          const SizedBox(height: 16),
                          if (_errorMessage.isNotEmpty) _buildErrorBanner(),
                          const SizedBox(height: 16),
                          _buildUnlockButton(primary),
                          const SizedBox(height: 20),
                          _buildBiometricsButton(isDark, primary),
                          const Spacer(),
                          _buildFooter(isDark),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Lock icon with pulse glow ─────────────────────────────────────────────
  Widget _buildLockIcon(bool isDark, Color primary) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        final offset =
            _shakeCtrl.isAnimating ? ((_shakeAnim.value * 2 - 1) * 8) : 0.0;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary.withValues(alpha: 0.10),
          border: Border.all(color: primary.withValues(alpha: 0.30), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.18),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.lock_shield_fill,
          size: 38,
          color: primary,
        ),
      ),
    );
  }

  Widget _buildTitle(bool isDark) {
    return Column(
      children: [
        Text(
          'CipherScribe',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: isDark ? AppColors.darkTitleText : AppColors.lightTitleText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your master password to unlock',
          style: TextStyle(
            fontSize: 15,
            color: isDark
                ? AppColors.darkDescriptionText
                : AppColors.lightDescriptionText,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(bool isDark, Color primary) {
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final bodyText =
        isDark ? AppColors.darkBodyText : AppColors.lightBodyText;
    final desc = isDark
        ? AppColors.darkDescriptionText
        : AppColors.lightDescriptionText;

    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        final offset =
            _shakeCtrl.isAnimating ? ((_shakeAnim.value * 2 - 1) * 6) : 0.0;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _errorMessage.isNotEmpty
                ? AppColors.darkError.withValues(alpha: 0.6)
                : _passwordFocus.hasFocus
                    ? primary.withValues(alpha: 0.55)
                    : (isDark ? AppColors.darkDivider : AppColors.lightDivider),
            width: 1.2,
          ),
          boxShadow: [
            if (_passwordFocus.hasFocus)
              BoxShadow(
                color: primary.withValues(alpha: 0.1),
                blurRadius: 12,
                spreadRadius: 1,
              ),
          ],
        ),
        child: TextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 17, color: bodyText),
          decoration: InputDecoration(
            hintText: 'Master Password',
            hintStyle: TextStyle(color: desc, fontSize: 16),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            suffixIcon: GestureDetector(
              onTap: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  _obscurePassword
                      ? CupertinoIcons.eye_slash_fill
                      : CupertinoIcons.eye_fill,
                  size: 19,
                  color: desc,
                ),
              ),
            ),
          ),
          onSubmitted: (_) => _verifyPassword(),
        ),
      ),
    );
  }

  Widget _buildUnlockButton(Color primary) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: _isVerifying
          ? Center(
              child:
                  CupertinoActivityIndicator(color: primary, radius: 13))
          : CupertinoButton(
              color: primary,
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              onPressed: _verifyPassword,
              child: const Text(
                'Unlock Vault',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  Widget _buildBiometricsButton(bool isDark, Color primary) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: _tryBiometrics,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.person_crop_circle_fill,
            size: 18,
            color: primary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 7),
          Text(
            'Use Face ID / Fingerprint',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: primary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkError.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkError.withValues(alpha: 0.35)),
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Text(
      'Zero-knowledge · Offline-only · AES-256-GCM',
      style: TextStyle(
        fontSize: 11.5,
        letterSpacing: 0.3,
        color: isDark
            ? AppColors.darkDisabledText
            : AppColors.lightDisabledText,
      ),
    );
  }
}
