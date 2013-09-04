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
  class Dumper < Emitter
    # Create a new Dumper.
    #
    # io     - IO object to write marshalled replicant objects to.
    # block  - Dump context block. If given, the end of the block's execution
    #          is assumed to be the end of the dump stream.
    def initialize(io=nil)
      @memo = Hash.new { |hash,k| hash[k] = {} }
      super() do
        marshal_to io if io
        yield self if block_given?
      end
    end

    # Register a filter to write marshalled data to the given IO object.
    def marshal_to(io)
      listen { |type, id, attrs, obj| Marshal.dump([type, id, attrs], io) }
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

    # Load a dump script. This evals the source of the file in the context
    # of a special object with a #dump method that forwards to this instance.
    # Dump scripts are useful when you want to dump a lot of stuff. Call the
    # dump method as many times as necessary to dump all objects.
    def load_script(path)
      dumper = self
      object = ::Object.new
      meta = (class<<object;self;end)
      [:dump, :load_script].each do |method|
        meta.send(:define_method, method) { |*args| dumper.send(method, *args) }
      end
      file = find_file(path)
      object.instance_eval File.read(file), file, 0
    end

    # Dump one or more objects to the internal array or provided dump
    # stream. This method guarantees that the same object will not be dumped
    # more than once.
    #
    # objects - ActiveRecord object instances.
    #
    # Returns nothing.
    def dump(*objects)
      opts = if objects.last.is_a? Hash
        objects.pop
      else
        {}
      end
      objects = objects[0] if objects.size == 1 && objects[0].respond_to?(:to_ary)
      objects.each do |object|
        next if object.nil? || dumped?(object)
        if object.respond_to?(:dump_replicant)
          args = [self]
          args << opts unless object.method(:dump_replicant).arity == 1
          object.dump_replicant(*args)
        else
          raise NoMethodError, "#{object.class} must respond to #dump_replicant"
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

    # Called exactly once per unique type and id. Emits to all listeners.
    #
    # type       - The model class name as a String.
    # id         - The record's id. Usually an integer.
    # attributes - All model attributes.
    # object     - The object this dump is generated for.
    #
    # Returns the object.
    def write(type, id, attributes, object)
      type = type.to_s
      return if dumped?([type, id])
      @memo[type][id] = true

      emit type, id, attributes, object
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

    protected
    def find_file(path)
      path = "#{path}.rb" unless path =~ /\.rb$/
      return path if File.exists? path
      $LOAD_PATH.each do |prefix|
        full_path = File.expand_path(path, prefix)
        return full_path if File.exists? full_path
      end
      false
    end
  end
end
