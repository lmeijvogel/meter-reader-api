require 'data_parsing/parse_chain/chainable'

class GasChain < Chainable
  def can_handle?(line)
    line.start_with? '0-1:24.3.0'
  end

  def handle(lines_enumerator, output)
    lines_enumerator.next # Skip the intro line
    line = lines_enumerator.next

    match = line.match(/\((\d*\.\d*)\)/)
    output.gas = match[1].to_f if match
  end
end