use 5.024;

package TableHandler;
use Mojo::Base 'Mojo::EventEmitter', '-signatures';
use experimental qw< postderef >;
no warnings qw< experimental::postderef >;
use Mojo::JSON qw< decode_json encode_json >;
use Ouch;
use Ordeal::Model;

has current_value    => undef;
has last_action_time => sub { time() };
has value_generator  => undef;

sub is_obsolete ($self, $reference_time) {
   $reference_time += time() if $reference_time < 0;
   return 0 if $self->has_subscribers;
   return $self->last_action_time < $reference_time;
}

sub onboard_controller ($self, $c) {
   my $method = sub ($e, $v) { $c->write("event:push\ndata: $v\n\n") };
   if (defined(my $current_value = $self->current_value)) {
      $method->($self, $current_value);
   }
   my $cb = $self->on(push => $method);    # subscribe
   $c->on(finish => sub ($c) { $self->unsubscribe(push => $cb) });
} ## end sub onboard_controller

sub tick ($self) { $self->last_action_time(time()) }

sub update ($self, %args) {
   my $generator = $self->value_generator
     or ouch 400, 'uninitialized table handler, no generator';
   my $v = $generator->(%args);
   $v = encode_json($v) if ref $v;
   $self->current_value($v);
   $self->emit(push => $v);
   return $v;
} ## end sub update

sub set_generator ($self, %args) {
   my $om =
     defined($args{model})
     ? Ordeal::Model->new(Raw => $args{model})
     : undef;
   my $exp = $args{expression};
   my $ast = defined($om) && defined($exp) ? $om->parse($exp) : undef;
   my $generator = sub (%args) {
      my $iom =
        defined($args{model})
        ? Ordeal::Model->new(Raw => $args{model})
        : undef;
      ouch 404, 'no cards/decks to shuffle' unless defined $iom // $om;
      my $iexp = $args{expression};
      ouch 404, 'no expression to evaluate' unless defined $iexp // $exp;
      my $iast =
          (defined($iom) || defined($iexp))
        ? ($iom // $om)->parse($iexp // $exp)
        : $ast;
      my $shuffle = ($iom // $om)->evaluate($iast);
      my @cards   = map {
         my ($ct, $data) = ($_->content_type, $_->data);
         ($ct eq 'application/json') ? decode_json($data) : $data;
      } $shuffle->draw(0);    # takes them all
      return \@cards;
   };
   $self->value_generator($generator);
   return $self;
} ## end sub set_generator

1;