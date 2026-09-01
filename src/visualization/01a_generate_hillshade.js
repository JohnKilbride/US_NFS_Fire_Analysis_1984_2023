function main () {

  // USGS 3DEP 10m DEM - best available for CONUS
  var dem = ee.Image("MERIT/DEM/v1_0_3");
  
  // Generate hillshade (default azimuth=315, elevation=45)
  var hillshade = ee.Terrain.hillshade(dem, 315, 45)
    .resample("bicubic")
    .reproject("EPSG:3857", null, 1000);
  
  // Export the hillshade layer to Google Drive
  Export.image.toDrive({
    image: hillshade.toByte(),
    description: 'Western_US_Hillshade_250m',
    folder: 'Western_US_Hillshade',
    region: ee.Geometry.Polygon([[
        [-131.819, 52.10], [-131.819, 24.05],
        [-92.0927, 24.05], [-92.092, 52.108]
      ]], null, false),
    scale: 250,
    crs: 'EPSG:3857',
    maxPixels: 1e13,
    fileFormat: 'GeoTIFF'
  });
  
  Map.addLayer(hillshade, {min: 100, max: 255}, 'Hillshade 100m');

  return null;

}


main();
