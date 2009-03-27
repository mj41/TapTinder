package TapTinder::Client;

our $VERSION = '0.10';

use Carp qw(carp croak verbose);
use File::Copy::Recursive qw(dircopy);

use Watchdog qw(sys sys_for_watchdog);
use SVNShell qw(svnversion svnup svndiff);

use TapTinder::Client::KeyPress qw(process_keypress sleep_and_process_keypress cleanup_before_exit);
use TapTinder::Client::WebAgent;


=head1 NAME

TapTinder::Client - Client for TapTinder software development tool.

=head1 DESCRIPTION

TapTinder is software development tool (continuous integration, test
harness, collect and analyse test results, create reports and diffs).

=head1 AUTHOR

Michal Jurosz <mj@mj41.cz>

=head1 COPYRIGHT

Copyright (c) 2007-2008 Michal Jurosz. All rights reserved.

=head1 LICENSE

TapTinder is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

TapTinder is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Foobar.  If not, see <http://www.gnu.org/licenses/>.

=head1 BUGS

L<http://dev.taptinder.org/>

=head1 SEE ALSO

L<TapTinder>, L<TapTinder::Web>

=cut

our $ver = 0;
our $debug = 0;


=head2 new

Create Client object.

=cut

sub new {
    my ( $class, $client_conf, $t_ver, $t_debug ) = @_;

    $ver = $t_ver;
    $debug = $t_debug;

    my $self  = {};
    $self->{client_conf} = $client_conf;

    $self->{agent} = undef;

    bless ($self, $class);
    $self->init_agent();
    $self->init_keypress();

    return $self;
}


=head2 init_agent

Initialize WebAgent object.

=cut

sub init_agent {
    my ( $self ) = @_;

    print "Starting WebAgent.\n" if $ver >= 3;
    $agent = TapTinder::Client::WebAgent->new(
        $self->{client_conf}->{taptinderserv},
        $self->{client_conf}->{machine_id},
        $self->{client_conf}->{machine_passwd}
    );

    $self->{agent} = $agent;
    return 1;
}


=head2 init_agent

Initialize KeyPress.

=cut

sub init_keypress {
    my ( $self ) = @_;

    $TapTinder::Client::KeyPress::ver = $ver;
    Term::ReadKey::ReadMode('cbreak');
    select(STDOUT); $| = 1;

    $TapTinder::Client::KeyPress::sub_before_exit = sub {
        Term::ReadKey::ReadMode('normal');
        if ( $self->{msession_id} ) {
            $self->{agent}->msdestroy( $self->{msession_id} );
        }
    };
    return 1;
}


=head2 ccmd_get_src

Run get_src client command.

=cut

sub ccmd_get_src {
    my ( $self, $msjobp_cmd_id, $rep_path_id, $rev_id ) = @_;

    my $data = $self->{agent}->rriget(
        $self->{msession_id}, $rep_path_id, $rev_id
    );
    croak "cmd error\n" unless defined $data;
    if ( $data->{err} ) {
        croak $data->{err_msg};
    }
    my $rep_info = { %$data };
    if ( $ver >= 2 ) {
        print "Getting revision $data->{rev_num} from $data->{rep_path}$data->{rep_path_path}\n";
    }

    $data = $self->{agent}->sset(
        $self->{msession_id},
        $msjobp_cmd_id,
        2 # running, $cmd_status_id
    );
    if ( $data->{err} ) {
        croak $data->{err_msg};
    }

    # TODO

    return 1;
}


sub run {
    my ( $self ) = @_;

    print "Creating new machine session.\n" if $ver >= 3;
    my ( $login_rc, $msession_id ) = $agent->mscreate();
    if ( ! $login_rc ) {
        croak "Login failed\n";
    }
    $self->{msession_id} = $msession_id;
    process_keypress();

    my $msjobp_cmd_id = undef;
    my $attempt_number = 1;
    while ( 1 ) {
        my $estimated_finish_time = undef;
        my $data = $self->{agent}->cget(
            $self->{msession_id}, $attempt_number, $estimated_finish_time,
            $msjobp_cmd_id,
        );
        #print Dumper( $data );

        croak "cmd error\n" unless defined $data;
        if ( $data->{err} ) {
            croak $data->{err_msg};
        }

        if ( $data->{msjobp_cmd_id} ) {
            $msjobp_cmd_id = $data->{msjobp_cmd_id};
            $attempt_number = 1;

            my $cmd_name = $data->{cmd_name};
            if ( $cmd_name eq 'get_src' ) {
                $self->ccmd_get_src(
                    $msjobp_cmd_id,
                    $data->{rep_path_id},
                    $data->{rev_id}
                );
            }


            if ( 0 ) {
                my $status = 3; # todo
                my $output_file_path = catfile( $RealBin, 'README' );
                $data = $self->{agent}->sset(
                    $msession_id,
                    $msjobp_cmd_id, # $msjobp_cmd_id
                    $status,
                    time(), # $end_time, TODO - is GMT?
                    $output_file_path
                );

                if ( $data->{err} ) {
                    croak $data->{err_msg};
                }
            }

            # debug sleep
            if ( 0 ) {
                my $sleep_time = 5;
                print "Debug sleep. Waiting for $sleep_time s ...\n" if $ver >= 1;
                sleep_and_process_keypress( $sleep_time );
            }

        } else {
            print "New msjobp_cmd_id not found.\n";
            last if $debug;
            $attempt_number++;
            $msjobp_cmd_id = undef;

            my $sleep_time = 15;
            print "Waiting for $sleep_time s ...\n" if $ver >= 1;
            sleep_and_process_keypress( $sleep_time );
        }
    }

    cleanup_before_exit();
}

1;