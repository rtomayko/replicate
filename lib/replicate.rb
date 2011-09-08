module Replicate
  autoload :Emitter, 'replicate/emitter'
  autoload :Dumper,  'replicate/dumper'
  autoload :Loader,  'replicate/loader'
  autoload :Object,  'replicate/object'
  autoload :Status,  'replicate/status'
  autoload :AR,      'replicate/active_record'

  AR if defined?(::ActiveRecord::Base)
end
