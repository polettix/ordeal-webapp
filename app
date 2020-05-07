#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use 5.0240;

use Mojolicious::Lite;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Ordeal::Model;
use Try::Tiny;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

Log::Any::Adapter->set(MojoLog => logger => app->log);

use constant DEFAULT_DECK => 'avocado';
use constant DEFAULT_N    => 9;
use constant DEFAULT_EXPRESSION =>
  ($ENV{ORDEAL_EXPRESSION} || join('@', DEFAULT_DECK, DEFAULT_N));

app->secrets([split m{\s+}mxs, ($ENV{SECRETS} || 'ordeal!')]);

get '/' => sub ($c) {
   my $n_cards = $c->param('n_cards') // 0;    # avoid undef
   $n_cards = DEFAULT_N unless $n_cards =~ m{\A [1-9]\d* \z}mxs;
   my $expression = join '@', DEFAULT_DECK, $n_cards;
   my @cards = get_cards($c, $expression);
   $c->render(
      template => 'index',
      cards    => \@cards,
      n_cards  => $n_cards,
   );
};

get '/emod' => sub ($c) {
   my $expr = $c->param('expression') // DEFAULT_EXPRESSION;
   my $error = $c->param('error');
   $c->render(
      template   => 'index2',
      expression => $expr,
      error      => $error,
   );
};

get '/e' => sub ($c) {
   my $expr = $c->param('expression') // DEFAULT_EXPRESSION;
   my ($err, @cards) = try { (0, get_cards($c, $expr)) }
   catch {
      $log->error("got expression error: $_");
      (1);
   };
   return $err
     ? $c->redirect_to(
      $c->url_for('emod')->query(expression => $expr, error => 1))
     : $c->respond_to(
         html => {
            template   => 'expression',
            cards      => \@cards,
            expression => $expr,
         },
         json => {json => {cards => \@cards, expression => $expr}},
     );
};

get '/credits' => {template => 'credits'};
get '/other'   => {template => 'other'};

app->start;

sub get_cards ($c, $expression) {
   state $model = Ordeal::Model->new;
   return map {
      my $id  = $_->id;
      my $url = $c->url_for("cards/$id");
      (my $html_id = $id) =~ s{\W}{_}gmxs;
      {url => $url, id => $html_id};
   } $model->evaluate($expression)->draw;
} ## end sub get_cards

