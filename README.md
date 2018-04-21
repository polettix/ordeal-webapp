## `ordeal`

An app for drawing cards from one or more decks, for a somehow wide
definition of *deck*. For example... did you ever think that a die is just
a deck with six cards inside, where you always draw only one of them?

This app is ready to be deployed via [Dokku][dokku] (there's [a post in my
blog][dytp] about it). Otherwise, you might have to put a bit of effort to
adapt it.

There are a couple of environment variables that are recognized:

- `ORDEAL_EXPRESSION`: the default expression to evaluate. Defaults to
  `avocado@9`.
- `SECRETS`: used to initialize [Mojolicious][], put something and
  separate with spaces when you want to change them. As a matter of fact,
  this is a bit of cargo-cult for me, I just know I have to set it but no
  clue about whether it's really useful in this application.

If you want to see a (hopefully) running instance [go here][ordeal].

[dokku]: http://dokku.viewdocs.io/dokku/
[dytp]: https://blog.polettix.it/dokku-your-tiny-paas/
[Mojolicious]: https://metacpan.org/pod/Mojolicious
[ordeal]: https://ordeal.introm.it
