# GitHub::Replicator (`script/replicate-repo`)

### Basic usage

Common case is live dumping a repository and all associated objects from
production and loading into the current environment.

The [amiridis/playground](https://github.com/amiridis/playground) repository is
Petros's work bench and makes for great sample data. To import the repository,
issues, pull requests, and other associated objects into your environment:

    [rtomayko@iron:github]$ script/replicate-repo https://github.com/amiridis/playground
    ==> connecting to aux1-ext.rs.github.com for amiridis/playground
    ==> loaded 221 total objects:
    CommitComment                11
    Download                     12
    Habtm                        31
    Issue                        31
    IssueComment                 18
    IssueEvent                   67
    Label                         4
    Language                      6
    LanguageName                  6
    Milestone                     5
    Page                          1
    Profile                       4
    PullRequest                   4
    PullRequestReviewComment      3
    Repository                    2
    User                          5
    UserEmail                    11
    ==> mirroring 2 git repositories
    mirroring: git@github.com:amiridis/playground.git
    mirroring: git@github.com:amiridis-test/playground.git

Now visit: http://github.dev/amiridis/playground

This connects to the remote environment via SSH, starts the dump and begins
loading objects locally. After the database is loaded, git repositories are
fetched for any repository objects included in the dump. You can cancel the git
mirroring stage at any time with `Ctrl+C`.

### Advanced usage

It's also possible to dump everything to a file instead of loading right now.
You can then load the file into any environment without access to production.
For instance, to dump the current production github/haystack repository state
(including all associated orgs, teams, users, issues, pull requests, etc.) to
a `haystack.dump` file in the current directory:

    [rtomayko@iron:github]$ script/replicate-repo -d https://github.com/github/haystack > haystack.dump
    ==> connecting to aux1-ext.rs.github.com for github/haystack
    ==> dumped 382 total objects:
    CommitComment      5
    Habtm             10
    Issue             10
    IssueComment      42
    IssueEvent        48
    Language           3
    LanguageName       3
    Organization       1
    Profile           36
    PullRequest        4
    Repository         1
    Team               5
    TeamMember        70
    User              36
    UserEmail        108

You can then load this dump file into the current environment at any time using:

    [rtomayko@iron:github]$ script/replicate-repo -l < haystack.dump
    ==> loaded 382 total objects:
    CommitComment      5
    Habtm             10
    Issue             10
    IssueComment      42
    IssueEvent        48
    Language           3
    LanguageName       3
    Organization       1
    Profile           36
    PullRequest        4
    Repository         1
    Team               5
    TeamMember        70
    User              36
    UserEmail        108
    ==> mirroring 1 git repositories
    mirroring: git@github.com:github/haystack.git

### Troubleshooting

Dumping remote repositories currently requires shell access over SSH. If you can
execute this command, you should be fine:

    $ ssh aux1-ext.rs.github.com 'gudo hostname'
    aux1.rs.github.com

If ssh fails due to a bad login, try setting the `github.shelluser` git config
variable to your UNIX username in production / staging environments:

    $ git config --global github.shelluser jdoe

If something else happens, tell @rtomayko.
