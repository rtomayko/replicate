module Replicate
  # Dump replicants in a streaming fashion.
  #
  # The Dumper takes objects and generates one or more replicant objects. A
  # replicant has the form [type, id, attributes] and describes exactly one
  # addressable record in a datastore. The type and id identify the model
  # class name and model primary key id. The attributes Hash is a set of attribute
  # name to primitively typed object value mappings.
  #
  # Example dump session:
  #
  #     >> Replicate::Dumper.new do |dumper|
  #     >>   dumper.marshal_to $stdout
  #     >>   dumper.log_to $stderr
  #     >>   dumper.dump User.find(1234)
  #     >> end
  #
  class Dumper
    # Create a new Dumper.
    #
    # io     - IO object to write marshalled replicant objects to.
    # block  - Dump context block. If given, the end of the block's execution
    #          is assumed to be the end of the dump stream.
    def initialize(io=nil)
      @filters = []
      @memo = Hash.new { |hash,k| hash[k] = {} }

      marshal_to io if io
      if block_given?
        yield self
        complete
      end
    end

    # Register a dump filter. Guaranteed to be called exactly once per
    # distinct object with the type, id, attributes, object structure. Filters
    # may modify the attributes hash to modify the view of successive filters.
    # Filters are executed in the reverse order of which they were registered.
    # This means filters registered later modify the view of filters
    # registered earlier.
    #
    # Dump filters are used to implement all output generating as well as
    # logging status output.
    #
    # p - An optional Proc object. Must respond to call.
    # block - An optional block.
    #
    # Returns nothing.
    def filter(p=nil, &block)
      @filters.unshift p if p
      @filters.unshift block if block
    end

    # Sugar for creating a filter with an object instance. Instances of the
    # class must respond to call(type, id, attrs, object).
    #
    # klass - The class to create. Must respond to new.
    # args  - Arguments to pass to klass#new in addition to self.
    #
    # Returns the object created.
    def use(klass, *args, &block)
      instance = klass.new(self, *args, &block)
      filter instance
      instance
    end

    # Notify all filters that processing is complete.
    def complete
      @filters.each { |f| f.complete if f.respond_to?(:complete) }
    end

    # Register a filter to write marshalled data to the given IO object.
    def marshal_to(io)
      filter do |type, id, attrs, obj|
        Marshal.dump([type, id, attrs], io)
      end
    end

    # Register a filter to write status information to the given stream. By
    # default, a single line is used to report object counts while the dump is
    # in progress; dump counts for each class are written when complete. The
    # verbose and quiet options can be used to increase or decrease
    # verbosity.
    #
    # out - An IO object to write to, like stderr.
    # verbose - Whether verbose output should be enabled.
    # quiet - Whether quiet output should be enabled.
    #
    # Returns the Replicate::Status object.
    def log_to(out=$stderr, verbose=false, quiet=false)
      use Replicate::Status, 'dump', out, verbose, quiet
    end

    # Dump one or more objects to the internal array or provided dump
    # stream. This method guarantees that the same object will not be dumped
    # more than once.
    #
    # objects - ActiveRecord object instances.
    #
    # Returns nothing.
    def dump(*objects)
      objects = objects[0] if objects.size == 1 && objects[0].respond_to?(:to_ary)
      objects.each do |object|
        next if object.nil? || dumped?(object)
        if object.respond_to?(:dump_replicant)
          object.dump_replicant(self)
        else
          raise NoMethodError, "#{object.class} must define #dump_replicant"
        end
      end
    end

    # Check if object has been written yet.
    def dumped?(object)
      if object.respond_to?(:replicant_id)
        type, id = object.replicant_id
      elsif object.is_a?(Array)
        type, id = object
      else
        return false
      end
      @memo[type.to_s][id]
    end

    # Called exactly once per unique type and id. Runs all registered filters.
    #
    # type       - The model class name as a String.
    # id         - The record's id. Usually an integer.
    # attributes - All model attributes.
    # object     - The object this dump is generated for.
    #
    # Returns nothing.
    def write(type, id, attributes, object)
      type = type.to_s
      return if dumped?([type, id])
      @memo[type][id] = true

      @filters.each { |meth| meth.call(type, id, attributes, object) }
    end

    # Retrieve dumped object counts for all classes.
    #
    # Returns a Hash of { class_name => count } where count is the number of
    # objects dumped with a class of class_name.
    def stats
      stats = {}
      @memo.each { |class_name, items| stats[class_name] = items.size }
      stats
    end
  end
end
