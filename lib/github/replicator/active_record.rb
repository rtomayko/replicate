module GitHub
  module Replicator
    # ActiveRecord::Base extension methods used to replicate objects from one
    # environment to another.
    module AR
      # The replicant id is a two tuple containing the class and object id.
      def replicant_id
        [self.class.name, id]
      end

      # Ask the current AR record object to dump itself to the
      def dump_replicant(dumper)
        dump_all_association_replicants dumper, :belongs_to
        dumper.write self.class.to_s, id, attributes
        dump_all_association_replicants dumper, :has_one
      end

      # Dump all associations of a given type.
      #
      # dumper           - The Dumper object used to dump additional objects.
      # association_type - :has_one, :belongs_to, :has_many
      #
      # Returns nothing.
      def dump_all_association_replicants(dumper, association_type)
        self.class.reflect_on_all_associations(association_type).each do |reflection|
          dependent = __send__(reflection.name)
          case dependent
          when ActiveRecord::Base, Array
            dumper.dump(dependent)
          when nil
            next
          else
            warn "warn: #{model}##{reflection.name} #{association_type} association " \
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
          warn "warn: #{model}##{reflection.name} - habtm not supported yet"
        end
        objects = __send__(reflection.name)
        dumper.dump(objects)
      end
    end

    # Load active record and install the extension methods.
    require 'active_record'
    ::ActiveRecord::Base.send :include, AR
  end
end
