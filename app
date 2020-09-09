#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use FindBin '$Bin';
use lib "$Bin/lib";

use 5.024;

use Mojolicious::Lite;
use Mojo::JSON qw< decode_json >;
use Mojo::UserAgent;
use Mojo::Util qw< hmac_sha1_sum >;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Ordeal::Model;
use Try::Tiny;
use Ouch;

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
post '/table' => sub ($c) {
   my %args = get_table_args($c);
   ouch 400, 'missing identifier' unless defined $args{id};
   my $th = table_setup($c, %args);
   return $c->render(json => {response => 'OK'});
};

put '/table/:id' => sub ($c) {
   table_setup($c,
      decode_json($c->req->body || '{}')->%*,
      id => $c->param('id'),
      auth => undef,
   );
   return $c->render(json => {response => 'OK'});
};

put '/table/:id/:auth' => sub ($c) {
   table_setup($c,
      decode_json($c->req->body || '{}')->%*,
      id => $c->param('id'),
      auth => $c->param('auth'),
   );
   return $c->render(json => {response => 'OK'});
};

# Trigger generation of a new state for the table
post '/table/:id' => sub ($c) {
   my $v = table_draw($c, get_table_args($c), id => $c->param('id'));
   my $headers = $c->res->headers;
   $headers->header('Access-Control-Allow-Origin' => '*');
   return $c->render(data => $v, format => 'json');
};

sub permissive_empty ($c) {
   my $headers = $c->res->headers;
   $headers->header('Access-Control-Allow-Origin' => '*');
   $headers->header('Access-Control-Allow-Headers' => '*');
   $headers->header('Access-Control-Allow-Methods' => '*');
   return $c->render(status => 204, data => '');
}

options '/table/:id/:auth' => \&permissive_empty;
options '/table/:id' => \&permissive_empty;
options '/table' => \&permissive_empty;

sub table_draw ($c, %args) {
   my $id = delete $args{id};
   check_auth($c, $id, $args{auth});
   return $thc->handler_for($id)->update(%args);
}

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
   $headers->header('Access-Control-Allow-Origin' => '*');
   $c->write;

   $thc->handler_for($c->param('id'))->onboard_controller($c);
};

app->start;

sub check_auth ($c, $id, $got_hmac) {
   my $th = $thc->handler_for($id);
   my $auth_failure = defined($got_hmac)
      ? ($got_hmac ne hmac_sha1_sum($id, $c->app->secrets->[0]))
      : $th->is_authenticated;
   ouch 403, 'Forbidden' if $auth_failure;
   return defined $got_hmac;
}

sub table_setup ($c, %args) {
   my $id = delete $args{id};
   ouch 400, 'missing identifier for table' unless defined $id;
   my $th = $thc->handler_for($id);

   $th->is_authenticated(check_auth($c, $id, $args{auth}));

   # "Resolve" configuration, only if authenticated
   if ($th->is_authenticated) {
      my $n = 5;
      while ($args{url} && $n-- > 0) {
         my $url = delete $args{url};
         my $ua = Mojo::UserAgent->new(max_redirects => 10);
         my $tx = $ua->get($url);
         my $rs = $tx->result;
         if ($rs->is_success) {
            %args = ($rs->json->%*, %args);
         }
         else {
            ouch 400, 'received error from remote url', $url;
         }
      }
      ouch 400, 'too many inclusions' if $n < 0;
   }

   $th->set_generator(%args);
   return $th;
};

sub get_table_args ($c) {
   my %args;
   my $ct = $c->req->headers->content_type;
   if ($ct =~ m{\A application/json (?: \W.*|)\z}imxs) {
      %args = $c->req->json->%*;
   }
   else {
      %args = map {
         my $v = $c->param($_);
         defined $v ? ($_ => $v) : ();
      } qw< auth expression id model url >;
      $args{model} = decode_json($args{model}) if defined $args{model};
   }
   return %args;
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

