module Replicate
  # Base class for Dumper / Loader classes. Manages a list of callback listeners
  # and dispatches to each when #emit is called.
  class Emitter
    # Yields self to the block and calls #complete when block is finished.
    def initialize
      @listeners = []
      if block_given?
        yield self
        complete
      end
    end

    # Register a listener to be called for each loaded object with the
    # type, id, attributes, object structure. Listeners are executed in the
    # reverse order of which they were registered. Listeners registered later
    # modify the view of listeners registered earlier.
    #
    # p     - An optional Proc object. Must respond to call.
    # block - An optional block.
    #
    # Returns nothing.
    def listen(p=nil, &block)
      @listeners.unshift p if p
      @listeners.unshift block if block
    end

    # Sugar for creating a listener with an object instance. Instances of the
    # class must respond to call(type, id, attrs, object).
    #
    # klass - The class to create. Must respond to new.
    # args  - Arguments to pass to new in addition to self.
    #
    # Returns the object created.
    def use(klass, *args, &block)
      instance = klass.new(self, *args, &block)
      listen instance
      instance
    end

    # Emit an object event to each listener.
    #
    # Returns the object.
    def emit(type, id, attributes, object)
      @listeners.each { |p| p.call(type, id, attributes, object) }
      object
    end

    # Notify all listeners that processing is complete.
    def complete
      @listeners.each { |p| p.complete if p.respond_to?(:complete) }
    end
  end
end
