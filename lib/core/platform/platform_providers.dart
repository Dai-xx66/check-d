import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_capabilities.dart';

final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (ref) => PlatformCapabilities.current(),
);
