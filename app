#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use Mojolicious::Lite;
use Log::Any qw< $log >;
use Log::Any::Adapter;
use Bot::ChatBots::Utils qw< pipeline >;

Log::Any::Adapter->set(MojoLog => logger => app->log);

app->secrets([split m{\s+}mxs, ($ENV{SECRETS} || 'befunge!')]);

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

get '/unregister' => sub {
   app->chatbots->telegram->instances->[0]->unregister;
   shift->render(text => 'done');
};

get '/registration' => sub {
   require WWW::Telegram::BotAPI;
   my $outcome = WWW::Telegram::BotAPI->new(token => $token)
     ->getWebhookInfo();
   shift->render(json => $outcome || {});
};

app->start;

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
