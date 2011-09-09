Dump and load relational objects between Ruby environments.
===========================================================

The project started at GitHub to simplify the process of getting real production
data into development and staging environments. We use it to replicate entire
repository data (including associated issue, pull request, commit comment, etc.
records) from production to our development environments with a single command.
It's excessively useful for troubleshooting issues, support requests, and
exception reports as well as for establishing real data for evaluating design
concepts.

Synopsis
--------

Installing:

    $ gem install replicate

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

ActiveRecord
------------

Basic support for dumping and loading ActiveRecord objects is included. The
tests pass under ActiveRecord versions 2.2.3, 2.3.14, 3.0.10, and 3.1.0 under
MRI 1.8.7 as well as under MRI 1.9.2.

To use customization macros in your models, require the replicate library after
ActiveRecord (in e.g., `config/initializers/libraries.rb`):

    require 'active_record'
    require 'replicate'

ActiveRecord support works sensibly without customization so this isn't strictly
necessary to use the `replicate` command. The following sections document the
available customization macros.

### Association Dumping

The baked in support adds some more or less sensible default behavior for all
subclasses of `ActiveRecord::Base` such that dumping an object will bring in
objects related via `belongs_to` and `has_one` associations.

Unlike 1:1 associations, `has_many` and `has_and_belongs_to_many` associations
are not automatically included. Doing so would quickly lead to the entire
database being sucked in. It can be useful to mark specific associations for
automatic inclusion using the `replicate_associations` macro. For instance,
to always include `EmailAddress` records belonging to a `User`:

    class User < ActiveRecord::Base
      belongs_to :profile
      has_many   :email_addresses

      replicate_associations :email_addresses
    end

### Natural Keys

By default, the loader attempts to create a new record with a new primary key id
for all objects. This can lead to unique constraint errors when a record already
exists with matching attributes. To update existing records instead of
creating new ones, define a natural key for the model using the `replicate_natural_key`
macro:

    class User < ActiveRecord::Base
      belongs_to :profile
      has_many   :email_addresses

      replicate_natural_key :login
      replicate_associations :email_addresses
    end

    class EmailAddress < ActiveRecord::Base
      belongs_to :user
      replicate_natural_key :user_id, :email
    end

Multiple attribute names may be specified to define a compound key. Foreign key
column attributes (`user_id`) are often included in natural keys.

### Validations and Callbacks

__IMPORTANT:__ All ActiveRecord validations and callbacks are disabled on the
loading side. While replicate piggybacks on AR for relationship information and
uses `ActiveRecord::Base#save` to write objects to the database, it's designed
to act as a simple dump / load tool.

It's sometimes useful to run certain types of callbacks on replicate. For
instance, you might want to create files on disk or load information into a
separate data store any time an object enters the database. The best way to go
about this currently is to override the model's `load_replicant` class method:

    class User < ActiveRecord::Base
      def self.load_replicant(type, id, attrs)
        id, object = super
        object.register_in_redis
        object.some_other_callback
        [id, object]
      end
    end

This interface will be improved in future versions.

Custom Objects
--------------

Other object types may be included in the dump stream so long as they implement
the `dump_replicant` and `load_replicant` methods.

### dump_replicant

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

### load_replicant

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

How it works
------------

The dump format is designed for streaming relational data. Each object is
encoded as a `[type, id, attributes]` tuple and marshalled directly onto the
stream. The `type` (class name string) and `id` must form a distinct key when
combined, `attributes` must consist of only string keys and simply typed values.

Relationships between objects in the stream are managed as follows:

 - An object's attributes may encode references to objects that precede it
   in the stream using a simple tuple format: [:id, 'User', 1234].

 - The dump side ensures that objects are written to the dump stream in
   "reference order" such that when an object A includes a reference attribute
   to an object B, B is guaranteed to arrive before A.

 - The load side maintains a mapping of ids from the dumping system to the newly
   replicated objects on the loading system. When the loader encounters a
   reference value [:id, 'User', 1234] in an object's attributes, it converts it
   to the load side id value.

Dumping and loading happens in a streaming fashion. There is no limit on the
number of objects included in the stream.
