module GitHub
  module Replicator
    class Dumper
      def initialize(&write)
        @objects = []
        @write = write || lambda { |type,id,att| @objects << [type,id,att] }
        @memo = {}
      end

      def write(type, id, attributes)
        @write.call(type, id, attributes)
      end

      def dump(*objects)
        objects.each do |object|
          type = object.class.to_s.underscore
          meth = "dump_#{type}"
          if respond_to?(meth)
            send meth, object
          else
            dump_object object
          end
        end
      end

      def dump_repository(repository)
        dump repository.owner
        dump repository.plan_owner
        dump_object repository
        dump *repository.issues
      end

      def dump_user(user)
        dump_object user
        dump user.profile
        user.emails.each { |email| dump email }
      end

      def dump_object(object)
        return if object.nil?
        type = object.class.to_s
        id = "#{type}:#{object.id}"
        return if @memo.key?(id)
        @memo[id] = object
        write type, object.id, object.attributes
      end

      def to_a
        @objects
      end

      def to_s
        @objects.inspect
      end
    end

    class Loader
    end
  end
end
