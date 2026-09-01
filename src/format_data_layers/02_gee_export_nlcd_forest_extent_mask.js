/**
 * Builds a single, multi-year binary forest mask from the Annual NLCD
 * Landcover collection for an 11-state western U.S. study area (1984–2024),
 * masks it to the study-area boundary, and exports one cloud-optimized GeoTIFF.
 *
 * Workflow:
 * 1) Defines the study area from TIGER/2018 State boundaries using a custom
 *    multipoint filter, then dissolves to one geometry.
 * 2) Loads the Annual NLCD Landcover ImageCollection (1984–2024).
 * 3) For each image, remaps NLCD classes {41, 42, 43} → 1 (forest), all others → 0,
 *    and sets masked (no-data) pixels to 255 for differentiation.
 * 4) Reduces the remapped collection with a pixel-wise max to produce a single
 *    composite forest mask across all years.
 * 5) Applies a simple boundary mask (painted from the study area buffered by 100 m).
 * 6) Exports the composite to Google Drive as a COG GeoTIFF.
 *
 * Export:
 * - Folder: WESTERN_CONUS_NLCD_ALL_YEARS
 * - File name: nlcd_forest_mask_1984_2024.tif
 * - CRS: EPSG:5070; Pixel size: 30 m; Max pixels: 1e13
 *
 * Inputs:
 * - TIGER/2018/States (study area definition)
 * - projects/sat-io/open-datasets/USGS/ANNUAL_NLCD/LANDCOVER (Annual NLCD landcover)
 *
 * Forest Class Mapping:
 * - 41: Deciduous Forest
 * - 42: Evergreen Forest
 * - 43: Mixed Forest
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

  // Load in the Annual NLCD Rasters
  var nlcd_landcover = ee.ImageCollection("projects/sat-io/open-datasets/USGS/ANNUAL_NLCD/LANDCOVER")
    .map(remap_nlcd_layer)
    .max();
  
  // Generate and apply a boundary mask
  var output_mask = ee.Image(0).paint(study_area.buffer(100), 1);
  var output_nlcd_layer = nlcd_landcover.updateMask(output_mask);
  
  // Export the formatted annual NLCD forest layer
  var output_name = "nlcd_forest_mask_1984_2024";
  Export.image.toDrive({
    image: output_nlcd_layer,
    description: output_name,
    folder: 'ncld_forest_mask_shards',
    region: study_area.bounds(),
    crs: 'EPSG:5070',
    scale: 30,
    maxPixels: 1e13,
    fileFormat: 'GeoTIFF',
    formatOptions: {cloudOptimized: true},
    skipEmptyTiles: true
  });

  Map.addLayer(nlcd_landcover, {min:0, max:1, palette:['black', 'green']}, "NLCD - Forest - Mask");

  return null;

}


// Convert the NLCD layers into binary forest/non-forest rasters
function remap_nlcd_layer (nlcd_landcover) {
  
  // Get and remap the current NLCD layer to a binary forest mask
  var nlcd_forest_mask = ee.Image(nlcd_landcover).remap({
      from: [41, 42, 43], 
      to: [1, 1, 1], 
      defaultValue: 0
    })
    .unmask(0)
    .byte();
  
  return nlcd_forest_mask;
  
}


main();

