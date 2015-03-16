require 'pathname'
require 'serialport'
require 'mysql2'
require 'trollop'

require_relative "models/meterstand.rb"
require_relative "lib/data_parsing/stream_splitter.rb"
require_relative "lib/output/database_writer.rb"
require_relative "lib/output/redis_writer.rb"
require_relative "lib/database_config.rb"

require_relative 'daemon.rb'

ROOT_PATH = Pathname.new File.dirname(__FILE__)

opts = Trollop::options do
  opt :env, "Environment", default: "development"
  opt :pidfile, "PID file", default: "/var/run/runner.pid"
  opt :no_fork, "Don't daemonize", default: false
end

class MeterstandenRecorder
  def initialize(options)
    database_connection = Mysql2::Client.new(DatabaseConfig.for(options[:environment]))

    self.database_writer = DatabaseWriter.new(database_connection)
    self.database_writer.save_interval = 15
    self.redis_writer    = RedisWriter.new
    self.meterstanden_parser = Meterstand.new
    self.stream_splitter = StreamSplitter.new(serial_port, "/XMX5XMXABCE100129872")
  end

  def collect_data
    loop do
      message = stream_splitter.read

      measurement = meterstanden_parser.parse(message)
      database_writer.save_unless_exists(measurement)
      redis_writer.save(measurement)
    end
  end

  protected
  attr_accessor :database_writer, :redis_writer, :meterstanden_parser, :stream_splitter

  private
  def serial_port
    serial_port = SerialPort.new("/dev/ttyUSB0", 9600)
    serial_port.data_bits = 7
    serial_port.stop_bits = 1
    serial_port.parity = SerialPort::EVEN

    serial_port
  end
end

daemon = Daemon.new(process_name: "meterstanden", pidfile: opts[:pidfile], daemonize: !opts[:no_fork])

recorder = MeterstandenRecorder.new(environment: opts[:env])

daemon.run do
  recorder.collect_data
end
