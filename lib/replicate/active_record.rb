module Replicate
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

    # Replicate::Dumper calls this method on objects to trigger dumping a
    # replicant object tuple.
    #
    # dumper - Dumper object whose #write method must be called with the
    #          type, id, and attributes hash.
    #
    # Returns nothing.
    def dump_replicant(dumper)
      dump_all_association_replicants dumper, :belongs_to
      dumper.write self.class.to_s, id, replicant_attributes, self
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
      create_or_update_replicant new, attributes
    end

    # Update an AR object's attributes and persist to the database without
    # running validations or callbacks.
    def create_or_update_replicant(instance, attributes)
      def instance.callback(*args);end # Rails 2.x hack to disable callbacks.

      attributes.each do |key, value|
        next if key == primary_key
        instance.write_attribute key, value
      end

      instance.save false
      [instance.id, instance]
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
        'id'         => [:id, "#{@object.class}:#{@object.id}"],
        'class'      => @object.class.to_s,
        'ref_class'  => @reflection.klass.to_s,
        'ref_name'   => @reflection.name.to_s,
        'collection' => [:ids, @reflection.klass.to_s, ids]
      }
    end

    def dump_replicant(dumper)
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

  # Load active record and install the extension methods.
  require 'active_record'
  ::ActiveRecord::Base.send :include, ARDumpMethods
  ::ActiveRecord::Base.send :extend,  ARLoadMethods
end
