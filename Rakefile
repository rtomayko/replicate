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

# supported activerecord gem versions
AR_VERSIONS = %w[2.2.3 2.3.14 3.0.10 3.1.0]

desc "Run unit tests under all supported AR versions"
task 'test:all' => 'setup:all' do
  failures = false
  AR_VERSIONS.each do |vers|
    warn "==> testing activerecord ~> #{vers}"
    ENV['AR_VERSION'] = vers
    ok = system("rake test")
    failures = true if !ok
    warn ''
  end
  fail "test failures detected" if failures
end

# install GEM_HOME with various activerecord versions under ./vendor
task 'setup:all' do
  AR_VERSIONS.each do |vers|
    version_file = "#{vendor_dir}/versions/#{vers}"
    next if File.exist?(version_file)
    warn "installing activerecord ~> #{vers} to ./vendor"
    sh "gem install -q -V --no-rdoc --no-ri activerecord -v '~> #{vers}' >/dev/null", :verbose => false
    mkdir_p File.dirname(version_file)
    File.open(version_file, 'wb') {}
  end
end
CLEAN.include 'vendor'

