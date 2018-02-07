#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use 5.024;

use Mojolicious::Lite;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Bot::ChatBots::Utils qw< pipeline >;
use Ordeal::Model;

use experimental qw< postderef signatures >;
no warnings qw< experimental::postderef experimental::signatures >;

Log::Any::Adapter->set(MojoLog => logger => app->log);

sub ordeal;

app->secrets([split m{\s+}mxs, ($ENV{SECRETS} || 'befunge!')]);

if ($ENV{TOKEN}) {
   my $domain = $ENV{DOMAIN};
   my $token  = $ENV{TOKEN};
   (my $wtoken = $token) =~ s{\W}{-}gmxs;
   plugin 'Bot::ChatBots::Telegram' => instances => [
      [
         'WebHook',
         processor  => pipeline(
            \&log_request,
            \&pre_processor,
            {tap => 'bucket'},
         ),
         register   => 1,
         token      => $token,
         unregister => 0,
         url        => "https://$domain/telegram/$wtoken",
      ],
      # more can follow here...
   ];
}

get '/' => sub ($c) {
   my $cards = $c->param('n_cards') || 9;
   $c->stash(n_cards => $cards);
   my @cards = ordeal->get_shuffled_cards(
      items => [qw< public-001-all >],
      default_n_draw => $cards,
      n => 1,
   );
   for my $card (@cards) {
      my $url = $c->url_for('cards/' . $card->id);
      (my $html_id = $card->id) =~ s{\W}{_}gmxs;
      $card = {url => $url, id => $html_id};
   }
   $c->stash(cards => \@cards);
   $c->render(
      template => 'index',
      stash => {
         n_cards => $cards
      }
   );
};

get '/credits' => {template => 'credits'};



app->start;

sub ordeal { state $model = Ordeal::Model->new }

sub log_request {
   my $record = shift;
   local $Data::Dumper::Indent = 1;
   $log->info('Payload: ', Dumper($record->{payload}));
   return $record;
}

sub pre_processor {
   my $record = shift;
   $log->info("setting response");
   # do whatever you want with $record, e.g. set a quick response
   $record->{send_response} =
      'your thoughts are important for us! ' . $];
   return $record;
}
