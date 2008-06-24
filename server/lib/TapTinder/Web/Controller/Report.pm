package TapTinder::Web::Controller::Report;

use strict;
use warnings;
use base 'Catalyst::Controller::BindLex';

use Data::Page::HTML qw/get_pager_html/;
use DBIx::Dumper qw/Dumper dump_row/;

=head1 NAME

TapTinder::Web::Controller::Report - Catalyst Controller

=head1 DESCRIPTION

Catalyst controller for TapTinder web reports. The actions for reports browsing.

=head1 METHODS

=cut

=head2 index

=cut

# TODO - temporary solution
# dbix-class bug, see commented code in Taptinder::DB::SchemaAdd
sub CreateMyResultSets {
    my ( $self, $c ) = @_;

    my $source = TapTinder::DB::Schema::rep_path->result_source_instance;
    my $new_source = $source->new($source);
    $new_source->source_name('ActiveRepPathList');

    $new_source->name(\<<'');
(
   SELECT rp.*,
          mr.max_rev_num,
          r.rev_id, r.author_id, r.date,
          ra.rep_login
     FROM rep_path rp,
        ( SELECT rrp.rep_path_id, max(r.rev_num) as max_rev_num
           FROM rev_rep_path  rrp, rev r
          WHERE r.rev_id = rrp.rev_id
          GROUP BY rrp.rep_path_id
        ) mr,
        rev r,
        rep_author ra
    WHERE rp.rep_id = ?
      and rp.rev_num_to is null -- optimalization
      and rp.path not like "tags/%"
      and mr.rep_path_id = rp.rep_path_id
      and r.rev_num = mr.max_rev_num
      and ra.rep_author_id = r.author_id
    ORDER BY max_rev_num DESC
)

    my $schema = $c->model('WebDB')->schema;
    $schema->register_source('ActiveRepPathList' => $new_source);

    return 1;
}


sub index : Path  {
    my ( $self, $c, $p_project, $par1, $par2, @args ) = @_;
    my $params;

    my $ot : Stashed = '';
    #$ot = Dumper( { p_project => $p_project, par1 => $par1, par2 => $par2, args => \@args } );

    my $project_name = undef;

    my $is_index = 0;
    $is_index = 1 if !$p_project; # project list
    # project name found
    if ( $p_project ) {
        $project_name = $p_project;
        $project_name =~ s{^pr-}{};
        $c->stash->{project_name} = $project_name;
    }
    $c->stash->{project_uri} = $c->uri_for( '/report/pr-'.$project_name.'/' );

    # project name, nothing else
    if ( !$par1 ) {
        $is_index = 1;
    # project name and parameters
    } elsif ( $par1 =~ /^(page|rows|offset)\-/ ) {
        $params = $par1;
        $is_index = 1;
    # probably rep_path name
    } else {
        $params = $par2 if $par2;
    }

    # default page listing values
    my $pr = {
        page => 1,
    };
    if ( $params ) {
        # try to set page, rows, ... values from url params
        my @parts = split( ',', $params );
        foreach my $part ( @parts ) {
            if ( $part =~ m/^ page-(\d+) $/x ) {
                $pr->{page} = $1;
                next;
            }
            if ( $part =~ m/^ (rows|offset)-(\d+) $/x ) {
                $pr->{$1} = $2;
                next;
            }
        }
        $pr->{page} = 1 if $pr->{page} < 1;
    }


    $c->model('WebDB')->storage->debug(1);

    if ( $is_index ) {
        my $search = { active => 1, };
        $search->{'project_id.name'} = $project_name if $project_name;
        my $rs = $c->model('WebDB::rep')->search( $search,
            {
                join => [qw/ project_id /],
                'select' => [qw/ rep_id project_id.name project_id.url /],
                'as' => [qw/ rep_id name url /],
            }
        );

        my @projects = ();
        my %rep_paths = ();

        $self->CreateMyResultSets( $c );

        while (my $row = $rs->next) {
            my $project_data = { $row->get_columns };

            my $plus_rows = [ qw/ max_rev_num rev_id author_id date rep_login /];

            my $search_conf = {
                '+select' => $plus_rows,
                '+as' => $plus_rows,
                bind  => [ $project_data->{rep_id} ],
                rows  => $pr->{rows} || 15,
            };
            if ( $project_name ) {
                $search_conf->{page} = $pr->{page};
            }
            my $rs_rp = $c->model('WebDB')->schema->resultset( 'ActiveRepPathList' )->search( {}, $search_conf );

            if ( $project_name ) {
                my $base_uri = '/' . $c->action->namespace . '/pr-' . $project_name . '/page-';
                my $page_uri_prefix = $c->uri_for( $base_uri )->as_string;
                $c->stash->{pager_html} = get_pager_html( $rs_rp->pager, $page_uri_prefix );
            }

            my $row_project_name = $project_data->{name};
            $rep_paths{ $row_project_name } = [];

            while (my $row_rp = $rs_rp->next) {
                my $row_rp_data = { $row_rp->get_columns };
                my $path = $row_rp_data->{path};
                $path =~ s{\/$}{};
                my ( $path_nice, $path_report_uri, $path_type );
                my $path_report_uri_base = $c->uri_for( '/' . $c->action->namespace, 'pr-' . $row_project_name, 'rp-' )->as_string;

                # branches, tags
                if ( my ( $bt, $name ) = $path =~ m{^(branches|tags)\/(.*)$} ) {
                    if ( $bt eq 'branches' ) {
                        $path_type = 'branch';
                    } elsif ( $bt eq 'tags' ) {
                        $path_type = 'tag';
                    }
                    $path_nice = $name;

                    $path_report_uri = $path;
                    $path_report_uri =~ s{\/}{-};
                    $path_report_uri = $path_report_uri_base . $path_report_uri;
                # trunk
                } else {
                    $path_type = '';
                    $path_nice = $path;
                    $path_report_uri = $path_report_uri_base . $path;
                }
                $row_rp_data->{path_type} = $path_type;
                $row_rp_data->{path_nice} = $path_nice;
                $row_rp_data->{path_report_uri} = $path_report_uri;
                push @{ $rep_paths{ $row_project_name } }, $row_rp_data;
            }

            push @projects, $project_data;
        }
        $c->stash->{projects} = \@projects;
        $c->stash->{rep_paths} = \%rep_paths;
        $c->stash->{template} = 'report/index.tt2';

        return;
    }

    if ( $par1 =~ /^diff/ ) {
        #$ot .= Dumper( $c->request->params );
        my @selected_trun_ids = grep { defined $_; } map { $_ =~ /^trun-(\d+)/; $1; } keys %{$c->request->params};
        $ot .= Dumper( \@selected_trun_ids );

        #$ot .= Dumper( $c->model('WebDB::build') );
        my $rs_trun_info = $c->model('WebDB::trun')->search(
            {
                trun_id => \@selected_trun_ids,
            },
            {
                prefetch => {
                    build_id => [ 'rev_id', { 'rep_path_id' => 'rep_id' } ]
                },
                '+select' => [qw/ rev_id.rev_num  /],
                '+as' => [qw/ rev_num /],
                order_by => 'rev_id.rev_num',
            }
        );
        my @trun_infos = ();
        while (my $trun_info = $rs_trun_info->next) {
            my %row = ( $trun_info->get_columns() );
            push @trun_infos, \%row;
        }
        $c->stash->{trun_infos} = \@trun_infos;
        $ot .= Dumper( \@trun_infos );


        my $rs = $c->model('WebDB::ttest')->search(
            {
                trun_id => \@selected_trun_ids,
            },
            {
                join => [
                    { rep_test_id => 'rep_file_id' },
                ],
                '+select' => [qw/
                    rep_test_id.rep_file_id
                    rep_test_id.number
                    rep_test_id.name

                    rep_file_id.rep_path_id
                    rep_file_id.sub_path
                    rep_file_id.rev_num_from
                    rep_file_id.rev_num_to
                /],
                '+as' => [qw/
                    rep_file_id
                    test_number
                    test_name

                    rep_path_id
                    sub_path
                    rev_num_from
                    rev_num_to
                /],
                order_by => [ 'rep_file_id.sub_path', 'me.rep_test_id' ],
            }
        );

        my @ress = ();
        my $prev_rt_id = 0;
        my %res_cache = ();
        my %res_ids_sum = ();
        my $num_of_res = scalar @selected_trun_ids;
        my %row;
        my %prev_row = ();
        my $same_rep_path_id = 1;
        # $rs is ordered by ttest.rep_test_id


        # we need $prev_row, $row and info if next row will be defined
        my $res = undef;
        my $res_next = $rs->next;
        my $num = 1;
        TTEST_NEXT: while ( 1 ) {
            # first run of while loop
            unless ( defined $res ) {
                # nothing found
                last TTEST_NEXT unless defined $res_next;
            }

            # use previous rs to get row
            $res = $res_next;
            $res_next = $rs->next;

            if ( defined $res ) {
                %row = ( $res->get_columns() );
                $same_rep_path_id = 0 if %prev_row && $row{rep_path_id} != $prev_row{rep_path_id};
            }

            #
            # find if results are same
            if ( (not defined $res) || $prev_rt_id != $row{rep_test_id} ) {
                my $are_same = 1;
                if ( $prev_rt_id ) {
                    $are_same = 0 if scalar( keys %res_ids_sum ) > 1;
                    if ( $are_same ) {
                        TTEST_SAME: while (  my ( $k, $v ) = each(%res_ids_sum) ) {
                            if ( $num_of_res != $v ) {
                                $are_same = 0;
                                last TTEST_SAME;
                            }
                        }
                    }
                }

                # remember not different results
                unless ( $are_same ) {
                    #$ot .= Dumper( \%res_ids_sum );
                    #$ot .= Dumper( \@res_cache );
                    delete $prev_row{trest_id};
                    delete $prev_row{trun_id};
                    #$ot .= Dumper( \%prev_row );

                    $ot .= Dumper( \%res_cache );
                    foreach my $trun_info ( @trun_infos ) {
                        next if exists $res_cache{ $trun_info->{trun_id} };
                        my $rev_num = $res_cache{ $trun_info->{trun_id} }->{rev_num};
                        $ot .= Dumper( $trun_info );
                        if ( $rev_num >= $trun_info->{rev_num_from}
                             && ( (not defined $trun_info->{rev_num_to}) || $rev_num <= $trun_info->{rev_num_to} )
                           )
                        {
                            $res_cache{ $trun_info->{trun_id} } = 6;
                        }
                        #my $trun_
                    }
                    $ot .= Dumper( \%res_cache );
                    $ot .= "num $num---\n";
                    push @ress, {
                        file => { %prev_row },
                        results => { %res_cache },
                    };
                }

                last TTEST_NEXT unless defined $res;

                %prev_row = %row;
                $prev_rt_id = $row{rep_test_id};
                %res_cache = ();
                %res_ids_sum = ();
            }


            # another test
            $res_cache{ $row{trun_id} } = $row{trest_id};
            $res_ids_sum{ $row{trest_id} }++;
            $num++;

        }
        $ot .= Dumper( \@ress );
        $c->stash->{same_rep_path_id} = $same_rep_path_id;
        $c->stash->{ress} = \@ress;


        #$ot .= Dumper( $c->model('WebDB::build') );
        my $rs_trest_info = $c->model('WebDB::trest')->search;
        my %trest_infos = ();
        while (my $trest_info = $rs_trest_info->next) {
            my %row = ( $trest_info->get_columns() );
            $trest_infos{ $trest_info->trest_id } = \%row;
        }
        $c->stash->{trest_infos} = \%trest_infos;
        $ot .= Dumper( \%trest_infos );

        $c->stash->{template} = 'report/diff.tt2';
        return;
    }

    # project path selected
    my $p_rep_path = $par1;
    my $rep_path_simple = $p_rep_path;
    $rep_path_simple =~ s{^rp-}{};
    my $rep_path_db = $rep_path_simple;
    $rep_path_db =~ s{-}{\/}g;
    $rep_path_db .= '/';

    $c->stash->{rep_path_param} = $p_rep_path;
    $c->stash->{template} = 'report/report.tt2';

    my $rs = $c->model('WebDB::rep_path')->find(
        {
            path => $rep_path_db,
            'project_id.name' => $project_name
        },
        {
            join => { rep_id => 'project_id', },
            '+select' => [qw/ project_id.project_id /],
            '+as'     => [qw/ project_id /],
        }
    );
    unless ( $rs ) {
        $c->stash->{error} = "Rep_path '$rep_path_db' for project '$project_name' not found.";
        return;
    }
    my $rep_path_id = $rs->rep_path_id ;
    my $project_id = $rs->get_columns('project_id') ;

    my ( $path_nice, $path_type );
    # branches, tags
    if ( my ( $bt, $name ) = $rep_path_simple =~ m{^(branches|tags)\-(.*)$} ) {
        if ( $bt eq 'branches' ) {
            $path_type = 'branch ';
        } elsif ( $bt eq 'tags' ) {
            $path_type = 'tag ';
        }
        $path_nice = $name;

    # trunk
    } else {
        $path_type = '';
        $path_nice = $rep_path_simple;
    }

    #$ot .= "rep_path_id: $rep_path_id\n\n";
    $rs = $c->model('WebDB::rev')->search(
        {
            'get_rev_rep_path.rep_path_id' => $rep_path_id,
        },
        {
            join => [
                'get_rev_rep_path',
                'author_id',
            ],
            'select' => [qw/
                get_rev_rep_path.rep_path_id
                me.rev_id
                me.rev_num
                me.date
                me.author_id
                author_id.rep_login
             /],
            'as' => [qw/
                rep_path_id
                rev_id
                rev_num
                date
                author_id
                rep_login
            /],
            order_by => 'me.rev_num DESC',
            page => $pr->{page},
            rows => $pr->{rows} || 5,
            offset => $pr->{offset} || 0,
        }
    );

    my $build_search = {
            join => [
                { msession_id => 'machine_id', },
                'conf_id',
                { get_trun => 'conf_id', },
            ],
            'select' => [qw/
                me.build_id

                machine_id.machine_id
                machine_id.name
                machine_id.cpuarch
                machine_id.osname
                machine_id.archname

                conf_id.build_conf_id
                conf_id.cc
                conf_id.devel
                conf_id.optimize

                get_trun.trun_id
                get_trun.num_notseen
                get_trun.num_failed
                get_trun.num_unknown
                get_trun.num_todo
                get_trun.num_bonus
                get_trun.num_skip
                get_trun.num_ok

                conf_id_2.trun_conf_id
                conf_id_2.harness_args
            /],
            'as' => [qw/
                build_id

                machine_id
                machine_name
                cpuarch
                osname
                archname

                build_conf_id
                cc
                devel
                optimize

                trun_id
                num_notseen
                num_failed
                num_unknown
                num_todo
                num_bonus
                num_skip
                num_ok

                trun_conf_id
                harness_args
            /],
            order_by => 'machine_id',

        };


    my @revs = ();
    my $builds = {};
    while (my $rev = $rs->next) {
        my %rev_rows = ( $rev->get_columns() );

        my $rs_build = $c->model('WebDB::build')->search(
            {
                'me.rep_path_id' => $rev_rows{rep_path_id},
                'me.rev_id' => $rev_rows{rev_id},
            },
            $build_search
        );
        push @revs, \%rev_rows;

        while (my $build = $rs_build->next) {
            my %build_rows = ( $build->get_columns() );
            push @{$builds->{ $rev_rows{rev_id} }->{ $rev_rows{rep_path_id} }}, \%build_rows;
        }
    }
    #$c->stash->{dump} = sub { return Dumper( \@_ ); };
    #$ot .= Dumper( $builds );
    $c->stash->{revs} = \@revs;
    $c->stash->{builds} = $builds;

    $c->stash->{project_id} = $project_id;
    $c->stash->{rep_path_id} = $rep_path_id;

    $c->stash->{rep_path_nice} = $path_nice;
    $c->stash->{rep_path_type} = $path_type;
    my $path_full = $path_nice;
    $path_full = $path_type . ' ' . $path_full if $path_type;
    $c->stash->{rep_path_full} = $path_full;

    my $base_uri = '/' . $c->action->namespace . '/' . $p_project . '/' . $p_rep_path . '/page-';
    my $page_uri_prefix = $c->uri_for( $base_uri )->as_string;
    $c->stash->{pager_html} = get_pager_html( $rs->pager, $page_uri_prefix );
}


=head1 SEE ALSO

L<TapTinder::Web>, L<Catalyst::Controller>

=head1 AUTHOR

Michal Jurosz <mj@mj41.cz>

=head1 LICENSE

This file is part of TapTinder. See L<TapTinder> license.

=cut


1;