module Replicate
  autoload :Dumper, 'replicate/dumper'
  autoload :Loader, 'replicate/loader'
  autoload :Status, 'replicate/status'

  if defined?(ActiveRecord::Base)
    require 'replicate/active_record'
  end
end
