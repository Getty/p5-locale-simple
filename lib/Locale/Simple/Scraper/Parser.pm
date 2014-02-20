use strict;
use warnings;

package Locale::Simple::Scraper::Parser;

use base qw( Parser::MGC );

use Moo;
use Try::Tiny;

has func_qr => ( is => 'ro', default => sub { qr/\bl(|n|p|np|d|dn|dnp)\b/ } );
has debug_sub => (
    is      => 'ro',
    default => sub {
        sub { shift, warn "- " . sprintf shift . "\n", @_ }
    }
);
has found => ( is => 'ro', default => sub { [] } );

sub debug { shift->debug_sub->( @_ ) }

sub parse {
    my ( $self ) = @_;
    $self->sequence_of( sub { $self->parse_item } );
    return $self->found;
}

sub parse_item {
    my ( $self ) = @_;
    return $self->any_of( sub { $self->parse_noise }, sub { $self->parse_call } );
}

sub parse_noise {
    my ( $self ) = @_;
    my $noise = $self->substring_before( $self->func_qr );
    $self->fail( "no noise found" ) if !length $noise;
    $self->debug( "discarded %d characters of noise", length $noise );
    return $noise;
}

sub parse_call {
    my ( $self ) = @_;
    my $func = $self->expect( $self->func_qr );
    $self->debug( "found func $func at line %d", ( $self->where )[0] );

    try { $self->parse_valid_call( $func ) }
    catch {
        die $_ if !eval { $_->isa( "Parser::MGC::Failure" ) };
        $self->report_failure( $_ );
    };

    return;
}

sub parse_valid_call {
    my ( $self, $func ) = @_;

    {    # force the debug output to point at the position after the func name
        local $self->{patterns}{ws} = qr//;
        $self->fail( "Expected \"(\"" ) if !$self->maybe_expect( "(" );
    }

    my $args_method = "parse_req_args_$func";
    my @arguments   = $self->$args_method;

    while ( $self->maybe_expect( "," ) ) {
        my $arg = $self->maybe(
            sub {
                $self->any_of( sub { $self->complex_string }, sub { $self->token_int }, sub { $self->parse_call } );
            }
        );
        last if !$arg;
        push @arguments, $arg;
    }

    $self->fail( "Expected \")\"" ) if !$self->maybe_expect( ")" );

    $self->debug( "found %d arguments", scalar @arguments );
    push @{ $self->found }, { func => $func, args => \@arguments, line => ( $self->where )[0] };

    return;
}

sub collect_from {
    my ( $self, @methods ) = @_;
    return map { $self->$_ } @methods;
}

sub parse_req_args_l    { shift->collect_from( qw( translation_token ) ) }
sub parse_req_args_ln   { shift->collect_from( qw( translation_token  comma  plural_args ) ) }
sub parse_req_args_lp   { shift->collect_from( qw( context_id         comma  translation_token ) ) }
sub parse_req_args_lnp  { shift->collect_from( qw( parse_req_args_lp  comma  parse_plural_args ) ) }
sub parse_req_args_ld   { shift->collect_from( qw( domain_id          comma  translation_token ) ) }
sub parse_req_args_ldn  { shift->collect_from( qw( domain_id          comma  parse_req_args_ln ) ) }
sub parse_req_args_ldnp { shift->collect_from( qw( domain_id          comma  parse_req_args_lnp ) ) }

sub plural_args { shift->collect_from( qw( plural_translation_token  comma  plural_count ) ) }

sub named_arg_token {
    my ( $self, $name, $type ) = @_;
    $type ||= "complex_string";
    my $token = $self->maybe( sub { $self->$type } ) or $self->fail( "Expected $name" );
    return $token;
}

sub translation_token        { shift->named_arg_token( "translation token" ) }
sub plural_translation_token { shift->named_arg_token( "plural translation token" ) }
sub plural_count             { shift->named_arg_token( "count of plural entity", "token_int" ) }
sub context_id               { shift->named_arg_token( "context id" ) }
sub domain_id                { shift->named_arg_token( "domain id" ) }

sub comma {
    my ( $self ) = @_;
    $self->fail( "Expected \",\"" ) if !$self->maybe_expect( "," );
    return;
}

sub complex_string {
    my ( $self ) = @_;

    my $patterns = $self->{patterns};

    my $string = $self->any_of(
        sub {
            $self->scope_of( q["], sub { local $patterns->{ws} = qr//; $self->double_quote_string_contents }, q["] );
        },
        sub {
            $self->scope_of( q['], sub { local $patterns->{ws} = qr//; $self->single_quote_string_contents }, q['] );
        }
    );

    return $string;
}

sub double_quote_string_contents {
    my ( $self ) = @_;
    my $elements = $self->sequence_of(
        sub {
            $self->any_of(
                sub { $self->expect( qr/[^\\"]+/ ); },
                sub {
                    $self->expect( qr/\\"/ );
                    '"';
                },
            );
        }
    );
    my $string = join "", @{$elements};
    return $string if length $string;
    $self->fail( "no string contents found" );
}

sub single_quote_string_contents {
    my ( $self ) = @_;
    my $elements = $self->sequence_of(
        sub {
            $self->any_of(
                sub { $self->expect( qr/[^\\']+/ ); },
                sub {
                    $self->expect( qr/\\'/ );
                    "'";
                },
                sub {
                    $self->expect( qr/\\\\/ );
                    "\\";
                },
                sub { $self->expect( qr/\\/ ) },
            );
        }
    );
    my $string = join "", @{$elements};
    return $string if length $string;
    $self->fail( "no string contents found" );
}

sub report_failure {
    my ( $self, $f ) = @_;
    $f->{parser}->report( $f->{message}, $f->{pos} );
    return;
}

sub report {
    my ( $self, $problem, $pos ) = @_;
    my ( $linenum, $col, $text ) = $self->where( $pos || $self->pos );
    my $indent = substr( $text, 0, $col );
    $_ =~ s/\t/    /g for $text, $indent;
    $indent =~ s/./-/g;     # blank out all the non-whitespace
    $text   =~ s/\%/%%/g;
    $self->debug( "$problem:\n |$text\n |$indent^" );
    return;
}

1;
