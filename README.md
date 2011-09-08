# Replicate

Dump and load relational objects between Ruby environments.

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

Basic support for dumping and loading ActiveRecord objects is included. When an
object is dumped, all `belongs_to` and `has_one` associations are automatically
followed and included in the dump.

The `dump_replicant` method can be overridden on a class-by-class basis to
include additional associations:

    class User < ActiveRecord::Base
      belongs_to :profile
      has_many   :email_addresses

      def dump_replicant(dumper)
        super
        dump_association_replicants dumper, :email_addresses
      end
    end

Here, the `dump_replicant` method is overridden to include all email address
records for a User any time a user object is dumped. The `super` implementation
handles dumping the `profile` object and the User object itself. The
`dump_association_replicants` helper method handles `has_many` and
`has_and_belongs_to_many` associations.

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
