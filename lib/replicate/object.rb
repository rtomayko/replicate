module Replicate
  # Simple OpenStruct style object that supports the dump and load protocols.
  # Useful in tests and also when you want to dump an object that doesn't
  # implement the dump and load methods.
  #
  #     >> object = Replicate::Object.new :name => 'Joe', :age => 24
  #     >> object.age
  #     >> 24
  #     >> object.attributes
  #     { 'name' => 'Joe', 'age' => 24 }
  #
  class Object
    attr_accessor :id
    attr_accessor :attributes

    def initialize(id=nil, attributes={})
      attributes, id = id, nil if id.is_a?(Hash)
      @id = id || self.class.generate_id
      self.attributes = attributes
    end

    def attributes=(hash)
      @attributes = {}
      hash.each { |key, value| write_attribute key, value }
    end

    def [](key)
      @attributes[key.to_s]
    end

    def []=(key, value)
      @attributes[key.to_s] = value
    end

    def write_attribute(key, value)
      meta = (class<<self;self;end)
      meta.send(:define_method, key) { value }
      meta.send(:define_method, "#{key}=") { |val| write_attribute(key, val) }
      @attributes[key.to_s] = value
      value
    end

    def dump_replicant(dumper)
      dumper.write self.class, @id, @attributes, self
    end

    def self.load_replicant(type, id, attrs)
      object = new(generate_id, attrs)
      [object.id, object]
    end

    def self.generate_id
      @last_id ||= 0
      @last_id += 1
    end
  end
end
