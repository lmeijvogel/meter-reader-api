require 'sinatra'

require 'mysql2'
require 'json'
require 'pathname'
require 'fileutils'
require 'connection_pool'
require 'bcrypt'
require 'redis'
require 'dotenv'

require 'digest/sha1'

require_relative '../lib/database_config.rb'
require_relative '../lib/database_reader.rb'

NoPasswordsFile = Class.new(StandardError)
UsernameNotFound = Class.new(StandardError)

ROOT_PATH = Pathname.new(File.join(File.dirname(__FILE__), "..")).realpath
Dotenv.load

set :bind, '0.0.0.0'

FileUtils.mkdir_p(ROOT_PATH.join("tmp/cache"))

$database = ConnectionPool.new(size: 2) do
  Mysql2::Client.new(DatabaseConfig.for(settings.environment))
end

class EnergieApi < Sinatra::Base
  configure do
    # Storing login information in cookies is good enough for our purposes
    one_year = 60*60*24*365
    secret = ENV.fetch('SESSION_SECRET')
    use Rack::Session::Cookie, :expire_after => one_year, :secret => secret

    set :static, false
  end

  before do
    assert_logged_in unless request.path.include?("login")
  end

  get "/" do
    status 204
  end

  get "/day/:year/:month/:day" do
    day = DateTime.new(params[:year].to_i, params[:month].to_i, params[:day].to_i)

    cached(:day, day) do
      $database.with {|database_connection|
        database_reader = DatabaseReader.new(database_connection)

        database_reader.day = day

        database_reader.read().to_json
      }
    end
  end

  get "/month/:year/:month" do
    $database.with {|database_connection|
      database_reader = DatabaseReader.new(database_connection)

      database_reader.month = DateTime.new(params[:year].to_i, params[:month].to_i)

      database_reader.read().to_json
    }
  end

  get "/energy/current" do
    result = JSON.parse(Redis.new.get("measurement"))

    @id = result["id"];
    @current_measurement = result["stroom_current"]

    { id: @id, current: @current_measurement }.to_json
  end

  def cached(prefix, date)
    cache_file = ROOT_PATH.join("tmp", "cache", "#{prefix}_#{date.year}_#{date.month}_#{date.day}")

    should_cache = production? && date < Date.today
    if should_cache
      if File.exist?(cache_file)
        File.read(cache_file)
      else
        contents = yield
        File.open(cache_file, "w") do |file|
          file.write contents
        end
        contents
      end
    else
      yield
    end
  end

  post "/login/create" do
    username = params["username"]
    password = params["password"]

    begin
      stored_password_hash = read_password_hash(username)

      password_valid = BCrypt::Password.new(stored_password_hash) == password
      if password_valid
        session.clear
        session[:username] = username

        status 200
        "Welcome!"
      else
        invalid_username_or_password!
      end
    rescue UsernameNotFound, BCrypt::Errors::InvalidHash
      invalid_username_or_password!
    rescue NoPasswordsFile
      halt 401, "No passwords file"
    end
  end

  def read_password_hash(username)
    raise NoPasswordsFile unless File.exists? "passwords"

    password_hashes = YAML.load(File.read("passwords"))

    password_hashes.fetch(username) { raise UsernameNotFound }
  end

  def invalid_username_or_password!
    halt 401, "Invalid username or password"
  end

  def assert_logged_in
    if session[:username].nil?
      halt 401, "Not logged in"
    else
      pass
    end
  end

  def production?
    ENV.fetch("RACK_ENV") == "production"
  end
end
