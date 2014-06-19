require 'rbconfig'
require 'rake/clean'
task :default => [:setup, :test]

vendor_dir   = './vendor'
ruby_version = RbConfig::CONFIG['ruby_version']
ENV['GEM_HOME'] = "#{vendor_dir}/#{ruby_version}"

desc "Install gem dependencies for development"
task :setup => 'setup:latest' do
  verbose(false) do
    gem_install 'sqlite3'
    gem_install 'test_after_commit'
  end
end

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

# supported activerecord gem versions
AR_VERSIONS = []
AR_VERSIONS.concat %w[2.2.3 2.3.5] if RUBY_VERSION < '1.9'
AR_VERSIONS.concat %w[2.3.14 3.0.10 3.1.0 3.2.0]

desc "Run unit tests under all supported AR versions"
task 'test:all' => 'setup:all' do
  failures = []
  AR_VERSIONS.each do |vers|
    warn "==> testing activerecord ~> #{vers}"
    ENV['AR_VERSION'] = vers
    ok = system("rake -s test")
    failures << vers if !ok
    warn ''
  end
  fail "activerecord version failures: #{failures.join(', ')}" if failures.any?
end

# file tasks for installing each AR version
desc 'Install gem dependencies for all supported AR versions'
task 'setup:all' => 'setup'
AR_VERSIONS.each do |vers|
  version_file = "#{ENV['GEM_HOME']}/versions/activerecord-#{vers}"
  file version_file do |f|
    verbose(false) { gem_install 'activerecord', vers }
  end
  task "setup:#{vers}" => version_file
  task "setup:all"     => "setup:#{vers}"
end
task "setup:latest" => "setup:#{AR_VERSIONS.last}"
CLEAN.include 'vendor'

# Install a gem to the local GEM_HOME but only if it isn't already installed
def gem_install(name, version = nil)
  version_name = [name, version].compact.join('-')
  version_file = "#{ENV['GEM_HOME']}/versions/#{version_name}"
  return if File.exist?(version_file)
  warn "installing #{version_name} to #{ENV['GEM_HOME']}"
  command = "gem install --no-rdoc --no-ri #{name}"
  command += " -v '~> #{version}'" if version
  command += " >/dev/null"
  sh command
  mkdir_p File.dirname(version_file)
  File.open(version_file, 'wb') { }
end
