import 'package:flutter/widgets.dart';

import 'banner_creative_network.dart'
    if (dart.library.io) 'banner_creative_io.dart' as platform;
import 'banner_creative_types.dart';

class RahaBannerCreative extends StatelessWidget {
  const RahaBannerCreative({
    required this.url,
    required this.width,
    required this.height,
    required this.onRendered,
    required this.onError,
    super.key,
    this.fileLoader,
  });

  final Uri url;
  final double width;
  final double height;
  final VoidCallback onRendered;
  final ValueChanged<Object> onError;
  final RahaBannerCreativeFileLoader? fileLoader;

  @override
  Widget build(BuildContext context) {
    return platform.buildBannerCreative(
      url: url,
      width: width,
      height: height,
      onRendered: onRendered,
      onError: onError,
      fileLoader: fileLoader,
    );
  }
}
