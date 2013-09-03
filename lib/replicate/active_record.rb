require 'active_record'
require 'active_record/version'

module Replicate
  # ActiveRecord::Base instance methods used to dump replicant objects for the
  # record and all 1:1 associations. This module implements the replicant_id
  # and dump_replicant methods using AR's reflection API to determine
  # relationships with other objects.
  module AR
    # Mixin for the ActiveRecord instance.
    module InstanceMethods
      # Replicate::Dumper calls this method on objects to trigger dumping a
      # replicant object tuple. The default implementation dumps all belongs_to
      # associations, then self, then all has_one associations, then any
      # has_many or has_and_belongs_to_many associations declared with the
      # replicate_associations macro.
      #
      # dumper - Dumper object whose #write method must be called with the
      #          type, id, and attributes hash.
      #
      # Returns nothing.
      def dump_replicant(dumper, opts={})
        @replicate_opts = opts
        @replicate_opts[:associations] ||= []
        @replicate_opts[:omit] ||= []
        dump_all_association_replicants dumper, :belongs_to
        dumper.write self.class.to_s, id, replicant_attributes, self
        dump_all_association_replicants dumper, :has_one
        included_associations.each do |association|
          dump_association_replicants dumper, association
        end
      end

      # List of associations to explicitly include when dumping this object.
      def included_associations
        (self.class.replicate_associations + @replicate_opts[:associations]).uniq
      end

      # List of attributes and associations to omit when dumping this object.
      def omitted_attributes
        (self.class.replicate_omit_attributes + @replicate_opts[:omit]).uniq
      end

      # Attributes hash used to persist this object. This consists of simply
      # typed values (no complex types or objects) with the exception of special
      # foreign key values. When an attribute value is [:id, "SomeClass:1234"],
      # the loader will handle translating the id value to the local system's
      # version of the same object.
      def replicant_attributes
        attributes = self.attributes.dup

        omitted_attributes.each { |omit| attributes.delete(omit.to_s) }
        self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
          if info = replicate_reflection_info(reflection)
            if replicant_id = info[:replicant_id]
              foreign_key = info[:foreign_key].to_s
              attributes[foreign_key] = [:id, *replicant_id]
            end
          end
        end

        attributes
      end

      # Retrieve information on a reflection's associated class and various
      # keys.
      #
      # Returns an info hash with these keys:
      #   :class - The class object the association points to.
      #   :primary_key  - The string primary key column name.
      #   :foreign_key  - The string foreign key column name.
      #   :replicant_id - The [classname, id] tuple identifying the record.
      #
      # Returns nil when the reflection can not be linked to a model.
      def replicate_reflection_info(reflection)
        options = reflection.options
        if options[:polymorphic]
          reference_class =
            if ::ActiveRecord::VERSION::MAJOR == 3 && ::ActiveRecord::VERSION::MINOR > 0
              attributes[reflection.foreign_type]
            else
              attributes[options[:foreign_type]]
            end
          return if reference_class.nil?

          klass = reference_class.constantize
          primary_key = klass.primary_key
          foreign_key = "#{reflection.name}_id"
        else
          klass = reflection.klass
          primary_key = (options[:primary_key] || klass.primary_key).to_s
          foreign_key = (options[:foreign_key] || "#{reflection.name}_id").to_s
        end

        info = {
          :class       => klass,
          :primary_key => primary_key,
          :foreign_key => foreign_key
        }

        if primary_key == klass.primary_key
          if id = attributes[foreign_key]
            info[:replicant_id] = [klass.to_s, id]
          else
            # nil value in association reference
          end
        else
          # association uses non-primary-key foreign key. no special key
          # conversion needed.
        end

        info
      end

      # The replicant id is a two tuple containing the class and object id. This
      # is used by Replicant::Dumper to determine if the object has already been
      # dumped or not.
      def replicant_id
        [self.class.name, id]
      end

      # Dump all associations of a given type.
      #
      # dumper           - The Dumper object used to dump additional objects.
      # association_type - :has_one, :belongs_to, :has_many
      #
      # Returns nothing.
      def dump_all_association_replicants(dumper, association_type)
        self.class.reflect_on_all_associations(association_type).each do |reflection|
          next if omitted_attributes.include?(reflection.name)

          # bail when this object has already been dumped
          next if (info = replicate_reflection_info(reflection)) &&
            (replicant_id = info[:replicant_id]) &&
            dumper.dumped?(replicant_id)

          next if (dependent = __send__(reflection.name)).nil?

          case dependent
          when ActiveRecord::Base, Array
            dumper.dump(dependent)

            # clear reference to allow GC
            if respond_to?(:association)
              association(reflection.name).reset
            elsif respond_to?(:association_instance_set, true)
              association_instance_set(reflection.name, nil)
            end
          else
            warn "warn: #{self.class}##{reflection.name} #{association_type} association " \
                 "unexpectedly returned a #{dependent.class}. skipping."
          end
        end
      end

      # Dump objects associated with an AR object through an association name.
      #
      # object      - AR object instance.
      # association - Name of the association whose objects should be dumped.
      #
      # Returns nothing.
      def dump_association_replicants(dumper, association)
        if reflection = self.class.reflect_on_association(association)
          objects = __send__(reflection.name)
          dumper.dump(objects)
          if reflection.macro == :has_and_belongs_to_many
            dump_has_and_belongs_to_many_replicant(dumper, reflection)
          end
          __send__(reflection.name).reset # clear to allow GC
        else
          warn "error: #{self.class}##{association} is invalid"
        end
      end

      # Dump the special Habtm object used to establish many-to-many
      # relationships between objects that have already been dumped. Note that
      # this object and all objects referenced must have already been dumped
      # before calling this method.
      def dump_has_and_belongs_to_many_replicant(dumper, reflection)
        dumper.dump Habtm.new(self, reflection)
      end
    end

    # Mixin for the ActiveRecord class.
    module ClassMethods
      # Set and retrieve list of association names that should be dumped when
      # objects of this class are dumped. This method may be called multiple
      # times to add associations.
      def replicate_associations(*names)
        self.replicate_associations += names if names.any?
        @replicate_associations || superclass.replicate_associations
      end

      # Set the list of association names to dump to the specific set of values.
      def replicate_associations=(names)
        @replicate_associations = names.uniq.map { |name| name.to_sym }
      end

      # Compound key used during load to locate existing objects for update.
      # When no natural key is defined, objects are created new.
      #
      # attribute_names - Macro style setter.
      def replicate_natural_key(*attribute_names)
        self.replicate_natural_key = attribute_names if attribute_names.any?
        @replicate_natural_key || superclass.replicate_natural_key
      end

      # Set the compound key used to locate existing objects for update when
      # loading. When not set, loading will always create new records.
      #
      # attribute_names - Array of attribute name symbols
      def replicate_natural_key=(attribute_names)
        @replicate_natural_key = attribute_names
      end

      # Set or retrieve whether replicated object should keep its original id.
      # When not set, replicated objects will be created with new id.
      def replicate_id(boolean=nil)
        self.replicate_id = boolean unless boolean.nil?
        @replicate_id.nil? ? superclass.replicate_id : @replicate_id
      end

      # Set flag for replicating original id.
      def replicate_id=(boolean)
        self.replicate_natural_key = [:id] if boolean
        @replicate_id = boolean
      end

      # Set which, if any, attributes should not be dumped. Also works for
      # associations.
      #
      # attribute_names - Macro style setter.
      def replicate_omit_attributes(*attribute_names)
        self.replicate_omit_attributes = attribute_names if attribute_names.any?
        @replicate_omit_attributes || superclass.replicate_omit_attributes
      end

      # Set which, if any, attributes should not be dumped. Also works for
      # associations.
      #
      # attribute_names - Array of attribute name symbols
      def replicate_omit_attributes=(attribute_names)
        @replicate_omit_attributes = attribute_names
      end

      # Load an individual record into the database. If the models defines a
      # replicate_natural_key then an existing record will be updated if found
      # instead of a new record being created.
      #
      # type  - Model class name as a String.
      # id    - Primary key id of the record on the dump system. This must be
      #         translated to the local system and stored in the keymap.
      # attrs - Hash of attributes to set on the new record.
      #
      # Returns the ActiveRecord object instance for the new record.
      def load_replicant(type, id, attributes)
        instance = replicate_find_existing_record(attributes) || new
        create_or_update_replicant instance, attributes
      end

      # Locate an existing record using the replicate_natural_key attribute
      # values.
      #
      # Returns the existing record if found, nil otherwise.
      def replicate_find_existing_record(attributes)
        return if replicate_natural_key.empty?
        conditions = {}
        replicate_natural_key.each do |attribute_name|
          conditions[attribute_name] = attributes[attribute_name.to_s]
        end
        find(:first, :conditions => conditions)
      end

      # Update an AR object's attributes and persist to the database without
      # running validations or callbacks.
      #
      # Returns the [id, object] tuple for the newly replicated objected.
      def create_or_update_replicant(instance, attributes)
        # write replicated attributes to the instance
        attributes.each do |key, value|
          next if key == primary_key and not replicate_id
          instance.send :write_attribute, key, value
        end

        # save the instance bypassing all callbacks and validations
        replicate_disable_callbacks instance
        if ::ActiveRecord::VERSION::MAJOR >= 3
          instance.save :validate => false
        else
          instance.save false
        end

        [instance.id, instance]
      end

      # Disable all callbacks on an ActiveRecord::Base instance. Only the
      # instance is effected. There is no way to re-enable callbacks once
      # they've been disabled on an object.
      def replicate_disable_callbacks(instance)
        if ::ActiveRecord::VERSION::MAJOR >= 3
          # AR 3.1.x
          def instance.run_callbacks(*args); yield; end

          # AR 3.0.x
          def instance._run_save_callbacks(*args); yield; end
          def instance._run_create_callbacks(*args); yield; end
          def instance._run_update_callbacks(*args); yield; end
        else
          # AR 2.x
          def instance.callback(*args)
          end
          def instance.record_timestamps
            false
          end
        end
      end

    end

    # Special object used to dump the list of associated ids for a
    # has_and_belongs_to_many association. The object includes attributes for
    # locating the source object and writing the list of ids to the appropriate
    # association method.
    class Habtm
      def initialize(object, reflection)
        @object = object
        @reflection = reflection
      end

      def id
      end

      def attributes
        ids = @object.__send__("#{@reflection.name.to_s.singularize}_ids")
        {
          'id'         => [:id, @object.class.to_s, @object.id],
          'class'      => @object.class.to_s,
          'ref_class'  => @reflection.klass.to_s,
          'ref_name'   => @reflection.name.to_s,
          'collection' => [:id, @reflection.klass.to_s, ids]
        }
      end

      def dump_replicant(dumper, opts={})
        type = self.class.name
        id   = "#{@object.class.to_s}:#{@reflection.name}:#{@object.id}"
        dumper.write type, id, attributes, self
      end

      def self.load_replicant(type, id, attrs)
        object = attrs['class'].constantize.find(attrs['id'])
        ids    = attrs['collection']
        object.__send__("#{attrs['ref_name'].to_s.singularize}_ids=", ids)
        [id, new(object, nil)]
      end
    end

    # Backport connection.enable_query_cache! for Rails 2.x
    require 'active_record/connection_adapters/abstract/query_cache'
    query_cache = ::ActiveRecord::ConnectionAdapters::QueryCache
    if !query_cache.methods.any? { |m| m.to_sym == :enable_query_cache! }
      query_cache.module_eval do
        attr_writer :query_cache, :query_cache_enabled

        def enable_query_cache!
          @query_cache ||= {}
          @query_cache_enabled = true
        end

        def disable_query_cache!
          @query_cache_enabled = false
        end
      end
    end

    # Load active record and install the extension methods.
    ::ActiveRecord::Base.send :include, InstanceMethods
    ::ActiveRecord::Base.send :extend,  ClassMethods
    ::ActiveRecord::Base.replicate_associations = []
    ::ActiveRecord::Base.replicate_natural_key  = []
    ::ActiveRecord::Base.replicate_omit_attributes  = []
    ::ActiveRecord::Base.replicate_id           = false
  end
end
