import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/auth/set_password_page.dart'
    show kSecurityQuestions;
import 'dart:typed_data';

/// A page that allows users to update their vault security questions.
///
/// This page requires a [importedDek] which is the decrypted Master Key (DEK).
/// It re-wraps the DEK with the new security answers and updates secure storage.
class UpdateSecurityQuestionsPage extends StatefulWidget {
  final Uint8List importedDek;

  const UpdateSecurityQuestionsPage({super.key, required this.importedDek});

  @override
  State<UpdateSecurityQuestionsPage> createState() =>
      _UpdateSecurityQuestionsPageState();
}

class _UpdateSecurityQuestionsPageState
    extends State<UpdateSecurityQuestionsPage> {
  // --- Services ---
  final _storage = SecureStorageService();
  final _crypto = CryptoService();

  // --- State Variables ---
  int? _question1Index = 0;
  int? _question2Index = 1;
  final _answer1Controller = TextEditingController();
  final _answer2Controller = TextEditingController();

  String _errorMessage = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _answer1Controller.dispose();
    _answer2Controller.dispose();
    super.dispose();
  }

  /// Validates the answers and saves the new security questions to secure storage.
  Future<void> _saveQuestions() async {
    // 1. Basic validation
    if (_question1Index == null || _question2Index == null) {
      setState(() => _errorMessage = 'Please select both questions.');
      return;
    }
    if (_question1Index == _question2Index) {
      setState(() => _errorMessage = 'Please select two distinct questions.');
      return;
    }
    if (_answer1Controller.text.trim().isEmpty ||
        _answer2Controller.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please answer both questions.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 2. Derive a new KEK from the combined security answers
      final ans1 = _answer1Controller.text.trim().toLowerCase();
      final ans2 = _answer2Controller.text.trim().toLowerCase();
      final combined = ans1 + ans2;

      final salt = await _storage.getDeviceHardwareSalt();
      final backupKek = await _crypto.deriveKEK(pin: combined, salt: salt);

      // 3. Re-wrap the existing DEK with the new KEK
      final backupWrapped = await _crypto.wrapDEK(
        widget.importedDek,
        backupKek,
      );

      // 4. Update all security-related fields in storage
      await _storage.writeString('cs_security_q1', _question1Index.toString());
      await _storage.writeString('cs_security_q2', _question2Index.toString());
      await _storage.writeString(
        'cs_backup_wrapped_dek',
        _crypto.hexEncode(Uint8List.fromList(backupWrapped)),
      );

      // 5. Success feedback and exit
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Security questions updated successfully'),
            backgroundColor: AppColors.darkSuccess,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Failed to update security questions. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

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
          middle: const Text('Update Security Questions'),
        ),
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Section
              _buildHeader(isDark, primary),

              const SizedBox(height: 20),

              // Questions Form Section
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuestionSection(
                        number: 1,
                        selectedIndex: _question1Index,
                        controller: _answer1Controller,
                        onChanged: (idx) =>
                            setState(() => _question1Index = idx),
                        isDark: isDark,
                      ),

                      const SizedBox(height: 32),

                      _buildQuestionSection(
                        number: 2,
                        selectedIndex: _question2Index,
                        controller: _answer2Controller,
                        onChanged: (idx) =>
                            setState(() => _question2Index = idx),
                        isDark: isDark,
                      ),

                      const SizedBox(height: 32),

                      // Error Message
                      if (_errorMessage.isNotEmpty) _buildErrorBanner(),

                      const SizedBox(height: 12),

                      // Save Button
                      _buildSaveButton(primary),

                      const SizedBox(height: 48),
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

  // --- UI Components ---

  Widget _buildHeader(bool isDark, Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.person_3_fill, color: primary, size: 44),
          const SizedBox(height: 14),
          Text(
            'Security Questions',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These answers will help you regain access if you forget your PIN or Password.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionSection({
    required int number,
    required int? selectedIndex,
    required TextEditingController controller,
    required ValueChanged<int> onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Question $number'),
        const SizedBox(height: 8),
        _buildQuestionPicker(selectedIndex, onChanged, isDark),
        const SizedBox(height: 12),
        if (selectedIndex != null) _buildAnswerField(controller, isDark),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildQuestionPicker(
    int? selectedIndex,
    ValueChanged<int> onChanged,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedIndex,
          isExpanded: true,
          dropdownColor: isDark ? AppColors.darkBackground : Colors.white,
          icon: const Icon(CupertinoIcons.chevron_down, size: 16),
          items: List.generate(kSecurityQuestions.length, (index) {
            return DropdownMenuItem(
              value: index,
              child: Text(
                kSecurityQuestions[index],
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            );
          }),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }

  Widget _buildAnswerField(TextEditingController controller, bool isDark) {
    return CupertinoTextField(
      controller: controller,
      placeholder: 'Your Answer',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      style: TextStyle(
        fontSize: 15,
        color: isDark ? Colors.white : Colors.black87,
      ),
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
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            color: Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(Color primary) {
    return SizedBox(
      width: double.infinity,
      child: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : CupertinoButton(
              color: primary,
              borderRadius: BorderRadius.circular(14),
              onPressed: _saveQuestions,
              child: const Text(
                'Save Questions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }
}
