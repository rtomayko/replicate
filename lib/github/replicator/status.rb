module GitHub
  module Replicator
    # Replicator filter that writes info to the console. Used by the Dumper and
    # Loader to get basic console output.
    class Status
      def initialize(dumper, prefix, out, verbose=false, quiet=false)
        @dumper = dumper
        @prefix = prefix
        @out = out
        @verbose = verbose
        @quiet = quiet
        @count = 0
      end

      def call(type, id, attrs, object)
        @count += 1
        if @verbose
          verbose_log type, id, attrs, object
        elsif !@quiet
          normal_log type, id, attrs, object
        end
      end

      def verbose_log(type, id, attrs, object)
        desc_attr = %w[name login email number title].find { |k| attrs.key?(k) }
        desc = desc_attr ? attrs[desc_attr] : id
        @out.puts "#{@prefix}: %-30s %s" % [type.sub('GitHub::Replicator::', ''), desc]
      end

      def normal_log(type, id, attrs, object)
        @out.write "==> #{@prefix}ing: #{@count} objects      \r"
      end

      def complete
        dump_stats if !@quiet
      end

      def dump_stats(stats=@dumper.stats.dup)
        @out.puts "==> #{@prefix}ed #{@count} total objects:    "
        width = 0
        stats.keys.each do |key|
          class_name = format_class_name(key)
          stats[class_name] = stats.delete(key)
          width = class_name.size if class_name.size > width
        end
        stats.to_a.sort_by { |k,n| k }.each do |class_name, count|
          @out.write "%-#{width + 1}s %5d\n" % [class_name, count]
        end
      end

      def format_class_name(class_name)
        class_name.sub(/GitHub::Replicator::/, '')
      end
    end
  end
end
