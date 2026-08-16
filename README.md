# Raha Adsense

Flutter SDK for Raha banner, video, interstitial, and native advertising on Raha.

This package handles ad setup, request flow, tracking, and impression/click
reporting while exposing a simple integration surface for Flutter apps.

## Features

- Initialize Raha advertising with a single `RahaAdsense.setup(...)` call
- Display banner ads using `RahaBannerAd`
- Display video ads using `RahaVideoAd`
- Show interstitial ads with `RahaInterstitialPresenter`
- Render native ads with `RahaNativeAd`
- Support contextual signals for targeting
- Custom click handling via `clickOpener`
- Built-in retry, URL validation, and viewability policy

## Requirements

- Flutter `>=3.24.0`
- Dart `>=3.5.0 <4.0.0`

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  raha_adsense: ^2.0.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

Initialize the SDK before loading ads. Production endpoints are used by default:

```dart
await RahaAdsense.setup(
  appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
);
```

Use the development environment only when testing against the dev backend:

```dart
await RahaAdsense.setup(
  appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
  environment: RahaAdsenseEnvironment.development,
);
```

### Banner Ad

```dart
const RahaBannerAd(
  size: RahaBannerSize.mobile320x50,
  signals: {'genre': 'news', 'language': 'fa'},
)
```

### Video Ad

```dart
const RahaVideoAd(
  signals: {'genre': 'sports', 'playback_position': 'pre_roll'},
)
```

### Native Ad

```dart
const RahaNativeAd(
  signals: {'genre': 'business', 'language': 'fa'},
)
```

### Interstitial Ad

```dart
final ad = await RahaAdsense.adRequest(
  type: RahaAdFormat.interstitial,
  signals: const {'screen': 'article_complete'},
);

if (ad is RahaInterstitialAdResponse && context.mounted) {
  await RahaInterstitialPresenter.show(context: context, ad: ad);
}
```

## Custom Click Handling

For embedded systems, STBs, or custom shells, you can provide a custom click
opener during setup. The SDK tracks clicks first and then passes the destination
URL to your opener.

```dart
await RahaAdsense.setup(
  appId: '743e8c4b-08e0-4152-877e-e035f7d92d9a',
  clickOpener: (destinationUrl, adInfo) async {
    await StbNativeBridge.openAdUrl(destinationUrl.toString());
  },
);
```

## API Overview

- `RahaAdsense.setup(...)` — Initialize the SDK with your Raha app ID.
- `RahaAdsense.adRequest(...)` — Request an ad response for interstitials or
  other manual ad flows.
- `RahaBannerAd` — Widget for responsive banner ad placements.
- `RahaVideoAd` — Widget for video ad placements.
- `RahaNativeAd` — Widget for native ad rendering.
- `RahaInterstitialPresenter.show(...)` — Display an interstitial ad response.

## Notes

The package expects the Raha backend response format to include top-level
fields like `id`, `format`, tracking URLs, optional `clickUrl`, and a
format-specific `asset` object.

## Example

For a complete example integration, see the `example/` directory included with
this package.

## License

This package is distributed under the terms of the LICENSE file in this
repository.
