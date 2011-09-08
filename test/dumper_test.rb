require 'test/unit'
require 'stringio'
require 'replicate'

class DumperTest < Test::Unit::TestCase
  def setup
    @dumper = Replicate::Dumper.new
  end

  def thing(attrs={})
    attrs = {'number' => 123, 'string' => 'hello', 'time' => Time.new}.merge(attrs)
    Replicate::Object.new attrs
  end

  def test_basic_filter
    called = false
    object = thing('test' => 'value')
    @dumper.filter do |type, id, attrs, obj|
      assert !called
      assert_equal 'DumperTest::Thing', type
      assert_equal object.id, id
      assert_equal 'value', attrs['test']
      assert_equal object.attributes, attrs
      called = true
    end
    @dumper.dump object
    assert called
  end

  def test_failure_when_object_not_respond_to_dump_replicant
    assert_raise(NoMethodError) { @dumper.dump Object.new }
  end

  def test_never_dumps_objects_more_than_once
    called = false
    object = thing('test' => 'value')
    @dumper.filter do |type, id, attrs, obj|
      assert !called
      called = true
    end
    @dumper.dump object
    @dumper.dump object
    @dumper.dump object
    assert called
  end

  def test_writing_to_io
    io = StringIO.new
    @dumper.marshal_to io
    @dumper.dump object = thing
    assert_equal Marshal.dump([Thing.to_s, object.id, object.attributes]), io.string
  end

  def test_stats
    10.times { @dumper.dump thing }
    assert_equal({Thing.to_s => 10}, @dumper.stats)
  end

  def test_block_form_runs_complete
    called = false
    Replicate::Dumper.new do |dumper|
      filter = lambda { |*args| }
      (class <<filter;self;end).send(:define_method, :complete) { called = true }
      dumper.filter filter
      dumper.dump thing
      assert !called
    end
    assert called
  end
end
