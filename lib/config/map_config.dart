/// Central Mapbox configuration.
///
/// The app renders Mapbox raster tiles through `flutter_map`'s [TileLayer],
/// so switching the base map is just a matter of pointing the tile URL at a
/// Mapbox style. Mapbox styles already include labels (roads, places, POIs),
/// so no separate label layer is needed.
class MapConfig {
  MapConfig._();

  /// Mapbox public access token (pk.*).
  static const String mapboxAccessToken =
      'pk.eyJ1IjoieWFuZWdpIiwiYSI6ImNtb2xyYTlyeDBsczEyb3Mxajc4M3R6bTYifQ.Ry0AcPukYey3nwlR1u2BMQ';

  /// Best-looking Mapbox styles for each theme.
  /// Light: vibrant Streets with full POI/terrain detail.
  /// Dark: Navigation Night — blue water, green parks, amber roads; much richer than dark-v11.
  static const String lightStyleId = 'streets-v12';
  static const String darkStyleId = 'navigation-night-v1';

  /// Picker variants — cleaner focus for location dropping.
  static const String lightPickerStyleId = 'light-v11';
  static const String darkPickerStyleId = 'navigation-night-v1';

  /// Builds a `flutter_map`-compatible raster tile URL template for a Mapbox
  /// style. Uses the 256px endpoint so `{r}` -> `@2x` yields crisp retina tiles
  /// without needing a zoom offset.
  static String rasterTileUrl(String styleId) =>
      'https://api.mapbox.com/styles/v1/mapbox/$styleId/tiles/256/{z}/{x}/{y}{r}'
      '?access_token=$mapboxAccessToken';

  /// User-Agent package name sent with tile requests.
  static const String userAgentPackageName = 'com.yanegi.app';
}
