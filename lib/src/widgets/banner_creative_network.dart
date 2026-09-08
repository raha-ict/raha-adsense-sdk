import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'banner_creative_types.dart';

Widget buildBannerCreative({
  required Uri url,
  required double width,
  required double height,
  required VoidCallback onRendered,
  required ValueChanged<Object> onError,
  required RahaBannerCreativeFileLoader? fileLoader,
}) {
  if (isSvgBannerCreative(url)) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onRendered());
    return SvgPicture.network(
      url.toString(),
      width: width,
      height: height,
      fit: BoxFit.fill,
      placeholderBuilder: (_) => const SizedBox.expand(),
      errorBuilder: (context, error, stackTrace) {
        onError(error);
        return const SizedBox.shrink();
      },
    );
  }

  return Image.network(
    url.toString(),
    width: width,
    height: height,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.low,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (frame != null || wasSynchronouslyLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onRendered());
      }
      return child;
    },
    errorBuilder: (context, error, stackTrace) {
      onError(error);
      return const SizedBox.shrink();
    },
  );
}
