extends Control



@onready var load_geo_data_button : Button = %LoadGeoDataButton
@onready var load_geo_data_file_dialog : FileDialog = %LoadGeoDataFileDialog

@onready var height_map_inspector_window : Window = %HeightMapInspectorWindow
@onready var height_map_texture_rect : TextureRect = %HeightMapTextureRect
@onready var elevation_display_label : Label = %ElevationDisplayLabel


func _ready() -> void:
	load_geo_data_button.pressed.connect(load_geo_data_file_dialog.show)
	load_geo_data_file_dialog.file_selected.connect(_on_geo_data_file_selected)
	
	height_map_inspector_window.close_requested.connect(height_map_inspector_window.hide)
	height_map_texture_rect.gui_input.connect(_height_map_gui_input)


func _on_geo_data_file_selected(path : String) -> void:
	# load geodata from path
	var geo_data : GeoData = GeoData.new()
	var error : int = geo_data.load_from_dted(path)
	
	print("loaded geo data from ", path, " with code ", error)
	
	if error == OK:
		# display geo data if it was successfully loaded
		print_geo_data_meta_data(geo_data)
		
		height_map_inspector_window.show()
		
		# cache geo_data object in the window meta data
		height_map_inspector_window.set_meta(&"geo_data", geo_data)
		
		height_map_texture_rect.texture = texture_from_geo_data(geo_data)


## Shows elevation for a given LAT/LON depending on the position of the mouse
## within the texture. Intended for demonstration purposes.
func _height_map_gui_input(event : InputEvent) -> void:
	# get the selected geo data object
	var geo_data : GeoData = height_map_inspector_window.get_meta(&"geo_data")
	
	if geo_data and event is InputEventMouseMotion:
		# convert mouse position within the texture rect to coordinates
		# LAT/LON within the texture
		var longitude : float = (
			geo_data.dsi_data.north_west_corner.longitude
			+ (event.position.x / height_map_texture_rect.texture.get_size().x)
			* (geo_data.dsi_data.north_east_corner.longitude - geo_data.dsi_data.north_west_corner.longitude)
		)
		var latitude : float = (
			geo_data.dsi_data.north_west_corner.latitude
			+ (event.position.y / height_map_texture_rect.texture.get_size().y)
			* (geo_data.dsi_data.south_west_corner.latitude - geo_data.dsi_data.north_west_corner.latitude)
		)
		
		# get elevation - is float or null if the coordinates are out of bounds
		var elevation = geo_data.get_elevation(latitude, longitude)
		
		elevation_display_label.text = (
			"LAT: " + str(latitude) + " LON: " + str(longitude) + \
			"\n" + "HEIGHT: " + str(elevation)
		)


## This is a quick and dirty method I wrote for creating a black-and-white
## [ImageTexture] based off of the elevation data. Intended for demonstration
## purposes.
func texture_from_geo_data(geo_data : GeoData) -> ImageTexture:
	# an elevation of this height will be displayed as the brightest color
	const MAX_ELEVATION_DISPLAYED : float = 2000
	
	# get lat and lon as floats
	var longitude_count : float = geo_data.dsi_data.shape.left()
	var latitude_count : float = geo_data.dsi_data.shape.right()
	
	# create black-and-white image to display elevation data
	var dynamic_image : Image = Image.new()
	dynamic_image = Image.create(longitude_count, latitude_count, false, Image.FORMAT_L8)
	
	# set pixel colors
	for lon : int in longitude_count:
		for lat in latitude_count:
			var elevation : int = geo_data._data[lon][lat]
			dynamic_image.set_pixel(lon, latitude_count - 1 - lat, Color(
				elevation / MAX_ELEVATION_DISPLAYED,
				elevation / MAX_ELEVATION_DISPLAYED,
				elevation / MAX_ELEVATION_DISPLAYED,
				1.0
			))
	
	# create and return image texture
	var image_texture : ImageTexture = ImageTexture.new()
	image_texture = ImageTexture.create_from_image(dynamic_image)
	return image_texture


func print_geo_data_meta_data(geo_data : GeoData) -> void:
	print("UHL Origin:")
	print(geo_data.uhl_data.origin.latitude, "/", geo_data.uhl_data.origin.longitude)
	print("Lon Interval:")
	print(geo_data.uhl_data.longitude_interval)
	print("Lat Interval:")
	print(geo_data.uhl_data.latitude_interval)
	print("Vertical Accuracy:")
	print(geo_data.uhl_data.vertical_accuracy)
	print("Security Code:")
	print(geo_data.uhl_data.security_code)
	print("Reference Bytes:")
	print(geo_data.uhl_data.reference_bytes)
	print("Shape:")
	print(geo_data.uhl_data.shape.left(), "/", geo_data.uhl_data.shape.right())
	print("Multiple Accuracy:")
	print(geo_data.uhl_data.multiple_accuracy)
	
	print("DSI Security Code:")
	print(geo_data.dsi_data.security_code)
	print("Release Markings:")
	print(geo_data.dsi_data.release_markings)
	print("Handling Description:")
	print(geo_data.dsi_data.handling_description)
	print("Product Level:")
	print(geo_data.dsi_data.product_level)
	print("Reference Bytes:")
	print(geo_data.dsi_data.reference_bytes)
	print("Edition:")
	print(geo_data.dsi_data.edition)
	print("Merge Version:")
	print(geo_data.dsi_data.merge_version)
	print("Maintenance Date:")
	print(geo_data.dsi_data.maintenance_date)
	print("Merge Date:")
	print(geo_data.dsi_data.merge_date)
	print("Maintenance Code:")
	print(geo_data.dsi_data.maintenance_code)
	print("Producer Code:")
	print(geo_data.dsi_data.producer_code)
	print("Product Specification")
	print(geo_data.dsi_data.product_specification)
	print("Specification Date:")
	print(geo_data.dsi_data.specification_date)
	print("Vertical Datum:")
	print(geo_data.dsi_data.vertical_datum)
	print("Horizontal Datum:")
	print(geo_data.dsi_data.horizontal_datum)
	print("Collection System:")
	print(geo_data.dsi_data.collection_system)
	print("Compilation Date:")
	print(geo_data.dsi_data.compilation_date)
	print("DSI Origin:")
	print(geo_data.dsi_data.origin.latitude, "/", geo_data.dsi_data.origin.longitude)
	print("SW Corner:")
	print(geo_data.dsi_data.south_west_corner.latitude, "/", geo_data.dsi_data.south_west_corner.longitude)
	print("NW Corner:")
	print(geo_data.dsi_data.north_west_corner.latitude, "/", geo_data.dsi_data.north_west_corner.longitude)
	print("NE Corner:")
	print(geo_data.dsi_data.north_east_corner.latitude, "/", geo_data.dsi_data.north_east_corner.longitude)
	print("SE Corner:")
	print(geo_data.dsi_data.south_east_corner.latitude, "/", geo_data.dsi_data.south_east_corner.longitude)
	print("Orientation:")
	print(geo_data.dsi_data.orientation)
	print("DSI Longitude Interval:")
	print(geo_data.dsi_data.longitude_interval)
	print("DSI Latitude Interval:")
	print(geo_data.dsi_data.latitude_interval)
	print("DSI Shape:")
	print(geo_data.dsi_data.shape.left(), "/", geo_data.dsi_data.shape.right())
	print("Coverage:")
	print(geo_data.dsi_data.coverage)
	
	print("Absolute Horizontal:")
	print(geo_data.acc_data.absolute_horizontal)
	print("Absolute Vertical:")
	print(geo_data.acc_data.absolute_vertical)
	print("Relative Horizontal:")
	print(geo_data.acc_data.relative_horizontal)
	print("Relative Vertical:")
	print(geo_data.acc_data.relative_vertical)
