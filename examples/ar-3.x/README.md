Replicate - ActiveRecord 3.1 Example Environment
================================================

This is a skeleton Rails environment that includes some basic seed data for
experimenting with replicate. First, run `rake setup` to install gem
dependencies and copy over the sample database:

    $ rake setup

The sample database is copied into the development environment. The schema is
straightforward. See `db/schema.rb` for the gist.

Dumping a Country object will bring in all associated cities and languages:

    $ replicate -r ./config/environment -d "Country.first" > country.dump
    ==> dumped 10 total objects:
    City          4
    Country       1
    Language      5

Now that you have a dump file at country.dump, you can load it into your test
database:

    $ RAILS_ENV=test replicate -r ./config/environment -l < country.dump
    ==> loaded 10 total objects:
    City          4
    Country       1
    Language      5

Dump everything:

    $ replicate -r ./config/environment -d "Country.all" > countries.dump
    ==> dumped 5302 total objects:
    City       4079
    Country     239
    Language    984
