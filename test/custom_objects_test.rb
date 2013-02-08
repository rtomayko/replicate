require 'test/unit'
require 'stringio'
require 'replicate'

class MyCustomObject
  attr_accessor :custom_val

  def dump_replicant(dumper)
    attributes = { 'test' => 'value' }
    dumper.write self.class, 3, attributes, self
  end

  def self.load_replicant(type, id, attributes)
    @test = attributes['context']
    @test.assert_equal 5, id
    @test.assert_equal 'value', attributes['test']
    @test.assert_equal 'MyCustomObject', type
    obj = MyCustomObject.new
    obj.custom_val = 'custom'
    [id, obj]
  end
end

class CustomObjectsTest < Test::Unit::TestCase
  def test_custom_dump
    @dumper = Replicate::Dumper.new
    called = false
    object = MyCustomObject.new
    @dumper.listen do |type, id, attrs, obj|
      assert !called
      assert_equal 'MyCustomObject', type
      assert_equal 3, id
      assert_equal({ 'test' => 'value' }, attrs)
      called = true
    end
    @dumper.dump object
    assert called
  end

  def test_custom_load
    @loader = Replicate::Loader.new
    called = false
    object = MyCustomObject.new
    @loader.listen do |type, id, attrs, obj|
      assert !called
      assert_equal 'MyCustomObject', type
      assert_equal 'custom', obj.custom_val
      called = true
    end
    @loader.feed object.class, 5, { 'test' => 'value', 'context' => self }
    assert called
  end
end
