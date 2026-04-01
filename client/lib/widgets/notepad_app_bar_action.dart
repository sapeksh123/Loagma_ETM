import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../screen/admin/notepad_list_screen.dart';

Future<void> showNotepadPopup(
  BuildContext context, {
  String? userId,
  String? userRole,
  String? userName,
}) async {
  var resolvedUserId = userId;
  var resolvedUserRole = userRole;
  var resolvedUserName = userName;

  if (resolvedUserId == null || resolvedUserRole == null) {
    final storedUser = await AuthService.getStoredUser();
    if (storedUser != null) {
      resolvedUserId ??= storedUser.id;
      resolvedUserRole ??= storedUser.role;
      resolvedUserName ??= storedUser.name;
    }
  }

  if (resolvedUserId == null ||
      resolvedUserId.trim().isEmpty ||
      resolvedUserRole == null ||
      resolvedUserRole.trim().isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to open notepad right now. Please re-login.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  if (!context.mounted) return;
  final size = MediaQuery.of(context).size;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(size.width * 0.96, 980),
          height: math.min(size.height * 0.92, 760),
          child: NotepadListScreen(
            userId: resolvedUserId!,
            userRole: resolvedUserRole!,
            userName: resolvedUserName,
            showAppBar: true,
            showNotepadAction: false,
            autoOpenLastOpenedNote: false,
          ),
        ),
      );
    },
  );
}

Widget buildNotepadAppBarAction(
  BuildContext context, {
  String? userId,
  String? userRole,
  String? userName,
}) {
  return IconButton(
    icon: const Icon(Icons.note_alt_outlined),
    tooltip: 'Notepad',
    onPressed: () async {
      await showNotepadPopup(
        context,
        userId: userId,
        userRole: userRole,
        userName: userName,
      );
    },
  );
}
