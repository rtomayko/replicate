task :default => :test

desc "Install gem dependencies for development"
task :setup do
  sh "bundle install"
end

desc "Run tests"
task :test do
  ENV['RUBYOPT'] = [ENV['RUBYOPT'], 'rubygems'].compact.join(' ')
  ENV['RUBYLIB'] = ['lib', ENV['RUBYLIB']].compact.join(':')
  sh "testrb test/*_test.rb", :verbose => false
end
