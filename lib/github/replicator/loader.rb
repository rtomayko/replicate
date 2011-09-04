module GitHub
  module Replicator
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
    class Loader
      def initialize
        fail "not ready for production" if RAILS_ENV == 'production'
        @keymap = {}
        @warned = {}
        @foreign_key_map = {}
      end

      # Read replicant tuples from the given IO object and load into the
      # database within a single transaction.
      def read(io)
        ActiveRecord::Base.transaction do
          begin
            while object = Marshal.load(io)
              type, id, attrs = object
              record = load(type, id, attrs)
              yield record if block_given?
            end
          rescue EOFError
          end
        end
      end

      # Load an individual record into the database.
      #
      # type  - Model class name as a String.
      # id    - Primary key id of the record on the dump system. This must be
      #         translated to the local system and stored in the keymap.
      # attrs - Hash of attributes to set on the new record.
      #
      # Returns the ActiveRecord object instance for the new record.
      def load(type, id, attributes)
        model = Object::const_get(type)
        instance = load_object model, attributes
        primary_key = nil
        foreign_key_map = model_foreign_key_map(model)

        # write each attribute separately, converting foreign key values to
        # their local system values.
        attributes.each do |key, value|
          if key == model.primary_key
            primary_key = value
            next
          elsif value.nil?
            instance.write_attribute key, value
          elsif dependent_model = foreign_key_map[key]
            if record = find_dependent_object(dependent_model, value)
              instance.write_attribute key, record.id
            else
              warn "warn: #{model} referencing #{dependent_model}[#{value}] " \
                   "not found in keymap"
            end
          elsif key =~ /^(.*)_id$/
            if !@warned["#{model}:#{key}"]
              warn "warn: #{model}.#{key} looks like a foreign key but has no association."
              @warned["#{model}:#{key}"] = true
            end
            instance.write_attribute key, value
          else
            instance.write_attribute key, value
          end
        end

        # write to the database without validations and callbacks, register in
        # the keymap and return the AR object
        instance.save false
        register_dependent_object instance, primary_key
        instance
      end

      # Load a mapping of foreign key column names to association model classes.
      #
      # model - The AR class.
      #
      # Returns a Hash of { foreign_key => model_class } items.
      def model_foreign_key_map(model)
        @foreign_key_map[model] ||=
          begin
            map = {}
            model.reflect_on_all_associations(:belongs_to).each do |reflection|
              foreign_key = reflection.options[:foreign_key] || "#{reflection.name}_id"
              map[foreign_key.to_s] = reflection.klass
            end
            map
          end
      end

      # Find the local AR object instance for the given model class and dump
      # system primary key.
      #
      # model - An ActiveRecord subclass.
      # id    - The dump system primary key id.
      #
      # Returns the AR object instance if found, nil otherwise.
      def find_dependent_object(model, id)
        @keymap["#{model}:#{id}"]
      end

      # Register a newly created or updated AR object in the keymap.
      #
      # object - An ActiveRecord object instance.
      # id     - The dump system primary key id.
      #
      # Returns object.
      def register_dependent_object(object, id)
        model = object.class
        while model != ActiveRecord::Base && model != Object
          @keymap["#{model}:#{id}"] = object
          model = model.superclass
        end
        object
      end

      # Load an AR instance from the current environment.
      #
      # model - The ActiveRecord class to search for.
      # attrs - Hash of dumped record attributes.
      #
      # Returns an instance of model. This is usually a new record instance but
      # can be overridden to return an existing record instead.
      def load_object(model, attributes)
        meth = "load_#{model.to_s.underscore}"
        instance =
          if respond_to?(meth)
            send(meth, attributes) || model.new
          else
            model.new
          end
        def instance.callback(*args);end # Rails 2.x hack to disable callbacks.
        instance
      end

      ##
      # Loadspecs

      # Use existing users when the login is available.
      def load_user(attrs)
        User.find_by_login(attrs['login'])
      end

      # Delete existing repositories and create new ones. Nice because we don't
      # have to worry about updating existing issues, comments, etc.
      def load_repository(attrs)
        owner = find_dependent_object(User, attrs['owner_id'])
        if repo = Repository.find_by_name_with_owner("#{owner.login}/#{attrs['name']}")
          warn "warn: deleting existing repository: #{repo.name_with_owner} (#{repo.id})"
          repo.destroy
        end
        Repository.new
      end

      def load_language_name(attrs)
        LanguageName.find_by_name(attrs['name'])
      end
    end
  end
end
