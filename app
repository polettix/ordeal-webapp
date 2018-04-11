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
         processor =>
           pipeline(\&log_request, \&pre_processor, {tap => 'bucket'},),
         register   => 1,
         token      => $token,
         unregister => 0,
         url        => "https://$domain/telegram/$wtoken",
      ],

      # more can follow here...
   ];
} ## end if ($ENV{TOKEN})

get '/' => sub ($c) {
   my $n_cards = $c->param('n_cards') || 9;
   $n_cards = 9 unless $n_cards =~ m{\A[1-9]\d*\z}mxs;
   my $expression = qq<"public-001-all"@[#$n_cards]>;
   my @cards = get_cards($c, $expression);
   $c->render(
      template   => 'index',
      cards      => \@cards,
      n_cards    => $n_cards,
   );
};

get '/e' => sub ($c) {
   my $expr = $c->param('expression') // qq<"public-001-all"@[#9]>;
   my @cards = get_cards($c, $expr);
   $c->render(
      template   => 'index2',
      cards      => \@cards,
      expression => $expr,
   );
};

get '/credits' => {template => 'credits'};

get '/shuffler/*expression' => sub ($c) {
   my $expression = $c->param('expression');
   my @cards = get_cards($c, $expression);
   $c->render(
      template   => 'index',
      cards      => \@cards,
      n_cards    => 9,
      expression => $expression,
   );
};

app->start;

sub get_cards ($c, $expression) {
   return map {
      my $id  = $_->id;
      my $url = $c->url_for("cards/$id");
      (my $html_id = $id) =~ s{\W}{_}gmxs;
      {url => $url, id => $html_id};
   } ordeal->get_shuffled_cards(expression => $expression);
} ## end sub get_cards

sub ordeal { state $model = Ordeal::Model->new }

sub log_request {
   my $record = shift;
   local $Data::Dumper::Indent = 1;
   $log->info('Payload: ', Dumper($record->{payload}));
   return $record;
} ## end sub log_request

sub pre_processor {
   my $record = shift;
   $log->info("setting response");

   # do whatever you want with $record, e.g. set a quick response
   $record->{send_response} = 'your thoughts are important for us! ' . $];
   return $record;
} ## end sub pre_processor
