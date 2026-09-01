library(terra)

# Define the input and output paths
project_folder = "<PATH/TO/PROJECT/FOLDER>"
template_raster_path = paste0(project_folder, "/data/rasters/mtbs_severity_annual/mtbs_annual_1984_mosaic.tif")
state_shp_path       = paste0(project_folder, "/data/shapefiles/westernstates.shp")
out_raster_path      = paste0(project_folder, "/data/rasters/western_states.tif")

# Define a raster that will serve as the template for mapping the rasterized state ids
template = rast(template_raster_path)

# Load in the US state boundaries.
v_states = vect(state_shp_path) |>
  makeValid() |>
  project(crs(template))

# Burn the STATE_INT identification value into template grid.
# The grid's background value is 0.
r_states = rasterize(v_states, template, field = "STATE_INT", background = 0)
r_states[is.na(r_states)] = 0
names(r_states) = "western_states"

# Write the GeoTIFF with the state IDs. 
# Unsigned 16-bit integer, DEFLATE, tiled
dir.create(dirname(out_raster_path), showWarnings = FALSE, recursive = TRUE)
writeRaster(
  r_states, filename = out_raster_path, overwrite = TRUE,
  filetype = "GTiff", datatype = "INT2U",
  gdal = c(
    "COMPRESS=DEFLATE",
    "ZLEVEL=6",
    "PREDICTOR=2",
    "TILED=YES",
    "BLOCKXSIZE=256",
    "BLOCKYSIZE=256",
    "BIGTIFF=IF_SAFER"
  )
)
