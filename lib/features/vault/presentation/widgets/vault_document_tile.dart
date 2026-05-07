import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';

/// A tile representing a single document in the vault list.
/// 
/// Shows the file icon, name, size, and date.
class VaultDocumentTile extends StatelessWidget {
  final VaultDocument doc;
  final VoidCallback onTap;
  final VoidCallback onActions;

  const VaultDocumentTile({
    super.key,
    required this.doc,
    required this.onTap,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: _buildThumbnail(doc, primary),
          ),
        ),
        title: Text(
          doc.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_formatFileSize(doc.fileSize ?? 0)} • ${doc.createdAt.toLocal().toString().split(' ').first}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: IconButton(
          icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 20),
          onPressed: onActions,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildThumbnail(VaultDocument doc, Color primary) {
    IconData iconData = CupertinoIcons.doc_fill;
    if (doc.fileType == 'image') {
      iconData = CupertinoIcons.photo_fill;
    } else if (doc.fileType == 'pdf') {
      iconData = CupertinoIcons.doc_text_fill;
    }
    
    return Icon(
      iconData,
      color: primary,
      size: 24,
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return "${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}";
  }
}
