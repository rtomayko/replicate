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
        model_class = Object::const_get(type)
        translate_ids attributes
        new_id, instance = model_class.load_replicant(type, id, attributes)
        register_id instance, type, id, new_id
        instance
      end

      def translate_ids(attributes)
        attributes.each do |key, value|
          if value.is_a?(Array) && value.size == 2 && value[0] == :id
            remote_id = value[1]
            if local_id = @keymap[remote_id]
              attributes[key] = local_id
            else
              warn "error: #{remote_id} missing from keymap"
            end
          end
        end
      end

      def register_id(object, type, remote_id, local_id)
        @keymap["#{type}:#{remote_id}"] = local_id
        c = object.class
        while c != Object && c != ActiveRecord::Base
          @keymap["#{c.name}:#{remote_id}"] = local_id
          c = c.superclass
        end
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
