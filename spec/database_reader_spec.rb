require "spec_helper"
require 'mysql2'

require "p1_meter_reader/models/usage"
require "output/database_writer"
require "database_reader"

describe DatabaseReader do
  let(:time_stamp_1) { DateTime.now }
  let(:stroom_dal_1) { 12.23 }
  let(:stroom_piek_1) { 23.34 }
  let(:gas_1) { 12.23 }

  let(:time_stamp_2) { DateTime.now }
  let(:stroom_dal_2) { 13.23 }
  let(:stroom_piek_2) { 25.34 }
  let(:gas_2) { 12.23 }

  let(:stroom_totaal_1) { stroom_dal_1 + stroom_piek_1 }
  let(:stroom_totaal_2) { stroom_dal_2 + stroom_piek_2 }

  let(:config) { YAML.load(File.read(File.join(ROOT_PATH.join("database.yml"))))["test"] }
  let(:database_connection) { Mysql2::Client.new(host: config["host"],
                                                 database: config["database"],
                                                 username: config["username"],
                                                 password: config["password"])
  }

  let(:writer) { DatabaseWriter.new(database_connection) }
  let(:reader) { DatabaseReader.new(database_connection) }

  before do
    database_connection.query("DELETE FROM measurements")
    database_connection.query("INSERT INTO measurements(
                              time_stamp, stroom_dal, stroom_piek, gas)
                              VALUES ('#{time_stamp_1}', '#{stroom_dal_1}', '#{stroom_piek_1}', '#{gas_1}'),
                                     ('#{time_stamp_2}', '#{stroom_dal_2}', '#{stroom_piek_2}', '#{gas_2}')")

    reader.send(:granularity=, :hour)
    @usage = reader.read().first
  end

  it "sets the correct stroom_totaal" do
    @usage.stroom_totaal.should be_within(0.01).of(stroom_totaal_1)
  end

  it "sets the correct gas" do
    @usage.gas.should be_within(0.01).of(gas_1)
  end

  it "sets the correct time_stamp" do
    @usage.time_stamp.to_s.should == time_stamp_1.to_s
  end
end
