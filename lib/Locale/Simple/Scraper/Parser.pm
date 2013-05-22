use strict;
use warnings;

package Locale::Simple::Scraper::Parser;

use base qw( Parser::MGC );

use Moo;
use Try::Tiny;
use curry;

has func_qr => ( is => 'ro', default => sub { qr/\bl(|n|p|np|d|dn|dnp)\b/ } );
has found   => ( is => 'ro', default => sub { [] } );
has type => ( is => 'ro', required => 1 );

with "Locale::Simple::Scraper::ParserShortcuts";

sub parse {
    my ( $self ) = @_;
    $self->sequence_of( $self->c_any_of( $self->curry::noise, $self->curry::call ) );
    return $self->found;
}

sub noise {
    my ( $self ) = @_;
    my $noise = $self->substring_before( $self->func_qr );
    $self->fail( "no noise found" ) if !length $noise;
    $self->debug( "discarded %d characters of noise", length $noise );
    return $noise;
}

sub call {
    my ( $self ) = @_;
    my $func = $self->expect( $self->func_qr );
    $self->debug( "found func $func at line %d", ( $self->where )[0] );

    try { $self->arguments( $func ) }
    catch {
        die $_ if !eval { $_->isa( "Parser::MGC::Failure" ) };
        $self->warn_failure( $_ );
    };

    return;
}

sub arguments {
    my ( $self, $func ) = @_;

    {    # force the debug output to point at the position after the func name
        local $self->{patterns}{ws} = qr//;
        $self->expect_string( "(" );
    }

    my $args_method = "required_args_$func";
    my @arguments = ( $self->$args_method, $self->extra_arguments );

    $self->expect_string( ")" );

    $self->debug( "found %d arguments", scalar @arguments );
    push @{ $self->found }, { func => $func, args => \@arguments, line => ( $self->where )[0] };

    return;
}

sub extra_arguments {
    my ( $self ) = @_;
    return if !$self->maybe_expect( "," );

    my @types = ( $self->curry::call, $self->curry::dynamic_string, $self->curry::token_int, $self->curry::variable );
    my $extra_args = $self->list_of( ",", $self->c_any_of( @types ) );
    return @{$extra_args};
}

sub required_args_l    { shift->collect_from( qw( translation_token ) ) }
sub required_args_ln   { shift->collect_from( qw( translation_token  comma  plural_args ) ) }
sub required_args_lp   { shift->collect_from( qw( context_id         comma  translation_token ) ) }
sub required_args_lnp  { shift->collect_from( qw( required_args_lp   comma  plural_args ) ) }
sub required_args_ld   { shift->collect_from( qw( domain_id          comma  translation_token ) ) }
sub required_args_ldn  { shift->collect_from( qw( domain_id          comma  required_args_ln ) ) }
sub required_args_ldnp { shift->collect_from( qw( domain_id          comma  required_args_lnp ) ) }

sub plural_args { shift->collect_from( qw( plural_token  comma  plural_count ) ) }

sub translation_token { shift->named_token( "translation token" ) }
sub plural_token      { shift->named_token( "plural translation token" ) }
sub plural_count      { shift->named_token( "count of plural entity", "token_int" ) }
sub context_id        { shift->named_token( "context id" ) }
sub domain_id         { shift->named_token( "domain id" ) }
sub comma             { shift->expect_string( "," ); () }                               # consume, no output
sub variable          { shift->expect( qr/[\w\.]+/ ) }

sub constant_string {
    my ( $self, @components ) = @_;

    my $p = $self->{patterns};

    unshift @components,
      $self->curry::scope_of( q["], sub { local $p->{ws} = qr//; $self->double_quote_string_contents }, q["] ),
      $self->curry::scope_of( q['], sub { local $p->{ws} = qr//; $self->single_quote_string_contents }, q['] );

    my $string = $self->list_of( $self->concat_op, $self->c_any_of( @components ) );

    return join "", @{$string} if @{$string};

    $self->fail;
}

sub concat_op {
    my %ops = ( js => "+", pl => ".", tx => "_", py => "+" );
    return $ops{ shift->type };
}

sub dynamic_string {
    my ( $self ) = @_;
    return $self->constant_string( $self->curry::variable );
}

sub double_quote_string_contents {
    my ( $self ) = @_;
    return $self->string_contents( $self->c_expect( qr/[^\\"]+/ ), $self->c_expect_escaped( q["] ) );
}

sub single_quote_string_contents {
    my ( $self ) = @_;
    return $self->string_contents(
        $self->c_expect( qr/[^\\']+/ ),
        $self->c_expect_escaped( q['] ),
        $self->c_expect_escaped( q[\\] ),
        $self->c_expect( qr/\\/ ),
    );
}

sub string_contents {
    my ( $self, @contents ) = @_;
    my $elements = $self->sequence_of( $self->c_any_of( @contents ) );
    return join "", @{$elements} if @{$elements};
    $self->fail( "no string contents found" );
}

1;
