use 5.024;

package TableHandler;
use Mojo::Base 'Mojo::EventEmitter', '-signatures';
use experimental qw< postderef >;
no warnings qw< experimental::postderef >;
use Mojo::JSON qw< decode_json encode_json >;
use Ouch;
use Ordeal::Model;
use Ordeal::Model::ChaCha20;

use constant EVENT => 'push';

has current_value    => undef;
has is_authenticated => undef;
has last_action_time => sub { time() };
has value_generator  => undef;

sub is_obsolete ($self, $reference_time) {
   return if $self->is_authenticated;
   $reference_time += time() if $reference_time < 0;
   return 0 if $self->has_subscribers(EVENT());
   return $self->last_action_time < $reference_time;
}

sub onboard_controller ($self, $c) {
   my $event = EVENT;
   my $method = sub ($e, $v) { $c->write("event:$event\ndata: $v\n\n") };
   if (defined(my $current_value = $self->current_value)) {
      $method->($self, $current_value);
   }
   my $cb = $self->on(EVENT() => $method);    # subscribe
   $c->on(finish => sub ($c) { $self->unsubscribe(EVENT() => $cb) });
} ## end sub onboard_controller

sub tick ($self) { $self->last_action_time(time()) }

sub update ($self, %args) {
   my $generator = $self->value_generator
     or ouch 400, 'uninitialized table handler, no generator';
   my $v = $generator->(%args);
   $v = encode_json($v) if ref $v;
   $self->current_value($v);
   $self->emit(EVENT() => $v);
   return $v;
} ## end sub update

sub set_generator ($self, %args) {
   state $rs = Ordeal::Model::ChaCha20->new;
   my $exp = $args{expression};
   my ($om, $ast);
   if (defined $args{model}) {
      $om = Ordeal::Model->new(Raw => {data => $args{model}});
      $om->random_source($rs);
      $ast = $om->parse($exp) if defined $exp;
   }
   my $generator = sub (%args) {
      my ($iom, $iast) = ($om, $ast);
      if (defined $args{model}) {
         $iom = Ordeal::Model->new(Raw => {data => $args{model}});
         $iom->random_source($rs);
         $iast = undef; # reset the "inside AST" for regeneration
      }
      ouch 404, 'no cards/decks to shuffle' unless defined $iom;
      $iast = $iom->parse($args{expression}) if defined $args{expression};
      ouch 404, 'no expression to evaluate' unless defined($iast // $exp);
      my $shuffle = $iom->evaluate($iast // $iom->parse($exp));
      my @cards   = map {
         my ($ct, $data) = ($_->content_type, $_->data);
         $ct //= 'text/plain';
         ($ct eq 'application/json') ? decode_json($data) : $data;
      } $shuffle->draw(0);    # takes them all
      return \@cards;
   };
   $self->value_generator($generator);
   return $self;
} ## end sub set_generator

1;
