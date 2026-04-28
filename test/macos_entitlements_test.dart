import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS sandbox entitlements allow outbound network access', () async {
    final File debugEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    );
    final File releaseEntitlements = File('macos/Runner/Release.entitlements');

    expect(await debugEntitlements.exists(), isTrue);
    expect(await releaseEntitlements.exists(), isTrue);

    final String debugContents = await debugEntitlements.readAsString();
    final String releaseContents = await releaseEntitlements.readAsString();

    expect(debugContents, contains('com.apple.security.network.client'));
    expect(releaseContents, contains('com.apple.security.network.client'));
  });
}
