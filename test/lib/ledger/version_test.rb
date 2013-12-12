require_relative '../../test_helper'
 
describe Riak::Ledger do
 
  it "must be defined" do
    puts Riak::Ledger::VERSION.wont_be_nil
  end
 
end
