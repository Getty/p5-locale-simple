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

    try { $self->parse_valid_call( $func ) } catch { $self->report_failure( $_ ) };

    return;
}

sub parse_valid_call {
    my ( $self, $func ) = @_;

    {    # force the debug output to point at the position after the func name
        local $self->{patterns}{ws} = qr//;
        $self->fail( "Expected \"(\"" ) if !$self->maybe_expect( "(" );
    }

    my $first_arg = $self->maybe( sub { $self->complex_string } );
    $self->fail( "Expected an argument" ) if !$first_arg;

    my @arguments = ( $first_arg );
    while ( $self->maybe_expect( "," ) ) {
        my $arg = $self->maybe(
            sub {
                $self->any_of( sub { $self->complex_string }, sub { $self->token_int } );
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

sub complex_string {
    my ( $self ) = @_;

    my $string = $self->any_of(
        sub {
            $self->scope_of( "\"", sub { $self->double_quote_string_contents }, "\"" );
        },
        sub {
            $self->scope_of( "'", sub { $self->single_quote_string_contents }, "'" );
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
