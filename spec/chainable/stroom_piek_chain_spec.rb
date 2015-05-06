require 'spec_helper'
require 'measurement'
require 'data_parsing/parse_chain/stroom_piek_chain.rb'

describe StroomPiekChain do
  describe :can_handle? do
    subject { StroomPiekChain.new.can_handle?(line) }

    context "when the line starts with 1-0:1.8.2" do
      let(:line) { "1-0:1.8.2(00557.379*kWh)" }

      it { should == true }
    end

    context "when the line starts with something else" do
      let(:line) { "1-0:1.8.1(00610.251*kWh)" }

      it { should == false }
    end
  end

  describe :handle do
    let(:output) { Measurement.new }
    let(:next_line) { "next line" }
    let(:lines) { ["1-0:1.8.2(00557.379*kWh)", next_line].to_enum }

    it "sets the correct amount in :stroom_piek" do
      subject.handle(lines, output)

      output.stroom_piek.should == 557.379.kWh
    end

    it "notes the previous value" do
      subject.handle(lines, output)

      subject.last_value.should == 557.370.kWh
    end

    it "stores the difference from the last value" do
      subject.last_value = 557.370.kWh

      subject.handle(lines, output)

      output.diff_stroom_piek.should == 0.009.kWh
    end

    it "advances the enumerator" do
      subject.handle(lines, output)

      lines.next.should == next_line
    end
  end
end
