class_name GeoData extends Resource



## This implementation is based on the python DTED module and works with
## digital-terrain-elevation-data in *.dt1, *.dt2 and *.dt3 format.
## To use [GeoData] have to create a [GeoData] object with .new() and
## call [method load_from_dted] on said object.
## Validate the result of [method load_from_dted] by checking the
## [enum GlobalScope.ERROR] code it returns before accessing any of
## its methods.
## You can download geodata from the USGS Earth explorer at
## https://earthexplorer.usgs.gov/ (login required).
## Instructions on how to download DTED files can be found in the
## source repository at https://github.com/HauptmannBoosted/Godot-GeoData-DTED.
## You can read about the specification of DTED files at
## https://geoservice.dlr.de/web/dataguide/srtm/pdfs/SRTM-XSAR-DEM-DTED-1.1.pdf.
##
## Original license of the Python DTED Module (https://pypi.org/project/dted/):
## Copyright (c) 2024 Benjamin Bonenfant
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of
## this software and associated documentation files (the "Software"), to deal in
## the Software without restriction, including without limitation the rights to use,
## copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
## Software, and to permit persons to whom the Software is furnished to do so,
## subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
## OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
## WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
## IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


const _DATA_SENTINEL = 0xAA

## Definitions of the value DTED uses for void data. (-1 << 15) + 1
const VOID_DATA_VALUE : int = -32767
## Size of the User Header Label in bytes
const UHL_SIZE : int = 80
## Size of the Data Set Identification in bytes
const DSI_SIZE : int = 648
## Size of the Accuracy Description in bytes
const ACC_SIZE : int = 2700

var uhl_data : UserHdeaderLabel = null
var dsi_data : DataSetIdentification = null
var acc_data : AccuracyDescription = null

## Source path will be cached after calling [method load_from_dted]
var file_path : String

## Stores the parsed data from the file
var _data : Array[Array] = []

## Tries to load the dted file from the path, can fail and will return
## an error code. You must handle the error code because otherwise if you
## try to access [GeoData] without successfully calling [method load_from_dted],
## you get undefined behaviour.
func load_from_dted(path : String) -> int:
	# Store original file path
	self.file_path = path
	
	# Try to read file
	var file_content : PackedByteArray = FileAccess.get_file_as_bytes(path)
	
	# Validate if attempt was successful
	if file_content.is_empty():
		return FileAccess.get_open_error()
	
	# slice uhl, dsi and acc data from the raw bytes
	var uhl_bytes : PackedByteArray = file_content.slice(0, UHL_SIZE)
	var dsi_bytes : PackedByteArray = file_content.slice(UHL_SIZE, UHL_SIZE + DSI_SIZE)
	var acc_bytes : PackedByteArray = file_content.slice(UHL_SIZE + DSI_SIZE, UHL_SIZE + DSI_SIZE + ACC_SIZE)
	
	# try to parse the loaded bytes into their respective data structure
	uhl_data = UserHdeaderLabel.from_bytes(uhl_bytes)
	dsi_data = DataSetIdentification.from_bytes(dsi_bytes)
	acc_data = AccuracyDescription.from_bytes(acc_bytes)
	
	# check if anything went wrong
	if uhl_data == null or dsi_data == null or acc_data == null:
		return ERR_FILE_CORRUPT
	
	# slice to the 'data'-part of the file
	var data_record : PackedByteArray = file_content.slice(UHL_SIZE + DSI_SIZE + ACC_SIZE)
	var block_length : int = 12 + (2 * dsi_data.shape.right())
	
	# load elevation data into memory
	var parsed_data_blocks : Array[Array] = []
	for column : int in dsi_data.shape.left():
		var start_idx : int = column * block_length
		var end_idx : int = start_idx + block_length
		var block : PackedByteArray = data_record.slice(start_idx, end_idx)
		var parsed_result = GeoData._parse_data_block(block)
		
		# check if parsing was successful
		if parsed_result == null:
			return ERR_INVALID_DATA
		
		parsed_data_blocks.append(parsed_result)
	
	# store parsed data
	self._data = GeoData._convert_signed_magnitude(parsed_data_blocks)
	
	# check warnings
	for arr : Array in self._data:
		if VOID_DATA_VALUE in arr:
			push_warning(
				"Void data has been detected in ", self.file_path,
				" - this can happen when DTED data is non existant over bodies ",
				"of water. This doesn't mean the file in invalid, but needs to ",
				"be handled with care."
			)
			break
	
	return OK


## Returns null if parameter are not within the specified file, otherwise the
## elevation is returned
func get_elevation(latitude : float, longitude : float):
	# check if the coordinates are in the file
	var lat_long : LatitudeLongitude = LatitudeLongitude.new(latitude, longitude)
	if not contains(lat_long):
		return null
	
	# calculate indices of the elevation for given arguments
	var origin_latitude : float = self.dsi_data.origin.latitude
	var origin_longitude : float = self.dsi_data.origin.longitude
	
	var longitude_count : float = self.dsi_data.shape.left()
	var latitude_count : float = self.dsi_data.shape.right()
	
	var latitude_index : float = roundf((latitude - origin_latitude) * (latitude_count - 1))
	var longitude_index : float = roundf((longitude - origin_longitude) * (longitude_count - 1))
	
	# return the data at those indices
	return _data[longitude_index][latitude_index]


## checks if the given coordinates are contained within this object
func contains(lat_long : LatitudeLongitude) -> bool:
	if dsi_data == null:
		return false
	
	var minimum_latitude : float = self.dsi_data.south_west_corner.latitude
	var minimum_longitude : float = self.dsi_data.south_west_corner.longitude
	var maximum_latitude : float = self.dsi_data.north_east_corner.latitude
	var maximum_longitude : float = self.dsi_data.north_east_corner.longitude
	
	var within_latitude_band : bool = minimum_latitude <= lat_long.latitude and lat_long.latitude <= maximum_latitude
	var within_longitude_band : bool = minimum_longitude <= lat_long.longitude and lat_long.longitude <= maximum_longitude
	
	return within_latitude_band and within_longitude_band


## Returns an array if everything is fine else returns null.
static func _parse_data_block(block : PackedByteArray):
	if block[0] != _DATA_SENTINEL:
		push_error(
			"All data blocks within a DTED file must begin with ", _DATA_SENTINEL
		)
		return null
	
	# raw data is defined by the specification as being from the 8th byte until
	# the excluding fourth last byte
	var raw_data : PackedByteArray = block.slice(8, block.size() - 4)
	
	var result : Array = []
	for i in range(0, raw_data.size(), 2):
		# slice the big endian number of the end the array
		var slice : PackedByteArray = raw_data.slice(i, i + 2)
		# reverse big endian to little endian so that it
		# is decodable by decode_s16()
		slice.reverse()
		# append decoded value to result
		result.append(slice.decode_s16(0))
	
	return result


## Converts an array of binary 16 bit integers between signed magnitude and 2's complement.
# TODO: so far unproperly tested
static func _convert_signed_magnitude(data : Array[Array]) -> Array[Array]:
	for outer : int in data.size():
		for inner : int in data[outer].size():
			if data[outer][inner] < 0:
				data[outer][inner] = -32768 - data[outer][inner]
			
	return data


class UserHdeaderLabel:
	## Is "UHL1" as byte literal
	const _SENTINEL : PackedByteArray = [85, 72, 76, 49]
	
	## origin: The origin of the DTED file as a latitude-longitude coordinate.
	var origin : LatitudeLongitude = null
	## longitude_interval: Longitude data interval in seconds.
	var longitude_interval : float = 0.0
	## latitude_interval: Latitude data interval in seconds.
	var latitude_interval : float
	## vertical_accuracy: Absolute vertical accuracy in meters (with 90%
	## assurance that the linear errors will not exceed this value relative
	## to mean sea level).
	var vertical_accuracy : int
	## security_code: The security code of the data (should be "U" for unclassified).
	var security_code : PackedByteArray
	## reference: Unique reference number.
	var reference_bytes : PackedByteArray
	## shape: The shape of the gridded data as number of longitude lines and
	## number of latitude lines.
	var shape : Tuple
	## multiple_accuracy: Whether multiple accuracy is enabled.
	var multiple_accuracy : bool
	## _data: raw binary data
	var _data : PackedByteArray
	
	static func from_bytes(bytes : PackedByteArray) -> UserHdeaderLabel:
		if bytes.size() < GeoData.UHL_SIZE:
			push_error(
				"Bytes Data too small"
			)
			return null
		
		var sentinel_length : int = _SENTINEL.size()
		if bytes.slice(0, sentinel_length) != _SENTINEL:
			push_error(
				"Invalid Sentinel"
			)
			return null
		
		# longitude and latitude string byte length is defined as 8 by the dted format specs
		var longitude_string : String = bytes.slice(sentinel_length, sentinel_length + 8).get_string_from_utf8()
		var latitude_string : String = bytes.slice(sentinel_length + 8, sentinel_length + 16).get_string_from_utf8()
		var origin : LatitudeLongitude = LatitudeLongitude.from_dted(latitude_string, longitude_string)
		
		var interval_start_byte : int = sentinel_length + 16
		var longitude_interval : float = float(bytes.slice(interval_start_byte, interval_start_byte + 4).get_string_from_utf8())
		
		var latitude_interval : float = float(bytes.slice(interval_start_byte + 4, interval_start_byte + 8).get_string_from_utf8())
		
		var accuracy_start_byte : int = interval_start_byte + 8
		var vertical_accuracy : int = float(bytes.slice(accuracy_start_byte, accuracy_start_byte + 4).get_string_from_utf8())
		
		var security_code : PackedByteArray = bytes.slice(accuracy_start_byte + 4, accuracy_start_byte + 7)
		var reference_bytes : PackedByteArray = bytes.slice(accuracy_start_byte + 7, accuracy_start_byte + 19)
		
		var shape_start_byte : int = accuracy_start_byte + 19
		var shape : Tuple = Tuple.new(
			float(bytes.slice(shape_start_byte, shape_start_byte + 4).get_string_from_utf8()),
			float(bytes.slice(shape_start_byte + 4, shape_start_byte + 8).get_string_from_utf8()),
		)
		
		var multiple_accuracy : bool = bytes.slice(shape_start_byte + 8, shape_start_byte + 9).get_string_from_utf8() != "0"
		
		# create result
		var result_uhl : UserHdeaderLabel = UserHdeaderLabel.new()
		result_uhl.origin = origin
		result_uhl.longitude_interval = longitude_interval / 10.0
		result_uhl.latitude_interval = latitude_interval / 10.0
		result_uhl.vertical_accuracy = vertical_accuracy
		result_uhl.security_code = security_code
		result_uhl.reference_bytes = reference_bytes
		result_uhl.shape = shape
		result_uhl.multiple_accuracy = multiple_accuracy
		result_uhl._data = bytes
		return result_uhl


class DataSetIdentification:
	## Is "DSI" as byte literal
	const _SENTINEL : PackedByteArray = [68, 83, 73]
	
	## security_code: The security code of the data (should be "U" for unclassified).
	var security_code : String
	## release_markings: Security control and release markings.
	var release_markings : PackedByteArray = []
	## handling_description: Security handling description.
	var handling_description : String
	## product_level: DMA Series designator for product level (i.e. DTED1 or DTED2).
	var product_level : String
	## reference: Unique reference number.
	var reference_bytes : PackedByteArray = []
	## edition: Data edition number (number between 1 and 99), if available.
	var edition : int
	## merge_version: match or merge version (single character A-Z).
	var merge_version : String
	## maintenance_date: Date of last maintenance (if it exists). NOTE: Only
	## year and month are provided -- no day specified.
	var maintenance_date : Date = null
	## merge_date: Date of last merge (if it exists). NOTE: Only year and month
	## are provided -- no day specified.
	var merge_date : Date = null
	## maintenance_code: Maintenance description code.
	var maintenance_code : PackedByteArray = []
	## producer_code: Code specifying the producer.
	var producer_code : PackedByteArray = []
	## product_specification: Code specifying the product.
	var product_specification : PackedByteArray = []
	## specification_date: Date of the product specification.
	var specification_date : Date = null
	## vertical_datum: The name of the vertical datum used to define elevation.
	var vertical_datum : String
	## horizontal_datum: The name of the horizontal datum used.
	var horizontal_datum : String
	## collection_system: The name of the digitizing or collection system.
	var collection_system : String
	## compilation_date: The date that the data was compiled.
	var compilation_date : Date
	## origin: The origin of the DTED file as a latitude-longitude coordinate.
	var origin : LatitudeLongitude = null
	## south_west_corner: The south west corner of the DTED data.
	var south_west_corner : LatitudeLongitude = null
	## north_west_corner: The north west corner of the DTED data.
	var north_west_corner : LatitudeLongitude = null
	## north_east_corner: The north east corner of the DTED data.
	var north_east_corner : LatitudeLongitude = null
	## south_east_corner: The south east corner of the DTED data.
	var south_east_corner : LatitudeLongitude = null
	## orientation: Clockwise orientation angle of data with respect to true
	## North, if it exists (this will usually be 0 for DTED).
	var orientation : float
	## longitude_interval: Longitude data interval in seconds.
	var longitude_interval : float
	## latitude_interval: Latitude data interval in seconds.
	var latitude_interval : float
	## shape: The shape of the gridded data as (number of longitude lines,
	## number of latitude lines).
	var shape : Tuple = null
	## coverage: Percentage of the cell covered by the DTED data, if available.
	var coverage : float
	## _data: raw binary data
	var _data : PackedByteArray = []
	
	static func from_bytes(bytes : PackedByteArray) -> DataSetIdentification:
		if bytes.size() < GeoData.DSI_SIZE:
			push_error(
				"Data Set Identification has length " + str(bytes.size()) + \
				" but should be " + str(GeoData.DSI_SIZE)
			)
			return null
		
		var sentinel_length : int = _SENTINEL.size()
		var sentinel : PackedByteArray = bytes.slice(0, sentinel_length)
		if sentinel != _SENTINEL:
			push_error(
				"Invalid Sentinel"
			)
			return null
		
		# first block
		var security_code : String = bytes.slice(sentinel_length, sentinel_length + 1).get_string_from_utf8()
		var release_marking : PackedByteArray = bytes.slice(sentinel_length + 1, sentinel_length + 3)
		var handling_description : String = bytes.slice(sentinel_length + 3, sentinel_length + 30).get_string_from_utf8()

		# there are empty (or at least unused) buffers between blocks
		# second block
		var second_block_start : int = sentinel_length + 56
		var product_level : String = bytes.slice(second_block_start, second_block_start + 5).get_string_from_utf8()
		var reference_bytes : PackedByteArray = bytes.slice(second_block_start + 5, second_block_start + 20)
		
		# there are empty (or at least unused) buffers between blocks
		# third block
		var third_block_start : int = second_block_start + 28
		var edition : int = int(bytes.slice(third_block_start, third_block_start + 2).get_string_from_utf8())
		var merge_version : String = bytes.slice(third_block_start + 2, third_block_start + 3).get_string_from_utf8()
		var maintenance_date : Date = Date.new(bytes.slice(third_block_start + 3, third_block_start + 7).get_string_from_utf8())
		var merge_date : Date = Date.new(bytes.slice(third_block_start + 7, third_block_start + 11).get_string_from_utf8())
		var maintenance_code : PackedByteArray = bytes.slice(third_block_start + 11, third_block_start + 15)
		var producer_code : PackedByteArray = bytes.slice(third_block_start + 15, third_block_start + 23)
		
		# there are empty (or at least unused) buffers between blocks
		# fourth block
		var fourth_block_start : int = third_block_start + 39
		var product_specification : PackedByteArray = bytes.slice(fourth_block_start, fourth_block_start + 11)
		var specification_date : Date = Date.new(bytes.slice(fourth_block_start + 11, fourth_block_start + 15).get_string_from_utf8())
		var vertical_datum : String = bytes.slice(fourth_block_start + 15, fourth_block_start + 18).get_string_from_utf8()
		var horizontal_datum : String = bytes.slice(fourth_block_start + 18, fourth_block_start + 23).get_string_from_utf8()
		var collection_system : String = bytes.slice(fourth_block_start + 23, fourth_block_start + 33).get_string_from_utf8()
		var compilation_date : Date = Date.new(bytes.slice(fourth_block_start + 33, fourth_block_start + 37).get_string_from_utf8())
		
		# there are empty (or at least unused) buffers between blocks
		# fifth block
		var fifth_block_start : int = fourth_block_start + 59
		var origin : LatitudeLongitude = LatitudeLongitude.from_dted(
			bytes.slice(fifth_block_start, fifth_block_start + 9).get_string_from_utf8(),
			bytes.slice(fifth_block_start + 9, fifth_block_start + 19).get_string_from_utf8()
		)
		var south_west_corner : LatitudeLongitude = LatitudeLongitude.from_dted(
			bytes.slice(fifth_block_start + 19, fifth_block_start + 26).get_string_from_utf8(),
			bytes.slice(fifth_block_start + 26, fifth_block_start + 34).get_string_from_utf8()
		)
		var north_west_corner : LatitudeLongitude = LatitudeLongitude.from_dted(
			bytes.slice(fifth_block_start + 34, fifth_block_start + 41).get_string_from_utf8(),
			bytes.slice(fifth_block_start + 41, fifth_block_start + 49).get_string_from_utf8()
		)
		var north_east_corner : LatitudeLongitude = LatitudeLongitude.from_dted(
			bytes.slice(fifth_block_start + 49, fifth_block_start + 56).get_string_from_utf8(),
			bytes.slice(fifth_block_start + 56, fifth_block_start + 64).get_string_from_utf8()
		)
		var south_east_corner : LatitudeLongitude = LatitudeLongitude.from_dted(
			bytes.slice(fifth_block_start + 64, fifth_block_start + 71).get_string_from_utf8(),
			bytes.slice(fifth_block_start + 71, fifth_block_start + 79).get_string_from_utf8()
		)
		var orientation : float = float(bytes.slice(fifth_block_start + 79, fifth_block_start + 88).get_string_from_utf8())
		var latitude_interval : float = int(bytes.slice(fifth_block_start + 88, fifth_block_start + 92).get_string_from_utf8())
		var longitude_interval : float = int(bytes.slice(fifth_block_start + 92, fifth_block_start + 96).get_string_from_utf8())
		var shape : Tuple = Tuple.new( # this shape apparently must be constructed in the reverse order
			float(bytes.slice(fifth_block_start + 100, fifth_block_start + 104).get_string_from_utf8()),
			float(bytes.slice(fifth_block_start + 96, fifth_block_start + 100).get_string_from_utf8())
		)
		var coverage : float = float(bytes.slice(fifth_block_start + 104, fifth_block_start + 106).get_string_from_utf8())
		
		# idk
		if coverage == 0:
			coverage = 1.0
		
		var data_set_identification : DataSetIdentification = DataSetIdentification.new()
		data_set_identification.security_code = security_code
		data_set_identification.release_markings = release_marking
		data_set_identification.handling_description = handling_description
		data_set_identification.product_level = product_level
		data_set_identification.reference_bytes = reference_bytes
		data_set_identification.edition = edition
		data_set_identification.merge_version = merge_version
		data_set_identification.maintenance_date = maintenance_date
		data_set_identification.merge_date = merge_date
		data_set_identification.maintenance_code = maintenance_code
		data_set_identification.producer_code = producer_code
		data_set_identification.product_specification = product_specification
		data_set_identification.specification_date = specification_date
		data_set_identification.vertical_datum = vertical_datum
		data_set_identification.horizontal_datum = horizontal_datum
		data_set_identification.collection_system = collection_system
		data_set_identification.compilation_date = compilation_date
		data_set_identification.origin = origin
		data_set_identification.south_west_corner = south_west_corner
		data_set_identification.south_east_corner = south_east_corner
		data_set_identification.north_east_corner = north_east_corner
		data_set_identification.north_west_corner = north_west_corner
		data_set_identification.orientation = orientation
		data_set_identification.latitude_interval = latitude_interval / 10.0
		data_set_identification.longitude_interval = longitude_interval / 10.0
		data_set_identification.shape = shape
		data_set_identification.coverage = coverage
		data_set_identification._data = bytes
		return data_set_identification


class AccuracyDescription:
	## Is "ACC" as byte literal
	const _SENTINEL : PackedByteArray = [65, 67, 67]
	
	var absolute_horizontal # of type optional int, so it is int but could also be null
	var absolute_vertical # of type optional int, so it is int but could also be null
	var relative_horizontal # of type optional int, so it is int but could also be null
	var relative_vertical # of type optional int, so it is int but could also be null
	var _data : PackedByteArray = []
	
	static func from_bytes(bytes : PackedByteArray) -> AccuracyDescription:
		if bytes.size() < GeoData.ACC_SIZE:
			push_error(
				"Accuracy Description has length " + str(bytes.size()) + \
				" but should be " + str(GeoData.ACC_SIZE)
			)
			return null
		
		var sentinel_length : int = _SENTINEL.size()
		
		if bytes.slice(0, sentinel_length) != _SENTINEL:
			push_error(
				"Invalid Sentinel"
			)
			return null
		
		var absolute_horizontal_string : String = bytes.slice(sentinel_length, sentinel_length + 4).get_string_from_utf8()
		var absolute_vertical_string : String = bytes.slice(sentinel_length + 4, sentinel_length + 8).get_string_from_utf8()
		var relative_horizontal_string : String = bytes.slice(sentinel_length + 8, sentinel_length + 12).get_string_from_utf8()
		var relative_vertical_string : String = bytes.slice(sentinel_length + 12, sentinel_length + 16).get_string_from_utf8()
		
		var accuracy_description : AccuracyDescription = AccuracyDescription.new()
		accuracy_description.absolute_horizontal = int(absolute_horizontal_string) if absolute_horizontal_string.is_valid_float() else null
		accuracy_description.absolute_vertical = int(absolute_vertical_string) if absolute_vertical_string.is_valid_float() else null
		accuracy_description.relative_horizontal = int(relative_horizontal_string) if relative_horizontal_string.is_valid_float() else null
		accuracy_description.relative_vertical = int(relative_vertical_string) if relative_vertical_string.is_valid_float() else null
		
		accuracy_description._data = bytes
		
		return accuracy_description


class LatitudeLongitude:
	var latitude : float = 0.0
	var longitude : float = 0.0
	
	func _init(lat : float, lon : float) -> void:
		self.latitude = lat
		self.longitude = lon
		
		if lat < -90 or lat > 90:
			push_error(
				"Latitude value must be between -90 and 90. Found: " + str(latitude)
			)
		if lon < -180 or lon > 180:
			push_error(
				"Longitude value must be between -180 and 180. Found: " + str(longitude)
			)
	
	static func from_dted(lat_str : String, long_str : String) -> LatitudeLongitude:
		var lat_sign : int = -1 if lat_str[-1] == "S" else 1
		var latitude : float = lat_sign * dms_coordinate_to_decimal(
			DMSCoordinate.parse_dms_coordinate(lat_str.substr(0, lat_str.length() - 1))
		)
		
		var lon_sign : int = -1 if long_str[-1] == "W" else 1
		var longitude : float = lon_sign * dms_coordinate_to_decimal(
			DMSCoordinate.parse_dms_coordinate(long_str.substr(0, long_str.length() - 1))
		)
		return LatitudeLongitude.new(latitude, longitude)
	
	## Converts values of a degree-minute-second coordinate to a decimal-degree coordinate.
	static func dms_to_decimal(degree: int, minute: int, second: float) -> float:
		return degree + ((minute + (second / 60)) / 60)
	
	## Converts a [DMSCoordinate] to a decimal-degree coordinate.
	static func dms_coordinate_to_decimal(coord : DMSCoordinate) -> float:
		return dms_to_decimal(coord.degrees, coord.minutes, coord.seconds)


class DMSCoordinate:
	var degrees : int = 0
	var minutes : int = 0
	var seconds : float = 0.0
	
	func _init(degree : int, minute : int, second : float) -> void:
		self.degrees = degree
		self.minutes = minute
		self.seconds = second
	
	## Parse a [DMSCoordinate] from a DTED coordinate string.
	## The DTED coordinate string has the following format: [D]DDMMSS[.S] where
	## D is Degree, M is Minute and S is Second. Args are coordinates:
	## DTED coordinate string (without the hemisphere identifier). Method returns
	## [DMSCoordinate] (degree minute second coordinate)
	static func parse_dms_coordinate(coordinate : String) -> DMSCoordinate:
		var seconds_index : int = -4 if coordinate[-2] == "." else -2
		var minutes_index : int = seconds_index - 2
		
		var degrees : int = coordinate.substr(0, coordinate.length() + minutes_index).to_int()
		var minutes : int = coordinate.substr(coordinate.length() + minutes_index, seconds_index - minutes_index).to_int()
		var seconds : float = coordinate.substr(coordinate.length() + seconds_index).to_float()
		
		return DMSCoordinate.new(degrees, minutes, seconds)


class Date:
	# TODO: implement or substitude this if you actually need a functional
	# Date class, because this is barely even more than a placeholder.
	var _date_string : String = ""
	
	func _init(date_string : String) -> void:
		self._date_string = date_string
	
	
	func get_date_string() -> String:
		return self._date_string
	
	
	func _to_string() -> String:
		return get_date_string()


## Helper class similar to Tuples in Python.
class Tuple:
	var _left
	var _right
	
	func _init(left, right) -> void:
		self._left = left
		self._right = right
	
	func left():
		return _left
	
	func right():
		return _right
