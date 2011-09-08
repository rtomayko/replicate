# Replicate

Dump and load relational objects between Ruby environments.

The project was started at GitHub to ease the process of getting real production
data into staging and development environments. We have a custom command that
uses the replicate machinery to dump entire repository data (including
associated objects like issues, pull requests, commit comments, etc.) from
production and load it into the current environment. This is excessively useful
for troubleshooting issues, support requests, and exception reports.

## Synopsis

Dumping objects:

    $ replicate -r config/environment -d 'User.find(1)' > user.dump
    ==> dumped 4 total objects:
    Profile        1
    User           1
    UserEmail      2

Loading objects:

    $ replicate -r config/environment -l < user.dump
    ==> loaded 4 total objects:
    Profile        1
    User           1
    UserEmail      2

Dumping and loading over SSH:

    $ remote_command="replicate -r /app/config/environment -d 'User.find(1234)'"
    $ ssh example.org "$remote_command" |replicate -r config/environment -l

## ActiveRecord

*NOTE: Replicate has been tested only under ActiveRecord 2.2. Support for
ActiveRecord 3.x is planned.*

Basic support for dumping and loading ActiveRecord objects is included. When an
object is dumped, all `belongs_to` and `has_one` associations are automatically
followed and included in the dump. You can mark `has_many` and
`has_and_belongs_to_many` associations for automatic inclusion using the
`replicate_attributes` macro:

    class User < ActiveRecord::Base
      belongs_to :profile
      has_many   :email_addresses

      replicate_attributes :email_addresses
    end

By default, the loader attempts to create a new record for all objects. This can
lead to unique constraint errors when a record already exists with matching
attributes. To update existing records instead of always creating new ones,
define a natural key for the model using the `replicate_natural_key` macro:

    class User < ActiveRecord::Base
      belongs_to :profile
      has_many   :email_addresses

      replicate_natural_key :login
      replicate_associations :email_addresses
    end

Multiple attribute names may be specified to define a compound key.

## Custom Objects

Other object types may be included in the dump stream so long as they implement
the `dump_replicant` and `load_replicant` methods.

The dump side calls `#dump_replicant(dumper)` on each object. The method must
call `dumper.write()` with the class name, id, and hash of primitively typed
attributes for the object:

    class User
      attr_reader   :id
      attr_accessor :name, :email

      def dump_replicant(dumper)
        attributes { 'name' => name, 'email' => email }
        dumper.write self.class, id, attributes
      end
    end

The load side calls `::load_replicant(type, id, attributes)` on the class to
load each object into the current environment. The method must return an
`[id, object]` tuple:

    class User
      def self.load_replicant(type, id, attributes)
        user = User.new
        user.name  = attributes['name']
        user.email = attributes['email']
        user.save!
        [user.id, user]
      end
    end
