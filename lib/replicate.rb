module Replicate
  autoload :Emitter, 'replicate/emitter'
  autoload :Dumper,  'replicate/dumper'
  autoload :Loader,  'replicate/loader'
  autoload :Object,  'replicate/object'
  autoload :Status,  'replicate/status'

  if defined?(ActiveRecord::Base)
    require 'replicate/active_record'
  end
end
