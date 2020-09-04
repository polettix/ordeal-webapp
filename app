#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use FindBin '$Bin';
use lib "$Bin/lib";

use 5.024;

use Mojolicious::Lite;
use Mojo::JSON qw< decode_json >;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Ordeal::Model;
use Try::Tiny;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;
use TableHandlerCollection;

Log::Any::Adapter->set(MojoLog => logger => app->log);

use constant DEFAULT_DECK => 'avocado';
use constant DEFAULT_N    => 9;
use constant DEFAULT_EXPRESSION =>
  ($ENV{ORDEAL_EXPRESSION} || join('@', DEFAULT_DECK, DEFAULT_N));
use constant TIMEOUT => ($ENV{TIMEOUT} || 60);

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


# Experimental...
my $thc = TableHandlerCollection->new(timeout => TIMEOUT);

# Sample browser-side stuff, only displays raw stuff
get '/table/ui/:id' => sub ($c) {
   return $c->render(template => 'table', id => scalar $c->param('id'));
};

# Arrange the specific table, overwriting current conditions
put '/table/:id' => sub ($c) {
   $thc->handler_for($c->param('id'))
      ->set_generator(decode_json($c->req->body || '{}')->%*);
   return $c->render(json => {response => 'OK'});
};

# Trigger generation of a new state for the table
post '/table/:id' => sub ($c) {
   my $v = $thc->handler_for($c->param('id'))->update(get_table_setup($c));
   return $c->render(data => $v, format => 'json');
};

# Invoked by reading clients to get the current state of the table
get '/table/:id' => sub ($c) {
   # Increase inactivity timeout for connection a bit
   $c->inactivity_timeout(300);

   # Change content type and finalize response headers. Make sure any
   # intermediate proxy (*COUGH*nginx*COUGH*) does not buffer.
   my $headers = $c->res->headers;
   $headers->content_type('text/event-stream');
   $headers->cache_control('No-Cache');
   $headers->header('X-Accel-Buffering' => 'no');
   $c->write;

   $thc->handler_for($c->param('id'))->onboard_controller($c);
};



app->start;

sub get_table_setup ($c) {
   my $model = $c->param('model');
   $model = decode_json($model) if defined $model;
   return (
      model => $model,
      expression => $c->param('expression'),
   );
}

sub get_cards ($c, $expression) {
   state $model = Ordeal::Model->new;
   return map {
      my $id  = $_->id;
      my $url = $c->url_for("cards/$id");
      (my $html_id = $id) =~ s{\W}{_}gmxs;
      {url => $url, id => $html_id};
   } $model->evaluate($expression)->draw;
} ## end sub get_cards

