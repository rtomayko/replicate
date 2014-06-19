Gem::Specification.new do |s|
  s.specification_version = 2 if s.respond_to? :specification_version=

  s.name     = 'replicate'
  s.version  = '1.5.1'
  s.date     = '2011-10-19'
  s.homepage = "http://github.com/rtomayko/replicate"
  s.authors  = ["Ryan Tomayko"]
  s.email    = "ryan@github.com"

  s.description = "Dump and load relational objects between Ruby environments."
  s.summary     = s.description

  s.files = %w[
    COPYING
    HACKING
    README.md
    Rakefile
    bin/replicate
    lib/replicate.rb
    lib/replicate/active_record.rb
    lib/replicate/dumper.rb
    lib/replicate/emitter.rb
    lib/replicate/loader.rb
    lib/replicate/object.rb
    lib/replicate/status.rb
    test/active_record_test.rb
    test/dumper_test.rb
    test/dumpscript.rb
    test/linked_dumpscript.rb
    test/loader_test.rb
    test/replicate_test.rb
  ]

  s.executables = ['replicate']
  s.test_files = s.files.select {|path| path =~ /^test\/.*_test.rb/}
  s.add_development_dependency 'activerecord', '~> 3.1'
  s.add_development_dependency 'sqlite3'
  s.add_development_dependency 'test_after_commit'

  s.require_paths = %w[lib]
end
