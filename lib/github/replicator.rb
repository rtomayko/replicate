module GitHub
  module Replicator
    autoload :Dumper, 'github/replicator/dumper'
    autoload :Loader, 'github/replicator/loader'
    require 'github/replicator/active_record'
  end
end
