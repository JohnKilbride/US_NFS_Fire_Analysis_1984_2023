library(terra)
library(future)
library(future.apply)

# Set up parallel processing (3 workers for 3 bands)
plan(multisession, workers = 3)

# Single-band processor (streams to disk on write)
process_band = function(gpkg_name, band_name, outfile, gpkg_dir, template_path, gdalopts) {
  
  # Load template fresh in each worker (terra objects don't serialize well)
  template = rast(template_path)
  
  v = vect(file.path(gpkg_dir, gpkg_name)) |>
    makeValid() |>
    project(crs(template))
  
  # fractional cover (0..1) per pixel; replace NA with 0
  r = rasterize(v, template, field = 1, cover = TRUE)
  r = ifel(is.na(r), 0, r)
  
  # 0..100 integers, clamped; keep name for band description in output
  r_i = clamp(round(r * 100), 0, 100)
  names(r_i) = band_name
  
  writeRaster(
    r_i, filename = outfile, overwrite = TRUE,
    filetype = "GTiff", datatype = "INT1U", gdal = gdalopts
  )
  
  invisible(outfile)
  
}

# File paths for inputs and outputs
project_folder = "<PATH/TO/PROJECT/FOLDER>"
template_raster_path = paste0(project_folder, "/data/rasters/mtbs_severity_annual/mtbs_annual_1984_mosaic.tif")
gpkg_dir = paste0(project_folder, "/data/access_class_gpkgs")
out_raster_path = paste0(project_folder, "/data/rasters/nfs_access_proportions.tif")
dir.create(dirname(out_raster_path), showWarnings = FALSE, recursive = TRUE)

# I/O + compression; PREDICTOR=2 suits integer bands, tiling helps windowed reads,
# BIGTIFF avoids the 4 GB ceiling on the intermediate/stacked writes
gdalopts = c(
  "COMPRESS=DEFLATE",
  "ZLEVEL=6",
  "PREDICTOR=2",
  "TILED=YES",
  "BLOCKXSIZE=256",
  "BLOCKYSIZE=256",
  "BIGTIFF=YES"
)

# One row per band -- defines the band order in the final stack
bands = data.frame(
  gpkg = c("roadless_nfs.gpkg", "wilderness_nfs.gpkg", "roaded_nfs.gpkg"),
  name = c("roadless", "wilderness", "roaded"),
  outfile = file.path(dirname(out_raster_path), 
                      c("nfs_access_proportions_roadless.tif",
                        "nfs_access_proportions_wilderness.tif",
                        "nfs_access_proportions_roaded.tif"))
)

# Process all 3 bands in parallel. Each worker writes a single-band tif.
future_mapply(
  process_band,
  gpkg_name = bands$gpkg,
  band_name = bands$name,
  outfile = bands$outfile,
  MoreArgs = list(
    gpkg_dir = gpkg_dir,
    template_path = template_raster_path,
    gdalopts = gdalopts
  ),
  future.seed = TRUE
)

# Shut down workers, releasing their memory before the merge
plan(sequential)

# Stack and write final 3-band GeoTIFF; rast() only opens the files,
# so the write streams rather than pulling all 3 bands into memory.
# Names are reassigned so they persist as band descriptions.
r_stack = rast(bands$outfile)
names(r_stack) = bands$name
writeRaster(
  r_stack, 
  filename = out_raster_path, 
  overwrite = TRUE,
  filetype = "GTiff", 
  datatype = "INT1U", 
  gdal = gdalopts
)
