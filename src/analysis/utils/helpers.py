import os
import re
import math
from glob import glob
from typing import Generator, List, Tuple
import rasterio
from rasterio.windows import Window


def list_year_rasters(folder: str) -> List[Tuple[int, str]]:
    """
    Find all .tif files with years (1900-2099) in filename and return sorted by year.
    """
    # Match only 1900–2099
    patt = re.compile(r"(19|20)\d{2}")  
    files = []

    # Iterate over the geotiffs
    for path in glob(os.path.join(folder, "*.tif")):
        
        fname = os.path.basename(path)
        match = patt.search(fname)
        
        if match:
            year = int(match.group(0))
            files.append((year, path))
    
    files.sort(key=lambda x: x[0])
    
    if not files:
        raise FileNotFoundError("No .tif rasters with a 19xx or 20xx year in the filename were found.")
    
    return files


def window_grid(width: int, height: int, blockx: int, blocky: int) -> Generator[Window, None, None]:
    """
    Generate rasterio Windows to tile a raster into blocks.
    """
    for row_off in range(0, height, blocky):
        rows = min(blocky, height - row_off)
        for col_off in range(0, width, blockx):
            cols = min(blockx, width - col_off)
            yield Window(col_off=col_off, row_off=row_off, width=cols, height=rows)


def total_windows(width: int, height: int, blockx: int, blocky: int) -> int:
    """
    Calculate total number of windows in a block grid.
    """
    return math.ceil(width / blockx) * math.ceil(height / blocky)


def pixel_area_hectares(ds: rasterio.io.DatasetReader) -> float:
    """
    Calculate pixel area in hectares from raster transform.
    """
    return abs(ds.transform.a * ds.transform.e) / 10_000.0