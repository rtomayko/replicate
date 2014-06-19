require 'test/unit'
require 'stringio'

# require a specific AR version.
version = ENV['AR_VERSION']
gem 'activerecord', "~> #{version}" if version
require 'active_record'
require 'active_record/version'
version = ActiveRecord::VERSION::STRING
warn "Using activerecord #{version}"

# replicate must be loaded after AR
require 'replicate'

# create the sqlite db on disk
dbfile = File.expand_path('../db', __FILE__)
File.unlink dbfile if File.exist?(dbfile)
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => dbfile)
require 'test_after_commit'

# load schema
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table "users", :force => true do |t|
    t.string   "login"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "profiles", :force => true do |t|
    t.integer  "user_id"
    t.string   "name"
    t.string   "homepage"
  end

  create_table "emails", :force => true do |t|
    t.integer  "user_id"
    t.string   "email"
    t.datetime "created_at"
  end

  if version[0,3] > '2.2'
    create_table "domains", :force => true do |t|
      t.string "host"
    end

    create_table "web_pages", :force => true do |t|
      t.string "url"
      t.string "domain_host"
    end
  end

  create_table "notes", :force => true do |t|
    t.integer "notable_id"
    t.string  "notable_type"
  end

  create_table "namespaced", :force => true
end

# models
class User < ActiveRecord::Base
  has_one  :profile, :dependent => :destroy
  has_many :emails,  :dependent => :destroy, :order => 'id'
  has_many :notes,   :as => :notable
  replicate_natural_key :login
end

class Profile < ActiveRecord::Base
  belongs_to :user
  replicate_natural_key :user_id
end

class Email < ActiveRecord::Base
  belongs_to :user
  replicate_natural_key :user_id, :email
end

if version[0,3] > '2.2'
  class WebPage < ActiveRecord::Base
    belongs_to :domain, :foreign_key => 'domain_host', :primary_key => 'host'
  end

  class Domain < ActiveRecord::Base
    replicate_natural_key :host
  end
end

class Note < ActiveRecord::Base
  belongs_to :notable, :polymorphic => true
end

class User::Namespaced < ActiveRecord::Base
  self.table_name = "namespaced"
end

# The test case loads some fixture data once and uses transaction rollback to
# reset fixture state for each test's setup.
class ActiveRecordTest < Test::Unit::TestCase
  def setup
    self.class.fixtures
    ActiveRecord::Base.connection.increment_open_transactions
    ActiveRecord::Base.connection.begin_db_transaction

    @rtomayko = User.find_by_login('rtomayko')
    @kneath   = User.find_by_login('kneath')
    @tmm1     = User.find_by_login('tmm1')

    User.replicate_associations = []

    @dumper = Replicate::Dumper.new
    @loader = Replicate::Loader.new
  end

  def teardown
    ActiveRecord::Base.connection.rollback_db_transaction
    ActiveRecord::Base.connection.decrement_open_transactions
  end

  def self.fixtures
    return if @fixtures
    @fixtures = true
    user = User.create! :login => 'rtomayko'
    user.create_profile :name => 'Ryan Tomayko', :homepage => 'http://tomayko.com'
    user.emails.create! :email => 'ryan@github.com'
    user.emails.create! :email => 'rtomayko@gmail.com'

    user = User.create! :login => 'kneath'
    user.create_profile :name => 'Kyle Neath', :homepage => 'http://warpspire.com'
    user.emails.create! :email => 'kyle@github.com'

    user = User.create! :login => 'tmm1'
    user.create_profile :name => 'tmm1', :homepage => 'https://github.com/tmm1'

    if defined?(Domain)
      github = Domain.create! :host => 'github.com'
      github_about_page = WebPage.create! :url => 'http://github.com/about', :domain => github
    end
  end

  def test_extension_modules_loaded
    assert User.respond_to?(:load_replicant)
    assert User.new.respond_to?(:dump_replicant)
  end

  def test_auto_dumping_belongs_to_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko.profile

    assert_equal 2, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert_equal rtomayko.id, id
    assert_equal 'rtomayko', attrs['login']
    assert_equal rtomayko.created_at, attrs['created_at']
    assert_equal rtomayko, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Profile', type
    assert_equal rtomayko.profile.id, id
    assert_equal 'Ryan Tomayko', attrs['name']
    assert_equal rtomayko.profile, obj
  end

  def test_omit_dumping_of_attribute
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    User.replicate_omit_attributes :created_at
    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko

    assert_equal 2, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal nil, attrs['created_at']
  end

  def test_omit_dumping_of_association
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    User.replicate_omit_attributes :profile
    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko

    assert_equal 1, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
  end

  if ActiveRecord::VERSION::STRING[0, 3] > '2.2'
    def test_dump_and_load_non_standard_foreign_key_association
      objects = []
      @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

      github_about_page = WebPage.find_by_url('http://github.com/about')
      assert_equal "github.com", github_about_page.domain.host
      @dumper.dump github_about_page

      WebPage.delete_all
      Domain.delete_all

      # load everything back up
      objects.each { |type, id, attrs, obj| @loader.feed type, id, attrs }

      github_about_page = WebPage.find_by_url('http://github.com/about')
      assert_equal "github.com", github_about_page.domain_host
      assert_equal "github.com", github_about_page.domain.host
    end
  end

  def test_auto_dumping_has_one_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko

    assert_equal 2, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert_equal rtomayko.id, id
    assert_equal 'rtomayko', attrs['login']
    assert_equal rtomayko.created_at, attrs['created_at']
    assert_equal rtomayko, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Profile', type
    assert_equal rtomayko.profile.id, id
    assert_equal 'Ryan Tomayko', attrs['name']
    assert_equal [:id, 'User', rtomayko.id], attrs['user_id']
    assert_equal rtomayko.profile, obj
  end

  def test_auto_dumping_does_not_fail_on_polymorphic_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    rtomayko = User.find_by_login('rtomayko')
    note = Note.create!(:notable => rtomayko)
    @dumper.dump note

    assert_equal 3, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert_equal rtomayko.id, id

    type, id, attrs, obj = objects.shift
    assert_equal 'Profile', type

    type, id, attrs, obj = objects.shift
    assert_equal 'Note', type
    assert_equal note.id, id
    assert_equal note.notable_type, attrs['notable_type']
    assert_equal attrs["notable_id"], [:id, 'User', rtomayko.id]
    assert_equal note, obj
  end

  def test_dumping_has_many_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    User.replicate_associations :emails
    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko

    assert_equal 4, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert_equal rtomayko.id, id
    assert_equal 'rtomayko', attrs['login']
    assert_equal rtomayko.created_at, attrs['created_at']
    assert_equal rtomayko, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Profile', type
    assert_equal rtomayko.profile.id, id
    assert_equal 'Ryan Tomayko', attrs['name']
    assert_equal rtomayko.profile, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Email', type
    assert_equal 'ryan@github.com', attrs['email']
    assert_equal [:id, 'User', rtomayko.id], attrs['user_id']
    assert_equal rtomayko.emails.first, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Email', type
    assert_equal 'rtomayko@gmail.com', attrs['email']
    assert_equal [:id, 'User', rtomayko.id], attrs['user_id']
    assert_equal rtomayko.emails.last, obj
  end

  def test_dumping_associations_at_dump_time
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko, :associations => [:emails], :omit => [:profile]

    assert_equal 3, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert_equal rtomayko.id, id
    assert_equal 'rtomayko', attrs['login']
    assert_equal rtomayko.created_at, attrs['created_at']
    assert_equal rtomayko, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Email', type
    assert_equal 'ryan@github.com', attrs['email']
    assert_equal [:id, 'User', rtomayko.id], attrs['user_id']
    assert_equal rtomayko.emails.first, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Email', type
    assert_equal 'rtomayko@gmail.com', attrs['email']
    assert_equal [:id, 'User', rtomayko.id], attrs['user_id']
    assert_equal rtomayko.emails.last, obj
  end

  def test_dumping_many_associations_at_dump_time
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    users = User.all(:conditions => {:login => %w[rtomayko kneath]})
    @dumper.dump users, :associations => [:emails], :omit => [:profile]

    assert_equal 5, objects.size
    assert_equal ['Email', 'Email', 'Email', 'User', 'User'], objects.map { |type,_,_| type }.sort
  end

  def test_omit_attributes_at_dump_time
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    rtomayko = User.find_by_login('rtomayko')
    @dumper.dump rtomayko, :omit => [:created_at]

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert attrs['updated_at']
    assert_nil attrs['created_at']
  end

  def test_dumping_polymorphic_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    User.replicate_associations :notes
    rtomayko = User.find_by_login('rtomayko')
    note = Note.create!(:notable => rtomayko)
    @dumper.dump rtomayko

    assert_equal 3, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User', type
    assert_equal rtomayko.id, id
    assert_equal 'rtomayko', attrs['login']
    assert_equal rtomayko.created_at, attrs['created_at']
    assert_equal rtomayko, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Profile', type
    assert_equal rtomayko.profile.id, id
    assert_equal 'Ryan Tomayko', attrs['name']
    assert_equal rtomayko.profile, obj

    type, id, attrs, obj = objects.shift
    assert_equal 'Note', type
    assert_equal note.notable_type, attrs['notable_type']
    assert_equal [:id, 'User', rtomayko.id], attrs['notable_id']
    assert_equal rtomayko.notes.first, obj

  end

  def test_dumping_empty_polymorphic_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    note = Note.create!()
    @dumper.dump note

    assert_equal 1, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'Note', type
    assert_equal nil, attrs['notable_type']
    assert_equal nil, attrs['notable_id']
  end

  def test_dumps_polymorphic_namespaced_associations
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    note = Note.create! :notable => User::Namespaced.create!
    @dumper.dump note

    assert_equal 2, objects.size

    type, id, attrs, obj = objects.shift
    assert_equal 'User::Namespaced', type

    type, id, attrs, obj = objects.shift
    assert_equal 'Note', type
  end

  def test_skips_belongs_to_information_if_omitted
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    Profile.replicate_omit_attributes :user
    @dumper.dump @rtomayko.profile

    assert_equal 1, objects.size
    type, id, attrs, obj = objects.shift
    assert_equal @rtomayko.profile.user_id, attrs["user_id"]
  end

  def test_loading_everything
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    # dump all users and associated objects and destroy
    User.replicate_associations :emails
    dumped_users = {}
    %w[rtomayko kneath tmm1].each do |login|
      user = User.find_by_login(login)
      @dumper.dump user
      user.destroy
      dumped_users[login] = user
    end
    assert_equal 9, objects.size

    # insert another record to ensure id changes for loaded records
    sr = User.create!(:login => 'sr')
    sr.create_profile :name => 'Simon Rozet'
    sr.emails.create :email => 'sr@github.com'

    # load everything back up
    objects.each { |type, id, attrs, obj| @loader.feed type, id, attrs }

    # verify attributes are set perfectly again
    user = User.find_by_login('rtomayko')
    assert_equal 'rtomayko', user.login
    assert_equal dumped_users['rtomayko'].created_at, user.created_at
    assert_equal dumped_users['rtomayko'].updated_at, user.updated_at
    assert_equal 'Ryan Tomayko', user.profile.name
    assert_equal 2, user.emails.size

    # make sure everything was recreated
    %w[rtomayko kneath tmm1].each do |login|
      user = User.find_by_login(login)
      assert_not_nil user
      assert_not_nil user.profile
      assert !user.emails.empty?, "#{login} has no emails" if login != 'tmm1'
    end
  end

  def test_loading_with_existing_records
    objects = []
    @dumper.listen { |type, id, attrs, obj| objects << [type, id, attrs, obj] }

    # dump all users and associated objects and destroy
    User.replicate_associations :emails
    dumped_users = {}
    %w[rtomayko kneath tmm1].each do |login|
      user = User.find_by_login(login)
      user.profile.update_attribute :name, 'CHANGED'
      @dumper.dump user
      dumped_users[login] = user
    end
    assert_equal 9, objects.size

    # load everything back up
    objects.each { |type, id, attrs, obj| @loader.feed type, id, attrs }

    # ensure additional objects were not created
    assert_equal 3, User.count

    # verify attributes are set perfectly again
    user = User.find_by_login('rtomayko')
    assert_equal 'rtomayko', user.login
    assert_equal dumped_users['rtomayko'].created_at, user.created_at
    assert_equal dumped_users['rtomayko'].updated_at, user.updated_at
    assert_equal 'CHANGED', user.profile.name
    assert_equal 2, user.emails.size

    # make sure everything was recreated
    %w[rtomayko kneath tmm1].each do |login|
      user = User.find_by_login(login)
      assert_not_nil user
      assert_not_nil user.profile
      assert_equal 'CHANGED', user.profile.name
      assert !user.emails.empty?, "#{login} has no emails" if login != 'tmm1'
    end
  end

  def test_loading_with_replicating_id
    objects = []
    @dumper.listen do |type, id, attrs, obj|
      objects << [type, id, attrs, obj] if type == 'User'
    end

    dumped_users = {}
    %w[rtomayko kneath tmm1].each do |login|
      user = User.find_by_login(login)
      @dumper.dump user
      dumped_users[login] = user
    end
    assert_equal 3, objects.size

    User.destroy_all
    User.replicate_id = false

    # load everything back up
    objects.each { |type, id, attrs, obj| User.load_replicant type, id, attrs }

    user = User.find_by_login('rtomayko')
    assert_not_equal dumped_users['rtomayko'].id, user.id

    User.destroy_all
    User.replicate_id = true

    # load everything back up
    objects.each { |type, id, attrs, obj| User.load_replicant type, id, attrs }

    user = User.find_by_login('rtomayko')
    assert_equal dumped_users['rtomayko'].id, user.id
  end

  def test_loader_saves_without_validations
    # note when a record is saved with validations
    ran_validations = false
    User.class_eval { validate { ran_validations = true } }

    # check our assumptions
    user = User.create(:login => 'defunkt')
    assert ran_validations, "should run validations here"
    ran_validations = false

    # load one and verify validations are not run
    user = nil
    @loader.listen { |type, id, attrs, obj| user = obj }
    @loader.feed 'User', 1, 'login' => 'rtomayko'
    assert_not_nil user
    assert !ran_validations, 'validations should not run on save'
  end

  def test_loader_saves_without_callbacks
    # note when a record is saved with callbacks
    callbacks = false
    User.class_eval { after_save { callbacks = true } }
    User.class_eval { after_create { callbacks = true } }
    User.class_eval { after_update { callbacks = true } }
    User.class_eval { after_commit { callbacks = true } }

    # check our assumptions
    user = User.create(:login => 'defunkt')
    assert callbacks, "should run callbacks here"
    callbacks = false

    # load one and verify validations are not run
    user = nil
    @loader.listen { |type, id, attrs, obj| user = obj }
    @loader.feed 'User', 1, 'login' => 'rtomayko'
    assert_not_nil user
    assert !callbacks, 'callbacks should not run on save'
  end

  def test_loader_saves_without_updating_created_at_timestamp
    timestamp = Time.at((Time.now - (24 * 60 * 60)).to_i)
    user = nil
    @loader.listen { |type, id, attrs, obj| user = obj }
    @loader.feed 'User', 23, 'login' => 'brianmario', 'created_at' => timestamp
    assert_equal timestamp, user.created_at
    user = User.find(user.id)
    assert_equal timestamp, user.created_at
  end

  def test_loader_saves_without_updating_updated_at_timestamp
    timestamp = Time.at((Time.now - (24 * 60 * 60)).to_i)
    user = nil
    @loader.listen { |type, id, attrs, obj| user = obj }
    @loader.feed 'User', 29, 'login' => 'rtomayko', 'updated_at' => timestamp
    assert_equal timestamp, user.updated_at
    user = User.find(user.id)
    assert_equal timestamp, user.updated_at
  end

  def test_enabling_active_record_query_cache
    ActiveRecord::Base.connection.enable_query_cache!
    ActiveRecord::Base.connection.disable_query_cache!
  end
end
