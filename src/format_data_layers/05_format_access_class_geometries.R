###############################################
######## Evaluate Fire in Roadless Areas ######
###############################################

# This script processes National Forest System lands in the western US and
# classifies them into three mutually exclusive access categories:
#   1. Wilderness Areas (highest protection, takes precedence)
#   2. Roadless Areas (2001 Rule + Idaho/Colorado amendments, excluding wilderness)
#   3. Roaded Areas (remaining NFS lands)
#
# Data Sources:
# - Administrative Forest Boundaries: USDA Forest Service FSGeodata Clearinghouse
#   (https://data.fs.usda.gov/geodata/edw/datasets.php) Last refresh: Jun 22, 2025
# - Roadless Areas: 2001, Idaho, and Colorado Rules Combined
#   (https://data.fs.usda.gov/geodata/edw/datasets.php) Last refresh: Oct 3, 2023
# - National Wilderness Areas
#   (https://data.fs.usda.gov/geodata/edw/datasets.php) Last refresh: Jan 28, 2024
# - Western States boundary: US Census Bureau TIGER/Line Shapefiles
#   (https://www2.census.gov/geo/tiger/TIGER2024/STATE/) Last refresh: Aug 10, 2025

# ========================= Setup =========================

rm(list = ls())
setwd("<PATH/TO/PROJECT/FOLDER>/data")

library(sf)
library(tidyverse)
library(terra)

# Use planar geometry engine (avoids s2 issues with projected data)
sf_use_s2(FALSE)

# ================= Configuration =================

shp_folder = "./shapefiles"
output_folder = "./access_class_gpkgs"
target_crs = 5070  # NAD83 / Conus Albers

dir.create(output_folder, showWarnings = FALSE, recursive = TRUE)

# ================= Helper Functions =================

# Minimal cleaning - only what's necessary
validate = function(x) {
  st_make_valid(x) |> st_buffer(0)
}

# Extract only polygons from geometry collections
as_polys = function(x) {
  st_collection_extract(st_make_valid(x), "POLYGON")
}

# ======= 1. Load and Prepare Base Layers =======

# Western states boundary
western_boundary = st_read(file.path(shp_folder, "westernstates.shp"), quiet = TRUE) |>
  st_transform(target_crs) |>
  st_union() |>
  validate()

# National Forest System lands - filter and clip immediately
nfs = st_read(file.path(shp_folder, "S_USA.AdministrativeForest.shp"), quiet = TRUE) |>
  st_transform(target_crs) |>
  st_filter(western_boundary) |>
  st_intersection(western_boundary) |>
  st_union() |>
  validate()

message("  NFS area: ", round(as.numeric(st_area(nfs)) / 1e6, 2), " km²")

# ======= 2. Load Overlay Layers (Clip to NFS Immediately) =======

# Key insight: We only care about wilderness/roadless WITHIN NFS lands
# So clip to NFS boundary right away - smaller geometries = fewer issues

message("  Loading wilderness (clipped to NFS)...")
wilderness = st_read(file.path(shp_folder, "S_USA.Wilderness.shp"), quiet = TRUE) |>
  st_transform(target_crs) |>
  st_filter(nfs) |>
  st_intersection(nfs) |>
  st_union() |>
  validate()

message("  Loading roadless (clipped to NFS)...")
roadless = st_read(file.path(shp_folder, "S_USA.RoadlessArea_2001_ID_CO.shp"), quiet = TRUE) |>
  st_transform(target_crs) |>
  st_filter(nfs) |>
  st_intersection(nfs) |>
  st_union() |>
  validate()

# ======= 3. Compute Mutually Exclusive Classes =======

# Now we have three clean, validated geometries all clipped to NFS:
#   - nfs (full extent)
#   - wilderness (within NFS)
#   - roadless (within NFS)
#
# Labeling hierarchy: Wilderness > Roadless > Roaded

message("Computing access classes...")

# Class 1: Wilderness (as-is, already clipped to NFS)
wilderness_nfs = wilderness

# Class 2: Roadless, excluding wilderness
message("  Roadless (excluding wilderness)...")
roadless_nfs = st_difference(roadless, wilderness) |>
  validate()

# Class 3: Roaded = NFS minus (wilderness + roadless)
message("  Roaded areas...")
undeveloped = st_union(wilderness, roadless) |> validate()
roaded_nfs = st_difference(nfs, undeveloped) |>
  validate()

# Clean up
rm(wilderness, roadless, undeveloped)

# ======= 4. Finalize Geometries =======

message("Finalizing geometries...")

# Convert to polygon-only (removes any linestring artifacts from differencing)
wilderness_nfs = as_polys(wilderness_nfs)
roadless_nfs = as_polys(roadless_nfs)
roaded_nfs = as_polys(roaded_nfs)

message("Saving outputs...")

st_write(wilderness_nfs, file.path(output_folder, "wilderness_nfs.gpkg"),
         delete_layer = TRUE, quiet = TRUE)
st_write(roadless_nfs, file.path(output_folder, "roadless_nfs.gpkg"),
         delete_layer = TRUE, quiet = TRUE)
st_write(roaded_nfs, file.path(output_folder, "roaded_nfs.gpkg"),
         delete_layer = TRUE, quiet = TRUE)
