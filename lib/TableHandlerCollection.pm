use 5.024;

package TableHandlerCollection;
use Mojo::Base qw< -base -signatures >;
use experimental qw< postderef >;
no warnings qw< experimental::postderef >;
use TableHandler;

has _handler_for => sub { return {} };
has timeout => ($ENV{TIMEOUT} // 60);

sub handler_for ($self, $id) {
   my $retval = $self->_handler_for->{$id} //= TableHandler->new;
   $retval->tick;
   $self->cleanup;
   return $retval;
} ## end sub handler_for

sub cleanup ($self) {
   my $handler_for = $self->_handler_for;
   my $timeout_threshold = time() - $self->timeout;
   for my $id (keys $handler_for->%*) {
      my $handler = $handler_for->{$id};
      next unless $handler->is_obsolete($timeout_threshold);
      delete $handler_for->{$id};
   } ## end for my $id (keys $handler_for...)
} ## end sub cleanup ($self)

1;
