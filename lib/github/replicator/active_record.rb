module GitHub
  module Replicator
    # ActiveRecord::Base instance methods used to dump replicant objects for the
    # record and all 1:1 associations. This module implements the replicant_id
    # and dump_replicant methods using AR's reflection API to determine
    # relationships with other objects.
    module ARDumpMethods
      # The replicant id is a two tuple containing the class and object id. This
      # is used by Replicant::Dumper to determine if the object has already been
      # dumped or not.
      def replicant_id
        [self.class.name, id]
      end

      # Replicator::Dumper calls this method on objects to trigger dumping a
      # replicant object tuple.
      #
      # dumper - Dumper object whose #write method must be called with the
      #          type, id, and attributes hash.
      #
      # Returns nothing.
      def dump_replicant(dumper)
        dump_all_association_replicants dumper, :belongs_to
        dumper.write self.class.to_s, id, replicant_attributes
        dump_all_association_replicants dumper, :has_one
      end

      # Attributes hash used to persist this object. This consists of simply
      # typed values (no complex types or objects) with the exception of special
      # foreign key values. When an attribute value is [:id, "SomeClass:1234"],
      # the loader will handle translating the id value to the local system's
      # version of the same object.
      def replicant_attributes
        attributes = self.attributes.dup
        self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
          foreign_key = (reflection.options[:foreign_key] || "#{reflection.name}_id").to_s
          if id = attributes[foreign_key]
            attributes[foreign_key] = [:id, "#{reflection.klass.to_s}:#{id}"]
          end
        end
        attributes
      end

      # Dump all associations of a given type.
      #
      # dumper           - The Dumper object used to dump additional objects.
      # association_type - :has_one, :belongs_to, :has_many
      #
      # Returns nothing.
      def dump_all_association_replicants(dumper, association_type)
        self.class.reflect_on_all_associations(association_type).each do |reflection|
          next if (dependent = __send__(reflection.name)).nil?
          case dependent
          when ActiveRecord::Base, Array
            dumper.dump(dependent)
          else
            warn "warn: #{self}##{reflection.name} #{association_type} association " \
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
        reflection = self.class.reflect_on_association(association)
        if reflection.macro == :has_and_belongs_to_many
          warn "warn: #{self}##{reflection.name} - habtm not supported yet"
        end
        objects = __send__(reflection.name)
        dumper.dump(objects)
      end
    end

    module ARLoadMethods
      # Load an individual record into the database.
      #
      # type  - Model class name as a String.
      # id    - Primary key id of the record on the dump system. This must be
      #         translated to the local system and stored in the keymap.
      # attrs - Hash of attributes to set on the new record.
      #
      # Returns the ActiveRecord object instance for the new record.
      def load_replicant(type, id, attributes)
        instance = new
        def instance.callback(*args);end # Rails 2.x hack to disable callbacks.

        attributes.each do |key, value|
          next if key == primary_key
          instance.write_attribute key, value
        end

        instance.save false
        [instance.id, instance]
      end
    end

    # Load active record and install the extension methods.
    require 'active_record'
    ::ActiveRecord::Base.send :include, ARDumpMethods
    ::ActiveRecord::Base.send :extend,  ARLoadMethods
  end
end
