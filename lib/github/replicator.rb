module GitHub
  module Replicator
    autoload :Dumper, 'github/replicator/dumper'
    autoload :Loader, 'github/replicator/loader'
    autoload :Status, 'github/replicator/status'
    require 'github/replicator/active_record'
  end
end
