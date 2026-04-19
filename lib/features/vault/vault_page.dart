import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:cipherscribe/features/vault/presentation/bloc/vault_bloc.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  @override
  void initState() {
    super.initState();
    // Dispatch initial load event if the Bloc is injected at a higher level
    // context.read<VaultBloc>().add(LoadVaultDocuments());
  }

  Future<void> _importDocument() async {
    final result = await FilePicker.pickFiles();
    if (result != null) {
      final String? pathStr = result.files.single.path;
      if (pathStr == null) return;
      
      final fileToRead = File(pathStr);
      if (!mounted) return;
      
      context.read<VaultBloc>().add(ImportNewDocument(fileToRead));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CipherScribe Vault')),
      body: BlocConsumer<VaultBloc, VaultState>(
        listener: (context, state) {
          if (state is VaultError) {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message, style: TextStyle(color: Theme.of(context).colorScheme.onError)), backgroundColor: Theme.of(context).colorScheme.error),
            );
          }
        },
        builder: (context, state) {
          if (state is VaultLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is VaultLoaded) {
            if (state.documents.isEmpty) {
              return const Center(child: Text('Vault is securely empty.'));
            }
            return ListView.builder(
              itemCount: state.documents.length,
              itemBuilder: (context, index) {
                final doc = state.documents[index];
                return ListTile(
                  leading: Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.secondary),
                  title: Text(doc.fileName),
                  subtitle: Text('Encrypted on ${doc.createdAt.toLocal().toString().split('.').first}'),
                );
              },
            );
          }
          return const Center(child: Text('Initializing Secure Vault...'));
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importDocument,
        child: const Icon(Icons.add),
      ),
    );
  }
}
