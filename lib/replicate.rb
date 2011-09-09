module Replicate
  autoload :Emitter, 'replicate/emitter'
  autoload :Dumper,  'replicate/dumper'
  autoload :Loader,  'replicate/loader'
  autoload :Object,  'replicate/object'
  autoload :Status,  'replicate/status'
  autoload :AR,      'replicate/active_record'

  # Determine if this is a production looking environment. Used in bin/replicate
  # to safeguard against loading in production.
  def self.production_environment?
    if defined?(Rails) && Rails.respond_to?(:env)
      Rails.env.to_s == 'production'
    elsif defined?(RAILS_ENV)
      RAILS_ENV == 'production'
    elsif ENV['RAILS_ENV']
      ENV['RAILS_ENV'] == 'production'
    elsif ENV['RACK_ENV']
      ENV['RAILS_ENV'] == 'production'
    end
  end

  AR if defined?(::ActiveRecord::Base)
end
