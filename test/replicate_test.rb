require 'test/unit'

class ReplicateTest < Test::Unit::TestCase
  def test_auto_loading
    require 'replicate'
    Replicate::Dumper
    Replicate::Loader
    Replicate::Status
  end
end
