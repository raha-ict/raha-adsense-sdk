import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
  return _CachedBannerCreative(
    url: url,
    width: width,
    height: height,
    onRendered: onRendered,
    onError: onError,
    fileLoader: fileLoader,
  );
}

class _CachedBannerCreative extends StatefulWidget {
  const _CachedBannerCreative({
    required this.url,
    required this.width,
    required this.height,
    required this.onRendered,
    required this.onError,
    required this.fileLoader,
  });

  final Uri url;
  final double width;
  final double height;
  final VoidCallback onRendered;
  final ValueChanged<Object> onError;
  final RahaBannerCreativeFileLoader? fileLoader;

  @override
  State<_CachedBannerCreative> createState() => _CachedBannerCreativeState();
}

class _CachedBannerCreativeState extends State<_CachedBannerCreative> {
  late Future<_LoadedBannerCreative> _creativeFuture;
  Object? _reportedError;
  bool _reportedRendered = false;

  @override
  void initState() {
    super.initState();
    _creativeFuture = _loadCreative();
  }

  @override
  void didUpdateWidget(covariant _CachedBannerCreative oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.fileLoader != widget.fileLoader) {
      _creativeFuture = _loadCreative();
      _reportedError = null;
      _reportedRendered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedBannerCreative>(
      future: _creativeFuture,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          _notifyError(error);
          return const SizedBox.expand();
        }

        final creative = snapshot.data;
        if (creative == null) return const SizedBox.expand();

        if (creative.isSvg) {
          _notifyRendered();
          return SvgPicture.file(
            creative.file,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.fill,
            placeholderBuilder: (_) => const SizedBox.expand(),
            errorBuilder: (context, error, stackTrace) {
              _notifyError(error);
              return const SizedBox.shrink();
            },
          );
        }

        return Image.file(
          creative.file,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) _notifyRendered();
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _notifyError(error);
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  Future<_LoadedBannerCreative> _loadCreative() async {
    final loader = widget.fileLoader;
    final file = loader != null
        ? await loader(widget.url) as File
        : await DefaultCacheManager().getSingleFile(widget.url.toString());
    final isSvg = isSvgBannerCreative(widget.url);
    if (isSvg) {
      final pictureInfo = await vg.loadPicture(SvgFileLoader(file), null);
      pictureInfo.picture.dispose();
    }
    return _LoadedBannerCreative(file: file, isSvg: isSvg);
  }

  void _notifyRendered() {
    if (_reportedRendered) return;
    _reportedRendered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRendered();
    });
  }

  void _notifyError(Object error) {
    if (identical(_reportedError, error)) return;
    _reportedError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onError(error);
    });
  }
}

class _LoadedBannerCreative {
  const _LoadedBannerCreative({
    required this.file,
    required this.isSvg,
  });

  final File file;
  final bool isSvg;
}
