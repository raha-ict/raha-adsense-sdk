typedef RahaBannerCreativeFileLoader = Future<Object> Function(Uri url);

bool isSvgBannerCreative(Uri url) {
  return url.path.toLowerCase().endsWith('.svg');
}
