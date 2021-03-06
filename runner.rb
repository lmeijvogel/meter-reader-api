require 'pathname'
require 'mysql2'
require 'dotenv'
require 'json'
require 'serialport'

$LOAD_PATH << File.expand_path("../lib", __FILE__)

require "p1_meter_reader/data_parsing/stream_splitter"
require "p1_meter_reader/data_parsing/fake_stream_splitter"
require "p1_meter_reader/data_parsing/water_measurement_listener"
require "p1_meter_reader/data_parsing/fake_water_measurement_listener"
require "p1_meter_reader/models/water_measurement_parser"
require "p1_meter_reader/recorder"

require "database_connection_factory"
require "database_reader"
require "output/database_writer"
require "database_config"

require "current_water_usage_store"
require "recent_measurement_store"

ROOT_PATH = Pathname.new File.dirname(__FILE__)

Dotenv.load

def get_last_water_measurement(environment)
  database_reader = DatabaseReader.new(DatabaseConnectionFactory.new(environment))

  database_reader.last_measurement.water
end

def main
  environment = ENV.fetch('ENVIRONMENT')

  measurement_counter = 0

  database_writer = DatabaseWriter.new(DatabaseConnectionFactory.new(environment))
  database_writer.save_interval = 5

  recent_measurement_store = RecentMeasurementStore.new(
    number_of_entries: 8 * 60, # 8 hours at 1 measurement per minute
    redis_list_name: ENV.fetch("REDIS_LIST_NAME")
  )

  current_water_usage_store = CurrentWaterUsageStore.new

  last_water_measurement = 0
  last_measurement = :no_last_measurement

  if environment == "production"
    last_water_measurement = get_last_water_measurement(environment)

    stream_splitter = P1MeterReader::DataParsing::StreamSplitter.new(ENV.fetch("P1_CONVERTER_MESSAGE_START"), input: serial_port)
    water_data_source = P1MeterReader::DataParsing::WaterMeasurementListener.new
  else
    puts "Fake stream splitter"
    stream_splitter = P1MeterReader::DataParsing::FakeStreamSplitter.new
    water_data_source = P1MeterReader::DataParsing::FakeWaterMeasurementListener.new
  end

  water_measurement_parser = P1MeterReader::Models::WaterMeasurementParser.new(last_water_measurement)

  water_measurement_parser.on_tick = ->() {
    current_water_usage_store.add_tick DateTime.now
  }

  recorder = P1MeterReader::Recorder.new(
    p1_data_source: stream_splitter,
    water_data_source: water_data_source,
    water_measurement_parser: water_measurement_parser
  )

  recorder.collect_data do |measurement|
    if valid?(measurement, last_measurement)
      json = measurement_to_json(measurement, measurement_counter)

      database_writer.save_unless_exists(measurement)
      recent_measurement_store.add(json)
      current_water_usage_store.add(measurement)

      measurement_counter += 1

      last_measurement = measurement
    end
  end
end

def measurement_to_json(measurement, measurement_counter)
  stroom = measurement.stroom_dal.to_f + measurement.stroom_piek.to_f

  {
    id:               measurement_counter,
    time_stamp:       measurement.time_stamp.to_s,
    time_stamp_utc:   measurement.time_stamp_utc.to_s,
    stroom:           stroom,
    stroom_current:   measurement.stroom_current.to_f,
    gas:              measurement.gas.to_f,
    water:            measurement.water.to_f
  }.to_json
end

def valid?(measurement, last_measurement)
  if last_measurement == :no_last_measurement
    measurement_not_zero?(measurement)
  else
    # The new meter is a bit less trustworthy and will sometimes report
    # invalid energy measurements, e.g. 0 or less than it should
    return false if measurement.stroom_dal.to_f < last_measurement.stroom_dal.to_f
    return false if measurement.stroom_piek.to_f < last_measurement.stroom_piek.to_f
    return false if measurement.gas < last_measurement.gas
    return false if measurement.water < last_measurement.water

    true
  end
end

def measurement_not_zero?(measurement)
  return false if measurement.stroom_dal.to_f.abs < 0.01
  return false if measurement.stroom_piek.to_f.abs < 0.01
  return false if measurement.gas.abs < 0.01
  return false if measurement.water.abs < 0.01

  true
end

def serial_port
  device = ENV.fetch("P1_CONVERTER_DEVICE")
  baud_rate = Integer(ENV.fetch("P1_CONVERTER_BAUD_RATE"))

  serial_port = SerialPort.new(device, baud_rate)
  serial_port.data_bits = 7
  serial_port.stop_bits = 1
  serial_port.parity = SerialPort::EVEN

  serial_port
end

puts "Starting..."
main
