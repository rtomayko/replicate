require 'rake/clean'
task :default => [:setup, :test]

vendor_dir = File.expand_path('../vendor', __FILE__)
ENV['GEM_HOME'] = vendor_dir

desc "Install gem dependencies for development"
task :setup => '.bundle/config'
file '.bundle/config' => %w[Gemfile replicate.gemspec] do |f|
  sh "bundle install --path='#{vendor_dir}'"
end
CLEAN.include 'Gemfile.lock', '.bundle'

desc "Run tests"
task :test do
  ENV['RUBYOPT'] = [ENV['RUBYOPT'], 'rubygems'].compact.join(' ')
  ENV['RUBYLIB'] = ['lib', ENV['RUBYLIB']].compact.join(':')
  sh "testrb test/*_test.rb", :verbose => false
end
CLEAN.include 'test/db'

desc "Build gem"
task :build do
  sh "gem build replicate.gemspec"
end
