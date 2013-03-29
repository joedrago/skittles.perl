Skittles IRC Bot
================

Skittles is a configurable, moddable, silly IRC bot.

Released under the Boost Software License (Version 1.0).

Requires Perl, and the following Perl modules for the core bot:

* POE
* POE::Component::IRC
* JSON::PP

Additional modules used by optional mods (rename/remove the .pm from /mods if you don't want to use it):

* URI::Escape
* HTML::Entities
* LWP::Simple
* LWP::UserAgent
* XML::Simple
* TeX::Hyphen

Once you have the right modules, copy/rename all .example files to not have .example appended, then
edit those and run skittles.pl.
