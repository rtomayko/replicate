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
    @dumper.listen do |type, id, attrs, obj|
      assert !called
      assert_equal 'Replicate::Object', type
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
    @dumper.listen do |type, id, attrs, obj|
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
    io.set_encoding 'BINARY' if io.respond_to?(:set_encoding)
    @dumper.marshal_to io
    @dumper.dump object = thing
    data = Marshal.dump(['Replicate::Object', object.id, object.attributes])
    assert_equal data, io.string
  end

  def test_stats
    10.times { @dumper.dump thing }
    assert_equal({'Replicate::Object' => 10}, @dumper.stats)
  end

  def test_block_form_runs_complete
    called = false
    Replicate::Dumper.new do |dumper|
      filter = lambda { |*args| }
      (class <<filter;self;end).send(:define_method, :complete) { called = true }
      dumper.listen filter
      dumper.dump thing
      assert !called
    end
    assert called
  end

  def test_loading_dump_scripts
    called = false
    @dumper.listen do |type, id, attrs, obj|
      assert !called
      called = true
    end
    @dumper.load_script File.expand_path('../dumpscript.rb', __FILE__)
    assert called
  end

  def test_dump_scripts_can_load_additional
    called = false
    @dumper.listen do |type, id, attrs, obj|
      assert !called
      called = true
    end
    @dumper.load_script File.expand_path('../linked_dumpscript.rb', __FILE__)
    assert called
  end

  def test_load_script_uses_load_path
    called = false
    @dumper.listen do |type, id, attrs, obj|
      assert !called
      called = true
    end
    $LOAD_PATH << File.dirname(__FILE__)
    @dumper.load_script 'linked_dumpscript'
    assert called
  end
end
