# Reading Geo Data with Godot

This Repository is a stripped down version of the [Python DTED Module](https://pypi.org/project/dted/),
originally by Ben Bonenfant, translated into GDScript for the use within the Godot-Game-Engine by me.
DTED means Digital Terrain Elevation Data and can appear in *.dt1, *.dt2 and *.dt3 format.
Map services and data available from U.S. Geological Survey, National Geospatial Program.

## Quickstart

If you want to use this module just copy [geo_data.gd](https://github.com/HauptmannBoosted/Godot-GeoData-DTED/blob/master/geo-data-demo/geo_data.gd) anywhere into your project.
Everything is documented inline, viewing the demo project is advised.

Example for reading a DTED file and querying elevation:

```GDScript
var geo_data : GeoData = GeoData.new()
var error : int = geo_data.load_from_dted(path)

if error == OK:
  var elevation = geo_data.get_elevation(latitude, longitude)
```

## View Demo

The example project is in [geo-data-demo/](https://github.com/HauptmannBoosted/Godot-GeoData-DTED/tree/master/geo-data-demo) and geo data you can use for this demo is in [geo-data-test-files/](https://github.com/HauptmannBoosted/Godot-GeoData-DTED/tree/master/geo-data-test-files).
You are advised to view the short demo for instructions on how to use this module.

## Intentions

The intend behind this repository is to give you a headstart when starting out with DTED in Godot.
It is not 100% matured for sure but among other things capable of reading DTED files according to the [DTED specification](https://geoservice.dlr.de/web/dataguide/srtm/pdfs/SRTM-XSAR-DEM-DTED-1.1.pdf), which can save you a lot of initial workload.

## Where to find Geo Data files (login required)

You can download DTED files from the [United States Geological Survey's Earth Explorer](https://earthexplorer.usgs.gov/).
Since the process for download DTED files from the Earth Explorer might not be straight forward for some, here is a small guide:

1. This is the initial view you will see when visiting the website.
![1](https://github.com/user-attachments/assets/87e85eb0-39e3-4043-a85d-c4dc139e5a2b)

2. Set points on the map in order to restrict the search for geo data to this area.
![2](https://github.com/user-attachments/assets/e849ff1b-c8cf-4a75-9a33-3caa75b2d861)

3. Under "Data Sets" select SRTM void filled and or non-void filled.
![3](https://github.com/user-attachments/assets/e1ff508d-749a-4f28-954b-76c19033be43)

4. Go to "Results".
![4](https://github.com/user-attachments/assets/80824fbf-4172-4fc3-b3f5-d5b5192d313a)

5. Toggle the footprint icon to view the area covered.
![5](https://github.com/user-attachments/assets/6659f827-49c1-4351-bfa6-cc3cdc502524)

6. Select the disk icon to prompt download options and pick "DTED" (requires you to be logged in)
![6](https://github.com/user-attachments/assets/dff75969-5fe9-4cd5-9041-835061187490)

## Credits

A big thank you to Ben Bonenfant for authoring the original Python DTED module.
