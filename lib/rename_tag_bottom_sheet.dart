import 'package:flutter/material.dart';
import 'tag_storage.dart';

Future<void> showRenameTagBottomSheet(
  BuildContext context,
  String deviceId, {
  String? currentName,
}) async {
  final TextEditingController controller = TextEditingController(text: currentName);
  await showModalBottomSheet(
    context: context,
    builder: (BuildContext ctx) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Device Name'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                TagStorage.saveTag(deviceId, controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
}