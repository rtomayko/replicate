require 'test/unit'
require 'stringio'
require 'active_record'
require 'replicate'

dbfile = File.expand_path('../db', __FILE__)
File.unlink dbfile if File.exist?(dbfile)
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => dbfile)

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
end

class User < ActiveRecord::Base
  has_one  :profile, :dependent => :destroy
  has_many :emails,  :dependent => :destroy, :order => 'id'
end

class Profile < ActiveRecord::Base
  belongs_to :user
end

class Email < ActiveRecord::Base
  belongs_to :user
end

class ActiveRecordTest < Test::Unit::TestCase
  def setup
    fixtures
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

  def fixtures
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
end
