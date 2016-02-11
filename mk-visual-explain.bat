@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/bin/env perl
#line 15
# This is mk-visual-explain, a program to transform MySQL's EXPLAIN output
# into a query execution plan formatted as a tree.
#
# This program is copyright 2007-2011 Baron Schwartz.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.

use strict;
use warnings FATAL => 'all';

our $VERSION = '1.0.22';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7477 $ =~ m/(\d+)/g, 0));

# ###########################################################################
# Converts text (e.g. saved output) to a "recordset" -- an array of hashrefs
# -- just like EXPLAIN does for selectall_arrayref({}).
# ###########################################################################
package ExplainParser;

use strict;
use warnings FATAL => 'all';

sub new {
   bless {}, shift;
}

sub parse_tabular {
   my ( $text, @cols ) = @_;
   my %row;
   my @vals = $text =~ m/\| +([^\|]*?)(?= +\|)/msg;
   return (undef, \@vals) unless @cols;
   @row{@cols} = @vals;
   return (\%row, undef);
}

sub parse_tab_sep {
   my ( $text, @cols ) = @_;
   my %row;
   my @vals = split(/\t/, $text);
   return (undef, \@vals) unless @cols;
   @row{@cols} = @vals;
   return (\%row, undef);
}

sub parse_vertical {
   my ( $text, @cols ) = @_;
   my %row = $text =~ m/^ *(\w+): ([^\n]*) *$/msg;
   return (\%row, undef);
}

sub parse {
   my ($self, $text) = @_;
   my $started = 0;
   my $lines   = 0;
   my @cols    = ();
   my @result  = ();

   # Detect which kind of input it is
   my ( $line_re, $vals_sub );
   if ( $text =~ m/^\+---/m ) { # standard "tabular" output
      $line_re  = qr/^(\| .*)[\r\n]+/m;
      $vals_sub = \&parse_tabular;
   }
   elsif ( $text =~ m/^id\tselect_type\t/m ) { # tab-separated
      $line_re  = qr/^(.*?\t.*)[\r\n]+/m;
      $vals_sub = \&parse_tab_sep;
   }
   elsif ( $text =~ m/\*\*\* 1. row/ ) { # "vertical" output
      $line_re  = qr/^( *.*?^ *Extra:[^\n]*$)/ms;
      $vals_sub = \&parse_vertical;
   }

   if ( $line_re ) {
      # Pull it apart into lines and parse them.
      LINE:
      foreach my $line ( $text =~ m/$line_re/g ) {
         my ($row, $cols) = $vals_sub->($line, @cols);
         if ( $row ) {
            foreach my $key ( keys %$row ) {
               if ( !$row->{$key} || $row->{$key} eq 'NULL' ) {
                  $row->{$key} = undef;
               }
            }
            push @result, $row;
         }
         else {
            @cols = @$cols;
         }
      }
   }

   return \@result;
}

# ###########################################################################
# Converts output of EXPLAIN into a human-readable tree.
# ###########################################################################
package ExplainTree;

use List::Util qw(max);
use Data::Dumper;

sub new {
   my ( $class, $options ) = @_;
   my $self = bless {}, $class;
   $self->load_options($options);
   return $self;
}

sub load_options {
   my ( $self, $options ) = @_;
   if ( $options && ref $options eq 'HASH' ) {
      @{$self}{keys %$options} = values %$options;
   }
   else {
      delete @{$self}{keys %$self};
   }
}

sub parse {
   my ( $self, $text, $options ) = @_;
   return $self->process(ExplainParser->new->parse($text), $options);
}

# The main method that turns a result set into a tree.  Accepts an arrayref of
# hashrefs which correspond to the rows in EXPLAIN.  See the ALGORITHM in the
# documentation for a small novel about this process.
sub process {
   my ( $self, $rows, $options ) = @_;
   $self->load_options($options);
   return unless ref $rows eq 'ARRAY' && @$rows;

   # Pre-process and sanity check the rows.
   my @rows = @$rows;
   foreach my $i ( 0 .. $#rows ) {
      my $row = $rows[$i];
      $row->{rowid} = $i;
      $row->{Extra} ||= '';

      # The source code says if there are too many tables unioned together, the
      # table column will get truncated, like "<union1,2,3,4...>".  If this
      # happens, I've got to bail out.  I'm not going to check all the source
      # code for all versions, but in 5.0 it looks like I can get this to happen
      # around table 20.
      die "UNION has too many tables: $row->{table}"
         if $row->{table} && $row->{table} =~ m/\./;

      if ( !defined $row->{id} ) {
         if ( $row->{table} && (my ($id) = $row->{table} =~ m/^<union(\d+)/) ) {
            $row->{id} = $id;
         }
         else {
            die "Unexpected NULL in id column, please report as a bug";
         }
      }
   }

   # Re-order the rows so all references are forward.
   my %union_for
      = map  { $_->{id} => $_ }
        grep { $_->{select_type} eq 'UNION RESULT' }
        @rows;

   my $last_id = 0;
   my @reordered;
   foreach my $row ( grep { $_->{select_type} ne 'UNION RESULT' } @rows ) {
      if ( $last_id != $row->{id} && $union_for{$row->{id}} ) {
         push @reordered, $union_for{$row->{id}};
      }
      push @reordered, $row;
      $last_id = $row->{id};
   }

   # Process the rows recursively.
   my $tree = $self->build_query_plan(@reordered);

   return $tree;
}

sub build_query_plan {
   my ( $self, @rows ) = @_;

   if ( !@rows ) {
      die "I got no rows";
   }

   # Is it a UNION RESULT?  Split it up into sub-scopes and recurse.
   if ( $rows[0]->{select_type} eq 'UNION RESULT' ) {
      my $row = shift @rows;
      my @kids;
      my @ids   = $row->{table} =~ m/(\d+)/g;
      my $enclosing_scope;
      if ( $rows[0]->{select_type} =~ m/SUBQUERY/ ) {
         $enclosing_scope = $rows[0];
      }
      foreach my $i ( 0 .. $#ids ) {
         my $start = $self->index_of($ids[$i], @rows);
         my $end   = $i < $#ids ? $self->index_of($ids[$i + 1], @rows) : @rows;
         push @kids, $self->build_query_plan(splice(@rows, $start, $end - $start));
      }
      $row->{children} = [ @kids ];
      $row->{table}    = "union("
         . join(',', map { $self->recursive_table_name($_) || '<none>' } @kids)
         . ")";
      my $tree = $self->transform($row);
      if ( $enclosing_scope ) {
         my $node = $self->transform($enclosing_scope);
         $node->{children} = [ $tree ];
         $tree = $node;
      }
      return $tree;
   }

   # Are there DERIVED tables?  If so, find its children and pull them out of the
   # list under it.
   while ( my ($der) = grep { $_->{table} && $_->{table} =~ m/^<derived\d+>$/ } @rows ) {

      # Figure out the start and end of the derived scope.
      my ($der_id) = $der->{table} =~ m/^<derived(\d+)>$/;
      my $start    = $self->index_of($der_id, @rows);
      my $end      = $start;
      while ( $end < @rows && $rows[$end]->{id} >= $der_id ) {
         $end++;
      }

      # Get the rows that belong to this scope and recurse.
      my @enclosed_scope = splice(@rows, $start, $end - $start);
      my $kids           = $self->build_query_plan(@enclosed_scope);
      $der->{children}   = [$kids];
      $der->{table}      = "derived(" . ($self->recursive_table_name($kids) || '<none>') . ")";
   }

   # Handle the "normal case."  For each node, if the id is the same as the last
   # one, JOIN and continue.  If the id is greater, it's a subquery, so should
   # be recursed.

   # But, filesort/temporary have to be handled specially, because they appear
   # in the first row, even if they are done later.  Here are the cases,
   # according to http://s.petrunia.net/blog/?p=24:

   # ... MySQL has three ways to run a join and produce ordered output:
   # Method                               EXPLAIN output
   # ##################################   ####################################
   # Use index-based access method that   no mention of filesort
   # produces ordered output
   # ----------------------------------   ------------------------------------
   # Use filesort() on 1st non-constant   "Using filesort" in the first row
   # table
   # ----------------------------------   ------------------------------------
   # Put join result into a temporary     "Using temporary; Using filesort" in
   # table and use filesort() on it       the first row
   # ----------------------------------   ------------------------------------

   my $first = shift(@rows);

   # This is "case three" above.
   my $is_temp_filesort;
   if ( $first->{Extra} =~ m/Using temporary; Using filesort/ ) {
      # The entire join is being placed into a temporary table and filesorted,
      # so I'll make a note of that and apply it afterwards.  In the meantime I
      # must remove mention of it from the node so the node doesn't get extra
      # transformations in transform().
      $is_temp_filesort = 1;
      $first->{Extra} =~ s/Using temporary; Using filesort(?:; )?//;
   }

   # This is "case two" above.  Must find first non-constant table and move
   # the filesort() there.
   elsif ( $first->{Extra} =~ m/Using filesort/ && $first->{type} =~ m/^(?:system|const)$/ ) {
      my ( $first_non_const ) = grep { $_->{type} !~ m/^(?:system|const)$/ } @rows;
      if ( $first_non_const ) {
         $first->{Extra} =~ s/Using filesort(?:; )?//;
         $first_non_const->{Extra} .= '; Using filesort';
      }
   }

   my $scope = $first->{id};
   my $tree  = $self->transform($first);
   my $i     = 0;
   while ( $i < @rows ) {
      my $row = $rows[$i];
      if ( $row->{id} == $scope ) {
         $tree = {
            type     => 'JOIN',
            children => [ $tree, $self->transform($row) ],
         };
         $i++;
      }
      else {
         # It's another kind of "join".  Find the enclosing scope boundaries and
         # recurse.  The scope starts at $i.
         my $end = $i;
         while ( $end < @rows && $rows[$end]->{id} >= $row->{id} ) {
            $end++;
         }
         my @enclosed_scope = splice(@rows, $i, $end - $i);
         $tree = {
            type     => $row->{select_type},
            children => [ $tree, $self->build_query_plan(@enclosed_scope) ],
         };
         # Don't increment the pointer because I just removed rows from @rows.
         # $i++
      }
   }

   if ( $is_temp_filesort ) {
      $tree = $self->filesort(
         $self->temporary($tree, $self->recursive_table_name($tree)));
   }

   return $tree;
}

sub transform {
   my ( $self, $row ) = @_;

   my $sub = $row->{type};

   # ##################################################################
   # Dispatch to a class method to generate the tree.
   # ##################################################################
   my $no_matching_row = join('|',
      "Impossible (?:WHERE|HAVING)(?: noticed after reading const tables)?",
      'No matching.*row',
      '(?:unique|const) row not found',
   );
   my $node
      = $sub
         ? $self->$sub($row)
      : $row->{Extra} =~ m/No tables/
         ? { type => ( $row->{select_type} !~ m/^(?:PRIMARY|SIMPLE)$/
                     ? $row->{select_type}
                     : 'DUAL') }
      : $row->{Extra} =~ m/(?:$no_matching_row)/i
         ? { type => 'IMPOSSIBLE' }
      : $row->{Extra} =~ m/optimized away/
         ? { type => 'CONSTANT' }
      : die "Can't handle " . Dumper($row);

   my ($warn) = $row->{Extra} =~ m/($no_matching_row)/;
   if ( $warn ) {
      $node->{warning} = $warn;
   }

   # ##################################################################
   # Apply other tree transformations.
   # ##################################################################
   if ( $row->{Extra} =~ m/Using where/ ) {
      $node = {
         type     => 'Filter with WHERE',
         children => [$node],
      };
   }

   if ( $row->{Extra} =~ m/Using join buffer/ ) {
      $node = {
         type     => 'Join buffer',
         children => [$node],
      };
   }

   if ( $row->{Extra} =~ m/Distinct|Not exists/ ) {
      $node = {
         type     => 'Distinct/Not-Exists',
         children => [$node],
      };
   }

   if ( $row->{Extra} =~ m/Range checked for each record \(\w+ map: ([^\)]+)\)/ ) {
      # (index map: N) is a bitmap of which indexes are used.  For example:
      #  0x5  base 16 (or base 10)
      # 0101  base 2
      # 4321  position of bits
      #  3 1  indexes used
      my $bitmap = eval "int($1)";                    # Hex to decimal if it begins with '0x'
      $bitmap    = unpack("B32", pack("N", $bitmap)); # Convert into binary string of 1/0
      $bitmap    =~ s/^0+//;                          # Remove leading zeros
      $bitmap    = reverse $bitmap;                   # Iterate from left-to-right
      my $possible_keys = join(',',
         grep { substr($bitmap, $_ - 1, 1) }
        ( 1 .. length($bitmap) ));
      $node = {
         type          => 'Re-evaluate indexes each row',
         possible_keys => $possible_keys,
         children      => [$node],
      };
   }

   if ( $row->{Extra} =~ m/Using filesort/ ) {
      $node = $self->filesort($node);
   }

   if ( $row->{Extra} =~ m/Using temporary/ ) {
      $node = $self->temporary($node, $row->{table}, 1);
   }

   # Add some data that will help me keep track of nodes as I manipulate
   # them later
   $node->{id}    = $row->{id};
   $node->{rowid} = $row->{rowid};

   return $node;
}

sub index_of {
   my ( $self, $id, @rows ) = @_;
   my $i = 0;
   foreach my $row ( @rows ) {
      if ( $row->{id} && $row->{id} == $id ) {
         return $i;
      }
      $i++;
   }
   die "Can't find row $id in "
      . join(',', map { $_->{id} || '' } @rows);
}

sub pretty_print {
   my ( $self, $node, $prefix ) = @_;
   $prefix ||= '';
   my $branch = $prefix ? substr($prefix, 0, length($prefix) -3) . '+- ' : '';
   my $output = $branch . $node->{type} . "\n";

   my @kids;
   if ( $node->{children} ) {
      @kids   = reverse @{$node->{children}};
   }
   my $suffix = (@kids > 1) ? '|  ' : '   ';

   foreach my $thing ( qw(table key partitions possible_keys method key_len ref rows warning) ) {
      if ( defined $node->{$thing} ) {
         $output .= $prefix . sprintf('%-14s %s', $thing, $node->{$thing}) . "\n";
      }
   }

   my $last_child = pop @kids;
   foreach my $child ( @kids ) {
      $output .= $self->pretty_print($child, $prefix . $suffix);
   }
   if ( $last_child ) {
      $output .= $self->pretty_print($last_child, $prefix . '   ');
   }
   return $output;
}

#############################################################################
# Each method in this section corresponds to a value you will find in the 'type'
# column in EXPLAIN.
#############################################################################

sub ALL {
   my ( $self, $row ) = @_;
   return {
      type     => 'Table scan',
      rows     => $row->{rows},
      children => [$self->table($row)],
   };
}

sub fulltext {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Fulltext scan');
}

sub range {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Index range scan');
}

sub index {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Index scan');
}

sub eq_ref {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Unique index lookup');
}

sub ref {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Index lookup');
}

sub ref_or_null {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Index lookup with extra null lookup');
}

sub const {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Constant index lookup');
}

sub system {
   my ( $self, $row ) = @_;
   return {
      type => 'Constant table access',
      rows     => $row->{rows},
      children => [$self->table($row)],
   };
}

sub unique_subquery {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Unique subquery');
}

sub index_subquery {
   my ( $self, $row ) = @_;
   return $self->index_access($row, 'Index subquery');
}

# From the manual: "The Index Merge method is used to retrieve rows with
# several range scans and to merge their results into one."  Therefore each
# index access should be shown as an index range scan.  The unions and
# intersections can be recursive, as in
# union(intersect(key1,key2),intersect(key3,key4))
sub index_merge {
   my ( $self, $row ) = @_;
   my ( $merge_spec )
      = $row->{Extra} =~ m/Using ((?:intersect|union|sort_union)\(.*?\))(?=;|$)/;
   my ($merge, $num) = $self->recurse_index_merge($row, $merge_spec, 0);

   # index_merge_bookmark_lookup note:
   # From the manual, "If the used indexes don't cover all columns used in the
   # query, full rows are retrieved only when the range conditions for all
   # used keys are satisfied."  So a bookmark lookup shouldn't be shown for
   # all indexes; it should be shown from the merge results.
   return $self->bookmark_lookup($merge, $row);
}

# ###########################################################################
# Helper subroutines.
# ###########################################################################

sub recursive_table_name {
   my ( $self, $node ) = @_;
   if ( $node->{table} ) {
      return $node->{table};
   }
   if ( $node->{key} ) {
      my ( $table ) = $node->{key} =~ m/(.*?)->/;
      return $table;
   }
   if ( $node->{type} eq 'Bookmark lookup' ) {
      return $node->{children}->[1]->{table};
   }
   if ( $node->{type} eq 'IMPOSSIBLE' ) {
      return '<none>';
   }
   if ( $node->{children} ) {
      return join(',',
         grep { $_ }
         map  { $self->recursive_table_name($_) }
              @{$node->{children}});
   }
}

# $num is the number of nodes to the left of this node in a depth-first
# traversal.  It lets me figure out which value goes in key_len.
my $bal; # Workaround for issue 90 (Variable "$bal" will not stay shared).
sub recurse_index_merge {
   my ( $self, $row, $spec, $num ) = @_;
   my ($type, $args) = $spec =~ m/(intersect|union|sort_union)\((.*)\)$/;

   my @children;

   # See 'man perlre' and search for 'matches a parenthesized group'.
   $bal = qr/
      \(
      (?:
         (?> [^()]+ )    # Non-parens without backtracking
         |
         (??{ $bal })     # Group with matching parens
      )*
      \)
   /x;

   # Extract a thing, followed by balanced parentheses.
   foreach my $child ( $args =~ m/(\w+$bal)/g ) {
      my ( $subtree, $num ) = $self->recurse_index_merge($row, $child, $num);
      push @children, $subtree;
   }

   if ( !@children ) { # Recursion base case; $args is an index list
      foreach my $idx ( split(/,/, $args) ) {
         my $index_scan = $self->index_access($row, 'Index range scan', $idx);
         $index_scan->{key_len} = ($row->{key_len} =~ m/(\d+)/g)[$num++];
         push @children, $index_scan;
      }
   }

   return (
      {
         type     => 'Index merge',
         method   => $type,
         rows     => $row->{rows},
         children => \@children,
      },
      $num
   );

}

sub table {
   my ( $self, $row ) = @_;
   my $node = {
      type          => ($row->{table} && $row->{table} =~ m/^(derived|union)\(/)
                       ? uc $1
                       : 'Table',
      table         => $row->{table},
      possible_keys => $row->{possible_keys},
      partitions    => $row->{partitions},
   };
   if ( $row->{children} ) {
      $node->{children} = $row->{children};
   }
   return $node;
}

sub bookmark_lookup {
   my ( $self, $node, $row ) = @_;
   if ( $row->{Extra} =~ m/Using index/
         || ( $self->{clustered} && $row->{key} && $row->{key} eq 'PRIMARY' ))
   {
      return $node;
   }
   return {
      type     => 'Bookmark lookup',
      children => [ $node, $self->table($row) ],
   };
}

sub filesort {
   my ( $self, $node ) = @_;
   return {
      type     => 'Filesort',
      children => [$node],
   };
}

sub temporary {
   my ( $self, $node, $table_name, $is_scan ) = @_;
   $node = {
      type          => 'TEMPORARY',
      table         => "temporary($table_name)",
      possible_keys => undef,
      partitions    => undef,
      children      => [$node],
   };
   if ( $is_scan ) {
      $node = {
         type     => 'Table scan',
         rows     => undef,
         children => [ $node ],
      };
   }
   return $node;
}

sub index_access {
   my ( $self, $row, $type, $key ) = @_;
   my $node = {
      type          => $type,
      key           => $row->{table} . '->' . ( $key || $row->{key} ),
      possible_keys => $row->{possible_keys},
      partitions    => $row->{partitions},
      key_len       => $row->{key_len},
      'ref'         => $row->{ref},
      rows          => $row->{rows},
   };
   if ( $row->{Extra} =~ m/Full scan on NULL key/ ) {
      $node->{warning} = 'Full scan on NULL key';
   }
   if ( $row->{Extra} =~ m/Using index for group-by/ ) {
      $node->{type} = 'Loose index scan';
   }
   # See index_merge_bookmark_lookup note above.
   if ( $row->{type} ne 'index_merge' ) {
      $node = $self->bookmark_lookup($node, $row);
   }
   return $node;
}

# ###########################################################################
# OptionParser package 7102
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/OptionParser.pm
#   trunk/common/t/OptionParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package OptionParser;

use strict;
use warnings FATAL => 'all';
use List::Util qw(max);
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Getopt::Long;

my $POD_link_re = '[LC]<"?([^">]+)"?>';

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($program_name) = $PROGRAM_NAME =~ m/([.A-Za-z-]+)$/;
   $program_name ||= $PROGRAM_NAME;
   my $home = $ENV{HOME} || $ENV{HOMEPATH} || $ENV{USERPROFILE} || '.';

   my %attributes = (
      'type'       => 1,
      'short form' => 1,
      'group'      => 1,
      'default'    => 1,
      'cumulative' => 1,
      'negatable'  => 1,
   );

   my $self = {
      head1             => 'OPTIONS',        # These args are used internally
      skip_rules        => 0,                # to instantiate another Option-
      item              => '--(.*)',         # Parser obj that parses the
      attributes        => \%attributes,     # DSN OPTIONS section.  Tools
      parse_attributes  => \&_parse_attribs, # don't tinker with these args.

      %args,

      strict            => 1,  # disabled by a special rule
      program_name      => $program_name,
      opts              => {},
      got_opts          => 0,
      short_opts        => {},
      defaults          => {},
      groups            => {},
      allowed_groups    => {},
      errors            => [],
      rules             => [],  # desc of rules for --help
      mutex             => [],  # rule: opts are mutually exclusive
      atleast1          => [],  # rule: at least one opt is required
      disables          => {},  # rule: opt disables other opts 
      defaults_to       => {},  # rule: opt defaults to value of other opt
      DSNParser         => undef,
      default_files     => [
         "/etc/maatkit/maatkit.conf",
         "/etc/maatkit/$program_name.conf",
         "$home/.maatkit.conf",
         "$home/.$program_name.conf",
      ],
      types             => {
         string => 's', # standard Getopt type
         int    => 'i', # standard Getopt type
         float  => 'f', # standard Getopt type
         Hash   => 'H', # hash, formed from a comma-separated list
         hash   => 'h', # hash as above, but only if a value is given
         Array  => 'A', # array, similar to Hash
         array  => 'a', # array, similar to hash
         DSN    => 'd', # DSN
         size   => 'z', # size with kMG suffix (powers of 2^10)
         time   => 'm', # time, with an optional suffix of s/h/m/d
      },
   };

   return bless $self, $class;
}

sub get_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   my @specs = $self->_pod_to_specs($file);
   $self->_parse_specs(@specs);

   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   if ( $contents =~ m/^=head1 DSN OPTIONS/m ) {
      MKDEBUG && _d('Parsing DSN OPTIONS');
      my $dsn_attribs = {
         dsn  => 1,
         copy => 1,
      };
      my $parse_dsn_attribs = sub {
         my ( $self, $option, $attribs ) = @_;
         map {
            my $val = $attribs->{$_};
            if ( $val ) {
               $val    = $val eq 'yes' ? 1
                       : $val eq 'no'  ? 0
                       :                 $val;
               $attribs->{$_} = $val;
            }
         } keys %$attribs;
         return {
            key => $option,
            %$attribs,
         };
      };
      my $dsn_o = new OptionParser(
         description       => 'DSN OPTIONS',
         head1             => 'DSN OPTIONS',
         dsn               => 0,         # XXX don't infinitely recurse!
         item              => '\* (.)',  # key opts are a single character
         skip_rules        => 1,         # no rules before opts
         attributes        => $dsn_attribs,
         parse_attributes  => $parse_dsn_attribs,
      );
      my @dsn_opts = map {
         my $opts = {
            key  => $_->{spec}->{key},
            dsn  => $_->{spec}->{dsn},
            copy => $_->{spec}->{copy},
            desc => $_->{desc},
         };
         $opts;
      } $dsn_o->_pod_to_specs($file);
      $self->{DSNParser} = DSNParser->new(opts => \@dsn_opts);
   }

   return;
}

sub DSNParser {
   my ( $self ) = @_;
   return $self->{DSNParser};
};

sub get_defaults_files {
   my ( $self ) = @_;
   return @{$self->{default_files}};
}

sub _pod_to_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";

   my @specs = ();
   my @rules = ();
   my $para;

   local $INPUT_RECORD_SEPARATOR = '';
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=head1 $self->{head1}/;
      last;
   }

   while ( $para = <$fh> ) {
      last if $para =~ m/^=over/;
      next if $self->{skip_rules};
      chomp $para;
      $para =~ s/\s+/ /g;
      $para =~ s/$POD_link_re/$1/go;
      MKDEBUG && _d('Option rule:', $para);
      push @rules, $para;
   }

   die "POD has no $self->{head1} section" unless $para;

   do {
      if ( my ($option) = $para =~ m/^=item $self->{item}/ ) {
         chomp $para;
         MKDEBUG && _d($para);
         my %attribs;

         $para = <$fh>; # read next paragraph, possibly attributes

         if ( $para =~ m/: / ) { # attributes
            $para =~ s/\s+\Z//g;
            %attribs = map {
                  my ( $attrib, $val) = split(/: /, $_);
                  die "Unrecognized attribute for --$option: $attrib"
                     unless $self->{attributes}->{$attrib};
                  ($attrib, $val);
               } split(/; /, $para);
            if ( $attribs{'short form'} ) {
               $attribs{'short form'} =~ s/-//;
            }
            $para = <$fh>; # read next paragraph, probably short help desc
         }
         else {
            MKDEBUG && _d('Option has no attributes');
         }

         $para =~ s/\s+\Z//g;
         $para =~ s/\s+/ /g;
         $para =~ s/$POD_link_re/$1/go;

         $para =~ s/\.(?:\n.*| [A-Z].*|\Z)//s;
         MKDEBUG && _d('Short help:', $para);

         die "No description after option spec $option" if $para =~ m/^=item/;

         if ( my ($base_option) =  $option =~ m/^\[no\](.*)/ ) {
            $option = $base_option;
            $attribs{'negatable'} = 1;
         }

         push @specs, {
            spec  => $self->{parse_attributes}->($self, $option, \%attribs), 
            desc  => $para
               . (defined $attribs{default} ? " (default $attribs{default})" : ''),
            group => ($attribs{'group'} ? $attribs{'group'} : 'default'),
         };
      }
      while ( $para = <$fh> ) {
         last unless $para;
         if ( $para =~ m/^=head1/ ) {
            $para = undef; # Can't 'last' out of a do {} block.
            last;
         }
         last if $para =~ m/^=item /;
      }
   } while ( $para );

   die "No valid specs in $self->{head1}" unless @specs;

   close $fh;
   return @specs, @rules;
}

sub _parse_specs {
   my ( $self, @specs ) = @_;
   my %disables; # special rule that requires deferred checking

   foreach my $opt ( @specs ) {
      if ( ref $opt ) { # It's an option spec, not a rule.
         MKDEBUG && _d('Parsing opt spec:',
            map { ($_, '=>', $opt->{$_}) } keys %$opt);

         my ( $long, $short ) = $opt->{spec} =~ m/^([\w-]+)(?:\|([^!+=]*))?/;
         if ( !$long ) {
            die "Cannot parse long option from spec $opt->{spec}";
         }
         $opt->{long} = $long;

         die "Duplicate long option --$long" if exists $self->{opts}->{$long};
         $self->{opts}->{$long} = $opt;

         if ( length $long == 1 ) {
            MKDEBUG && _d('Long opt', $long, 'looks like short opt');
            $self->{short_opts}->{$long} = $long;
         }

         if ( $short ) {
            die "Duplicate short option -$short"
               if exists $self->{short_opts}->{$short};
            $self->{short_opts}->{$short} = $long;
            $opt->{short} = $short;
         }
         else {
            $opt->{short} = undef;
         }

         $opt->{is_negatable}  = $opt->{spec} =~ m/!/        ? 1 : 0;
         $opt->{is_cumulative} = $opt->{spec} =~ m/\+/       ? 1 : 0;
         $opt->{is_required}   = $opt->{desc} =~ m/required/ ? 1 : 0;

         $opt->{group} ||= 'default';
         $self->{groups}->{ $opt->{group} }->{$long} = 1;

         $opt->{value} = undef;
         $opt->{got}   = 0;

         my ( $type ) = $opt->{spec} =~ m/=(.)/;
         $opt->{type} = $type;
         MKDEBUG && _d($long, 'type:', $type);


         $opt->{spec} =~ s/=./=s/ if ( $type && $type =~ m/[HhAadzm]/ );

         if ( (my ($def) = $opt->{desc} =~ m/default\b(?: ([^)]+))?/) ) {
            $self->{defaults}->{$long} = defined $def ? $def : 1;
            MKDEBUG && _d($long, 'default:', $def);
         }

         if ( $long eq 'config' ) {
            $self->{defaults}->{$long} = join(',', $self->get_defaults_files());
         }

         if ( (my ($dis) = $opt->{desc} =~ m/(disables .*)/) ) {
            $disables{$long} = $dis;
            MKDEBUG && _d('Deferring check of disables rule for', $opt, $dis);
         }

         $self->{opts}->{$long} = $opt;
      }
      else { # It's an option rule, not a spec.
         MKDEBUG && _d('Parsing rule:', $opt); 
         push @{$self->{rules}}, $opt;
         my @participants = $self->_get_participants($opt);
         my $rule_ok = 0;

         if ( $opt =~ m/mutually exclusive|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{mutex}}, \@participants;
            MKDEBUG && _d(@participants, 'are mutually exclusive');
         }
         if ( $opt =~ m/at least one|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{atleast1}}, \@participants;
            MKDEBUG && _d(@participants, 'require at least one');
         }
         if ( $opt =~ m/default to/ ) {
            $rule_ok = 1;
            $self->{defaults_to}->{$participants[0]} = $participants[1];
            MKDEBUG && _d($participants[0], 'defaults to', $participants[1]);
         }
         if ( $opt =~ m/restricted to option groups/ ) {
            $rule_ok = 1;
            my ($groups) = $opt =~ m/groups ([\w\s\,]+)/;
            my @groups = split(',', $groups);
            %{$self->{allowed_groups}->{$participants[0]}} = map {
               s/\s+//;
               $_ => 1;
            } @groups;
         }
         if( $opt =~ m/accepts additional command-line arguments/ ) {
            $rule_ok = 1;
            $self->{strict} = 0;
            MKDEBUG && _d("Strict mode disabled by rule");
         }

         die "Unrecognized option rule: $opt" unless $rule_ok;
      }
   }

   foreach my $long ( keys %disables ) {
      my @participants = $self->_get_participants($disables{$long});
      $self->{disables}->{$long} = \@participants;
      MKDEBUG && _d('Option', $long, 'disables', @participants);
   }

   return; 
}

sub _get_participants {
   my ( $self, $str ) = @_;
   my @participants;
   foreach my $long ( $str =~ m/--(?:\[no\])?([\w-]+)/g ) {
      die "Option --$long does not exist while processing rule $str"
         unless exists $self->{opts}->{$long};
      push @participants, $long;
   }
   MKDEBUG && _d('Participants for', $str, ':', @participants);
   return @participants;
}

sub opts {
   my ( $self ) = @_;
   my %opts = %{$self->{opts}};
   return %opts;
}

sub short_opts {
   my ( $self ) = @_;
   my %short_opts = %{$self->{short_opts}};
   return %short_opts;
}

sub set_defaults {
   my ( $self, %defaults ) = @_;
   $self->{defaults} = {};
   foreach my $long ( keys %defaults ) {
      die "Cannot set default for nonexistent option $long"
         unless exists $self->{opts}->{$long};
      $self->{defaults}->{$long} = $defaults{$long};
      MKDEBUG && _d('Default val for', $long, ':', $defaults{$long});
   }
   return;
}

sub get_defaults {
   my ( $self ) = @_;
   return $self->{defaults};
}

sub get_groups {
   my ( $self ) = @_;
   return $self->{groups};
}

sub _set_option {
   my ( $self, $opt, $val ) = @_;
   my $long = exists $self->{opts}->{$opt}       ? $opt
            : exists $self->{short_opts}->{$opt} ? $self->{short_opts}->{$opt}
            : die "Getopt::Long gave a nonexistent option: $opt";

   $opt = $self->{opts}->{$long};
   if ( $opt->{is_cumulative} ) {
      $opt->{value}++;
   }
   else {
      $opt->{value} = $val;
   }
   $opt->{got} = 1;
   MKDEBUG && _d('Got option', $long, '=', $val);
}

sub get_opts {
   my ( $self ) = @_; 

   foreach my $long ( keys %{$self->{opts}} ) {
      $self->{opts}->{$long}->{got} = 0;
      $self->{opts}->{$long}->{value}
         = exists $self->{defaults}->{$long}       ? $self->{defaults}->{$long}
         : $self->{opts}->{$long}->{is_cumulative} ? 0
         : undef;
   }
   $self->{got_opts} = 0;

   $self->{errors} = [];

   if ( @ARGV && $ARGV[0] eq "--config" ) {
      shift @ARGV;
      $self->_set_option('config', shift @ARGV);
   }
   if ( $self->has('config') ) {
      my @extra_args;
      foreach my $filename ( split(',', $self->get('config')) ) {
         eval {
            push @extra_args, $self->_read_config_file($filename);
         };
         if ( $EVAL_ERROR ) {
            if ( $self->got('config') ) {
               die $EVAL_ERROR;
            }
            elsif ( MKDEBUG ) {
               _d($EVAL_ERROR);
            }
         }
      }
      unshift @ARGV, @extra_args;
   }

   Getopt::Long::Configure('no_ignore_case', 'bundling');
   GetOptions(
      map    { $_->{spec} => sub { $self->_set_option(@_); } }
      grep   { $_->{long} ne 'config' } # --config is handled specially above.
      values %{$self->{opts}}
   ) or $self->save_error('Error parsing options');

   if ( exists $self->{opts}->{version} && $self->{opts}->{version}->{got} ) {
      printf("%s  Ver %s Distrib %s Changeset %s\n",
         $self->{program_name}, $main::VERSION, $main::DISTRIB, $main::SVN_REV)
            or die "Cannot print: $OS_ERROR";
      exit 0;
   }

   if ( @ARGV && $self->{strict} ) {
      $self->save_error("Unrecognized command-line options @ARGV");
   }

   foreach my $mutex ( @{$self->{mutex}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$mutex;
      if ( @set > 1 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$mutex}[ 0 .. scalar(@$mutex) - 2] )
                 . ' and --'.$self->{opts}->{$mutex->[-1]}->{long}
                 . ' are mutually exclusive.';
         $self->save_error($err);
      }
   }

   foreach my $required ( @{$self->{atleast1}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$required;
      if ( @set == 0 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$required}[ 0 .. scalar(@$required) - 2] )
                 .' or --'.$self->{opts}->{$required->[-1]}->{long};
         $self->save_error("Specify at least one of $err");
      }
   }

   $self->_check_opts( keys %{$self->{opts}} );
   $self->{got_opts} = 1;
   return;
}

sub _check_opts {
   my ( $self, @long ) = @_;
   my $long_last = scalar @long;
   while ( @long ) {
      foreach my $i ( 0..$#long ) {
         my $long = $long[$i];
         next unless $long;
         my $opt  = $self->{opts}->{$long};
         if ( $opt->{got} ) {
            if ( exists $self->{disables}->{$long} ) {
               my @disable_opts = @{$self->{disables}->{$long}};
               map { $self->{opts}->{$_}->{value} = undef; } @disable_opts;
               MKDEBUG && _d('Unset options', @disable_opts,
                  'because', $long,'disables them');
            }

            if ( exists $self->{allowed_groups}->{$long} ) {

               my @restricted_groups = grep {
                  !exists $self->{allowed_groups}->{$long}->{$_}
               } keys %{$self->{groups}};

               my @restricted_opts;
               foreach my $restricted_group ( @restricted_groups ) {
                  RESTRICTED_OPT:
                  foreach my $restricted_opt (
                     keys %{$self->{groups}->{$restricted_group}} )
                  {
                     next RESTRICTED_OPT if $restricted_opt eq $long;
                     push @restricted_opts, $restricted_opt
                        if $self->{opts}->{$restricted_opt}->{got};
                  }
               }

               if ( @restricted_opts ) {
                  my $err;
                  if ( @restricted_opts == 1 ) {
                     $err = "--$restricted_opts[0]";
                  }
                  else {
                     $err = join(', ',
                               map { "--$self->{opts}->{$_}->{long}" }
                               grep { $_ } 
                               @restricted_opts[0..scalar(@restricted_opts) - 2]
                            )
                          . ' or --'.$self->{opts}->{$restricted_opts[-1]}->{long};
                  }
                  $self->save_error("--$long is not allowed with $err");
               }
            }

         }
         elsif ( $opt->{is_required} ) { 
            $self->save_error("Required option --$long must be specified");
         }

         $self->_validate_type($opt);
         if ( $opt->{parsed} ) {
            delete $long[$i];
         }
         else {
            MKDEBUG && _d('Temporarily failed to parse', $long);
         }
      }

      die "Failed to parse options, possibly due to circular dependencies"
         if @long == $long_last;
      $long_last = @long;
   }

   return;
}

sub _validate_type {
   my ( $self, $opt ) = @_;
   return unless $opt;

   if ( !$opt->{type} ) {
      $opt->{parsed} = 1;
      return;
   }

   my $val = $opt->{value};

   if ( $val && $opt->{type} eq 'm' ) {  # type time
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a time value');
      my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
      if ( !$suffix ) {
         my ( $s ) = $opt->{desc} =~ m/\(suffix (.)\)/;
         $suffix = $s || 's';
         MKDEBUG && _d('No suffix given; using', $suffix, 'for',
            $opt->{long}, '(value:', $val, ')');
      }
      if ( $suffix =~ m/[smhd]/ ) {
         $val = $suffix eq 's' ? $num            # Seconds
              : $suffix eq 'm' ? $num * 60       # Minutes
              : $suffix eq 'h' ? $num * 3600     # Hours
              :                  $num * 86400;   # Days
         $opt->{value} = ($prefix || '') . $val;
         MKDEBUG && _d('Setting option', $opt->{long}, 'to', $val);
      }
      else {
         $self->save_error("Invalid time suffix for --$opt->{long}");
      }
   }
   elsif ( $val && $opt->{type} eq 'd' ) {  # type DSN
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a DSN');
      my $prev = {};
      my $from_key = $self->{defaults_to}->{ $opt->{long} };
      if ( $from_key ) {
         MKDEBUG && _d($opt->{long}, 'DSN copies from', $from_key, 'DSN');
         if ( $self->{opts}->{$from_key}->{parsed} ) {
            $prev = $self->{opts}->{$from_key}->{value};
         }
         else {
            MKDEBUG && _d('Cannot parse', $opt->{long}, 'until',
               $from_key, 'parsed');
            return;
         }
      }
      my $defaults = $self->{DSNParser}->parse_options($self);
      $opt->{value} = $self->{DSNParser}->parse($val, $prev, $defaults);
   }
   elsif ( $val && $opt->{type} eq 'z' ) {  # type size
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a size value');
      $self->_parse_size($opt, $val);
   }
   elsif ( $opt->{type} eq 'H' || (defined $val && $opt->{type} eq 'h') ) {
      $opt->{value} = { map { $_ => 1 } split(/(?<!\\),\s*/, ($val || '')) };
   }
   elsif ( $opt->{type} eq 'A' || (defined $val && $opt->{type} eq 'a') ) {
      $opt->{value} = [ split(/(?<!\\),\s*/, ($val || '')) ];
   }
   else {
      MKDEBUG && _d('Nothing to validate for option',
         $opt->{long}, 'type', $opt->{type}, 'value', $val);
   }

   $opt->{parsed} = 1;
   return;
}

sub get {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{value};
}

sub got {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{got};
}

sub has {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   return defined $long ? exists $self->{opts}->{$long} : 0;
}

sub set {
   my ( $self, $opt, $val ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   $self->{opts}->{$long}->{value} = $val;
   return;
}

sub save_error {
   my ( $self, $error ) = @_;
   push @{$self->{errors}}, $error;
   return;
}

sub errors {
   my ( $self ) = @_;
   return $self->{errors};
}

sub usage {
   my ( $self ) = @_;
   warn "No usage string is set" unless $self->{usage}; # XXX
   return "Usage: " . ($self->{usage} || '') . "\n";
}

sub descr {
   my ( $self ) = @_;
   warn "No description string is set" unless $self->{description}; # XXX
   my $descr  = ($self->{description} || $self->{program_name} || '')
              . "  For more details, please use the --help option, "
              . "or try 'perldoc $PROGRAM_NAME' "
              . "for complete documentation.";
   $descr = join("\n", $descr =~ m/(.{0,80})(?:\s+|$)/g)
      unless $ENV{DONT_BREAK_LINES};
   $descr =~ s/ +$//mg;
   return $descr;
}

sub usage_or_errors {
   my ( $self, $file, $return ) = @_;
   $file ||= $self->{file} || __FILE__;

   if ( !$self->{description} || !$self->{usage} ) {
      MKDEBUG && _d("Getting description and usage from SYNOPSIS in", $file);
      my %synop = $self->_parse_synopsis($file);
      $self->{description} ||= $synop{description};
      $self->{usage}       ||= $synop{usage};
      MKDEBUG && _d("Description:", $self->{description},
         "\nUsage:", $self->{usage});
   }

   if ( $self->{opts}->{help}->{got} ) {
      print $self->print_usage() or die "Cannot print usage: $OS_ERROR";
      exit 0 unless $return;
   }
   elsif ( scalar @{$self->{errors}} ) {
      print $self->print_errors() or die "Cannot print errors: $OS_ERROR";
      exit 0 unless $return;
   }

   return;
}

sub print_errors {
   my ( $self ) = @_;
   my $usage = $self->usage() . "\n";
   if ( (my @errors = @{$self->{errors}}) ) {
      $usage .= join("\n  * ", 'Errors in command-line arguments:', @errors)
              . "\n";
   }
   return $usage . "\n" . $self->descr();
}

sub print_usage {
   my ( $self ) = @_;
   die "Run get_opts() before print_usage()" unless $self->{got_opts};
   my @opts = values %{$self->{opts}};

   my $maxl = max(
      map {
         length($_->{long})               # option long name
         + ($_->{is_negatable} ? 4 : 0)   # "[no]" if opt is negatable
         + ($_->{type} ? 2 : 0)           # "=x" where x is the opt type
      }
      @opts);

   my $maxs = max(0,
      map {
         length($_)
         + ($self->{opts}->{$_}->{is_negatable} ? 4 : 0)
         + ($self->{opts}->{$_}->{type} ? 2 : 0)
      }
      values %{$self->{short_opts}});

   my $lcol = max($maxl, ($maxs + 3));
   my $rcol = 80 - $lcol - 6;
   my $rpad = ' ' x ( 80 - $rcol );

   $maxs = max($lcol - 3, $maxs);

   my $usage = $self->descr() . "\n" . $self->usage();

   my @groups = reverse sort grep { $_ ne 'default'; } keys %{$self->{groups}};
   push @groups, 'default';

   foreach my $group ( reverse @groups ) {
      $usage .= "\n".($group eq 'default' ? 'Options' : $group).":\n\n";
      foreach my $opt (
         sort { $a->{long} cmp $b->{long} }
         grep { $_->{group} eq $group }
         @opts )
      {
         my $long  = $opt->{is_negatable} ? "[no]$opt->{long}" : $opt->{long};
         my $short = $opt->{short};
         my $desc  = $opt->{desc};

         $long .= $opt->{type} ? "=$opt->{type}" : "";

         if ( $opt->{type} && $opt->{type} eq 'm' ) {
            my ($s) = $desc =~ m/\(suffix (.)\)/;
            $s    ||= 's';
            $desc =~ s/\s+\(suffix .\)//;
            $desc .= ".  Optional suffix s=seconds, m=minutes, h=hours, "
                   . "d=days; if no suffix, $s is used.";
         }
         $desc = join("\n$rpad", grep { $_ } $desc =~ m/(.{0,$rcol})(?:\s+|$)/g);
         $desc =~ s/ +$//mg;
         if ( $short ) {
            $usage .= sprintf("  --%-${maxs}s -%s  %s\n", $long, $short, $desc);
         }
         else {
            $usage .= sprintf("  --%-${lcol}s  %s\n", $long, $desc);
         }
      }
   }

   $usage .= "\nOption types: s=string, i=integer, f=float, h/H/a/A=comma-separated list, d=DSN, z=size, m=time\n";

   if ( (my @rules = @{$self->{rules}}) ) {
      $usage .= "\nRules:\n\n";
      $usage .= join("\n", map { "  $_" } @rules) . "\n";
   }
   if ( $self->{DSNParser} ) {
      $usage .= "\n" . $self->{DSNParser}->usage();
   }
   $usage .= "\nOptions and values after processing arguments:\n\n";
   foreach my $opt ( sort { $a->{long} cmp $b->{long} } @opts ) {
      my $val   = $opt->{value};
      my $type  = $opt->{type} || '';
      my $bool  = $opt->{spec} =~ m/^[\w-]+(?:\|[\w-])?!?$/;
      $val      = $bool              ? ( $val ? 'TRUE' : 'FALSE' )
                : !defined $val      ? '(No value)'
                : $type eq 'd'       ? $self->{DSNParser}->as_string($val)
                : $type =~ m/H|h/    ? join(',', sort keys %$val)
                : $type =~ m/A|a/    ? join(',', @$val)
                :                    $val;
      $usage .= sprintf("  --%-${lcol}s  %s\n", $opt->{long}, $val);
   }
   return $usage;
}

sub prompt_noecho {
   shift @_ if ref $_[0] eq __PACKAGE__;
   my ( $prompt ) = @_;
   local $OUTPUT_AUTOFLUSH = 1;
   print $prompt
      or die "Cannot print: $OS_ERROR";
   my $response;
   eval {
      require Term::ReadKey;
      Term::ReadKey::ReadMode('noecho');
      chomp($response = <STDIN>);
      Term::ReadKey::ReadMode('normal');
      print "\n"
         or die "Cannot print: $OS_ERROR";
   };
   if ( $EVAL_ERROR ) {
      die "Cannot read response; is Term::ReadKey installed? $EVAL_ERROR";
   }
   return $response;
}

if ( MKDEBUG ) {
   print '# ', $^X, ' ', $], "\n";
   my $uname = `uname -a`;
   if ( $uname ) {
      $uname =~ s/\s+/ /g;
      print "# $uname\n";
   }
   printf("# %s  Ver %s Distrib %s Changeset %s line %d\n",
      $PROGRAM_NAME, ($main::VERSION || ''), ($main::DISTRIB || ''),
      ($main::SVN_REV || ''), __LINE__);
   print('# Arguments: ',
      join(' ', map { my $a = "_[$_]_"; $a =~ s/\n/\n# /g; $a; } @ARGV), "\n");
}

sub _read_config_file {
   my ( $self, $filename ) = @_;
   open my $fh, "<", $filename or die "Cannot open $filename: $OS_ERROR\n";
   my @args;
   my $prefix = '--';
   my $parse  = 1;

   LINE:
   while ( my $line = <$fh> ) {
      chomp $line;
      next LINE if $line =~ m/^\s*(?:\#|\;|$)/;
      $line =~ s/\s+#.*$//g;
      $line =~ s/^\s+|\s+$//g;
      if ( $line eq '--' ) {
         $prefix = '';
         $parse  = 0;
         next LINE;
      }
      if ( $parse
         && (my($opt, $arg) = $line =~ m/^\s*([^=\s]+?)(?:\s*=\s*(.*?)\s*)?$/)
      ) {
         push @args, grep { defined $_ } ("$prefix$opt", $arg);
      }
      elsif ( $line =~ m/./ ) {
         push @args, $line;
      }
      else {
         die "Syntax error in file $filename at line $INPUT_LINE_NUMBER";
      }
   }
   close $fh;
   return @args;
}

sub read_para_after {
   my ( $self, $file, $regex ) = @_;
   open my $fh, "<", $file or die "Can't open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';
   my $para;
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=pod$/m;
      last;
   }
   while ( $para = <$fh> ) {
      next unless $para =~ m/$regex/;
      last;
   }
   $para = <$fh>;
   chomp($para);
   close $fh or die "Can't close $file: $OS_ERROR";
   return $para;
}

sub clone {
   my ( $self ) = @_;

   my %clone = map {
      my $hashref  = $self->{$_};
      my $val_copy = {};
      foreach my $key ( keys %$hashref ) {
         my $ref = ref $hashref->{$key};
         $val_copy->{$key} = !$ref           ? $hashref->{$key}
                           : $ref eq 'HASH'  ? { %{$hashref->{$key}} }
                           : $ref eq 'ARRAY' ? [ @{$hashref->{$key}} ]
                           : $hashref->{$key};
      }
      $_ => $val_copy;
   } qw(opts short_opts defaults);

   foreach my $scalar ( qw(got_opts) ) {
      $clone{$scalar} = $self->{$scalar};
   }

   return bless \%clone;     
}

sub _parse_size {
   my ( $self, $opt, $val ) = @_;

   if ( lc($val || '') eq 'null' ) {
      MKDEBUG && _d('NULL size for', $opt->{long});
      $opt->{value} = 'null';
      return;
   }

   my %factor_for = (k => 1_024, M => 1_048_576, G => 1_073_741_824);
   my ($pre, $num, $factor) = $val =~ m/^([+-])?(\d+)([kMG])?$/;
   if ( defined $num ) {
      if ( $factor ) {
         $num *= $factor_for{$factor};
         MKDEBUG && _d('Setting option', $opt->{y},
            'to num', $num, '* factor', $factor);
      }
      $opt->{value} = ($pre || '') . $num;
   }
   else {
      $self->save_error("Invalid size for --$opt->{long}");
   }
   return;
}

sub _parse_attribs {
   my ( $self, $option, $attribs ) = @_;
   my $types = $self->{types};
   return $option
      . ($attribs->{'short form'} ? '|' . $attribs->{'short form'}   : '' )
      . ($attribs->{'negatable'}  ? '!'                              : '' )
      . ($attribs->{'cumulative'} ? '+'                              : '' )
      . ($attribs->{'type'}       ? '=' . $types->{$attribs->{type}} : '' );
}

sub _parse_synopsis {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   MKDEBUG && _d("Parsing SYNOPSIS in", $file);

   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $para;
   1 while defined($para = <$fh>) && $para !~ m/^=head1 SYNOPSIS/;
   die "$file does not contain a SYNOPSIS section" unless $para;
   my @synop;
   for ( 1..2 ) {  # 1 for the usage, 2 for the description
      my $para = <$fh>;
      push @synop, $para;
   }
   close $fh;
   MKDEBUG && _d("Raw SYNOPSIS text:", @synop);
   my ($usage, $desc) = @synop;
   die "The SYNOPSIS section in $file is not formatted properly"
      unless $usage && $desc;

   $usage =~ s/^\s*Usage:\s+(.+)/$1/;
   chomp $usage;

   $desc =~ s/\n/ /g;
   $desc =~ s/\s{2,}/ /g;
   $desc =~ s/\. ([A-Z][a-z])/.  $1/g;
   $desc =~ s/\s+$//;

   return (
      description => $desc,
      usage       => $usage,
   );
};

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End OptionParser package
# ###########################################################################

# ###########################################################################
# DSNParser package 7388
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/DSNParser.pm
#   trunk/common/t/DSNParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package DSNParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 0;
$Data::Dumper::Quotekeys = 0;

eval {
   require DBI;
};
my $have_dbi = $EVAL_ERROR ? 0 : 1;


sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(opts) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      opts => {}  # h, P, u, etc.  Should come from DSN OPTIONS section in POD.
   };
   foreach my $opt ( @{$args{opts}} ) {
      if ( !$opt->{key} || !$opt->{desc} ) {
         die "Invalid DSN option: ", Dumper($opt);
      }
      MKDEBUG && _d('DSN option:',
         join(', ',
            map { "$_=" . (defined $opt->{$_} ? ($opt->{$_} || '') : 'undef') }
               keys %$opt
         )
      );
      $self->{opts}->{$opt->{key}} = {
         dsn  => $opt->{dsn},
         desc => $opt->{desc},
         copy => $opt->{copy} || 0,
      };
   }
   return bless $self, $class;
}

sub prop {
   my ( $self, $prop, $value ) = @_;
   if ( @_ > 2 ) {
      MKDEBUG && _d('Setting', $prop, 'property');
      $self->{$prop} = $value;
   }
   return $self->{$prop};
}

sub parse {
   my ( $self, $dsn, $prev, $defaults ) = @_;
   if ( !$dsn ) {
      MKDEBUG && _d('No DSN to parse');
      return;
   }
   MKDEBUG && _d('Parsing', $dsn);
   $prev     ||= {};
   $defaults ||= {};
   my %given_props;
   my %final_props;
   my $opts = $self->{opts};

   foreach my $dsn_part ( split(/,/, $dsn) ) {
      if ( my ($prop_key, $prop_val) = $dsn_part =~  m/^(.)=(.*)$/ ) {
         $given_props{$prop_key} = $prop_val;
      }
      else {
         MKDEBUG && _d('Interpreting', $dsn_part, 'as h=', $dsn_part);
         $given_props{h} = $dsn_part;
      }
   }

   foreach my $key ( keys %$opts ) {
      MKDEBUG && _d('Finding value for', $key);
      $final_props{$key} = $given_props{$key};
      if (   !defined $final_props{$key}
           && defined $prev->{$key} && $opts->{$key}->{copy} )
      {
         $final_props{$key} = $prev->{$key};
         MKDEBUG && _d('Copying value for', $key, 'from previous DSN');
      }
      if ( !defined $final_props{$key} ) {
         $final_props{$key} = $defaults->{$key};
         MKDEBUG && _d('Copying value for', $key, 'from defaults');
      }
   }

   foreach my $key ( keys %given_props ) {
      die "Unknown DSN option '$key' in '$dsn'.  For more details, "
            . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
            . "for complete documentation."
         unless exists $opts->{$key};
   }
   if ( (my $required = $self->prop('required')) ) {
      foreach my $key ( keys %$required ) {
         die "Missing required DSN option '$key' in '$dsn'.  For more details, "
               . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
               . "for complete documentation."
            unless $final_props{$key};
      }
   }

   return \%final_props;
}

sub parse_options {
   my ( $self, $o ) = @_;
   die 'I need an OptionParser object' unless ref $o eq 'OptionParser';
   my $dsn_string
      = join(',',
          map  { "$_=".$o->get($_); }
          grep { $o->has($_) && $o->get($_) }
          keys %{$self->{opts}}
        );
   MKDEBUG && _d('DSN string made from options:', $dsn_string);
   return $self->parse($dsn_string);
}

sub as_string {
   my ( $self, $dsn, $props ) = @_;
   return $dsn unless ref $dsn;
   my %allowed = $props ? map { $_=>1 } @$props : ();
   return join(',',
      map  { "$_=" . ($_ eq 'p' ? '...' : $dsn->{$_})  }
      grep { defined $dsn->{$_} && $self->{opts}->{$_} }
      grep { !$props || $allowed{$_}                   }
      sort keys %$dsn );
}

sub usage {
   my ( $self ) = @_;
   my $usage
      = "DSN syntax is key=value[,key=value...]  Allowable DSN keys:\n\n"
      . "  KEY  COPY  MEANING\n"
      . "  ===  ====  =============================================\n";
   my %opts = %{$self->{opts}};
   foreach my $key ( sort keys %opts ) {
      $usage .= "  $key    "
             .  ($opts{$key}->{copy} ? 'yes   ' : 'no    ')
             .  ($opts{$key}->{desc} || '[No description]')
             . "\n";
   }
   $usage .= "\n  If the DSN is a bareword, the word is treated as the 'h' key.\n";
   return $usage;
}

sub get_cxn_params {
   my ( $self, $info ) = @_;
   my $dsn;
   my %opts = %{$self->{opts}};
   my $driver = $self->prop('dbidriver') || '';
   if ( $driver eq 'Pg' ) {
      $dsn = 'DBI:Pg:dbname=' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(h P));
   }
   else {
      $dsn = 'DBI:mysql:' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(F h P S A))
         . ';mysql_read_default_group=client';
   }
   MKDEBUG && _d($dsn);
   return ($dsn, $info->{u}, $info->{p});
}

sub fill_in_dsn {
   my ( $self, $dbh, $dsn ) = @_;
   my $vars = $dbh->selectall_hashref('SHOW VARIABLES', 'Variable_name');
   my ($user, $db) = $dbh->selectrow_array('SELECT USER(), DATABASE()');
   $user =~ s/@.*//;
   $dsn->{h} ||= $vars->{hostname}->{Value};
   $dsn->{S} ||= $vars->{'socket'}->{Value};
   $dsn->{P} ||= $vars->{port}->{Value};
   $dsn->{u} ||= $user;
   $dsn->{D} ||= $db;
}

sub get_dbh {
   my ( $self, $cxn_string, $user, $pass, $opts ) = @_;
   $opts ||= {};
   my $defaults = {
      AutoCommit         => 0,
      RaiseError         => 1,
      PrintError         => 0,
      ShowErrorStatement => 1,
      mysql_enable_utf8 => ($cxn_string =~ m/charset=utf8/i ? 1 : 0),
   };
   @{$defaults}{ keys %$opts } = values %$opts;

   if ( $opts->{mysql_use_result} ) {
      $defaults->{mysql_use_result} = 1;
   }

   if ( !$have_dbi ) {
      die "Cannot connect to MySQL because the Perl DBI module is not "
         . "installed or not found.  Run 'perl -MDBI' to see the directories "
         . "that Perl searches for DBI.  If DBI is not installed, try:\n"
         . "  Debian/Ubuntu  apt-get install libdbi-perl\n"
         . "  RHEL/CentOS    yum install perl-DBI\n"
         . "  OpenSolaris    pgk install pkg:/SUNWpmdbi\n";

   }

   my $dbh;
   my $tries = 2;
   while ( !$dbh && $tries-- ) {
      MKDEBUG && _d($cxn_string, ' ', $user, ' ', $pass, ' {',
         join(', ', map { "$_=>$defaults->{$_}" } keys %$defaults ), '}');

      eval {
         $dbh = DBI->connect($cxn_string, $user, $pass, $defaults);

         if ( $cxn_string =~ m/mysql/i ) {
            my $sql;

            $sql = 'SELECT @@SQL_MODE';
            MKDEBUG && _d($dbh, $sql);
            my ($sql_mode) = $dbh->selectrow_array($sql);

            $sql = 'SET @@SQL_QUOTE_SHOW_CREATE = 1'
                 . '/*!40101, @@SQL_MODE=\'NO_AUTO_VALUE_ON_ZERO'
                 . ($sql_mode ? ",$sql_mode" : '')
                 . '\'*/';
            MKDEBUG && _d($dbh, $sql);
            $dbh->do($sql);

            if ( my ($charset) = $cxn_string =~ m/charset=(\w+)/ ) {
               $sql = "/*!40101 SET NAMES $charset*/";
               MKDEBUG && _d($dbh, ':', $sql);
               $dbh->do($sql);
               MKDEBUG && _d('Enabling charset for STDOUT');
               if ( $charset eq 'utf8' ) {
                  binmode(STDOUT, ':utf8')
                     or die "Can't binmode(STDOUT, ':utf8'): $OS_ERROR";
               }
               else {
                  binmode(STDOUT) or die "Can't binmode(STDOUT): $OS_ERROR";
               }
            }

            if ( $self->prop('set-vars') ) {
               $sql = "SET " . $self->prop('set-vars');
               MKDEBUG && _d($dbh, ':', $sql);
               $dbh->do($sql);
            }
         }
      };
      if ( !$dbh && $EVAL_ERROR ) {
         MKDEBUG && _d($EVAL_ERROR);
         if ( $EVAL_ERROR =~ m/not a compiled character set|character set utf8/ ) {
            MKDEBUG && _d('Going to try again without utf8 support');
            delete $defaults->{mysql_enable_utf8};
         }
         elsif ( $EVAL_ERROR =~ m/locate DBD\/mysql/i ) {
            die "Cannot connect to MySQL because the Perl DBD::mysql module is "
               . "not installed or not found.  Run 'perl -MDBD::mysql' to see "
               . "the directories that Perl searches for DBD::mysql.  If "
               . "DBD::mysql is not installed, try:\n"
               . "  Debian/Ubuntu  apt-get install libdbd-mysql-perl\n"
               . "  RHEL/CentOS    yum install perl-DBD-MySQL\n"
               . "  OpenSolaris    pgk install pkg:/SUNWapu13dbd-mysql\n";
         }
         if ( !$tries ) {
            die $EVAL_ERROR;
         }
      }
   }

   MKDEBUG && _d('DBH info: ',
      $dbh,
      Dumper($dbh->selectrow_hashref(
         'SELECT DATABASE(), CONNECTION_ID(), VERSION()/*!50038 , @@hostname*/')),
      'Connection info:',      $dbh->{mysql_hostinfo},
      'Character set info:',   Dumper($dbh->selectall_arrayref(
                     'SHOW VARIABLES LIKE "character_set%"', { Slice => {}})),
      '$DBD::mysql::VERSION:', $DBD::mysql::VERSION,
      '$DBI::VERSION:',        $DBI::VERSION,
   );

   return $dbh;
}

sub get_hostname {
   my ( $self, $dbh ) = @_;
   if ( my ($host) = ($dbh->{mysql_hostinfo} || '') =~ m/^(\w+) via/ ) {
      return $host;
   }
   my ( $hostname, $one ) = $dbh->selectrow_array(
      'SELECT /*!50038 @@hostname, */ 1');
   return $hostname;
}

sub disconnect {
   my ( $self, $dbh ) = @_;
   MKDEBUG && $self->print_active_handles($dbh);
   $dbh->disconnect;
}

sub print_active_handles {
   my ( $self, $thing, $level ) = @_;
   $level ||= 0;
   printf("# Active %sh: %s %s %s\n", ($thing->{Type} || 'undef'), "\t" x $level,
      $thing, (($thing->{Type} || '') eq 'st' ? $thing->{Statement} || '' : ''))
      or die "Cannot print: $OS_ERROR";
   foreach my $handle ( grep {defined} @{ $thing->{ChildHandles} } ) {
      $self->print_active_handles( $handle, $level + 1 );
   }
}

sub copy {
   my ( $self, $dsn_1, $dsn_2, %args ) = @_;
   die 'I need a dsn_1 argument' unless $dsn_1;
   die 'I need a dsn_2 argument' unless $dsn_2;
   my %new_dsn = map {
      my $key = $_;
      my $val;
      if ( $args{overwrite} ) {
         $val = defined $dsn_1->{$key} ? $dsn_1->{$key} : $dsn_2->{$key};
      }
      else {
         $val = defined $dsn_2->{$key} ? $dsn_2->{$key} : $dsn_1->{$key};
      }
      $key => $val;
   } keys %{$self->{opts}};
   return \%new_dsn;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End DSNParser package
# ###########################################################################

# ###########################################################################
# Daemon package 6255
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Daemon.pm
#   trunk/common/t/Daemon.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Daemon;

use strict;
use warnings FATAL => 'all';

use POSIX qw(setsid);
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(o) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o = $args{o};
   my $self = {
      o        => $o,
      log_file => $o->has('log') ? $o->get('log') : undef,
      PID_file => $o->has('pid') ? $o->get('pid') : undef,
   };

   check_PID_file(undef, $self->{PID_file});

   MKDEBUG && _d('Daemonized child will log to', $self->{log_file});
   return bless $self, $class;
}

sub daemonize {
   my ( $self ) = @_;

   MKDEBUG && _d('About to fork and daemonize');
   defined (my $pid = fork()) or die "Cannot fork: $OS_ERROR";
   if ( $pid ) {
      MKDEBUG && _d('I am the parent and now I die');
      exit;
   }

   $self->{PID_owner} = $PID;
   $self->{child}     = 1;

   POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
   chdir '/'       or die "Cannot chdir to /: $OS_ERROR";

   $self->_make_PID_file();

   $OUTPUT_AUTOFLUSH = 1;

   if ( -t STDIN ) {
      close STDIN;
      open  STDIN, '/dev/null'
         or die "Cannot reopen STDIN to /dev/null: $OS_ERROR";
   }

   if ( $self->{log_file} ) {
      close STDOUT;
      open  STDOUT, '>>', $self->{log_file}
         or die "Cannot open log file $self->{log_file}: $OS_ERROR";

      close STDERR;
      open  STDERR, ">&STDOUT"
         or die "Cannot dupe STDERR to STDOUT: $OS_ERROR"; 
   }
   else {
      if ( -t STDOUT ) {
         close STDOUT;
         open  STDOUT, '>', '/dev/null'
            or die "Cannot reopen STDOUT to /dev/null: $OS_ERROR";
      }
      if ( -t STDERR ) {
         close STDERR;
         open  STDERR, '>', '/dev/null'
            or die "Cannot reopen STDERR to /dev/null: $OS_ERROR";
      }
   }

   MKDEBUG && _d('I am the child and now I live daemonized');
   return;
}

sub check_PID_file {
   my ( $self, $file ) = @_;
   my $PID_file = $self ? $self->{PID_file} : $file;
   MKDEBUG && _d('Checking PID file', $PID_file);
   if ( $PID_file && -f $PID_file ) {
      my $pid;
      eval { chomp($pid = `cat $PID_file`); };
      die "Cannot cat $PID_file: $OS_ERROR" if $EVAL_ERROR;
      MKDEBUG && _d('PID file exists; it contains PID', $pid);
      if ( $pid ) {
         my $pid_is_alive = kill 0, $pid;
         if ( $pid_is_alive ) {
            die "The PID file $PID_file already exists "
               . " and the PID that it contains, $pid, is running";
         }
         else {
            warn "Overwriting PID file $PID_file because the PID that it "
               . "contains, $pid, is not running";
         }
      }
      else {
         die "The PID file $PID_file already exists but it does not "
            . "contain a PID";
      }
   }
   else {
      MKDEBUG && _d('No PID file');
   }
   return;
}

sub make_PID_file {
   my ( $self ) = @_;
   if ( exists $self->{child} ) {
      die "Do not call Daemon::make_PID_file() for daemonized scripts";
   }
   $self->_make_PID_file();
   $self->{PID_owner} = $PID;
   return;
}

sub _make_PID_file {
   my ( $self ) = @_;

   my $PID_file = $self->{PID_file};
   if ( !$PID_file ) {
      MKDEBUG && _d('No PID file to create');
      return;
   }

   $self->check_PID_file();

   open my $PID_FH, '>', $PID_file
      or die "Cannot open PID file $PID_file: $OS_ERROR";
   print $PID_FH $PID
      or die "Cannot print to PID file $PID_file: $OS_ERROR";
   close $PID_FH
      or die "Cannot close PID file $PID_file: $OS_ERROR";

   MKDEBUG && _d('Created PID file:', $self->{PID_file});
   return;
}

sub _remove_PID_file {
   my ( $self ) = @_;
   if ( $self->{PID_file} && -f $self->{PID_file} ) {
      unlink $self->{PID_file}
         or warn "Cannot remove PID file $self->{PID_file}: $OS_ERROR";
      MKDEBUG && _d('Removed PID file');
   }
   else {
      MKDEBUG && _d('No PID to remove');
   }
   return;
}

sub DESTROY {
   my ( $self ) = @_;

   $self->_remove_PID_file() if ($self->{PID_owner} || 0) == $PID;

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Daemon package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_visual_explain;

use English qw(-no_match_vars);
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # #######################################################################
   # Get configuration information and parse command line options.
   # #######################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   $o->usage_or_errors();

   # ########################################################################
   # If --pid, check it first since we'll die if it already exits.
   # ########################################################################
   my $daemon;
   if ( $o->get('pid') ) {
      # We're not daemoninzing, it just handles PID stuff.  Keep $daemon
      # in the the scope of main() because when it's destroyed it automatically
      # removes the PID file.
      $daemon = new Daemon(o=>$o);
      $daemon->make_PID_file();
   }

   # #######################################################################
   # Get ready to do the main work.
   # #######################################################################
   # Magically read STDIN or files in @ARGV
   my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <>; };
   my $rows;

   if ( $o->got('connect') ) { # Connect to the database.
      if ( $o->got('ask-pass') && !$o->got('password') ) {
         $o->set('password', OptionParser::prompt_noecho("Enter password: "));
      }

      my $dsn = $dp->parse_options($o);
      my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), { AutoCommit => 1 } );

      $text =~ s{^.*?select}{EXPLAIN /*!50115 PARTITIONS*/ SELECT}is;
      $rows =  $dbh->selectall_arrayref($text, { Slice => {} } );
      $dbh->disconnect();
   }
   else {
      $rows = ExplainParser->new->parse($text);
   }

   # #######################################################################
   # Do the main work.
   # #######################################################################
   my $et   = ExplainTree->new();
   my $tree = $et->process($rows, { clustered => $o->get('clustered-pk') });
   if ( $tree ) {
      print $o->get('format') eq 'dump' ? Dumper($tree)
         : $et->pretty_print($tree);
   }

   return 0;
}

# ############################################################################
# Run the program.
# ############################################################################
if ( !caller ) { exit main(@ARGV); }

1; # Because this is a module as well as a script.

# ############################################################################
# Documentation.
# ############################################################################

=pod

=head1 NAME

mk-visual-explain - Format EXPLAIN output as a tree.

=head1 SYNOPSIS

Usage: mk-visual-explain [OPTION...] [FILE...]

mk-visual-explain transforms EXPLAIN output into a tree representation of
the query plan.  If FILE is given, input is read from the file(s).  With no
FILE, or when FILE is -, read standard input.

Examples:

  mk-visual-explain <file_containing_explain_output>

  mk-visual-explain -c <file_containing_query>

  mysql -e "explain select * from mysql.user" | mk-visual-explain

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-visual-explain is read-only and very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-visual-explain>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-visual-explain reverse-engineers MySQL's EXPLAIN output into a query
execution plan, which it then formats as a left-deep tree -- the same way the
plan is represented inside MySQL.  It is possible to do this by hand, or to read
EXPLAIN's output directly, but it requires patience and expertise.  Many people
find a tree representation more understandable.

You can pipe input into mk-visual-explain or specify a filename at the
command line, including the magical '-' filename, which will read from standard
input.  It can do two things with the input: parse it for something that looks
like EXPLAIN output, or connect to a MySQL instance and run EXPLAIN on the
input.

When parsing its input, mk-visual-explain understands three formats: tabular
like that shown in the mysql command-line client, vertical like that created by
using the \G line terminator in the mysql command-line client, and tab
separated.  It ignores any lines it doesn't know how to parse.

When executing the input, mk-visual-explain replaces everything in the input
up to the first SELECT keyword with 'EXPLAIN SELECT,' and then executes the
result.  You must specify L<"--connect"> to execute the input as a query.

Either way, it builds a tree from the result set and prints it to standard
output.  For the following query,

 select * from sakila.film_actor join sakila.film using(film_id);

mk-visual-explain generates this query plan:

 JOIN
 +- Bookmark lookup
 |  +- Table
 |  |  table          film_actor
 |  |  possible_keys  idx_fk_film_id
 |  +- Index lookup
 |     key            film_actor->idx_fk_film_id
 |     possible_keys  idx_fk_film_id
 |     key_len        2
 |     ref            sakila.film.film_id
 |     rows           2
 +- Table scan
    rows           952
    +- Table
       table          film
       possible_keys  PRIMARY

The query plan is left-deep, depth-first search, and the tree's root is the
output node -- the last step in the execution plan.  In other words, read it
like this:

=over

=item 1

Table scan the 'film' table, which accesses an estimated 952 rows.

=item 2

For each row, find matching rows by doing an index lookup into the
film_actor->idx_fk_film_id index with the value from sakila.film.film_id, then a
bookmark lookup into the film_actor table.

=back

For more information on how to read EXPLAIN output, please see
L<http://dev.mysql.com/doc/en/explain.html>, and this talk titled "Query
Optimizer Internals and What's New in the MySQL 5.2 Optimizer," from Timour
Katchaounov, one of the MySQL developers:
L<http://maatkit.org/presentations/katchaounov_timour.pdf>.

=head1 MODULES

This program is actually a runnable module, not just an ordinary Perl script.
In fact, there are two modules embedded in it.  This makes unit testing easy,
but it also makes it easy for you to use the parsing and tree-building
functionality if you want.

The ExplainParser package accepts a string and parses whatever it thinks looks
like EXPLAIN output from it.  The synopsis is as follows:

 require "mk-visual-explain";
 my $p    = ExplainParser->new();
 my $rows = $p->parse("some text");
 # $rows is an arrayref of hashrefs.

The ExplainTree package accepts a set of rows and turns it into a tree.  For
convenience, you can also have it delegate to ExplainParser and parse text for
you.  Here's the synopsis:

 require "mk-visual-explain";
 my $e      = ExplainTree->new();
 my $tree   = $e->parse("some text", \%options);
 my $output = $e->pretty_print($tree);
 print $tree;

=head1 ALGORITHM

This section explains the algorithm that converts EXPLAIN into a tree.  You may
be interested in reading this if you want to understand EXPLAIN more fully, or
trying to figure out how this works, but otherwise this section will probably
not make your life richer.

The tree can be built by examining the id, select_type, and table columns of
each row.  Here's what I know about them:

The id column is the sequential number of the select.  This does not indicate
nesting; it just comes from counting SELECT from the left of the SQL statement.
It's like capturing parentheses in a regular expression.  A UNION RESULT row
doesn't have an id, because it isn't a SELECT.  The source code actually refers
to UNIONs as a fake_lex, as I recall.

If two adjacent rows have the same id value, they are joined with the standard
single-sweep multi-join method.

The select_type column tells a) that a new sub-scope has opened b) what kind
of relationship the row has to the previous row c) what kind of operation the
row represents.

=over

=item *

SIMPLE means there are no subqueries or unions in the whole query.

=item *

PRIMARY means there are, but this is the outermost SELECT.

=item  *

[DEPENDENT] UNION means this result is UNIONed with the previous result (not
row; a result might encompass more than one row).

=item *

UNION RESULT terminates a set of UNIONed results.

=item *

[DEPENDENT|UNCACHEABLE] SUBQUERY means a new sub-scope is opening.  This is the
kind of subquery that happens in a WHERE clause, SELECT list or whatnot; it does
not return a so-called "derived table."

=item *

DERIVED is a subquery in the FROM clause.

=back

Tables that are JOINed all have the same select_type.  For example, if you JOIN
three tables inside a dependent subquery, they'll all say the same thing:
DEPENDENT SUBQUERY.

The table column usually specifies the table name or alias, but may also say
<derivedN> or <unionN,N...N>.  If it says <derivedN>, the row represents an
access to the temporary table that holds the result of the subquery whose id is
N.  If it says <unionN,..N> it's the same thing, but it refers to the results it
UNIONs together.

Finally, order matters.  If a row's id is less than the one before it, I think
that means it is dependent on something other than the one before it.  For
example,

 explain select
    (select 1 from sakila.film),
    (select 2 from sakila.film_actor),
    (select 3 from sakila.actor);

 | id | select_type | table      |
 +----+-------------+------------+
 |  1 | PRIMARY     | NULL       |
 |  4 | SUBQUERY    | actor      |
 |  3 | SUBQUERY    | film_actor |
 |  2 | SUBQUERY    | film       |

If the results were in order 2-3-4, I think that would mean 3 is a subquery of
2, 4 is a subquery of 3.  As it is, this means 4 is a subquery of the nearest
previous recent row with a smaller id, which is 1.  Likewise for 3 and 2.

This structure is hard to programatically build into a tree for the same reason
it's hard to understand by inspection: there are both forward and backward
references.  <derivedN> is a forward reference to selectN, while <unionM,N> is a
backward reference to selectM and selectN.  That makes recursion and other
tree-building algorithms hard to get right (NOTE: after implementation, I now
see how it would be possible to deal with both forward and backward references,
but I have no motivation to change something that works).  Consider the
following:

 select * from (
    select 1 from sakila.actor as actor_1
    union
    select 1 from sakila.actor as actor_2
 ) as der_1
 union
 select * from (
    select 1 from sakila.actor as actor_3
    union all
    select 1 from sakila.actor as actor_4
 ) as der_2;

 | id   | select_type  | table      |
 +------+--------------+------------+
 |  1   | PRIMARY      | <derived2> |
 |  2   | DERIVED      | actor_1    |
 |  3   | UNION        | actor_2    |
 | NULL | UNION RESULT | <union2,3> |
 |  4   | UNION        | <derived5> |
 |  5   | DERIVED      | actor_3    |
 |  6   | UNION        | actor_4    |
 | NULL | UNION RESULT | <union5,6> |
 | NULL | UNION RESULT | <union1,4> |

This would be a lot easier to work with if it looked like this (I've
bracketed the id on rows I moved):

 | id   | select_type  | table      |
 +------+--------------+------------+
 | [1]  | UNION RESULT | <union1,4> |
 |  1   | PRIMARY      | <derived2> |
 | [2]  | UNION RESULT | <union2,3> |
 |  2   | DERIVED      | actor_1    |
 |  3   | UNION        | actor_2    |
 |  4   | UNION        | <derived5> |
 | [5]  | UNION RESULT | <union5,6> |
 |  5   | DERIVED      | actor_3    |
 |  6   | UNION        | actor_4    |

In fact, why not re-number all the ids, so the PRIMARY row becomes 2, and so on?
That would make it even easier to read.  Unfortunately that would also have the
effect of destroying the meaning of the id column, which I think is important to
preserve in the final tree.  Also, though it makes it easier to read, it doesn't
make it easier to manipulate programmatically; so it's fine to leave them
numbered as they are.

The goal of re-ordering is to make it easier to figure out which rows are
children of which rows in the execution plan.  Given the reordered list and some
row whose table is <union...> or <derived>, it is easy to find the beginning of
the slice of rows that should be child nodes in the tree: you just look for the
first row whose ID is the same as the first number in the table.

The next question is how to find the last row that should be a child node of a
UNION or DERIVED.   I'll start with DERIVED, because the solution makes UNION
easy.

Consider how MySQL numbers the SELECTs sequentially according to their position
in the SQL, left-to-right.  Since a DERIVED table encloses everything within it
in a scope, which becomes a temporary table, there are only two things to think
about: its child subqueries and unions (if any), and its next siblings in the
scope that encloses it.  Its children will all have an id greater than it does,
by definition, so any later rows with a smaller id terminate the scope.

Here's an example.  The middle derived table here has a subquery and a UNION to
make it a little more complex for the example.

 explain select 1
 from (
    select film_id from sakila.film limit 1
 ) as der_1
 join (
    select film_id, actor_id, (select count(*) from sakila.rental) as r
    from sakila.film_actor limit 1
    union all
    select 1, 1, 1 from sakila.film_actor as dummy
 ) as der_2 using (film_id)
 join (
    select actor_id from sakila.actor limit 1
 ) as der_3 using (actor_id);

Here's the output of EXPLAIN:

 | id   | select_type  | table      |
 |  1   | PRIMARY      | <derived2> |
 |  1   | PRIMARY      | <derived6> |
 |  1   | PRIMARY      | <derived3> |
 |  6   | DERIVED      | actor      |
 |  3   | DERIVED      | film_actor |
 |  4   | SUBQUERY     | rental     |
 |  5   | UNION        | dummy      |
 | NULL | UNION RESULT | <union3,5> |
 |  2   | DERIVED      | film       |

The siblings all have id 1, and the middle one I care about is derived3.
(Notice MySQL doesn't execute them in the order I defined them, which is fine).
Now notice that MySQL prints out the rows in the opposite order I defined the
subqueries: 6, 3, 2.  It always seems to do this, and there might be other
methods of finding the scope boundaries including looking for the lower boundary
of the next largest sibling, but this is a good enough heuristic.  I am forced
to rely on it for non-DERIVED subqueries, so I rely on it here too.  Therefore,
I decide that everything greater than or equal to 3 belongs to the DERIVED
scope.

The rule for UNION is simple: they consume the entire enclosing scope, and to
find the component parts of each one, you find each part's beginning as referred
to in the <unionN,...> definition, and its end is either just before the next
one, or if it's the last part, the end is the end of the scope.

This is only simple because UNION consumes the entire scope, which is either the
entire statement, or the scope of a DERIVED table.  This is because a UNION
cannot be a sibling of another UNION or a table, DERIVED or not.  (Try writing
such a statement if you don't see it intuitively).  Therefore, you can just find
the enclosing scope's boundaries, and the rest is easy.  Notice in the example
above, the UNION is over <union3,5>, which includes the row with id 4 -- it
includes every row between 3 and 5.

Finally, there are non-derived subqueries to deal with as well.  In this case I
can't look at siblings to find the end of the scope as I did for DERIVED.  I
have to trust that MySQL executes depth-first.  Here's an example:

 explain
 select actor_id,
 (
    select count(film_id)
    + (select count(*) from sakila.film)
    from sakila.film join sakila.film_actor using(film_id)
    where exists(
       select * from sakila.actor
       where sakila.actor.actor_id = sakila.film_actor.actor_id
    )
 )
 from sakila.actor;

 | id | select_type        | table      |
 |  1 | PRIMARY            | actor      |
 |  2 | SUBQUERY           | film       |
 |  2 | SUBQUERY           | film_actor |
 |  4 | DEPENDENT SUBQUERY | actor      |
 |  3 | SUBQUERY           | film       |

In order, the tree should be built like this:

=over

=item *

See row 1.

=item *

See row 2.  It's a higher id than 1, so it's a subquery, along with every other
row whose id is greater than 2.

=item *

Inside this scope, see 2 and 2 and JOIN them.  See 4.  It's a higher id than 2,
so it's again a subquery; recurse.  After that, see 3, which is also higher;
recurse.

=back

But the only reason the nested subquery didn't include select 3 is because
select 4 came first.  In other words, if EXPLAIN looked like this,

 | id | select_type        | table      |
 |  1 | PRIMARY            | actor      |
 |  2 | SUBQUERY           | film       |
 |  2 | SUBQUERY           | film_actor |
 |  3 | SUBQUERY           | film       |
 |  4 | DEPENDENT SUBQUERY | actor      |

I would be forced to assume upon seeing select 3 that select 4 is a subquery
of it, rather than just being the next sibling in the enclosing scope.  If this
is ever wrong, then the algorithm is wrong, and I don't see what could be done
about it.

UNION is a little more complicated than just "the entire scope is a UNION,"
because the UNION might itself be inside an enclosing scope that's only
indicated by the first item inside the UNION.  There are only three kinds of
enclosing scopes: UNION, DERIVED, and SUBQUERY.  A UNION can't enclose a UNION,
and a DERIVED has its own "scope markers," but a SUBQUERY can wholly enclose a
UNION, like this strange example on the empty table t1:

 explain select * from t1 where not exists(
    (select t11.i from t1 t11) union (select t12.i from t1 t12));

 |   id | select_type  | table      | Extra                          |
 +------+--------------+------------+--------------------------------+
 |    1 | PRIMARY      | t1         | const row not found            |
 |    2 | SUBQUERY     | NULL       | No tables used                 |
 |    3 | SUBQUERY     | NULL       | no matching row in const table |
 |    4 | UNION        | t12        | const row not found            |
 | NULL | UNION RESULT | <union2,4> |                                |

The UNION's backward references might make it look like the UNION encloses the
subquery, but studying the query makes it clear this isn't the case.  So when a
UNION's first row says SUBQUERY, it is this special case.

By the way, I don't fully understand this query plan; there are 4 numbered
SELECT in the plan, but only 3 in the query.  The parens around the UNIONs are
meaningful.  Removing them will make the EXPLAIN different.  Please tell me how
and why this works if you know.

Armed with this knowledge, it's possible to use recursion to turn the
parent-child relationship between all the rows into a tree representing the
execution plan.

MySQL prints the rows in execution order, even the forward and backward
references.  At any given scope, the rows are processed as a left-deep tree.
MySQL does not do "bushy" execution plans.  It begins with a table, finds a
matching row in the next table, and continues till the last table, when it emits
a row.  When it runs out, it backtracks till it can find the next row and
repeats.  There are subtleties of course, but this is the basic plan.  This is
why MySQL transforms all RIGHT OUTER JOINs into LEFT OUTER JOINs and cannot do
FULL OUTER JOIN.

This means in any given scope, say

 | id   | select_type  | table      |
 |  1   | SIMPLE       | tbl1       |
 |  1   | SIMPLE       | tbl2       |
 |  1   | SIMPLE       | tbl3       |

The execution plan looks like a depth-first traversal of this tree:

       JOIN
      /    \
    JOIN  tbl3
   /    \
 tbl1   tbl2

The JOIN might not be a JOIN.  It might be a subquery, for example.  This comes
from the type column of EXPLAIN.  The documentation says this is a "join type,"
but I think "access type" is more accurate, because it's "how MySQL accesses
rows."

mk-visual-explain decorates the tree significantly more than just turning
rows into nodes.  Each node may get a series of transformations that turn it
into a subtree of more than one node.  For example, an index scan not marked
with 'Using index' must do a bookmark lookup into the table rows; that is a
three-node subtree.  However, after the above node-ordering and scoping stuff,
the rest of the process is pretty simple.

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
binmode on STDOUT without the utf8 layer, and runs SET NAMES after
connecting to MySQL.

=item --clustered-pk

Assume that PRIMARY KEY index accesses don't need to do a bookmark lookup to
retrieve rows.  This is the case for InnoDB.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --connect

Treat input as a query, and obtain EXPLAIN output by connecting to a MySQL
instance and running EXPLAIN on the query.  When this option is given,
mk-visual-explain uses the other connection-specific options such as
L<"--user"> to connect to the MySQL instance.  If you have a .my.cnf file,
it will read it, so you may not need to specify any connection-specific
options.

=item --database

short form: -D; type: string

Connect to this database.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --format

type: string; default: tree

Set output format.

The default is a terse pretty-printed tree. The valid values are:

 value  meaning
 =====  =======
 tree   Pretty-printed terse tree.
 dump   Data::Dumper output (see L<Data::Dumper> for more).

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file.  The file contains the process ID of the script.
The PID file is removed when the script exits.  Before starting, the script
checks if the PID file already exists.  If it does not, then the script creates
and writes its own PID to it.  If it does, then the script checks the following:
if the file contains a PID and a process is running with that PID, then
the script dies; or, if there is no process running with that PID, then the
script overwrites the file with its own PID and starts; else, if the file
contains no PID, then the script dies.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

=back

=head1 DSN OPTIONS

These DSN options are used to create a DSN.  Each option is given like
C<option=value>.  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the C<=> and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the L<maatkit> manpage for full details.

=over

=item * A

dsn: charset; copy: yes

Default character set.

=item * D

dsn: database; copy: yes

Default database.

=item * F

dsn: mysql_read_default_file; copy: yes

Only read default options from the given file

=item * h

dsn: host; copy: yes

Connect to host.

=item * p

dsn: password; copy: yes

Password to use when connecting.

=item * P

dsn: port; copy: yes

Port number to use for connection.

=item * S

dsn: mysql_socket; copy: yes

Socket file to use for connection.

=item * u

dsn: user; copy: yes

User for login if not current user.

=back

=head1 DOWNLOADING

You can download Maatkit from Google Code at
L<http://code.google.com/p/maatkit/>, or you can get any of the tools
easily with a command like the following:

   wget http://www.maatkit.org/get/toolname
   or
   wget http://www.maatkit.org/trunk/toolname

Where C<toolname> can be replaced with the name (or fragment of a name) of any
of the Maatkit tools.  Once downloaded, they're ready to run; no installation is
needed.  The first URL gets the latest released version of the tool, and the
second gets the latest trunk code from Subversion.

=head1 ENVIRONMENT

The environment variable C<MKDEBUG> enables verbose debugging output in all of
the Maatkit tools:

   MKDEBUG=1 mk-....

=head1 SYSTEM REQUIREMENTS

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-visual-explain>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2007-2011 Baron Schwartz.
Feedback and improvements are welcome.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue `man perlgpl' or `man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

=head1 SEE ALSO

See also L<mk-query-profiler>.

=head1 AUTHOR

Baron "Xaprb" Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.22 Distrib 7540 $Revision: 7477 $.

=cut

__END__
:endofperl
