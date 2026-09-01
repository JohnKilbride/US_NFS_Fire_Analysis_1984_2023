/**
 * Generates annual MTBS (Monitoring Trends in Burn Severity) burn severity mosaics
 * for an 11-state western U.S. study area from 1984–2024, remaps severity classes,
 * masks to the AOI, and exports each year's result to Google Drive as a COG GeoTIFF.
 *
 * Workflow:
 * 1. Defines the study area using TIGER/2018 State boundaries and a custom multipoint geometry.
 * 2. Loops over each year in the specified range.
 * 3. For each year:
 *    - Loads MTBS annual burn severity mosaics intersecting the AOI.
 *    - Filters to that year's date range.
 *    - Mosaics the collection.
 *    - Masks to the AOI and casts to byte type.
 *    - Exports to Google Drive as a cloud-optimized GeoTIFF.
 * 4. Adds the final year's burn severity map to the Map display for quick inspection.
 *
 * Exports:
 * - Folder: WESTERN_CONUS_MTBS (in Google Drive)
 * - File names: mtbs_annual_<year>.tif
 * - CRS: EPSG:5070
 * - Pixel size: 30m
 *
 * Inputs:
 * - TIGER/2018/States (study area definition)
 * - USFS/GTAC/MTBS/annual_burn_severity_mosaics/v1 (MTBS data source)
 */
function main () {
   
  // Define the area of interest (11 states)
  var study_area = ee.FeatureCollection("TIGER/2018/States")
    .filterBounds(ee.Geometry.MultiPoint([
      [-119.73973657093154, 47.665290673995806],
      [-114.99364282093154, 43.992711219004924],
      [-120.09129907093154, 44.24509617396524],
      [-119.91551782093154, 35.78205424020548],
      [-115.96043969593154, 40.48027223270012],
      [-111.47801782093154, 39.26617327555159],
      [-111.74168969593154, 34.48832950924179],
      [-105.32567407093154, 34.415854953184216],
      [-105.58934594593154, 38.65108621670265],
      [-107.25926782093154, 42.972396545345795],
      [-107.78661157093154, 48.07798302805881]
    ]))
    .geometry()
    .dissolve();
  
  // Define the start and the end year
  var start_year = 1984;
  var end_year = 2024;
  
  // Create a mask for the area of interest
  var output_mask = ee.Image(0).paint(study_area, 1);
  
  // Iterate over the years that need to be processed
  for (var year = start_year; year <= end_year; year++) {
    
    // Get all of the MTBS perimeters for the current year
    var mtbs_annual = ee.ImageCollection("USFS/GTAC/MTBS/annual_burn_severity_mosaics/v1")
      .filterBounds(study_area)
      .filterDate(year+"-01-01", year+"-12-31")
      .mosaic()
      .unmask(-1)
      .updateMask(output_mask)
      .int8();
      
    // Export the formatted MTBS annual layer
    var output_name = "mtbs_annual_" + year;
    Export.image.toDrive({
      image: mtbs_annual,
      description: output_name,
      folder: 'mtbs_annual_severity_shards',
      region: study_area.bounds(),
      crs: 'EPSG:5070',
      scale: 30,
      maxPixels: 1e13,
      fileFormat: 'GeoTIFF',
      formatOptions: {cloudOptimized: true},
      skipEmptyTiles: true
    });
    
  }
  
  Map.addLayer(mtbs_annual, {min:-1, max:6, palette:['gray', "#000000", "#006400", "#7FFFD4", "#FFFF00", "#FF0000", "#7FFF00", "#FFFFFF"]}, "Burn");

  return null;

}

main();
