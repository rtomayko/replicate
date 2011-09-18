module Replicate
  # Load replicants in a streaming fashion.
  #
  # The Loader reads [type, id, attributes] replicant tuples and creates
  # objects in the current environment.
  #
  # Objects are expected to arrive in order such that a record referenced via
  # foreign key always precedes the referencing record. The Loader maintains a
  # mapping of primary keys from the dump system to the current environment.
  # This mapping is used to properly establish new foreign key values on all
  # records inserted.
  class Loader < Emitter

    # Stats hash.
    attr_reader :stats

    def initialize
      @keymap = Hash.new { |hash,k| hash[k] = {} }
      @stats  = Hash.new { |hash,k| hash[k] = 0 }
      super
    end

    # Register a filter to write status information to the given stream. By
    # default, a single line is used to report object counts while the dump is
    # in progress; dump counts for each class are written when complete. The
    # verbose and quiet options can be used to increase or decrease
    # verbository.
    #
    # out - An IO object to write to, like stderr.
    # verbose - Whether verbose output should be enabled.
    # quiet - Whether quiet output should be enabled.
    #
    # Returns the Replicate::Status object.
    def log_to(out=$stderr, verbose=false, quiet=false)
      use Replicate::Status, 'load', out, verbose, quiet
    end

    # Feed a single replicant tuple into the loader.
    #
    # type  - The class to create. Must respond to load_replicant.
    # id    - The remote system's id for this object.
    # attrs - Hash of primitively typed objects.
    #
    # Returns the need object resulting from the load operation.
    def feed(type, id, attrs)
      type = type.to_s
      object = load(type, id, attrs)
      @stats[type] += 1
      emit type, id, attrs, object
    end

    # Read multiple [type, id, attrs] replicant tuples from io and call the
    # feed method to load and filter the object.
    def read(io)
      begin
        while object = Marshal.load(io)
          type, id, attrs = object
          feed type, id, attrs
        end
      rescue EOFError
      end
    end

    # Load an individual replicant into the underlying datastore.
    #
    # type  - Model class name as a String.
    # id    - Primary key id of the record on the dump system. This must be
    #         translated to the local system and stored in the keymap.
    # attrs - Hash of attributes to set on the new record.
    #
    # Returns the new object instance.
    def load(type, id, attributes)
      model_class = constantize(type)
      translate_ids type, id, attributes
      begin
        new_id, instance = model_class.load_replicant(type, id, attributes)
      rescue => boom
        warn "error: loading #{type} #{id} #{boom.class} #{boom}"
        raise
      end
      register_id instance, type, id, new_id
      instance
    end

    # Translate remote system id references in the attributes hash to their
    # local system id values. The attributes hash may include special id
    # values like this:
    #     { 'title'         => 'hello there',
    #       'repository_id' => [:id, 'Repository', 1234],
    #       'label_ids'     => [:id, 'Label', [333, 444, 555, 666, ...]]
    #       ... }
    # These values are translated to local system ids. All object
    # references must be loaded prior to the referencing object.
    def translate_ids(type, id, attributes)
      attributes.each do |key, value|
        next unless value.is_a?(Array) && value[0] == :id
        referenced_type, value = value[1].to_s, value[2]
        local_ids =
          Array(value).map do |remote_id|
            if local_id = @keymap[referenced_type][remote_id]
              local_id
            else
              warn "warn: #{referenced_type}(#{remote_id}) not in keymap, " +
                   "referenced by #{type}(#{id})##{key}"
            end
          end
        if value.is_a?(Array)
          attributes[key] = local_ids
        else
          attributes[key] = local_ids[0]
        end
      end
    end

    # Register an id in the keymap. Every object loaded must be stored here so
    # that key references can be resolved.
    def register_id(object, type, remote_id, local_id)
      @keymap[type.to_s][remote_id] = local_id
      c = object.class
      while !['Object', 'ActiveRecord::Base'].include?(c.name)
        @keymap[c.name][remote_id] = local_id
        c = c.superclass
      end
    end


    # Turn a string into an object by traversing constants.
    def constantize(string)
      namespace = ::Object
      string.split('::').each { |name| namespace = namespace.const_get(name) }
      namespace
    end
  end
end
