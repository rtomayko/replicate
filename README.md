Dump and load relational objects between Ruby environments.
===========================================================

*This repository is archived and no longer actively maintained by @rtomayko as of 2017-11-08. Issues and PRs documenting current issues have been intentionally left open for informational purposes.*

The project started at GitHub to simplify the process of getting real production
data into development and staging environments. We use it to replicate entire
repository data (including associated issue, pull request, commit comment, etc.
records) from production to our development environments with a single command.
It's excessively useful for troubleshooting issues, support requests, and
exception reports as well as for establishing real data for evaluating design
concepts.

Synopsis
--------

### Installing

    $ gem install replicate

### Dumping objects

Evaluate a Ruby expression, dumping all resulting objects to standard output:

    $ replicate -r ./config/environment -d "User.find(1)" > user.dump
    ==> dumped 4 total objects:
    Profile        1
    User           1
    UserEmail      2

The `-r ./config/environment` option is used to require environment setup and
model instantiation code needed by the ruby expression.

### Dumping many objects with a dump script

Dump scripts are normal ruby source files evaluated in the context of the
dumper. The `dump(object)` method is used to put objects into the dump stream.

```ruby
# config/replicate/dump-stuff.rb
require 'config/environment'

%w[rtomayko/tilt rtomayko/bcat].each do |repo_name|
  repo = Repository.find_by_name_with_owner(repo_name)
  dump repo
  dump repo.commit_comments
  dump repo.issues
end
```

Run the dump script:

    $ replicate -d config/replicate/dump-stuff.rb > repos.dump
    ==> dumped 1479 total objects:
    AR::Habtm                   101
    CommitComment                95
    Issue                       101
    IssueComment                427
    IssueEvent                  308
    Label                         5
    Language                     19
    LanguageName                  1
    Milestone                     3
    Organization                  4
    Profile                      82
    PullRequest                  44
    PullRequestReviewComment      8
    Repository                   20
    Team                          4
    TeamMember                    6
    User                         89
    UserEmail                   162

### Loading many objects:

    $ replicate -r ./config/environment -l < repos.dump
    ==> loaded 1479 total objects:
    AR::Habtm                   101
    CommitComment                95
    Issue                       101
    IssueComment                427
    IssueEvent                  308
    Label                         5
    Language                     19
    LanguageName                  1
    Milestone                     3
    Organization                  4
    Profile                      82
    PullRequest                  44
    PullRequestReviewComment      8
    Repository                   20
    Team                          4
    TeamMember                    6
    User                         89
    UserEmail                   162

### Dumping and loading over ssh

    $ remote_command="replicate -r /app/config/environment -d 'User.find(1234)'"
    $ ssh example.org "$remote_command" |replicate -r ./config/environment -l

ActiveRecord
------------

Basic support for dumping and loading ActiveRecord objects is included. The
tests pass under ActiveRecord versions 2.2.3, 2.3.5, 2.3.14, 3.0.10, 3.1.0, and 3.2.0 under
MRI 1.8.7 as well as under MRI 1.9.2.

To use customization macros in your models, require the replicate library after
ActiveRecord (in e.g., `config/initializers/libraries.rb`):

```ruby
require 'active_record'
require 'replicate'
```

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

```ruby
class User < ActiveRecord::Base
  belongs_to :profile
  has_many   :email_addresses

  replicate_associations :email_addresses
end
```

You may also do this by passing an option in your dump script:

```ruby
dump User.all, :associations => [:email_addresses]
```

### Natural Keys

By default, the loader attempts to create a new record with a new primary key id
for all objects. This can lead to unique constraint errors when a record already
exists with matching attributes. To update existing records instead of
creating new ones, define a natural key for the model using the `replicate_natural_key`
macro:

```ruby
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
```

Multiple attribute names may be specified to define a compound key. Foreign key
column attributes (`user_id`) are often included in natural keys.

### Omission of attributes and associations

You might want to exclude some attributes or associations from being dumped. For
this, use the replicate_omit_attributes macro:

```ruby
class User < ActiveRecord::Base
  has_one    :profile

  replicate_omit_attributes :created_at, :profile
end
```

You can omit belongs_to associations by omitting the foreign key column.

You may also do this by passing an option in your dump script:

```ruby
dump User.all, :omit => [:profile]
```

### Validations and Callbacks

__IMPORTANT:__ All ActiveRecord validations and callbacks are disabled on the
loading side. While replicate piggybacks on AR for relationship information and
uses `ActiveRecord::Base#save` to write objects to the database, it's designed
to act as a simple dump / load tool.

It's sometimes useful to run certain types of callbacks on replicate. For
instance, you might want to create files on disk or load information into a
separate data store any time an object enters the database. The best way to go
about this currently is to override the model's `load_replicant` class method:

```ruby
class User < ActiveRecord::Base
  def self.load_replicant(type, id, attrs)
    id, object = super
    object.register_in_redis
    object.some_other_callback
    [id, object]
  end
end
```

This interface will be improved in future versions.

Custom Objects
--------------

Other object types may be included in the dump stream so long as they implement
the `dump_replicant` and `load_replicant` methods.

### dump_replicant

The dump side calls `#dump_replicant(dumper, opts={})` on each object. The method must
call `dumper.write()` with the class name, id, and hash of primitively typed
attributes for the object:

```ruby
class User
  attr_reader   :id
  attr_accessor :name, :email

  def dump_replicant(dumper, opts={})
    attributes = { 'name' => name, 'email' => email }
    dumper.write self.class, id, attributes, self
  end
end
```

### load_replicant

The load side calls `::load_replicant(type, id, attributes)` on the class to
load each object into the current environment. The method must return an
`[id, object]` tuple:

```ruby
class User
  def self.load_replicant(type, id, attributes)
    user = User.new
    user.name  = attributes['name']
    user.email = attributes['email']
    user.save!
    [user.id, user]
  end
end
```

How it works
------------

The dump format is designed for streaming relational data. Each object is
encoded as a `[type, id, attributes]` tuple and marshalled directly onto the
stream. The `type` (class name string) and `id` must form a distinct key when
combined, `attributes` must consist of only string keys and simply typed values.

Relationships between objects in the stream are managed as follows:

 - An object's attributes may encode references to objects that precede it
   in the stream using a simple tuple format: `[:id, 'User', 1234]`.

 - The dump side ensures that objects are written to the dump stream in
   "reference order" such that when an object A includes a reference attribute
   to an object B, B is guaranteed to arrive before A.

 - The load side maintains a mapping of ids from the dumping system to the newly
   replicated objects on the loading system. When the loader encounters a
   reference value `[:id, 'User', 1234]` in an object's attributes, it converts it
   to the load side id value.

Dumping and loading happens in a streaming fashion. There is no limit on the
number of objects included in the stream.
