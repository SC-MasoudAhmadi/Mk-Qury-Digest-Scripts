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

# This is mk-archiver, a program to archive records from one MySQL table to
# a file and/or another table.
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

our $VERSION = '1.0.27';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7531 $ =~ m/(\d+)/g, 0));

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
# TableParser package 7156
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableParser.pm
#   trunk/common/t/TableParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TableParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub parse {
   my ( $self, $ddl, $opts ) = @_;
   return unless $ddl;
   if ( ref $ddl eq 'ARRAY' ) {
      if ( lc $ddl->[0] eq 'table' ) {
         $ddl = $ddl->[1];
      }
      else {
         return {
            engine => 'VIEW',
         };
      }
   }

   if ( $ddl !~ m/CREATE (?:TEMPORARY )?TABLE `/ ) {
      die "Cannot parse table definition; is ANSI quoting "
         . "enabled or SQL_QUOTE_SHOW_CREATE disabled?";
   }

   my ($name)     = $ddl =~ m/CREATE (?:TEMPORARY )?TABLE\s+(`.+?`)/;
   (undef, $name) = $self->{Quoter}->split_unquote($name) if $name;

   $ddl =~ s/(`[^`]+`)/\L$1/g;

   my $engine = $self->get_engine($ddl);

   my @defs   = $ddl =~ m/^(\s+`.*?),?$/gm;
   my @cols   = map { $_ =~ m/`([^`]+)`/ } @defs;
   MKDEBUG && _d('Table cols:', join(', ', map { "`$_`" } @cols));

   my %def_for;
   @def_for{@cols} = @defs;

   my (@nums, @null);
   my (%type_for, %is_nullable, %is_numeric, %is_autoinc);
   foreach my $col ( @cols ) {
      my $def = $def_for{$col};
      my ( $type ) = $def =~ m/`[^`]+`\s([a-z]+)/;
      die "Can't determine column type for $def" unless $type;
      $type_for{$col} = $type;
      if ( $type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ) {
         push @nums, $col;
         $is_numeric{$col} = 1;
      }
      if ( $def !~ m/NOT NULL/ ) {
         push @null, $col;
         $is_nullable{$col} = 1;
      }
      $is_autoinc{$col} = $def =~ m/AUTO_INCREMENT/i ? 1 : 0;
   }

   my ($keys, $clustered_key) = $self->get_keys($ddl, $opts, \%is_nullable);

   my ($charset) = $ddl =~ m/DEFAULT CHARSET=(\w+)/;

   return {
      name           => $name,
      cols           => \@cols,
      col_posn       => { map { $cols[$_] => $_ } 0..$#cols },
      is_col         => { map { $_ => 1 } @cols },
      null_cols      => \@null,
      is_nullable    => \%is_nullable,
      is_autoinc     => \%is_autoinc,
      clustered_key  => $clustered_key,
      keys           => $keys,
      defs           => \%def_for,
      numeric_cols   => \@nums,
      is_numeric     => \%is_numeric,
      engine         => $engine,
      type_for       => \%type_for,
      charset        => $charset,
   };
}

sub sort_indexes {
   my ( $self, $tbl ) = @_;

   my @indexes
      = sort {
         (($a ne 'PRIMARY') <=> ($b ne 'PRIMARY'))
         || ( !$tbl->{keys}->{$a}->{is_unique} <=> !$tbl->{keys}->{$b}->{is_unique} )
         || ( $tbl->{keys}->{$a}->{is_nullable} <=> $tbl->{keys}->{$b}->{is_nullable} )
         || ( scalar(@{$tbl->{keys}->{$a}->{cols}}) <=> scalar(@{$tbl->{keys}->{$b}->{cols}}) )
      }
      grep {
         $tbl->{keys}->{$_}->{type} eq 'BTREE'
      }
      sort keys %{$tbl->{keys}};

   MKDEBUG && _d('Indexes sorted best-first:', join(', ', @indexes));
   return @indexes;
}

sub find_best_index {
   my ( $self, $tbl, $index ) = @_;
   my $best;
   if ( $index ) {
      ($best) = grep { uc $_ eq uc $index } keys %{$tbl->{keys}};
   }
   if ( !$best ) {
      if ( $index ) {
         die "Index '$index' does not exist in table";
      }
      else {
         ($best) = $self->sort_indexes($tbl);
      }
   }
   MKDEBUG && _d('Best index found is', $best);
   return $best;
}

sub find_possible_keys {
   my ( $self, $dbh, $database, $table, $quoter, $where ) = @_;
   return () unless $where;
   my $sql = 'EXPLAIN SELECT * FROM ' . $quoter->quote($database, $table)
      . ' WHERE ' . $where;
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);
   $expl = { map { lc($_) => $expl->{$_} } keys %$expl };
   if ( $expl->{possible_keys} ) {
      MKDEBUG && _d('possible_keys =', $expl->{possible_keys});
      my @candidates = split(',', $expl->{possible_keys});
      my %possible   = map { $_ => 1 } @candidates;
      if ( $expl->{key} ) {
         MKDEBUG && _d('MySQL chose', $expl->{key});
         unshift @candidates, grep { $possible{$_} } split(',', $expl->{key});
         MKDEBUG && _d('Before deduping:', join(', ', @candidates));
         my %seen;
         @candidates = grep { !$seen{$_}++ } @candidates;
      }
      MKDEBUG && _d('Final list:', join(', ', @candidates));
      return @candidates;
   }
   else {
      MKDEBUG && _d('No keys in possible_keys');
      return ();
   }
}

sub check_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl) = @args{@required_args};
   my $q      = $self->{Quoter};
   my $db_tbl = $q->quote($db, $tbl);
   MKDEBUG && _d('Checking', $db_tbl);

   my $sql = "SHOW TABLES FROM " . $q->quote($db)
           . ' LIKE ' . $q->literal_like($tbl);
   MKDEBUG && _d($sql);
   my $row;
   eval {
      $row = $dbh->selectrow_arrayref($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return 0;
   }
   if ( !$row->[0] || $row->[0] ne $tbl ) {
      MKDEBUG && _d('Table does not exist');
      return 0;
   }

   MKDEBUG && _d('Table exists; no privs to check');
   return 1 unless $args{all_privs};

   $sql = "SHOW FULL COLUMNS FROM $db_tbl";
   MKDEBUG && _d($sql);
   eval {
      $row = $dbh->selectrow_hashref($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return 0;
   }
   if ( !scalar keys %$row ) {
      MKDEBUG && _d('Table has no columns:', Dumper($row));
      return 0;
   }
   my $privs = $row->{privileges} || $row->{Privileges};

   $sql = "DELETE FROM $db_tbl LIMIT 0";
   MKDEBUG && _d($sql);
   eval {
      $dbh->do($sql);
   };
   my $can_delete = $EVAL_ERROR ? 0 : 1;

   MKDEBUG && _d('User privs on', $db_tbl, ':', $privs,
      ($can_delete ? 'delete' : ''));

   if ( !($privs =~ m/select/ && $privs =~ m/insert/ && $privs =~ m/update/
          && $can_delete) ) {
      MKDEBUG && _d('User does not have all privs');
      return 0;
   }

   MKDEBUG && _d('User has all privs');
   return 1;
}

sub get_engine {
   my ( $self, $ddl, $opts ) = @_;
   my ( $engine ) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;
   MKDEBUG && _d('Storage engine:', $engine);
   return $engine || undef;
}

sub get_keys {
   my ( $self, $ddl, $opts, $is_nullable ) = @_;
   my $engine        = $self->get_engine($ddl);
   my $keys          = {};
   my $clustered_key = undef;

   KEY:
   foreach my $key ( $ddl =~ m/^  ((?:[A-Z]+ )?KEY .*)$/gm ) {

      next KEY if $key =~ m/FOREIGN/;

      my $key_ddl = $key;
      MKDEBUG && _d('Parsed key:', $key_ddl);

      if ( $engine !~ m/MEMORY|HEAP/ ) {
         $key =~ s/USING HASH/USING BTREE/;
      }

      my ( $type, $cols ) = $key =~ m/(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $key =~ m/(FULLTEXT|SPATIAL)/;
      $type = $type || $special || 'BTREE';
      if ( $opts->{mysql_version} && $opts->{mysql_version} lt '004001000'
         && $engine =~ m/HEAP|MEMORY/i )
      {
         $type = 'HASH'; # MySQL pre-4.1 supports only HASH indexes on HEAP
      }

      my ($name) = $key =~ m/(PRIMARY|`[^`]*`)/;
      my $unique = $key =~ m/PRIMARY|UNIQUE/ ? 1 : 0;
      my @cols;
      my @col_prefixes;
      foreach my $col_def ( $cols =~ m/`[^`]+`(?:\(\d+\))?/g ) {
         my ($name, $prefix) = $col_def =~ m/`([^`]+)`(?:\((\d+)\))?/;
         push @cols, $name;
         push @col_prefixes, $prefix;
      }
      $name =~ s/`//g;

      MKDEBUG && _d( $name, 'key cols:', join(', ', map { "`$_`" } @cols));

      $keys->{$name} = {
         name         => $name,
         type         => $type,
         colnames     => $cols,
         cols         => \@cols,
         col_prefixes => \@col_prefixes,
         is_unique    => $unique,
         is_nullable  => scalar(grep { $is_nullable->{$_} } @cols),
         is_col       => { map { $_ => 1 } @cols },
         ddl          => $key_ddl,
      };

      if ( $engine =~ m/InnoDB/i && !$clustered_key ) {
         my $this_key = $keys->{$name};
         if ( $this_key->{name} eq 'PRIMARY' ) {
            $clustered_key = 'PRIMARY';
         }
         elsif ( $this_key->{is_unique} && !$this_key->{is_nullable} ) {
            $clustered_key = $this_key->{name};
         }
         MKDEBUG && $clustered_key && _d('This key is the clustered key');
      }
   }

   return $keys, $clustered_key;
}

sub get_fks {
   my ( $self, $ddl, $opts ) = @_;
   my $fks = {};

   foreach my $fk (
      $ddl =~ m/CONSTRAINT .* FOREIGN KEY .* REFERENCES [^\)]*\)/mg )
   {
      my ( $name ) = $fk =~ m/CONSTRAINT `(.*?)`/;
      my ( $cols ) = $fk =~ m/FOREIGN KEY \(([^\)]+)\)/;
      my ( $parent, $parent_cols ) = $fk =~ m/REFERENCES (\S+) \(([^\)]+)\)/;

      if ( $parent !~ m/\./ && $opts->{database} ) {
         $parent = "`$opts->{database}`.$parent";
      }

      $fks->{$name} = {
         name           => $name,
         colnames       => $cols,
         cols           => [ map { s/[ `]+//g; $_; } split(',', $cols) ],
         parent_tbl     => $parent,
         parent_colnames=> $parent_cols,
         parent_cols    => [ map { s/[ `]+//g; $_; } split(',', $parent_cols) ],
         ddl            => $fk,
      };
   }

   return $fks;
}

sub remove_auto_increment {
   my ( $self, $ddl ) = @_;
   $ddl =~ s/(^\).*?) AUTO_INCREMENT=\d+\b/$1/m;
   return $ddl;
}

sub remove_secondary_indexes {
   my ( $self, $ddl ) = @_;
   my $sec_indexes_ddl;
   my $tbl_struct = $self->parse($ddl);

   if ( ($tbl_struct->{engine} || '') =~ m/InnoDB/i ) {
      my $clustered_key = $tbl_struct->{clustered_key};
      $clustered_key  ||= '';

      my @sec_indexes   = map {
         my $key_def = $_->{ddl};
         $key_def =~ s/([\(\)])/\\$1/g;
         $ddl =~ s/\s+$key_def//i;

         my $key_ddl = "ADD $_->{ddl}";
         $key_ddl   .= ',' unless $key_ddl =~ m/,$/;
         $key_ddl;
      }
      grep { $_->{name} ne $clustered_key }
      values %{$tbl_struct->{keys}};
      MKDEBUG && _d('Secondary indexes:', Dumper(\@sec_indexes));

      if ( @sec_indexes ) {
         $sec_indexes_ddl = join(' ', @sec_indexes);
         $sec_indexes_ddl =~ s/,$//;
      }

      $ddl =~ s/,(\n\) )/$1/s;
   }
   else {
      MKDEBUG && _d('Not removing secondary indexes from',
         $tbl_struct->{engine}, 'table');
   }

   return $ddl, $sec_indexes_ddl, $tbl_struct;
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
# End TableParser package
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
# VersionParser package 6667
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/VersionParser.pm
#   trunk/common/t/VersionParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package VersionParser;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub parse {
   my ( $self, $str ) = @_;
   my $result = sprintf('%03d%03d%03d', $str =~ m/(\d+)/g);
   MKDEBUG && _d($str, 'parses to', $result);
   return $result;
}

sub version_ge {
   my ( $self, $dbh, $target ) = @_;
   if ( !$self->{$dbh} ) {
      $self->{$dbh} = $self->parse(
         $dbh->selectrow_array('SELECT VERSION()'));
   }
   my $result = $self->{$dbh} ge $self->parse($target) ? 1 : 0;
   MKDEBUG && _d($self->{$dbh}, 'ge', $target, ':', $result);
   return $result;
}

sub innodb_version {
   my ( $self, $dbh ) = @_;
   return unless $dbh;
   my $innodb_version = "NO";

   my ($innodb) =
      grep { $_->{engine} =~ m/InnoDB/i }
      map  {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         \%hash;
      }
      @{ $dbh->selectall_arrayref("SHOW ENGINES", {Slice=>{}}) };
   if ( $innodb ) {
      MKDEBUG && _d("InnoDB support:", $innodb->{support});
      if ( $innodb->{support} =~ m/YES|DEFAULT/i ) {
         my $vars = $dbh->selectrow_hashref(
            "SHOW VARIABLES LIKE 'innodb_version'");
         $innodb_version = !$vars ? "BUILTIN"
                         :          ($vars->{Value} || $vars->{value});
      }
      else {
         $innodb_version = $innodb->{support};  # probably DISABLED or NO
      }
   }

   MKDEBUG && _d("InnoDB version:", $innodb_version);
   return $innodb_version;
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
# End VersionParser package
# ###########################################################################

# ###########################################################################
# Quoter package 6850
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Quoter.pm
#   trunk/common/t/Quoter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Quoter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

sub quote {
   my ( $self, @vals ) = @_;
   foreach my $val ( @vals ) {
      $val =~ s/`/``/g;
   }
   return join('.', map { '`' . $_ . '`' } @vals);
}

sub quote_val {
   my ( $self, $val ) = @_;

   return 'NULL' unless defined $val;          # undef = NULL
   return "''" if $val eq '';                  # blank string = ''
   return $val if $val =~ m/^0x[0-9a-fA-F]+$/;  # hex data

   $val =~ s/(['\\])/\\$1/g;
   return "'$val'";
}

sub split_unquote {
   my ( $self, $db_tbl, $default_db ) = @_;
   $db_tbl =~ s/`//g;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   return ($db, $tbl);
}

sub literal_like {
   my ( $self, $like ) = @_;
   return unless $like;
   $like =~ s/([%_])/\\$1/g;
   return "'$like'";
}

sub join_quote {
   my ( $self, $default_db, $db_tbl ) = @_;
   return unless $db_tbl;
   my ($db, $tbl) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   $db  = "`$db`"  if $db  && $db  !~ m/^`/;
   $tbl = "`$tbl`" if $tbl && $tbl !~ m/^`/;
   return $db ? "$db.$tbl" : $tbl;
}

1;

# ###########################################################################
# End Quoter package
# ###########################################################################

# ###########################################################################
# TableNibbler package 5266
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableNibbler.pm
#   trunk/common/t/TableNibbler.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableNibbler;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub generate_asc_stmt {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl_struct index);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($tbl_struct, $index) = @args{@required_args};
   my @cols = $args{cols}  ? @{$args{cols}} : @{$tbl_struct->{cols}};
   my $q    = $self->{Quoter};

   die "Index '$index' does not exist in table"
      unless exists $tbl_struct->{keys}->{$index};

   my @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   my @asc_slice;

   @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   MKDEBUG && _d('Will ascend index', $index);
   MKDEBUG && _d('Will ascend columns', join(', ', @asc_cols));
   if ( $args{asc_first} ) {
      @asc_cols = $asc_cols[0];
      MKDEBUG && _d('Ascending only first column');
   }

   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @asc_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @asc_slice, $col_posn{$col};
   }
   MKDEBUG && _d('Will ascend, in ordinal position:', join(', ', @asc_slice));

   my $asc_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   if ( @asc_slice ) {
      my $cmp_where;
      foreach my $cmp ( qw(< <= >= >) ) {
         $cmp_where = $self->generate_cmp_where(
            type        => $cmp,
            slice       => \@asc_slice,
            cols        => \@cols,
            quoter      => $q,
            is_nullable => $tbl_struct->{is_nullable},
         );
         $asc_stmt->{boundaries}->{$cmp} = $cmp_where->{where};
      }
      my $cmp = $args{asc_only} ? '>' : '>=';
      $asc_stmt->{where} = $asc_stmt->{boundaries}->{$cmp};
      $asc_stmt->{slice} = $cmp_where->{slice};
      $asc_stmt->{scols} = $cmp_where->{scols};
   }

   return $asc_stmt;
}

sub generate_cmp_where {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(type slice cols is_nullable) ) {
      die "I need a $arg arg" unless defined $args{$arg};
   }
   my @slice       = @{$args{slice}};
   my @cols        = @{$args{cols}};
   my $is_nullable = $args{is_nullable};
   my $type        = $args{type};
   my $q           = $self->{Quoter};

   (my $cmp = $type) =~ s/=//;

   my @r_slice;    # Resulting slice columns, by ordinal
   my @r_scols;    # Ditto, by name

   my @clauses;
   foreach my $i ( 0 .. $#slice ) {
      my @clause;

      foreach my $j ( 0 .. $i - 1 ) {
         my $ord = $slice[$j];
         my $col = $cols[$ord];
         my $quo = $q->quote($col);
         if ( $is_nullable->{$col} ) {
            push @clause, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
            push @r_slice, $ord, $ord;
            push @r_scols, $col, $col;
         }
         else {
            push @clause, "$quo = ?";
            push @r_slice, $ord;
            push @r_scols, $col;
         }
      }

      my $ord = $slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      my $end = $i == $#slice; # Last clause of the whole group.
      if ( $is_nullable->{$col} ) {
         if ( $type =~ m/=/ && $end ) {
            push @clause, "(? IS NULL OR $quo $type ?)";
         }
         elsif ( $type =~ m/>/ ) {
            push @clause, "((? IS NULL AND $quo IS NOT NULL) OR ($quo $cmp ?))";
         }
         else { # If $type =~ m/</ ) {
            push @clause, "((? IS NOT NULL AND $quo IS NULL) OR ($quo $cmp ?))";
         }
         push @r_slice, $ord, $ord;
         push @r_scols, $col, $col;
      }
      else {
         push @r_slice, $ord;
         push @r_scols, $col;
         push @clause, ($type =~ m/=/ && $end ? "$quo $type ?" : "$quo $cmp ?");
      }

      push @clauses, '(' . join(' AND ', @clause) . ')';
   }
   my $result = '(' . join(' OR ', @clauses) . ')';
   my $where = {
      slice => \@r_slice,
      scols => \@r_scols,
      where => $result,
   };
   return $where;
}

sub generate_del_stmt {
   my ( $self, %args ) = @_;

   my $tbl  = $args{tbl_struct};
   my @cols = $args{cols} ? @{$args{cols}} : ();
   my $tp   = $self->{TableParser};
   my $q    = $self->{Quoter};

   my @del_cols;
   my @del_slice;

   my $index = $tp->find_best_index($tbl, $args{index});
   die "Cannot find an ascendable index in table" unless $index;

   if ( $index ) {
      @del_cols = @{$tbl->{keys}->{$index}->{cols}};
   }
   else {
      @del_cols = @{$tbl->{cols}};
   }
   MKDEBUG && _d('Columns needed for DELETE:', join(', ', @del_cols));

   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @del_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @del_slice, $col_posn{$col};
   }
   MKDEBUG && _d('Ordinals needed for DELETE:', join(', ', @del_slice));

   my $del_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   my @clauses;
   foreach my $i ( 0 .. $#del_slice ) {
      my $ord = $del_slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      if ( $tbl->{is_nullable}->{$col} ) {
         push @clauses, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
         push @{$del_stmt->{slice}}, $ord, $ord;
         push @{$del_stmt->{scols}}, $col, $col;
      }
      else {
         push @clauses, "$quo = ?";
         push @{$del_stmt->{slice}}, $ord;
         push @{$del_stmt->{scols}}, $col;
      }
   }

   $del_stmt->{where} = '(' . join(' AND ', @clauses) . ')';

   return $del_stmt;
}

sub generate_ins_stmt {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ins_tbl sel_cols) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ins_tbl  = $args{ins_tbl};
   my @sel_cols = @{$args{sel_cols}};

   die "You didn't specify any SELECT columns" unless @sel_cols;

   my @ins_cols;
   my @ins_slice;
   for my $i ( 0..$#sel_cols ) {
      next unless $ins_tbl->{is_col}->{$sel_cols[$i]};
      push @ins_cols, $sel_cols[$i];
      push @ins_slice, $i;
   }

   return {
      cols  => \@ins_cols,
      slice => \@ins_slice,
   };
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
# End TableNibbler package
# ###########################################################################

# ###########################################################################
# MySQLDump package 6345
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MySQLDump.pm
#   trunk/common/t/MySQLDump.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MySQLDump;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

( our $before = <<'EOF') =~ s/^   //gm;
   /*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
   /*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
   /*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
   /*!40101 SET NAMES utf8 */;
   /*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
   /*!40103 SET TIME_ZONE='+00:00' */;
   /*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
   /*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
   /*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
   /*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
EOF

( our $after = <<'EOF') =~ s/^   //gm;
   /*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
   /*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
   /*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
   /*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
   /*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
   /*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
   /*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
   /*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
EOF

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      cache => 0,  # Afaik no script uses this cache any longer because
   };
   return bless $self, $class;
}

sub dump {
   my ( $self, $dbh, $quoter, $db, $tbl, $what ) = @_;

   if ( $what eq 'table' ) {
      my $ddl = $self->get_create_table($dbh, $quoter, $db, $tbl);
      return unless $ddl;
      if ( $ddl->[0] eq 'table' ) {
         return $before
            . 'DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . ";\n"
            . $ddl->[1] . ";\n";
      }
      else {
         return 'DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . ";\n"
            . '/*!50001 DROP VIEW IF EXISTS '
            . $quoter->quote($tbl) . "*/;\n/*!50001 "
            . $self->get_tmp_table($dbh, $quoter, $db, $tbl) . "*/;\n";
      }
   }
   elsif ( $what eq 'triggers' ) {
      my $trgs = $self->get_triggers($dbh, $quoter, $db, $tbl);
      if ( $trgs && @$trgs ) {
         my $result = $before . "\nDELIMITER ;;\n";
         foreach my $trg ( @$trgs ) {
            if ( $trg->{sql_mode} ) {
               $result .= qq{/*!50003 SET SESSION SQL_MODE='$trg->{sql_mode}' */;;\n};
            }
            $result .= "/*!50003 CREATE */ ";
            if ( $trg->{definer} ) {
               my ( $user, $host )
                  = map { s/'/''/g; "'$_'"; }
                    split('@', $trg->{definer}, 2);
               $result .= "/*!50017 DEFINER=$user\@$host */ ";
            }
            $result .= sprintf("/*!50003 TRIGGER %s %s %s ON %s\nFOR EACH ROW %s */;;\n\n",
               $quoter->quote($trg->{trigger}),
               @{$trg}{qw(timing event)},
               $quoter->quote($trg->{table}),
               $trg->{statement});
         }
         $result .= "DELIMITER ;\n\n/*!50003 SET SESSION SQL_MODE=\@OLD_SQL_MODE */;\n\n";
         return $result;
      }
      else {
         return undef;
      }
   }
   elsif ( $what eq 'view' ) {
      my $ddl = $self->get_create_table($dbh, $quoter, $db, $tbl);
      return '/*!50001 DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . "*/;\n"
         . '/*!50001 DROP VIEW IF EXISTS ' . $quoter->quote($tbl) . "*/;\n"
         . '/*!50001 ' . $ddl->[1] . "*/;\n";
   }
   else {
      die "You didn't say what to dump.";
   }
}

sub _use_db {
   my ( $self, $dbh, $quoter, $new ) = @_;
   if ( !$new ) {
      MKDEBUG && _d('No new DB to use');
      return;
   }
   my $sql = 'USE ' . $quoter->quote($new);
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);
   return;
}

sub get_create_table {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   if ( !$self->{cache} || !$self->{tables}->{$db}->{$tbl} ) {
      my $sql = '/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, '
         . q{@@SQL_MODE := REPLACE(REPLACE(@@SQL_MODE, 'ANSI_QUOTES', ''), ',,', ','), }
         . '@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, '
         . '@@SQL_QUOTE_SHOW_CREATE := 1 */';
      MKDEBUG && _d($sql);
      eval { $dbh->do($sql); };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      $self->_use_db($dbh, $quoter, $db);
      $sql = "SHOW CREATE TABLE " . $quoter->quote($db, $tbl);
      MKDEBUG && _d($sql);
      my $href;
      eval { $href = $dbh->selectrow_hashref($sql); };
      if ( $EVAL_ERROR ) {
         warn "Failed to $sql.  The table may be damaged.\nError: $EVAL_ERROR";
         return;
      }

      $sql = '/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, '
         . '@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
      my ($key) = grep { m/create table/i } keys %$href;
      if ( $key ) {
         MKDEBUG && _d('This table is a base table');
         $self->{tables}->{$db}->{$tbl} = [ 'table', $href->{$key} ];
      }
      else {
         MKDEBUG && _d('This table is a view');
         ($key) = grep { m/create view/i } keys %$href;
         $self->{tables}->{$db}->{$tbl} = [ 'view', $href->{$key} ];
      }
   }
   return $self->{tables}->{$db}->{$tbl};
}

sub get_columns {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   MKDEBUG && _d('Get columns for', $db, $tbl);
   if ( !$self->{cache} || !$self->{columns}->{$db}->{$tbl} ) {
      $self->_use_db($dbh, $quoter, $db);
      my $sql = "SHOW COLUMNS FROM " . $quoter->quote($db, $tbl);
      MKDEBUG && _d($sql);
      my $cols = $dbh->selectall_arrayref($sql, { Slice => {} });

      $self->{columns}->{$db}->{$tbl} = [
         map {
            my %row;
            @row{ map { lc $_ } keys %$_ } = values %$_;
            \%row;
         } @$cols
      ];
   }
   return $self->{columns}->{$db}->{$tbl};
}

sub get_tmp_table {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   my $result = 'CREATE TABLE ' . $quoter->quote($tbl) . " (\n";
   $result .= join(",\n",
      map { '  ' . $quoter->quote($_->{field}) . ' ' . $_->{type} }
      @{$self->get_columns($dbh, $quoter, $db, $tbl)});
   $result .= "\n)";
   MKDEBUG && _d($result);
   return $result;
}

sub get_triggers {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   if ( !$self->{cache} || !$self->{triggers}->{$db} ) {
      $self->{triggers}->{$db} = {};
      my $sql = '/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, '
         . q{@@SQL_MODE := REPLACE(REPLACE(@@SQL_MODE, 'ANSI_QUOTES', ''), ',,', ','), }
         . '@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, '
         . '@@SQL_QUOTE_SHOW_CREATE := 1 */';
      MKDEBUG && _d($sql);
      eval { $dbh->do($sql); };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      $sql = "SHOW TRIGGERS FROM " . $quoter->quote($db);
      MKDEBUG && _d($sql);
      my $sth = $dbh->prepare($sql);
      $sth->execute();
      if ( $sth->rows ) {
         my $trgs = $sth->fetchall_arrayref({});
         foreach my $trg (@$trgs) {
            my %trg;
            @trg{ map { lc $_ } keys %$trg } = values %$trg;
            push @{ $self->{triggers}->{$db}->{ $trg{table} } }, \%trg;
         }
      }
      $sql = '/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, '
         . '@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }
   if ( $tbl ) {
      return $self->{triggers}->{$db}->{$tbl};
   }
   return values %{$self->{triggers}->{$db}};
}

sub get_databases {
   my ( $self, $dbh, $quoter, $like ) = @_;
   if ( !$self->{cache} || !$self->{databases} || $like ) {
      my $sql = 'SHOW DATABASES';
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      my $sth = $dbh->prepare($sql);
      MKDEBUG && _d($sql, @params);
      $sth->execute( @params );
      my @dbs = map { $_->[0] } @{$sth->fetchall_arrayref()};
      $self->{databases} = \@dbs unless $like;
      return @dbs;
   }
   return @{$self->{databases}};
}

sub get_table_status {
   my ( $self, $dbh, $quoter, $db, $like ) = @_;
   if ( !$self->{cache} || !$self->{table_status}->{$db} || $like ) {
      my $sql = "SHOW TABLE STATUS FROM " . $quoter->quote($db);
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      MKDEBUG && _d($sql, @params);
      my $sth = $dbh->prepare($sql);
      $sth->execute(@params);
      my @tables = @{$sth->fetchall_arrayref({})};
      @tables = map {
         my %tbl; # Make a copy with lowercased keys
         @tbl{ map { lc $_ } keys %$_ } = values %$_;
         $tbl{engine} ||= $tbl{type} || $tbl{comment};
         delete $tbl{type};
         \%tbl;
      } @tables;
      $self->{table_status}->{$db} = \@tables unless $like;
      return @tables;
   }
   return @{$self->{table_status}->{$db}};
}

sub get_table_list {
   my ( $self, $dbh, $quoter, $db, $like ) = @_;
   if ( !$self->{cache} || !$self->{table_list}->{$db} || $like ) {
      my $sql = "SHOW /*!50002 FULL*/ TABLES FROM " . $quoter->quote($db);
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      MKDEBUG && _d($sql, @params);
      my $sth = $dbh->prepare($sql);
      $sth->execute(@params);
      my @tables = @{$sth->fetchall_arrayref()};
      @tables = map {
         my %tbl = (
            name   => $_->[0],
            engine => ($_->[1] || '') eq 'VIEW' ? 'VIEW' : '',
         );
         \%tbl;
      } @tables;
      $self->{table_list}->{$db} = \@tables unless $like;
      return @tables;
   }
   return @{$self->{table_list}->{$db}};
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
# End MySQLDump package
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
# MasterSlave package 7525
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MasterSlave.pm
#   trunk/common/t/MasterSlave.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package MasterSlave;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Indent    = 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
      replication_thread => {},
   };
   return bless $self, $class;
}

sub recurse_to_slaves {
   my ( $self, $args, $level ) = @_;
   $level ||= 0;
   my $dp   = $args->{dsn_parser};
   my $dsn  = $args->{dsn};

   my $dbh;
   eval {
      $dbh = $args->{dbh} || $dp->get_dbh(
         $dp->get_cxn_params($dsn), { AutoCommit => 1 });
      MKDEBUG && _d('Connected to', $dp->as_string($dsn));
   };
   if ( $EVAL_ERROR ) {
      print STDERR "Cannot connect to ", $dp->as_string($dsn), "\n"
         or die "Cannot print: $OS_ERROR";
      return;
   }

   my $sql  = 'SELECT @@SERVER_ID';
   MKDEBUG && _d($sql);
   my ($id) = $dbh->selectrow_array($sql);
   MKDEBUG && _d('Working on server ID', $id);
   my $master_thinks_i_am = $dsn->{server_id};
   if ( !defined $id
       || ( defined $master_thinks_i_am && $master_thinks_i_am != $id )
       || $args->{server_ids_seen}->{$id}++
   ) {
      MKDEBUG && _d('Server ID seen, or not what master said');
      if ( $args->{skip_callback} ) {
         $args->{skip_callback}->($dsn, $dbh, $level, $args->{parent});
      }
      return;
   }

   $args->{callback}->($dsn, $dbh, $level, $args->{parent});

   if ( !defined $args->{recurse} || $level < $args->{recurse} ) {

      my @slaves =
         grep { !$_->{master_id} || $_->{master_id} == $id } # Only my slaves.
         $self->find_slave_hosts($dp, $dbh, $dsn, $args->{method});

      foreach my $slave ( @slaves ) {
         MKDEBUG && _d('Recursing from',
            $dp->as_string($dsn), 'to', $dp->as_string($slave));
         $self->recurse_to_slaves(
            { %$args, dsn => $slave, dbh => undef, parent => $dsn }, $level + 1 );
      }
   }
}

sub find_slave_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn, $method ) = @_;

   my @methods = qw(processlist hosts);
   if ( $method ) {
      @methods = grep { $_ ne $method } @methods;
      unshift @methods, $method;
   }
   else {
      if ( ($dsn->{P} || 3306) != 3306 ) {
         MKDEBUG && _d('Port number is non-standard; using only hosts method');
         @methods = qw(hosts);
      }
   }
   MKDEBUG && _d('Looking for slaves on', $dsn_parser->as_string($dsn),
      'using methods', @methods);

   my @slaves;
   METHOD:
   foreach my $method ( @methods ) {
      my $find_slaves = "_find_slaves_by_$method";
      MKDEBUG && _d('Finding slaves with', $find_slaves);
      @slaves = $self->$find_slaves($dsn_parser, $dbh, $dsn);
      last METHOD if @slaves;
   }

   MKDEBUG && _d('Found', scalar(@slaves), 'slaves');
   return @slaves;
}

sub _find_slaves_by_processlist {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;

   my @slaves = map  {
      my $slave        = $dsn_parser->parse("h=$_", $dsn);
      $slave->{source} = 'processlist';
      $slave;
   }
   grep { $_ }
   map  {
      my ( $host ) = $_->{host} =~ m/^([^:]+):/;
      if ( $host eq 'localhost' ) {
         $host = '127.0.0.1'; # Replication never uses sockets.
      }
      $host;
   } $self->get_connected_slaves($dbh);

   return @slaves;
}

sub _find_slaves_by_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;

   my @slaves;
   my $sql = 'SHOW SLAVE HOSTS';
   MKDEBUG && _d($dbh, $sql);
   @slaves = @{$dbh->selectall_arrayref($sql, { Slice => {} })};

   if ( @slaves ) {
      MKDEBUG && _d('Found some SHOW SLAVE HOSTS info');
      @slaves = map {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         my $spec = "h=$hash{host},P=$hash{port}"
            . ( $hash{user} ? ",u=$hash{user}" : '')
            . ( $hash{password} ? ",p=$hash{password}" : '');
         my $dsn           = $dsn_parser->parse($spec, $dsn);
         $dsn->{server_id} = $hash{server_id};
         $dsn->{master_id} = $hash{master_id};
         $dsn->{source}    = 'hosts';
         $dsn;
      } @slaves;
   }

   return @slaves;
}

sub get_connected_slaves {
   my ( $self, $dbh ) = @_;

   my $show = "SHOW GRANTS FOR ";
   my $user = 'CURRENT_USER()';
   my $vp   = $self->{VersionParser};
   if ( $vp && !$vp->version_ge($dbh, '4.1.2') ) {
      $user = $dbh->selectrow_arrayref('SELECT USER()')->[0];
      $user =~ s/([^@]+)@(.+)/'$1'\@'$2'/;
   }
   my $sql = $show . $user;
   MKDEBUG && _d($dbh, $sql);

   my $proc;
   eval {
      $proc = grep {
         m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
      } @{$dbh->selectcol_arrayref($sql)};
   };
   if ( $EVAL_ERROR ) {

      if ( $EVAL_ERROR =~ m/no such grant defined for user/ ) {
         MKDEBUG && _d('Retrying SHOW GRANTS without host; error:',
            $EVAL_ERROR);
         ($user) = split('@', $user);
         $sql    = $show . $user;
         MKDEBUG && _d($sql);
         eval {
            $proc = grep {
               m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
            } @{$dbh->selectcol_arrayref($sql)};
         };
      }

      die "Failed to $sql: $EVAL_ERROR" if $EVAL_ERROR;
   }
   if ( !$proc ) {
      die "You do not have the PROCESS privilege";
   }

   $sql = 'SHOW PROCESSLIST';
   MKDEBUG && _d($dbh, $sql);
   grep { $_->{command} =~ m/Binlog Dump/i }
   map  { # Lowercase the column names
      my %hash;
      @hash{ map { lc $_ } keys %$_ } = values %$_;
      \%hash;
   }
   @{$dbh->selectall_arrayref($sql, { Slice => {} })};
}

sub is_master_of {
   my ( $self, $master, $slave ) = @_;
   my $master_status = $self->get_master_status($master)
      or die "The server specified as a master is not a master";
   my $slave_status  = $self->get_slave_status($slave)
      or die "The server specified as a slave is not a slave";
   my @connected     = $self->get_connected_slaves($master)
      or die "The server specified as a master has no connected slaves";
   my (undef, $port) = $master->selectrow_array('SHOW VARIABLES LIKE "port"');

   if ( $port != $slave_status->{master_port} ) {
      die "The slave is connected to $slave_status->{master_port} "
         . "but the master's port is $port";
   }

   if ( !grep { $slave_status->{master_user} eq $_->{user} } @connected ) {
      die "I don't see any slave I/O thread connected with user "
         . $slave_status->{master_user};
   }

   if ( ($slave_status->{slave_io_state} || '')
      eq 'Waiting for master to send event' )
   {
      my ( $master_log_name, $master_log_num )
         = $master_status->{file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      my ( $slave_log_name, $slave_log_num )
         = $slave_status->{master_log_file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      if ( $master_log_name ne $slave_log_name
         || abs($master_log_num - $slave_log_num) > 1 )
      {
         die "The slave thinks it is reading from "
            . "$slave_status->{master_log_file},  but the "
            . "master is writing to $master_status->{file}";
      }
   }
   return 1;
}

sub get_master_dsn {
   my ( $self, $dbh, $dsn, $dsn_parser ) = @_;
   my $master = $self->get_slave_status($dbh) or return undef;
   my $spec   = "h=$master->{master_host},P=$master->{master_port}";
   return       $dsn_parser->parse($spec, $dsn);
}

sub get_slave_status {
   my ( $self, $dbh ) = @_;
   if ( !$self->{not_a_slave}->{$dbh} ) {
      my $sth = $self->{sths}->{$dbh}->{SLAVE_STATUS}
            ||= $dbh->prepare('SHOW SLAVE STATUS');
      MKDEBUG && _d($dbh, 'SHOW SLAVE STATUS');
      $sth->execute();
      my ($ss) = @{$sth->fetchall_arrayref({})};

      if ( $ss && %$ss ) {
         $ss = { map { lc($_) => $ss->{$_} } keys %$ss }; # lowercase the keys
         return $ss;
      }

      MKDEBUG && _d('This server returns nothing for SHOW SLAVE STATUS');
      $self->{not_a_slave}->{$dbh}++;
   }
}

sub get_master_status {
   my ( $self, $dbh ) = @_;

   if ( $self->{not_a_master}->{$dbh} ) {
      MKDEBUG && _d('Server on dbh', $dbh, 'is not a master');
      return;
   }

   my $sth = $self->{sths}->{$dbh}->{MASTER_STATUS}
         ||= $dbh->prepare('SHOW MASTER STATUS');
   MKDEBUG && _d($dbh, 'SHOW MASTER STATUS');
   $sth->execute();
   my ($ms) = @{$sth->fetchall_arrayref({})};
   MKDEBUG && _d(Dumper($ms));

   if ( !$ms || scalar keys %$ms < 2 ) {
      MKDEBUG && _d('Server on dbh', $dbh, 'does not seem to be a master');
      $self->{not_a_master}->{$dbh}++;
   }

  return { map { lc($_) => $ms->{$_} } keys %$ms }; # lowercase the keys
}

sub wait_for_master {
   my ( $self, %args ) = @_;
   my @required_args = qw(master_status slave_dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($master_status, $slave_dbh) = @args{@required_args};
   my $timeout       = $args{timeout} || 60;

   my $result;
   my $waited;
   if ( $master_status ) {
      my $sql = "SELECT MASTER_POS_WAIT('$master_status->{file}', "
              . "$master_status->{position}, $timeout)";
      MKDEBUG && _d($slave_dbh, $sql);
      my $start = time;
      ($result) = $slave_dbh->selectrow_array($sql);

      $waited = time - $start;

      MKDEBUG && _d('Result of waiting:', $result);
      MKDEBUG && _d("Waited", $waited, "seconds");
   }
   else {
      MKDEBUG && _d('Not waiting: this server is not a master');
   }

   return {
      result => $result,
      waited => $waited,
   };
}

sub stop_slave {
   my ( $self, $dbh ) = @_;
   my $sth = $self->{sths}->{$dbh}->{STOP_SLAVE}
         ||= $dbh->prepare('STOP SLAVE');
   MKDEBUG && _d($dbh, $sth->{Statement});
   $sth->execute();
}

sub start_slave {
   my ( $self, $dbh, $pos ) = @_;
   if ( $pos ) {
      my $sql = "START SLAVE UNTIL MASTER_LOG_FILE='$pos->{file}', "
              . "MASTER_LOG_POS=$pos->{position}";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   else {
      my $sth = $self->{sths}->{$dbh}->{START_SLAVE}
            ||= $dbh->prepare('START SLAVE');
      MKDEBUG && _d($dbh, $sth->{Statement});
      $sth->execute();
   }
}

sub catchup_to_master {
   my ( $self, $slave, $master, $timeout ) = @_;
   $self->stop_slave($master);
   $self->stop_slave($slave);
   my $slave_status  = $self->get_slave_status($slave);
   my $slave_pos     = $self->repl_posn($slave_status);
   my $master_status = $self->get_master_status($master);
   my $master_pos    = $self->repl_posn($master_status);
   MKDEBUG && _d('Master position:', $self->pos_to_string($master_pos),
      'Slave position:', $self->pos_to_string($slave_pos));

   my $result;
   if ( $self->pos_cmp($slave_pos, $master_pos) < 0 ) {
      MKDEBUG && _d('Waiting for slave to catch up to master');
      $self->start_slave($slave, $master_pos);

      $result = $self->wait_for_master(
            master_status => $master_status,
            slave_dbh     => $slave,
            timeout       => $timeout,
            master_status => $master_status
      );
      if ( !defined $result->{result} ) {
         $slave_status = $self->get_slave_status($slave);
         if ( !$self->slave_is_running($slave_status) ) {
            MKDEBUG && _d('Master position:',
               $self->pos_to_string($master_pos),
               'Slave position:', $self->pos_to_string($slave_pos));
            $slave_pos = $self->repl_posn($slave_status);
            if ( $self->pos_cmp($slave_pos, $master_pos) != 0 ) {
               die "MASTER_POS_WAIT() returned NULL but slave has not "
                  . "caught up to master";
            }
            MKDEBUG && _d('Slave is caught up to master and stopped');
         }
         else {
            die "Slave has not caught up to master and it is still running";
         }
      }
   }
   else {
      MKDEBUG && _d("Slave is already caught up to master");
   }

   return $result;
}

sub catchup_to_same_pos {
   my ( $self, $s1_dbh, $s2_dbh ) = @_;
   $self->stop_slave($s1_dbh);
   $self->stop_slave($s2_dbh);
   my $s1_status = $self->get_slave_status($s1_dbh);
   my $s2_status = $self->get_slave_status($s2_dbh);
   my $s1_pos    = $self->repl_posn($s1_status);
   my $s2_pos    = $self->repl_posn($s2_status);
   if ( $self->pos_cmp($s1_pos, $s2_pos) < 0 ) {
      $self->start_slave($s1_dbh, $s2_pos);
   }
   elsif ( $self->pos_cmp($s2_pos, $s1_pos) < 0 ) {
      $self->start_slave($s2_dbh, $s1_pos);
   }

   $s1_status = $self->get_slave_status($s1_dbh);
   $s2_status = $self->get_slave_status($s2_dbh);
   $s1_pos    = $self->repl_posn($s1_status);
   $s2_pos    = $self->repl_posn($s2_status);

   if ( $self->slave_is_running($s1_status)
     || $self->slave_is_running($s2_status)
     || $self->pos_cmp($s1_pos, $s2_pos) != 0)
   {
      die "The servers aren't both stopped at the same position";
   }

}

sub change_master_to {
   my ( $self, $dbh, $master_dsn, $master_pos ) = @_;
   $self->stop_slave($dbh);
   MKDEBUG && _d(Dumper($master_dsn), Dumper($master_pos));
   my $sql = "CHANGE MASTER TO MASTER_HOST='$master_dsn->{h}', "
      . "MASTER_PORT= $master_dsn->{P}, MASTER_LOG_FILE='$master_pos->{file}', "
      . "MASTER_LOG_POS=$master_pos->{position}";
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);
}

sub make_sibling_of_master {
   my ( $self, $slave_dbh, $slave_dsn, $dsn_parser, $timeout) = @_;

   my $master_dsn  = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "This server is not a slave";
   my $master_dbh  = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($master_dsn), { AutoCommit => 1 });
   my $gmaster_dsn
      = $self->get_master_dsn($master_dbh, $master_dsn, $dsn_parser)
      or die "This server's master is not a slave";
   my $gmaster_dbh = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($gmaster_dsn), { AutoCommit => 1 });
   if ( $self->short_host($slave_dsn) eq $self->short_host($gmaster_dsn) ) {
      die "The slave's master's master is the slave: master-master replication";
   }

   $self->stop_slave($master_dbh);
   $self->catchup_to_master($slave_dbh, $master_dbh, $timeout);
   $self->stop_slave($slave_dbh);

   my $master_status = $self->get_master_status($master_dbh);
   my $mslave_status = $self->get_slave_status($master_dbh);
   my $slave_status  = $self->get_slave_status($slave_dbh);
   my $master_pos    = $self->repl_posn($master_status);
   my $slave_pos     = $self->repl_posn($slave_status);

   if ( !$self->slave_is_running($mslave_status)
     && !$self->slave_is_running($slave_status)
     && $self->pos_cmp($master_pos, $slave_pos) == 0)
   {
      $self->change_master_to($slave_dbh, $gmaster_dsn,
         $self->repl_posn($mslave_status)); # Note it's not $master_pos!
   }
   else {
      die "The servers aren't both stopped at the same position";
   }

   $mslave_status = $self->get_slave_status($master_dbh);
   $slave_status  = $self->get_slave_status($slave_dbh);
   my $mslave_pos = $self->repl_posn($mslave_status);
   $slave_pos     = $self->repl_posn($slave_status);
   if ( $self->short_host($mslave_status) ne $self->short_host($slave_status)
     || $self->pos_cmp($mslave_pos, $slave_pos) != 0)
   {
      die "The servers don't have the same master/position after the change";
   }
}

sub make_slave_of_sibling {
   my ( $self, $slave_dbh, $slave_dsn, $sib_dbh, $sib_dsn,
        $dsn_parser, $timeout) = @_;

   if ( $self->short_host($slave_dsn) eq $self->short_host($sib_dsn) ) {
      die "You are trying to make the slave a slave of itself";
   }

   my $master_dsn1 = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "This server is not a slave";
   my $master_dbh1 = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($master_dsn1), { AutoCommit => 1 });
   my $master_dsn2 = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "The sibling is not a slave";
   if ( $self->short_host($master_dsn1) ne $self->short_host($master_dsn2) ) {
      die "This server isn't a sibling of the slave";
   }
   my $sib_master_stat = $self->get_master_status($sib_dbh)
      or die "Binary logging is not enabled on the sibling";
   die "The log_slave_updates option is not enabled on the sibling"
      unless $self->has_slave_updates($sib_dbh);

   $self->catchup_to_same_pos($slave_dbh, $sib_dbh);

   $sib_master_stat = $self->get_master_status($sib_dbh);
   $self->change_master_to($slave_dbh, $sib_dsn,
         $self->repl_posn($sib_master_stat));

   my $slave_status = $self->get_slave_status($slave_dbh);
   my $slave_pos    = $self->repl_posn($slave_status);
   $sib_master_stat = $self->get_master_status($sib_dbh);
   if ( $self->short_host($slave_status) ne $self->short_host($sib_dsn)
     || $self->pos_cmp($self->repl_posn($sib_master_stat), $slave_pos) != 0)
   {
      die "After changing the slave's master, it isn't a slave of the sibling, "
         . "or it has a different replication position than the sibling";
   }
}

sub make_slave_of_uncle {
   my ( $self, $slave_dbh, $slave_dsn, $unc_dbh, $unc_dsn,
        $dsn_parser, $timeout) = @_;

   if ( $self->short_host($slave_dsn) eq $self->short_host($unc_dsn) ) {
      die "You are trying to make the slave a slave of itself";
   }

   my $master_dsn = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "This server is not a slave";
   my $master_dbh = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($master_dsn), { AutoCommit => 1 });
   my $gmaster_dsn
      = $self->get_master_dsn($master_dbh, $master_dsn, $dsn_parser)
      or die "The master is not a slave";
   my $unc_master_dsn
      = $self->get_master_dsn($unc_dbh, $unc_dsn, $dsn_parser)
      or die "The uncle is not a slave";
   if ($self->short_host($gmaster_dsn) ne $self->short_host($unc_master_dsn)) {
      die "The uncle isn't really the slave's uncle";
   }

   my $unc_master_stat = $self->get_master_status($unc_dbh)
      or die "Binary logging is not enabled on the uncle";
   die "The log_slave_updates option is not enabled on the uncle"
      unless $self->has_slave_updates($unc_dbh);

   $self->catchup_to_same_pos($master_dbh, $unc_dbh);
   $self->catchup_to_master($slave_dbh, $master_dbh, $timeout);

   my $slave_status  = $self->get_slave_status($slave_dbh);
   my $master_status = $self->get_master_status($master_dbh);
   if ( $self->pos_cmp(
         $self->repl_posn($slave_status),
         $self->repl_posn($master_status)) != 0 )
   {
      die "The slave is not caught up to its master";
   }

   $unc_master_stat = $self->get_master_status($unc_dbh);
   $self->change_master_to($slave_dbh, $unc_dsn,
      $self->repl_posn($unc_master_stat));


   $slave_status    = $self->get_slave_status($slave_dbh);
   my $slave_pos    = $self->repl_posn($slave_status);
   if ( $self->short_host($slave_status) ne $self->short_host($unc_dsn)
     || $self->pos_cmp($self->repl_posn($unc_master_stat), $slave_pos) != 0)
   {
      die "After changing the slave's master, it isn't a slave of the uncle, "
         . "or it has a different replication position than the uncle";
   }
}

sub detach_slave {
   my ( $self, $dbh ) = @_;
   $self->stop_slave($dbh);
   my $stat = $self->get_slave_status($dbh)
      or die "This server is not a slave";
   $dbh->do('CHANGE MASTER TO MASTER_HOST=""');
   $dbh->do('RESET SLAVE'); # Wipes out master.info, etc etc
   return $stat;
}

sub slave_is_running {
   my ( $self, $slave_status ) = @_;
   return ($slave_status->{slave_sql_running} || 'No') eq 'Yes';
}

sub has_slave_updates {
   my ( $self, $dbh ) = @_;
   my $sql = q{SHOW VARIABLES LIKE 'log_slave_updates'};
   MKDEBUG && _d($dbh, $sql);
   my ($name, $value) = $dbh->selectrow_array($sql);
   return $value && $value =~ m/^(1|ON)$/;
}

sub repl_posn {
   my ( $self, $status ) = @_;
   if ( exists $status->{file} && exists $status->{position} ) {
      return {
         file     => $status->{file},
         position => $status->{position},
      };
   }
   else {
      return {
         file     => $status->{relay_master_log_file},
         position => $status->{exec_master_log_pos},
      };
   }
}

sub get_slave_lag {
   my ( $self, $dbh ) = @_;
   my $stat = $self->get_slave_status($dbh);
   return $stat->{seconds_behind_master};
}

sub pos_cmp {
   my ( $self, $a, $b ) = @_;
   return $self->pos_to_string($a) cmp $self->pos_to_string($b);
}

sub short_host {
   my ( $self, $dsn ) = @_;
   my ($host, $port);
   if ( $dsn->{master_host} ) {
      $host = $dsn->{master_host};
      $port = $dsn->{master_port};
   }
   else {
      $host = $dsn->{h};
      $port = $dsn->{P};
   }
   return ($host || '[default]') . ( ($port || 3306) == 3306 ? '' : ":$port" );
}

sub is_replication_thread {
   my ( $self, $query, %args ) = @_; 
   return unless $query;

   my $type = lc $args{type} || 'all';
   die "Invalid type: $type"
      unless $type =~ m/^binlog_dump|slave_io|slave_sql|all$/i;

   my $match = 0;
   if ( $type =~ m/binlog_dump|all/i ) {
      $match = 1
         if ($query->{Command} || $query->{command} || '') eq "Binlog Dump";
   }
   if ( !$match ) {
      if ( ($query->{User} || $query->{user} || '') eq "system user" ) {
         MKDEBUG && _d("Slave replication thread");
         if ( $type ne 'all' ) { 
            my $state = $query->{State} || $query->{state} || '';

            if ( $state =~ m/^init|end$/ ) {
               MKDEBUG && _d("Special state:", $state);
               $match = 1;
            }
            else {
               my ($slave_sql) = $state =~ m/
                  ^(Waiting\sfor\sthe\snext\sevent
                   |Reading\sevent\sfrom\sthe\srelay\slog
                   |Has\sread\sall\srelay\slog;\swaiting
                   |Making\stemp\sfile
                   |Waiting\sfor\sslave\smutex\son\sexit)/xi; 

               $match = $type eq 'slave_sql' &&  $slave_sql ? 1
                      : $type eq 'slave_io'  && !$slave_sql ? 1
                      :                                       0;
            }
         }
         else {
            $match = 1;
         }
      }
      else {
         MKDEBUG && _d('Not system user');
      }

      if ( !defined $args{check_known_ids} || $args{check_known_ids} ) {
         my $id = $query->{Id} || $query->{id};
         if ( $match ) {
            $self->{replication_thread}->{$id} = 1;
         }
         else {
            if ( $self->{replication_thread}->{$id} ) {
               MKDEBUG && _d("Thread ID is a known replication thread ID");
               $match = 1;
            }
         }
      }
   }

   MKDEBUG && _d('Matches', $type, 'replication thread:',
      ($match ? 'yes' : 'no'), '; match:', $match);

   return $match;
}


sub get_replication_filters {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};

   my %filters = ();

   my $status = $self->get_master_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         binlog_do_db
         binlog_ignore_db
      );
   }

   $status = $self->get_slave_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         replicate_do_db
         replicate_ignore_db
         replicate_do_table
         replicate_ignore_table 
         replicate_wild_do_table
         replicate_wild_ignore_table
      );

      my $sql = "SHOW VARIABLES LIKE 'slave_skip_errors'";
      MKDEBUG && _d($dbh, $sql);
      my $row = $dbh->selectrow_arrayref($sql);
      $filters{slave_skip_errors} = $row->[1] if $row->[1] && $row->[1] ne 'OFF';
   }

   return \%filters; 
}


sub pos_to_string {
   my ( $self, $pos ) = @_;
   my $fmt  = '%s/%020d';
   return sprintf($fmt, @{$pos}{qw(file position)});
}

sub reset_known_replication_threads {
   my ( $self ) = @_;
   $self->{replication_thread} = {};
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
# End MasterSlave package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_archiver;

use English qw(-no_match_vars);
use List::Util qw(max);
use IO::File;
use sigtrap qw(handler finish untrapped normal-signals);
use Time::HiRes qw(gettimeofday sleep time);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Global variables; as few as possible.
my $oktorun   = 1;
my $txn_cnt   = 0;
my $cnt       = 0;
my $can_retry = 1;
my $archive_fh;
my $get_sth;
my ( $OUT_OF_RETRIES, $ROLLED_BACK, $ALL_IS_WELL ) = ( 0, -1, 1 );
my ( $src, $dst );

# Holds the arguments for the $sth's bind variables, so it can be re-tried
# easily.
my @beginning_of_txn;
my $vp = new VersionParser;
my $q  = new Quoter;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # Reset global vars else tests, which run this tool as a module,
   # may encounter weird results.
   $oktorun          = 1;
   $txn_cnt          = 0;
   $cnt              = 0;
   $can_retry        = 1;
   $archive_fh       = undef;
   $get_sth          = undef;
   ($src, $dst)      = (undef, undef);
   @beginning_of_txn = ();
   undef *trace;
   ($OUT_OF_RETRIES, $ROLLED_BACK, $ALL_IS_WELL ) = (0, -1, 1);

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   # Frequently used options.
   $src             = $o->get('source');
   $dst             = $o->get('dest');
   my $sentinel     = $o->get('sentinel');
   my $bulk_del     = $o->get('bulk-delete');
   my $commit_each  = $o->get('commit-each');
   my $limit        = $o->get('limit');
   my $archive_file = $o->get('file');
   my $txnsize      = $o->get('txn-size');
   my $quiet        = $o->get('quiet');

   # First things first: if --stop was given, create the sentinel file.
   if ( $o->get('stop') ) {
      my $sentinel_fh = IO::File->new($sentinel, ">>")
         or die "Cannot open $sentinel: $OS_ERROR\n";
      print $sentinel_fh "Remove this file to permit mk-archiver to run\n"
         or die "Cannot write to $sentinel: $OS_ERROR\n";
      close $sentinel_fh
         or die "Cannot close $sentinel: $OS_ERROR\n";
      print STDOUT "Successfully created file $sentinel\n"
         unless $quiet;
      return 0;
   }

   # Generate a filename with sprintf-like formatting codes.
   if ( $archive_file ) {
      my @time = localtime();
      my %fmt = (
         d => sprintf('%02d', $time[3]),
         H => sprintf('%02d', $time[2]),
         i => sprintf('%02d', $time[1]),
         m => sprintf('%02d', $time[4] + 1),
         s => sprintf('%02d', $time[0]),
         Y => $time[5] + 1900,
         D => $src && $src->{D} ? $src->{D} : '',
         t => $src && $src->{t} ? $src->{t} : '',
      );
      $archive_file =~ s/%([dHimsYDt])/$fmt{$1}/g;
   }

   if ( !$o->got('help') ) {
      $o->save_error("--source DSN requires a 't' (table) part")
         unless $src->{t};

      if ( $dst ) {
         # Ensure --source and --dest don't point to the same place
         my $same = 1;
         foreach my $arg ( qw(h P D t S) ) {
            if ( defined $src->{$arg} && defined $dst->{$arg}
                 && $src->{$arg} ne $dst->{$arg} ) {
               $same = 0;
               last;
            }
         }
         if ( $same ) {
            $o->save_error("--source and --dest refer to the same table");
         }
      }
      if ( $o->get('bulk-insert') ) {
         $o->save_error("--bulk-insert is meaningless without a destination")
            unless $dst;
         $bulk_del = 1; # VERY IMPORTANT for safety.
      }
      if ( $bulk_del && $limit < 2 ) {
         $o->save_error("--bulk-delete is meaningless with --limit 1");
      }

   }

   if ( $bulk_del || $o->get('bulk-insert') ) {
      $o->set('commit-each', 1);
   }

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
      
   # ########################################################################
   # Set up statistics.
   # ########################################################################
   my %statistics = ();
   my $stat_start;

   if ( $o->get('statistics') ) {
      my $start    = gettimeofday();
      my $obs_cost = gettimeofday() - $start; # cost of observation

      *trace = sub {
         my ( $thing, $sub ) = @_;
         my $start = gettimeofday();
         $sub->();
         $statistics{$thing . '_time'}
            += (gettimeofday() - $start - $obs_cost);
         ++$statistics{$thing . '_count'};
         $stat_start ||= $start;
      }
   }
   else { # Generate a version that doesn't do any timing
      *trace = sub {
         my ( $thing, $sub ) = @_;
         $sub->();
      }
   }

   # ########################################################################
   # Inspect DB servers and tables.
   # ########################################################################

   my $tp = new TableParser(Quoter => $q);
   my $du = new MySQLDump();
   foreach my $table ( grep { $_ } ($src, $dst) ) {
      my $ac = !$txnsize && !$commit_each;
      if ( !defined $table->{p} && $o->get('ask-pass') ) {
         $table->{p} = OptionParser::prompt_noecho("Enter password: ");
      }
      my $dbh = $dp->get_dbh(
         $dp->get_cxn_params($table), { AutoCommit => $ac });
      MKDEBUG && _d('Inspecting table on', $dp->as_string($table));

      # Set options that can enable removing data on the master and archiving it
      # on the slaves.
      if ( $table->{a} ) {
         $dbh->do("USE $table->{a}");
      }
      if ( $table->{b} ) {
         $dbh->do("SET SQL_LOG_BIN=0");
      }

      $table->{dbh}  = $dbh;
      $table->{irot} = get_irot($dbh);

      $can_retry = $can_retry && !$table->{irot};

      $table->{db_tbl} = $q->quote(
         map  { $_ =~ s/(^`|`$)//g; $_; }
         grep { $_ }
         ( $table->{D}, $table->{t} )
      );

      # Create objects for archivable and dependency handling, BEFORE getting
      # the tbl structure (because the object might do some setup, including
      # creating the table to be archived).
      if ( $table->{m} ) {
         eval "require $table->{m}";
         die $EVAL_ERROR if $EVAL_ERROR;

         trace('plugin_start', sub {
            $table->{plugin} = $table->{m}->new(
               dbh          => $table->{dbh},
               db           => $table->{D},
               tbl          => $table->{t},
               OptionParser => $o,
               DSNParser    => $dp,
               Quoter       => $q,
            );
         });
      }

      $table->{info} = $tp->parse(
         $du->get_create_table($dbh, $q, $table->{D}, $table->{t}));

      if ( $o->get('check-charset') ) {
         my $sql = 'SELECT CONCAT(/*!40100 @@session.character_set_connection, */ "")';
         MKDEBUG && _d($sql);
         my ($dbh_charset) =  $table->{dbh}->selectrow_array($sql);
         if ( ($dbh_charset || "") ne ($table->{info}->{charset} || "") ) {
            $src->{dbh}->disconnect() if $src && $src->{dbh};
            $dst->{dbh}->disconnect() if $dst && $dst->{dbh};
            die "Character set mismatch: "
               . ($src && $table eq $src ? "--source " : "--dest ")
               . "DSN uses "     . ($dbh_charset || "")
               . ", table uses " . ($table->{info}->{charset} || "")
               . ".  You can disable this check by specifying "
               . "--no-check-charset.\n";
         }
      }
   }

   if ( $o->get('primary-key-only')
        && !exists $src->{info}->{keys}->{PRIMARY} ) {
      $src->{dbh}->disconnect();
      $dst->{dbh}->disconnect() if $dst && $dst->{dbh};
      die "--primary-key-only was specified by the --source table "
         . "$src->{db_tbl} does not have a PRIMARY KEY";
   }

   if ( $dst && $o->get('check-columns') ) {
      my @not_in_src = grep {
         !$src->{info}->{is_col}->{$_}
      } @{$dst->{info}->{cols}};
      if ( @not_in_src ) {
         $src->{dbh}->disconnect();
         $dst->{dbh}->disconnect() if $dst && $dst->{dbh};
         die "The following columns exist in --dest but not --source: "
            . join(', ', @not_in_src)
            . "\n";
      }
      my @not_in_dst = grep {
         !$dst->{info}->{is_col}->{$_}
      } @{$src->{info}->{cols}};
      if ( @not_in_dst ) {
         $src->{dbh}->disconnect();
         $dst->{dbh}->disconnect() if $dst && $dst->{dbh};
         die "The following columns exist in --source but not --dest: "
            . join(', ', @not_in_dst)
            . "\n";
      }
   }

   # ########################################################################
   # Get lag dbh.
   # ########################################################################
   my $lag_dbh;
   my $ms;
   if ( $o->get('check-slave-lag') ) {
      my $dsn_defaults = $dp->parse_options($o);
      my $dsn  = $dp->parse($o->get('check-slave-lag'), $dsn_defaults);
      $lag_dbh = $dp->get_dbh($dp->get_cxn_params($dsn), { AutoCommit => 1 });
      $ms      = new MasterSlave(VersionParser => $vp);
   }

   # ########################################################################
   # Set up general plugin.
   # ########################################################################
   my $plugin;
   if ( $o->get('plugin') ) {
      eval "require " . $o->get('plugin');
      die $EVAL_ERROR if $EVAL_ERROR;
      $plugin = $o->get('plugin')->new(
         src  => $src,
         dst  => $dst,
         opts => $o,
      );
   }

   # ########################################################################
   # Design SQL statements.
   # ########################################################################
   my $dbh = $src->{dbh};
   my $nibbler = new TableNibbler(
      TableParser => $tp,
      Quoter      => $q,
   );
   my ($first_sql, $next_sql, $del_sql, $ins_sql);
   my ($sel_stmt, $ins_stmt, $del_stmt);
   my (@asc_slice, @sel_slice, @del_slice, @bulkdel_slice, @ins_slice);
   my @sel_cols = $o->get('columns')          ? @{$o->get('columns')}    # Explicit
                : $o->get('primary-key-only') ? @{$src->{info}->{keys}->{PRIMARY}->{cols}} 
                :                               @{$src->{info}->{cols}}; # All
   MKDEBUG && _d("sel cols: ", @sel_cols);

   $del_stmt = $nibbler->generate_del_stmt(
      tbl_struct => $src->{info},
      cols       => \@sel_cols,
      index      => $src->{i},
   );
   @del_slice = @{$del_stmt->{slice}};

   # Generate statement for ascending index, if desired
   if ( !$o->get('no-ascend') ) {
      $sel_stmt = $nibbler->generate_asc_stmt(
         tbl_struct => $src->{info},
         cols       => $del_stmt->{cols},
         index      => $del_stmt->{index},
         asc_first  => $o->get('ascend-first'),
         # A plugin might prevent rows in the source from being deleted
         # when doing single delete, but it cannot prevent rows from
         # being deleted when doing a bulk delete.
         asc_only   => $o->get('no-delete') ?  1
                    : $src->{m}             ? ($o->get('bulk-delete') ? 0 : 1)
                    :                          0,
      )
   }
   else {
      $sel_stmt = {
         cols  => $del_stmt->{cols},
         index => undef,
         where => '1=1',
         slice => [], # No-ascend = no bind variables in the WHERE clause.
         scols => [], # No-ascend = no bind variables in the WHERE clause.
      };
   }
   @asc_slice = @{$sel_stmt->{slice}};
   @sel_slice = 0..$#sel_cols;

   $first_sql
      = 'SELECT' . ( $o->get('high-priority-select') ? ' HIGH_PRIORITY' : '' )
      . ' /*!40001 SQL_NO_CACHE */ '
      . join(',', map { $q->quote($_) } @{$sel_stmt->{cols}} )
      . " FROM $src->{db_tbl}"
      . ( $sel_stmt->{index}
         ? (($vp->version_ge($dbh, '4.0.9') ? " FORCE" : " USE")
            . " INDEX(`$sel_stmt->{index}`)")
         : '')
      . " WHERE (".$o->get('where').")";

   if ( $o->get('safe-auto-increment')
         && $sel_stmt->{index}
         && scalar(@{$src->{info}->{keys}->{$sel_stmt->{index}}->{cols}}) == 1
         && $src->{info}->{is_autoinc}->{
            $src->{info}->{keys}->{$sel_stmt->{index}}->{cols}->[0]
         }
   ) {
      my $col = $q->quote($sel_stmt->{scols}->[0]);
      my ($val) = $dbh->selectrow_array("SELECT MAX($col) FROM $src->{db_tbl}");
      $first_sql .= " AND ($col < " . $q->quote_val($val) . ")";
   }

   $next_sql = $first_sql;
   if ( !$o->get('no-ascend') ) {
      $next_sql .= " AND $sel_stmt->{where}";
   }

   foreach my $thing ( $first_sql, $next_sql ) {
      $thing .= " LIMIT $limit";
      if ( $o->get('for-update') ) {
         $thing .= ' FOR UPDATE';
      }
      elsif ( $o->get('share-lock') ) {
         $thing .= ' LOCK IN SHARE MODE';
      }
   }

   MKDEBUG && _d("Index for DELETE:", $del_stmt->{index});
   if ( !$bulk_del ) {
      # The LIMIT might be 1 here, because even though a SELECT can return
      # many rows, an INSERT only does one at a time.  It would not be safe to
      # iterate over a SELECT that was LIMIT-ed to 500 rows, read and INSERT
      # one, and then delete with a LIMIT of 500.  Only one row would be written
      # to the file; only one would be INSERT-ed at the destination.  But
      # LIMIT 1 is actually only needed when the index is not unique
      # (http://code.google.com/p/maatkit/issues/detail?id=1166).
      $del_sql = 'DELETE'
         . ($o->get('low-priority-delete') ? ' LOW_PRIORITY' : '')
         . ($o->get('quick-delete')        ? ' QUICK'        : '')
         . " FROM $src->{db_tbl} WHERE $del_stmt->{where}";

         if ( $src->{info}->{keys}->{$del_stmt->{index}}->{is_unique} ) {
            MKDEBUG && _d("DELETE index is unique; LIMIT 1 is not needed");
         }
         else {
            MKDEBUG && _d("Adding LIMIT 1 to DELETE because DELETE index "
               . "is not unique");
            $del_sql .= " LIMIT 1";
         }
   }
   else {
      # Unless, of course, it's a bulk DELETE, in which case the 500 rows have
      # already been INSERT-ed.
      my $asc_stmt = $nibbler->generate_asc_stmt(
         tbl_struct => $src->{info},
         cols       => $del_stmt->{cols},
         index      => $del_stmt->{index},
         asc_first  => 0,
      );
      $del_sql = 'DELETE'
         . ($o->get('low-priority-delete') ? ' LOW_PRIORITY' : '')
         . ($o->get('quick-delete')        ? ' QUICK'        : '')
         . " FROM $src->{db_tbl} WHERE ("
         . $asc_stmt->{boundaries}->{'>='}
         . ') AND (' . $asc_stmt->{boundaries}->{'<='}
         # Unlike the row-at-a-time DELETE, this one must include the user's
         # specified WHERE clause and an appropriate LIMIT clause.
         . ") AND (".$o->get('where').")"
         . ($o->get('bulk-delete-limit') ? " LIMIT $limit" : "");
      @bulkdel_slice = @{$asc_stmt->{slice}};
   }

   if ( $dst ) {
      $ins_stmt = $nibbler->generate_ins_stmt(
         ins_tbl  => $dst->{info},
         sel_cols => \@sel_cols,
      );
      MKDEBUG && _d("inst stmt: ", Dumper($ins_stmt));
      @ins_slice = @{$ins_stmt->{slice}};
      if ( $o->get('bulk-insert') ) {
         $ins_sql = 'LOAD DATA'
                  . ($o->get('low-priority-insert') ? ' LOW_PRIORITY' : '')
                  . ' LOCAL INFILE ?'
                  . ($o->get('replace')    ? ' REPLACE'      : '')
                  . ($o->get('ignore')     ? ' IGNORE'       : '')
                  . " INTO TABLE $dst->{db_tbl}("
                  . join(",", map { $q->quote($_) } @{$ins_stmt->{cols}} )
                  . ")";
      }
      else {
         $ins_sql = ($o->get('replace')             ? 'REPLACE'      : 'INSERT')
                  . ($o->get('low-priority-insert') ? ' LOW_PRIORITY' : '')
                  . ($o->get('delayed-insert')      ? ' DELAYED'      : '')
                  . ($o->get('ignore')              ? ' IGNORE'       : '')
                  . " INTO $dst->{db_tbl}("
                  . join(",", map { $q->quote($_) } @{$ins_stmt->{cols}} )
                  . ") VALUES ("
                  . join(",", map { "?" } @{$ins_stmt->{cols}} ) . ")";
      }
   }
   else {
      $ins_sql = '';
   }

   if ( MKDEBUG ) {
      _d("get first sql:", $first_sql);
      _d("get next sql:", $next_sql);
      _d("del row sql:", $del_sql);
      _d("ins row sql:", $ins_sql);
   }
   
   if ( $o->get('dry-run') ) {
      if ( !$quiet ) {
         print join("\n", grep { $_ } ($archive_file || ''),
                  $first_sql, $next_sql,
                  ($o->get('no-delete') ? '' : $del_sql), $ins_sql)
            , "\n";
      }
      $src->{dbh}->disconnect();
      $dst->{dbh}->disconnect() if $dst && $dst->{dbh};
      return 0;
   }

   my $get_first = $dbh->prepare($first_sql);
   my $get_next  = $dbh->prepare($next_sql);
   my $del_row   = $dbh->prepare($del_sql);
   my $ins_row   = $dst->{dbh}->prepare($ins_sql) if $dst; # Different $dbh!

   # ########################################################################
   # Set MySQL options.
   # ########################################################################

   if ( $o->get('skip-foreign-key-checks') ) {
      $src->{dbh}->do("/*!40014 SET FOREIGN_KEY_CHECKS=0 */");
      if ( $dst ) {
         $dst->{dbh}->do("/*!40014 SET FOREIGN_KEY_CHECKS=0 */");
      }
   }

   # ########################################################################
   # Set up the plugins
   # ########################################################################
   foreach my $table ( $dst, $src ) {
      next unless $table && $table->{plugin};
      trace ('before_begin', sub {
         $table->{plugin}->before_begin(
            cols    => \@sel_cols,
            allcols => $sel_stmt->{cols},
         );
      });
   }

   # ########################################################################
   # Start archiving.
   # ########################################################################
   my $start   = time();
   my $end     = $start + ($o->get('run-time') || 0); # When to exit
   my $now     = $start;
   my $last_select_time;  # for --sleep-coef
   my $retries = $o->get('retries');
   printf("%-19s %7s %7s\n", 'TIME', 'ELAPSED', 'COUNT')
      if $o->get('progress') && !$quiet;
   printf("%19s %7d %7d\n", ts($now), $now - $start, $cnt)
      if $o->get('progress') && !$quiet;

   $get_sth = $get_first; # Later it may be assigned $get_next
   trace('select', sub {
      my $select_start = time;
      $get_sth->execute;
      $last_select_time = time - $select_start;
      $statistics{SELECT} += $get_sth->rows;
   });
   my $row = $get_sth->fetchrow_arrayref();
   MKDEBUG && _d("First row: ", Dumper($row), 'rows:', $get_sth->rows);
   if ( !$row ) {
      $get_sth->finish;
      $src->{dbh}->disconnect();
      $dst->{dbh}->disconnect() if $dst && $dst->{dbh};
      return 0;
   }

   # Open the file and print the header to it. 
   if ( $archive_file ) { 
      my $need_hdr = $o->get('header') && !-f $archive_file; 
      my $charset  = lc $o->get('charset'); 
      if ( $charset ) { 
          $archive_fh = IO::File->new($archive_file, ">>:$charset") 
             or die "Cannot open $charset $archive_file: $OS_ERROR\n"; 
      } 
      else { 
          $archive_fh = IO::File->new($archive_file, ">>") 
             or die "Cannot open $archive_file: $OS_ERROR\n"; 
      } 
      $archive_fh->autoflush(1) unless $o->get('buffer'); 
      if ( $need_hdr ) { 
         print $archive_fh '', escape(\@sel_cols), "\n" 
            or die "Cannot write to $archive_file: $OS_ERROR\n"; 
      } 
   } 

   # Open the bulk insert file, which doesn't get any header info.
   my $bulkins_file;
   if ( $o->get('bulk-insert') ) {
      require File::Temp;
      $bulkins_file = File::Temp->new( SUFFIX => 'mk-archiver' )
         or die "Cannot open temp file: $OS_ERROR\n";
   }

   # This row is the first row fetched from each 'chunk'.
   my $first_row = [ @$row ];
   my $csv_row;

   ROW:
   while (                                 # Quit if:
      $row                                 # There is no data
      && $retries >= 0                     # or retries are exceeded
      && (!$o->get('run-time') || $now < $end) # or time is exceeded
      && !-f $sentinel                     # or the sentinel is set
      && $oktorun                          # or instructed to quit
      )
   {
      my $lastrow = $row;

      if ( !$src->{plugin}
         || trace('is_archivable', sub {
            $src->{plugin}->is_archivable(row => $row)
         })
      ) {

         # Do the archiving.  Write to the file first since, like the file,
         # MyISAM and other tables cannot be rolled back etc.  If there is a
         # problem, hopefully the data has at least made it to the file.
         my $escaped_row;
         if ( $archive_fh || $bulkins_file ) {
            $escaped_row = escape([@{$row}[@sel_slice]]);
         }
         if ( $archive_fh ) {
            trace('print_file', sub {
               print $archive_fh $escaped_row, "\n"
                  or die "Cannot write to $archive_file: $OS_ERROR\n";
            });
         }

         # ###################################################################
         # This code is for the row-at-a-time archiving functionality.
         # ###################################################################
         # INSERT must come first, to be as safe as possible.
         if ( $dst && !$bulkins_file ) {
            my $ins_sth; # Let plugin change which sth is used for the INSERT.
            if ( $dst->{plugin} ) {
               trace('before_insert', sub {
                  $dst->{plugin}->before_insert(row => $row);
               });
               trace('custom_sth', sub {
                  $ins_sth = $dst->{plugin}->custom_sth(
                     row => $row, sql => $ins_sql);
               });
            }
            $ins_sth ||= $ins_row; # Default to the sth decided before.
            my $success = do_with_retries($o, 'inserting', sub {
               $ins_sth->execute(@{$row}[@ins_slice]);
               MKDEBUG && _d('Inserted', $del_row->rows, 'rows');
               $statistics{INSERT} += $ins_sth->rows;
            });
            if ( $success == $OUT_OF_RETRIES ) {
               $retries = -1;
               last ROW;
            }
            elsif ( $success == $ROLLED_BACK ) {
               --$retries;
               next ROW;
            }
         }

         if ( !$bulk_del ) {
            # DELETE comes after INSERT for safety.
            if ( $src->{plugin} ) {
               trace('before_delete', sub {
                  $src->{plugin}->before_delete(row => $row);
               });
            }
            if ( !$o->get('no-delete') ) {
               my $success = do_with_retries($o, 'deleting', sub {
                  $del_row->execute(@{$row}[@del_slice]);
                  MKDEBUG && _d('Deleted', $del_row->rows, 'rows');
                  $statistics{DELETE} += $del_row->rows;
               });
               if ( $success == $OUT_OF_RETRIES ) {
                  $retries = -1;
                  last ROW;
               }
               elsif ( $success == $ROLLED_BACK ) {
                  --$retries;
                  next ROW;
               }
            }
         }

         # ###################################################################
         # This code is for the bulk archiving functionality.
         # ###################################################################
         if ( $bulkins_file ) {
            trace('print_bulkfile', sub {
               print $bulkins_file $escaped_row, "\n"
                  or die "Cannot write to bulk file: $OS_ERROR\n";
            });
         }

      }  # row is archivable

      $now = time();
      ++$cnt;
      ++$txn_cnt;
      $retries = $o->get('retries');

      # Possibly flush the file and commit the insert and delete.
      commit($o) unless $commit_each;

      # Report on progress.
      if ( !$quiet && $o->get('progress') && $cnt % $o->get('progress') == 0 ) {
         printf("%19s %7d %7d\n", ts($now), $now - $start, $cnt);
      }

      # Get the next row in this chunk.
      # First time through this loop $get_sth is set to $get_first.
      # For non-bulk operations this means that rows ($row) are archived
      # one-by-one in in the code block above ("row is archivable").  For
      # bulk operations, the 2nd to 2nd-to-last rows are ignored and
      # only the first row ($first_row) and the last row ($last_row) of
      # this chunk are used to do bulk INSERT or DELETE on the range of
      # rows between first and last.  After the bulk ops, $first_row and
      # $last_row are reset to the next chunk.
      if ( $get_sth->{Active} ) { # Fetch until exhausted
         $row = $get_sth->fetchrow_arrayref();
      }
      if ( !$row ) {
         MKDEBUG && _d('No more rows in this chunk; doing bulk operations');

         # ###################################################################
         # This code is for the bulk archiving functionality.
         # ###################################################################
         if ( $bulkins_file ) {
            $bulkins_file->close()
               or die "Cannot close bulk insert file: $OS_ERROR\n";
            my $ins_sth; # Let plugin change which sth is used for the INSERT.
            if ( $dst->{plugin} ) {
               trace('before_bulk_insert', sub {
                  $dst->{plugin}->before_bulk_insert(
                     first_row => $first_row,
                     last_row  => $lastrow,
                     filename  => $bulkins_file->filename(),
                  );
               });
               trace('custom_sth', sub {
                  $ins_sth = $dst->{plugin}->custom_sth_bulk(
                     first_row => $first_row,
                     last_row  => $lastrow,
                     filename  => $bulkins_file->filename(),
                     sql       => $ins_sql,
                  );
               });
            }
            $ins_sth ||= $ins_row; # Default to the sth decided before.
            my $success = do_with_retries($o, 'bulk_inserting', sub {
               $ins_sth->execute($bulkins_file->filename());
               MKDEBUG && _d('Bulk inserted', $del_row->rows, 'rows');
               $statistics{INSERT} += $ins_sth->rows;
            });
            if ( $success != $ALL_IS_WELL ) {
               $retries = -1;
               last ROW; # unlike other places, don't do 'next'
            }
         }

         if ( $bulk_del ) {
            if ( $src->{plugin} ) {
               trace('before_bulk_delete', sub {
                  $src->{plugin}->before_bulk_delete(
                     first_row => $first_row,
                     last_row  => $lastrow,
                  );
               });
            }
            if ( !$o->get('no-delete') ) {
               my $success = do_with_retries($o, 'bulk_deleting', sub {
                  $del_row->execute(
                     @{$first_row}[@bulkdel_slice],
                     @{$lastrow}[@bulkdel_slice],
                  );
                  MKDEBUG && _d('Bulk deleted', $del_row->rows, 'rows');
                  $statistics{DELETE} += $del_row->rows;
               });
               if ( $success != $ALL_IS_WELL ) {
                  $retries = -1;
                  last ROW; # unlike other places, don't do 'next'
               }
            }
         }

         # ###################################################################
         # This code is for normal operation AND bulk operation.
         # ###################################################################
         commit($o, 1) if $commit_each;
         $get_sth = $get_next;

         MKDEBUG && _d('Fetching rows in next chunk');
         trace('select', sub {
            my $select_start = time;
            $get_sth->execute(@{$lastrow}[@asc_slice]);
            $last_select_time = time - $select_start;
            MKDEBUG && _d('Fetched', $get_sth->rows, 'rows');
            $statistics{SELECT} += $get_sth->rows;
         });

         # Reset $first_row to the first row of this new chunk.
         @beginning_of_txn = @{$lastrow}[@asc_slice] unless $txn_cnt;
         $row              = $get_sth->fetchrow_arrayref();
         $first_row        = $row ? [ @$row ] : undef;

         if ( $o->get('bulk-insert') ) {
            $bulkins_file = File::Temp->new( SUFFIX => 'mk-archiver' )
               or die "Cannot open temp file: $OS_ERROR\n";
         }
      }  # no next row (do bulk operations)
      else {
         MKDEBUG && _d('Got another row in this chunk');
      }

      # Check slave lag and wait if slave is too far behind.
      if ( $lag_dbh ) {
         my $lag = $ms->get_slave_lag($lag_dbh);
         while ( !defined $lag || $lag > $o->get('max-lag') ) {
            MKDEBUG && _d('Sleeping: slave lag is', $lag);
            sleep($o->get('check-interval'));
            $lag = $ms->get_slave_lag($lag_dbh);
         }
      }

      # Sleep between rows.
      if( my $sleep_time = $o->get('sleep') ) {
         $sleep_time = $last_select_time * $o->get('sleep-coef')
            if $o->get('sleep-coef');
         MKDEBUG && _d('Sleeping', $sleep_time);
         trace('sleep', sub {
            sleep($sleep_time);
         });
      }
   }  # ROW 
   MKDEBUG && _d('Done fetching rows');

   # Transactions might still be open, etc
   commit($o, $txnsize || $commit_each);
   if ( $archive_file && $archive_fh ) {
      close $archive_fh
         or die "Cannot close $archive_file: $OS_ERROR\n";
   }

   if ( !$quiet && $o->get('progress') ) {
      printf("%19s %7d %7d\n", ts($now), $now - $start, $cnt);
   }

   # Tear down the plugins.
   foreach my $table ( $dst, $src ) {
      next unless $table && $table->{plugin};
      trace('after_finish', sub {
         $table->{plugin}->after_finish();
      });
   }

   # Run ANALYZE or OPTIMIZE.
   if ( $oktorun && ($o->get('analyze') || $o->get('optimize')) ) {
      my $action = $o->get('analyze') || $o->get('optimize');
      my $maint  = ($o->get('analyze') ? 'ANALYZE' : 'OPTIMIZE')
                 . ($o->get('local') ? ' /*!40101 NO_WRITE_TO_BINLOG*/' : '');
      if ( $action =~ m/s/i ) {
         trace($maint, sub {
            $src->{dbh}->do("$maint TABLE $src->{db_tbl}");
         });
      }
      if ( $action =~ m/d/i && $dst ) {
         trace($maint, sub {
            $dst->{dbh}->do("$maint TABLE $dst->{db_tbl}");
         });
      }
   } 

   # ########################################################################
   # Print statistics
   # ########################################################################
   if ( $plugin ) {
      $plugin->statistics(\%statistics, $stat_start);
   }

   if ( !$quiet && $o->get('statistics') ) {
      my $stat_stop  = gettimeofday();
      my $stat_total = $stat_stop - $stat_start;

      my $total2 = 0;
      my $maxlen = 0;
      my %summary;

      printf("Started at %s, ended at %s\n", ts($stat_start), ts($stat_stop));
      print("Source: ", $dp->as_string($src), "\n");
      print("Dest:   ", $dp->as_string($dst), "\n") if $dst;
      print(join("\n", map { "$_ " . ($statistics{$_} || 0) }
            qw(SELECT INSERT DELETE)), "\n");

      foreach my $thing ( grep { m/_(count|time)/ } keys %statistics ) {
         my ( $action, $type ) = $thing =~ m/^(.*?)_(count|time)$/;
         $summary{$action}->{$type}  = $statistics{$thing};
         $summary{$action}->{action} = $action;
         $maxlen                     = max($maxlen, length($action));
         # Just in case I get only one type of statistic for a given action (in
         # case there was a crash or CTRL-C or something).
         $summary{$action}->{time}  ||= 0;
         $summary{$action}->{count} ||= 0;
      }
      printf("%-${maxlen}s \%10s %10s %10s\n", qw(Action Count Time Pct));
      my $fmt = "%-${maxlen}s \%10d %10.4f %10.2f\n";

      foreach my $stat (
         reverse sort { $a->{time} <=> $b->{time} } values %summary )
      {
         my $pct = $stat->{time} / $stat_total * 100;
         printf($fmt, @{$stat}{qw(action count time)}, $pct);
         $total2 += $stat->{time};
      }
      printf($fmt, 'other', 0, $stat_total - $total2,
         ($stat_total - $total2) / $stat_total * 100);
   }

   # Optionally print the reason for exiting.  Do this even if --quiet is
   # specified.
   if ( $o->get('why-quit') ) {
      if ( $retries < 0 ) {
         print "Exiting because retries exceeded.\n";
      }
      elsif ( $o->get('run-time') && $now >= $end ) {
         print "Exiting because time exceeded.\n";
      }
      elsif ( -f $sentinel ) {
         print "Exiting because sentinel file $sentinel exists.\n";
      }
      elsif ( $o->get('statistics') ) {
         print "Exiting because there are no more rows.\n";
      }
   }

   $get_sth->finish() if $get_sth;
   $src->{dbh}->disconnect();
   $dst->{dbh}->disconnect() if $dst && $dst->{dbh};

   return 0;
}

# ############################################################################
# Subroutines.
# ############################################################################

# Catches signals so mk-archiver can exit gracefully.
sub finish {
   my ($signal) = @_;
   print STDERR "Exiting on SIG$signal.\n";
   $oktorun = 0;
}

# Accesses globals, but I wanted the code in one place.
sub commit {
   my ( $o, $force ) = @_;
   my $txnsize = $o->get('txn-size');
   if ( $force || ($txnsize && $txn_cnt && $cnt % $txnsize == 0) ) {
      if ( $o->get('buffer') && $archive_fh ) {
         my $archive_file = $o->get('file');
         trace('flush', sub {
            $archive_fh->flush or die "Cannot flush $archive_file: $OS_ERROR\n";
         });
      }
      if ( $dst ) {
         trace('commit', sub {
            $dst->{dbh}->commit;
         });
      }
      trace('commit', sub {
         $src->{dbh}->commit;
      });
      $txn_cnt = 0;
   }
}

# Repeatedly retries the code until retries runs out, a really bad error
# happens, or it succeeds.  This sub uses lots of global variables; I only wrote
# it to factor out some repeated code.
sub do_with_retries {
   my ( $o, $doing, $code ) = @_;
   my $retries = $o->get('retries');
   my $txnsize = $o->get('txn-size');
   my $success = $OUT_OF_RETRIES;

   RETRY:
   while ( !$success && $retries >= 0 ) {
      eval {
         trace($doing, $code);
         $success = $ALL_IS_WELL;
      };
      if ( $EVAL_ERROR ) {
         if ( $EVAL_ERROR =~ m/Lock wait timeout exceeded|Deadlock found/ ) {
            if (
               # More than one row per txn
               (
                  ($txnsize && $txnsize > 1)
                  || ($o->get('commit-each') && $o->get('limit') > 1)
               )
               # Not first row
               && $txn_cnt
               # And it's not retry-able
               && (!$can_retry || $EVAL_ERROR =~ m/Deadlock/)
            ) {
               # The txn, which is more than 1 statement, was rolled back.
               last RETRY;
            }
            else {
               # Only one statement had trouble, and the rest of the txn was
               # not rolled back.  The statement can be retried.
               --$retries;
            }
         }
         else {
            die $EVAL_ERROR;
         }
      }
   }

   if ( $success != $ALL_IS_WELL ) {
      # Must throw away everything and start the transaction over.
      if ( $retries >= 0 ) {
         warn "Deadlock or non-retryable lock wait while $doing; "
            . "rolling back $txn_cnt rows.\n";
         $success = $ROLLED_BACK;
      }
      else {
         warn "Exhausted retries while $doing; rolling back $txn_cnt rows.\n";
         $success = $OUT_OF_RETRIES;
      }
      $get_sth->finish;
      trace('rollback', sub {
         $dst->{dbh}->rollback;
      });
      trace('rollback', sub {
         $src->{dbh}->rollback;
      });
      # I wish: $archive_fh->rollback
      trace('select', sub {
         $get_sth->execute(@beginning_of_txn);
      });
      $cnt -= $txn_cnt;
      $txn_cnt = 0;
   }
   return $success;
}

# Formats a row the same way SELECT INTO OUTFILE does by default.  This is
# described in the LOAD DATA INFILE section of the MySQL manual,
# http://dev.mysql.com/doc/refman/5.0/en/load-data.html
sub escape {
   my ($row) = @_;
   return join("\t", map {
      s/([\t\n\\])/\\$1/g if defined $_;  # Escape tabs etc
      defined $_ ? $_ : '\N';             # NULL = \N
   } @$row);
}

sub ts {
   my ( $time ) = @_;
   my ( $sec, $min, $hour, $mday, $mon, $year )
      = localtime($time);
   $mon  += 1;
   $year += 1900;
   return sprintf("%d-%02d-%02dT%02d:%02d:%02d",
      $year, $mon, $mday, $hour, $min, $sec);
}

sub get_irot {
   my ( $dbh ) = @_;
   return 1 unless $vp->version_ge($dbh, '5.0.13');
   my $rows = $dbh->selectall_arrayref(
      "show variables like 'innodb_rollback_on_timeout'",
      { Slice => {} });
   return 0 unless $rows;
   return @$rows && $rows->[0]->{Value} ne 'OFF';
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
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

mk-archiver - Archive rows from a MySQL table into another table or a file.

=head1 SYNOPSIS

Usage: mk-archiver [OPTION...] --source DSN --where WHERE

mk-archiver nibbles records from a MySQL table.  The --source and --dest
arguments use DSN syntax; if COPY is yes, --dest defaults to the key's value
from --source.

Examples:

Archive all rows from oltp_server to olap_server and to a file:

  mk-archiver --source h=oltp_server,D=test,t=tbl --dest h=olap_server \
    --file '/var/log/archive/%Y-%m-%d-%D.%t'                           \
    --where "1=1" --limit 1000 --commit-each

Purge (delete) orphan rows from child table:

  mk-archiver --source h=host,D=db,t=child --purge \
    --where 'NOT EXISTS(SELECT * FROM parent WHERE col=child.col)'

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-achiver is a read-write tool.  It deletes data from the source by default, so
you should test your archiving jobs with the L<"--dry-run"> option if you're not
sure about them.  It is designed to have as little impact on production systems
as possible, but tuning with L<"--limit">, L<"--txn-size"> and similar options
might be a good idea too.

If you write or use L<"--plugin"> modules, you should ensure they are good
quality and well-tested. 

At the time of this release there is an unverified bug with
L<"--bulk-insert"> that may cause data loss.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-archiver>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-archiver is the tool I use to archive tables as described in
L<http://tinyurl.com/mysql-archiving>.  The goal is a low-impact, forward-only
job to nibble old data out of the table without impacting OLTP queries much.
You can insert the data into another table, which need not be on the same
server.  You can also write it to a file in a format suitable for LOAD DATA
INFILE.  Or you can do neither, in which case it's just an incremental DELETE.

mk-archiver is extensible via a plugin mechanism.  You can inject your own
code to add advanced archiving logic that could be useful for archiving
dependent data, applying complex business rules, or building a data warehouse
during the archiving process.

You need to choose values carefully for some options.  The most important are
L<"--limit">, L<"--retries">, and L<"--txn-size">.

The strategy is to find the first row(s), then scan some index forward-only to
find more rows efficiently.  Each subsequent query should not scan the entire
table; it should seek into the index, then scan until it finds more archivable
rows.  Specifying the index with the 'i' part of the L<"--source"> argument can
be crucial for this; use L<"--dry-run"> to examine the generated queries and be
sure to EXPLAIN them to see if they are efficient (most of the time you probably
want to scan the PRIMARY key, which is the default).  Even better, profile
mk-archiver with mk-query-profiler and make sure it is not scanning the whole
table every query.

You can disable the seek-then-scan optimizations partially or wholly with
L<"--no-ascend"> and L<"--ascend-first">.  Sometimes this may be more efficient
for multi-column keys.  Be aware that mk-archiver is built to start at the
beginning of the index it chooses and scan it forward-only.  This might result
in long table scans if you're trying to nibble from the end of the table by an
index other than the one it prefers.  See L<"--source"> and read the
documentation on the C<i> part if this applies to you.

=head1 OUTPUT

If you specify L<"--progress">, the output is a header row, plus status output
at intervals.  Each row in the status output lists the current date and time,
how many seconds mk-archiver has been running, and how many rows it has
archived.

If you specify L<"--statistics">, C<mk-archiver> outputs timing and other
information to help you identify which part of your archiving process takes the
most time.

=head1 ERROR-HANDLING

mk-archiver tries to catch signals and exit gracefully; for example, if you
send it SIGTERM (Ctrl-C on UNIX-ish systems), it will catch the signal, print a
message about the signal, and exit fairly normally.  It will not execute
L<"--analyze"> or L<"--optimize">, because these may take a long time to finish.
It will run all other code normally, including calling after_finish() on any
plugins (see L<"EXTENDING">).

In other words, a signal, if caught, will break out of the main archiving
loop and skip optimize/analyze.

=head1 OPTIONS

Specify at least one of L<"--dest">, L<"--file">, or L<"--purge">.

L<"--ignore"> and L<"--replace"> are mutually exclusive.

L<"--txn-size"> and L<"--commit-each"> are mutually exclusive.

L<"--low-priority-insert"> and L<"--delayed-insert"> are mutually exclusive.

L<"--share-lock"> and L<"--for-update"> are mutually exclusive.

L<"--analyze"> and L<"--optimize"> are mutually exclusive.

L<"--no-ascend"> and L<"--no-delete"> are mutually exclusive.

DSN values in L<"--dest"> default to values from L<"--source"> if COPY is yes.

=over

=item --analyze

type: string

Run ANALYZE TABLE afterwards on L<"--source"> and/or L<"--dest">.

Runs ANALYZE TABLE after finishing.  The argument is an arbitrary string.  If it
contains the letter 's', the source will be analyzed.  If it contains 'd', the
destination will be analyzed.  You can specify either or both.  For example, the
following will analyze both:

  --analyze=ds

See L<http://dev.mysql.com/doc/en/analyze-table.html> for details on ANALYZE
TABLE.

=item --ascend-first

Ascend only first column of index.

If you do want to use the ascending index optimization (see L<"--no-ascend">),
but do not want to incur the overhead of ascending a large multi-column index,
you can use this option to tell mk-archiver to ascend only the leftmost column
of the index.  This can provide a significant performance boost over not
ascending the index at all, while avoiding the cost of ascending the whole
index.

See L<"EXTENDING"> for a discussion of how this interacts with plugins.

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --buffer

Buffer output to L<"--file"> and flush at commit.

Disables autoflushing to L<"--file"> and flushes L<"--file"> to disk only when a
transaction commits.  This typically means the file is block-flushed by the
operating system, so there may be some implicit flushes to disk between
commits as well.  The default is to flush L<"--file"> to disk after every row.

The danger is that a crash might cause lost data.

The performance increase I have seen from using L<"--buffer"> is around 5 to 15
percent.  Your mileage may vary.

=item --bulk-delete

Delete each chunk with a single statement (implies L<"--commit-each">).

Delete each chunk of rows in bulk with a single C<DELETE> statement.  The
statement deletes every row between the first and last row of the chunk,
inclusive.  It implies L<"--commit-each">, since it would be a bad idea to
C<INSERT> rows one at a time and commit them before the bulk C<DELETE>.

The normal method is to delete every row by its primary key.  Bulk deletes might
be a lot faster.  B<They also might not be faster> if you have a complex
C<WHERE> clause.

This option completely defers all C<DELETE> processing until the chunk of rows
is finished.  If you have a plugin on the source, its C<before_delete> method
will not be called.  Instead, its C<before_bulk_delete> method is called later.

B<WARNING>: if you have a plugin on the source that sometimes doesn't return
true from C<is_archivable()>, you should use this option only if you understand
what it does.  If the plugin instructs C<mk-archiver> not to archive a row,
it will still be deleted by the bulk delete!

=item --[no]bulk-delete-limit

default: yes

Add L<"--limit"> to L<"--bulk-delete"> statement.

This is an advanced option and you should not disable it unless you know what
you are doing and why!  By default, L<"--bulk-delete"> appends a L<"--limit">
clause to the bulk delete SQL statement.  In certain cases, this clause can be
omitted by specifying C<--no-bulk-delete-limit>.  L<"--limit"> must still be
specified.

=item --bulk-insert

Insert each chunk with LOAD DATA INFILE (implies L<"--bulk-delete"> L<"--commit-each">).

Insert each chunk of rows with C<LOAD DATA LOCAL INFILE>.  This may be much
faster than inserting a row at a time with C<INSERT> statements.  It is
implemented by creating a temporary file for each chunk of rows, and writing the
rows to this file instead of inserting them.  When the chunk is finished, it
uploads the rows.

To protect the safety of your data, this option forces bulk deletes to be used.
It would be unsafe to delete each row as it is found, before inserting the rows
into the destination first.  Forcing bulk deletes guarantees that the deletion
waits until the insertion is successful.

The L<"--low-priority-insert">, L<"--replace">, and L<"--ignore"> options work
with this option, but L<"--delayed-insert"> does not.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
without the utf8 layer, and runs SET NAMES after connecting to MySQL.

See also L<"--[no]check-charset">.

=item --[no]check-charset

default: yes

Ensure connection and table character sets are the same.  Disabling this check
may cause text to be erroneously converted from one character set to another
(usually from utf8 to latin1) which may cause data loss or mojibake.  Disabling
this check may be useful or necessary when character set conversions are
intended.

=item --[no]check-columns

default: yes

Ensure L<"--source"> and L<"--dest"> have same columns.

Enabled by default; causes mk-archiver to check that the source and destination
tables have the same columns.  It does not check column order, data type, etc.
It just checks that all columns in the source exist in the destination and
vice versa.  If there are any differences, mk-archiver will exit with an
error.

To disable this check, specify --no-check-columns.

=item --check-interval

type: time; default: 1s

How often to check for slave lag if L<"--check-slave-lag"> is given.

=item --check-slave-lag

type: string

Pause archiving until the specified DSN's slave lag is less than L<"--max-lag">.

=item --columns

short form: -c; type: array

Comma-separated list of columns to archive.

Specify a comma-separated list of columns to fetch, write to the file, and
insert into the destination table.  If specified, mk-archiver ignores other
columns unless it needs to add them to the C<SELECT> statement for ascending an
index or deleting rows.  It fetches and uses these extra columns internally, but
does not write them to the file or to the destination table.  It I<does> pass
them to plugins.

See also L<"--primary-key-only">.

=item --commit-each

Commit each set of fetched and archived rows (disables L<"--txn-size">).

Commits transactions and flushes L<"--file"> after each set of rows has been
archived, before fetching the next set of rows, and before sleeping if
L<"--sleep"> is specified.  Disables L<"--txn-size">; use L<"--limit"> to
control the transaction size with L<"--commit-each">.

This option is useful as a shortcut to make L<"--limit"> and L<"--txn-size"> the
same value, but more importantly it avoids transactions being held open while
searching for more rows.  For example, imagine you are archiving old rows from
the beginning of a very large table, with L<"--limit"> 1000 and L<"--txn-size">
1000.  After some period of finding and archiving 1000 rows at a time,
mk-archiver finds the last 999 rows and archives them, then executes the next
SELECT to find more rows.  This scans the rest of the table, but never finds any
more rows.  It has held open a transaction for a very long time, only to
determine it is finished anyway.  You can use L<"--commit-each"> to avoid this.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --delayed-insert

Add the DELAYED modifier to INSERT statements.

Adds the DELAYED modifier to INSERT or REPLACE statements.  See
L<http://dev.mysql.com/doc/en/insert.html> for details.

=item --dest

type: DSN

DSN specifying the table to archive to.

This item specifies a table into which mk-archiver will insert rows
archived from L<"--source">.  It uses the same key=val argument format as
L<"--source">.  Most missing values default to the same values as
L<"--source">, so you don't have to repeat options that are the same in
L<"--source"> and L<"--dest">.  Use the L<"--help"> option to see which values
are copied from L<"--source">.

B<WARNING>: Using a default options file (F) DSN option that defines a
socket for L<"--source"> causes mk-archiver to connect to L<"--dest"> using
that socket unless another socket for L<"--dest"> is specified.  This
means that mk-archiver may incorrectly connect to L<"--source"> when it
connects to L<"--dest">.  For example:

  --source F=host1.cnf,D=db,t=tbl --dest h=host2

When mk-archiver connects to L<"--dest">, host2, it will connect via the
L<"--source">, host1, socket defined in host1.cnf.

=item --dry-run

Print queries and exit without doing anything.

Causes mk-archiver to exit after printing the filename and SQL statements
it will use.

=item --file

type: string

File to archive to, with DATE_FORMAT()-like formatting.

Filename to write archived rows to.  A subset of MySQL's DATE_FORMAT()
formatting codes are allowed in the filename, as follows:

   %d    Day of the month, numeric (01..31)
   %H    Hour (00..23)
   %i    Minutes, numeric (00..59)
   %m    Month, numeric (01..12)
   %s    Seconds (00..59)
   %Y    Year, numeric, four digits

You can use the following extra format codes too:

   %D    Database name
   %t    Table name

Example:

   --file '/var/log/archive/%Y-%m-%d-%D.%t'

The file's contents are in the same format used by SELECT INTO OUTFILE, as
documented in the MySQL manual: rows terminated by newlines, columns
terminated by tabs, NULL characters are represented by \N, and special
characters are escaped by \.  This lets you reload a file with LOAD DATA
INFILE's default settings.

If you want a column header at the top of the file, see L<"--header">.  The file
is auto-flushed by default; see L<"--buffer">.

=item --for-update

Adds the FOR UPDATE modifier to SELECT statements.

For details, see L<http://dev.mysql.com/doc/en/innodb-locking-reads.html>.

=item --header

Print column header at top of L<"--file">.

Writes column names as the first line in the file given by L<"--file">.  If the
file exists, does not write headers; this keeps the file loadable with LOAD
DATA INFILE in case you append more output to it.

=item --help

Show help and exit.

=item --high-priority-select

Adds the HIGH_PRIORITY modifier to SELECT statements.

See L<http://dev.mysql.com/doc/en/select.html> for details.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore

Use IGNORE for INSERT statements.

Causes INSERTs into L<"--dest"> to be INSERT IGNORE.

=item --limit

type: int; default: 1

Number of rows to fetch and archive per statement.

Limits the number of rows returned by the SELECT statements that retrieve rows
to archive.  Default is one row.  It may be more efficient to increase the
limit, but be careful if you are archiving sparsely, skipping over many rows;
this can potentially cause more contention with other queries, depending on the
storage engine, transaction isolation level, and options such as
L<"--for-update">.

=item --local

Do not write OPTIMIZE or ANALYZE queries to binlog.

Adds the NO_WRITE_TO_BINLOG modifier to ANALYZE and OPTIMIZE queries.  See
L<"--analyze"> for details.

=item --low-priority-delete

Adds the LOW_PRIORITY modifier to DELETE statements.

See L<http://dev.mysql.com/doc/en/delete.html> for details.

=item --low-priority-insert

Adds the LOW_PRIORITY modifier to INSERT or REPLACE statements.

See L<http://dev.mysql.com/doc/en/insert.html> for details.

=item --max-lag

type: time; default: 1s

Pause archiving if the slave given by L<"--check-slave-lag"> lags.

This option causes mk-archiver to look at the slave every time it's about
to fetch another row.  If the slave's lag is greater than the option's value,
or if the slave isn't running (so its lag is NULL), mk-table-checksum sleeps
for L<"--check-interval"> seconds and then looks at the lag again.  It repeats
until the slave is caught up, then proceeds to fetch and archive the row.

This option may eliminate the need for L<"--sleep"> or L<"--sleep-coef">.

=item --no-ascend

Do not use ascending index optimization.

The default ascending-index optimization causes C<mk-archiver> to optimize
repeated C<SELECT> queries so they seek into the index where the previous query
ended, then scan along it, rather than scanning from the beginning of the table
every time.  This is enabled by default because it is generally a good strategy
for repeated accesses.

Large, multiple-column indexes may cause the WHERE clause to be complex enough
that this could actually be less efficient.  Consider for example a four-column
PRIMARY KEY on (a, b, c, d).  The WHERE clause to start where the last query
ended is as follows:

   WHERE (a > ?)
      OR (a = ? AND b > ?)
      OR (a = ? AND b = ? AND c > ?)
      OR (a = ? AND b = ? AND c = ? AND d >= ?)

Populating the placeholders with values uses memory and CPU, adds network
traffic and parsing overhead, and may make the query harder for MySQL to
optimize.  A four-column key isn't a big deal, but a ten-column key in which
every column allows C<NULL> might be.

Ascending the index might not be necessary if you know you are simply removing
rows from the beginning of the table in chunks, but not leaving any holes, so
starting at the beginning of the table is actually the most efficient thing to
do.

See also L<"--ascend-first">.  See L<"EXTENDING"> for a discussion of how this
interacts with plugins.

=item --no-delete

Do not delete archived rows.

Causes C<mk-archiver> not to delete rows after processing them.  This disallows
L<"--no-ascend">, because enabling them both would cause an infinite loop.

If there is a plugin on the source DSN, its C<before_delete> method is called
anyway, even though C<mk-archiver> will not execute the delete.  See
L<"EXTENDING"> for more on plugins.

=item --optimize

type: string

Run OPTIMIZE TABLE afterwards on L<"--source"> and/or L<"--dest">.

Runs OPTIMIZE TABLE after finishing.  See L<"--analyze"> for the option syntax
and L<http://dev.mysql.com/doc/en/optimize-table.html> for details on OPTIMIZE
TABLE.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file when daemonized.  The file contains the process ID of
the daemonized instance.  The PID file is removed when the daemonized instance
exits.  The program checks for the existence of the PID file when starting; if
it exists and the process with the matching PID exists, the program exits.

=item --plugin

type: string

Perl module name to use as a generic plugin.

Specify the Perl module name of a general-purpose plugin.  It is currently used
only for statistics (see L<"--statistics">) and must have C<new()> and a
C<statistics()> method.

The C<new( src => $src, dst => $dst, opts => $o )> method gets the source
and destination DSNs, and their database connections, just like the
connection-specific plugins do.  It also gets an OptionParser object (C<$o>) for
accessing command-line options (example: C<$o->get('purge');>).

The C<statistics(\%stats, $time)> method gets a hashref of the statistics
collected by the archiving job, and the time the whole job started.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --primary-key-only

Primary key columns only.

A shortcut for specifying L<"--columns"> with the primary key columns.  This is
an efficiency if you just want to purge rows; it avoids fetching the entire row,
when only the primary key columns are needed for C<DELETE> statements.  See also
L<"--purge">.

=item --progress

type: int

Print progress information every X rows.

Prints current time, elapsed time, and rows archived every X rows.

=item --purge

Purge instead of archiving; allows omitting L<"--file"> and L<"--dest">.

Allows archiving without a L<"--file"> or L<"--dest"> argument, which is
effectively a purge since the rows are just deleted.

If you just want to purge rows, consider specifying the table's primary key
columns with L<"--primary-key-only">.  This will prevent fetching all columns
from the server for no reason.

=item --quick-delete

Adds the QUICK modifier to DELETE statements.

See L<http://dev.mysql.com/doc/en/delete.html> for details.  As stated in the
documentation, in some cases it may be faster to use DELETE QUICK followed by
OPTIMIZE TABLE.  You can use L<"--optimize"> for this.

=item --quiet

short form: -q

Do not print any output, such as for L<"--statistics">.

Suppresses normal output, including the output of L<"--statistics">, but doesn't
suppress the output from L<"--why-quit">.

=item --replace

Causes INSERTs into L<"--dest"> to be written as REPLACE.

=item --retries

type: int; default: 1

Number of retries per timeout or deadlock.

Specifies the number of times mk-archiver should retry when there is an
InnoDB lock wait timeout or deadlock.  When retries are exhausted,
mk-archiver will exit with an error.

Consider carefully what you want to happen when you are archiving between a
mixture of transactional and non-transactional storage engines.  The INSERT to
L<"--dest"> and DELETE from L<"--source"> are on separate connections, so they
do not actually participate in the same transaction even if they're on the same
server.  However, mk-archiver implements simple distributed transactions in
code, so commits and rollbacks should happen as desired across the two
connections.

At this time I have not written any code to handle errors with transactional
storage engines other than InnoDB.  Request that feature if you need it.

=item --run-time

type: time

Time to run before exiting.

Optional suffix s=seconds, m=minutes, h=hours, d=days; if no suffix, s is used.

=item --[no]safe-auto-increment

default: yes

Do not archive row with max AUTO_INCREMENT.

Adds an extra WHERE clause to prevent mk-archiver from removing the newest
row when ascending a single-column AUTO_INCREMENT key.  This guards against
re-using AUTO_INCREMENT values if the server restarts, and is enabled by
default.

The extra WHERE clause contains the maximum value of the auto-increment column
as of the beginning of the archive or purge job.  If new rows are inserted while
mk-archiver is running, it will not see them.

=item --sentinel

type: string; default: /tmp/mk-archiver-sentinel

Exit if this file exists.

The presence of the file specified by L<"--sentinel"> will cause mk-archiver to
stop archiving and exit.  The default is /tmp/mk-archiver-sentinel.  You
might find this handy to stop cron jobs gracefully if necessary.  See also
L<"--stop">.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.

Specify any variables you want to be set immediately after connecting to MySQL.
These will be included in a C<SET> command.

=item --share-lock

Adds the LOCK IN SHARE MODE modifier to SELECT statements.

See L<http://dev.mysql.com/doc/en/innodb-locking-reads.html>.

=item --skip-foreign-key-checks

Disables foreign key checks with SET FOREIGN_KEY_CHECKS=0.

=item --sleep

type: int

Sleep time between fetches.

Specifies how long to sleep between SELECT statements.  Default is not to
sleep at all.  Transactions are NOT committed, and the L<"--file"> file is NOT
flushed, before sleeping.  See L<"--txn-size"> to control that.

If L<"--commit-each"> is specified, committing and flushing happens before
sleeping.

=item --sleep-coef

type: float

Calculate L<"--sleep"> as a multiple of the last SELECT time.

If this option is specified, mk-archiver will sleep for the query time of the
last SELECT multiplied by the specified coefficient.

This is a slightly more sophisticated way to throttle the SELECTs: sleep a
varying amount of time between each SELECT, depending on how long the SELECTs
are taking.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --source

type: DSN

DSN specifying the table to archive from (required).  This argument is a DSN.
See L<DSN OPTIONS> for the syntax.  Most options control how mk-archiver
connects to MySQL, but there are some extended DSN options in this tool's
syntax.  The D, t, and i options select a table to archive:

  --source h=my_server,D=my_database,t=my_tbl

The a option specifies the database to set as the connection's default with USE.
If the b option is true, it disables binary logging with SQL_LOG_BIN.  The m
option specifies pluggable actions, which an external Perl module can provide.
The only required part is the table; other parts may be read from various
places in the environment (such as options files).

The 'i' part deserves special mention.  This tells mk-archiver which index
it should scan to archive.  This appears in a FORCE INDEX or USE INDEX hint in
the SELECT statements used to fetch archivable rows.  If you don't specify
anything, mk-archiver will auto-discover a good index, preferring a C<PRIMARY
KEY> if one exists.  In my experience this usually works well, so most of the
time you can probably just omit the 'i' part.

The index is used to optimize repeated accesses to the table; mk-archiver
remembers the last row it retrieves from each SELECT statement, and uses it to
construct a WHERE clause, using the columns in the specified index, that should
allow MySQL to start the next SELECT where the last one ended, rather than
potentially scanning from the beginning of the table with each successive
SELECT.  If you are using external plugins, please see L<"EXTENDING"> for a
discussion of how they interact with ascending indexes.

The 'a' and 'b' options allow you to control how statements flow through the
binary log.  If you specify the 'b' option, binary logging will be disabled on
the specified connection.  If you specify the 'a' option, the connection will
C<USE> the specified database, which you can use to prevent slaves from
executing the binary log events with C<--replicate-ignore-db> options.  These
two options can be used as different methods to achieve the same goal: archive
data off the master, but leave it on the slave.  For example, you can run a
purge job on the master and prevent it from happening on the slave using your
method of choice.

B<WARNING>: Using a default options file (F) DSN option that defines a
socket for L<"--source"> causes mk-archiver to connect to L<"--dest"> using
that socket unless another socket for L<"--dest"> is specified.  This
means that mk-archiver may incorrectly connect to L<"--source"> when it
is meant to connect to L<"--dest">.  For example:

  --source F=host1.cnf,D=db,t=tbl --dest h=host2

When mk-archiver connects to L<"--dest">, host2, it will connect via the
L<"--source">, host1, socket defined in host1.cnf.

=item --statistics

Collect and print timing statistics.

Causes mk-archiver to collect timing statistics about what it does.  These
statistics are available to the plugin specified by L<"--plugin">

Unless you specify L<"--quiet">, C<mk-archiver> prints the statistics when it
exits.  The statistics look like this:

 Started at 2008-07-18T07:18:53, ended at 2008-07-18T07:18:53
 Source: D=db,t=table
 SELECT 4
 INSERT 4
 DELETE 4
 Action         Count       Time        Pct
 commit            10     0.1079      88.27
 select             5     0.0047       3.87
 deleting           4     0.0028       2.29
 inserting          4     0.0028       2.28
 other              0     0.0040       3.29

The first two (or three) lines show times and the source and destination tables.
The next three lines show how many rows were fetched, inserted, and deleted.

The remaining lines show counts and timing.  The columns are the action, the
total number of times that action was timed, the total time it took, and the
percent of the program's total runtime.  The rows are sorted in order of
descending total time.  The last row is the rest of the time not explicitly
attributed to anything.  Actions will vary depending on command-line options.

If L<"--why-quit"> is given, its behavior is changed slightly.  This option
causes it to print the reason for exiting even when it's just because there are
no more rows.

This option requires the standard Time::HiRes module, which is part of core Perl
on reasonably new Perl releases.

=item --stop

Stop running instances by creating the sentinel file.

Causes mk-archiver to create the sentinel file specified by L<"--sentinel"> and
exit.  This should have the effect of stopping all running instances which are
watching the same sentinel file.

=item --txn-size

type: int; default: 1

Number of rows per transaction.

Specifies the size, in number of rows, of each transaction. Zero disables
transactions altogether.  After mk-archiver processes this many rows, it
commits both the L<"--source"> and the L<"--dest"> if given, and flushes the
file given by L<"--file">.

This parameter is critical to performance.  If you are archiving from a live
server, which for example is doing heavy OLTP work, you need to choose a good
balance between transaction size and commit overhead.  Larger transactions
create the possibility of more lock contention and deadlocks, but smaller
transactions cause more frequent commit overhead, which can be significant.  To
give an idea, on a small test set I worked with while writing mk-archiver, a
value of 500 caused archiving to take about 2 seconds per 1000 rows on an
otherwise quiet MySQL instance on my desktop machine, archiving to disk and to
another table.  Disabling transactions with a value of zero, which turns on
autocommit, dropped performance to 38 seconds per thousand rows.

If you are not archiving from or to a transactional storage engine, you may
want to disable transactions so mk-archiver doesn't try to commit.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

=item --where

type: string

WHERE clause to limit which rows to archive (required).

Specifies a WHERE clause to limit which rows are archived.  Do not include the
word WHERE.  You may need to quote the argument to prevent your shell from
interpreting it.  For example:

   --where 'ts < current_date - interval 90 day'

For safety, L<"--where"> is required.  If you do not require a WHERE clause, use
L<"--where"> 1=1.

=item --why-quit

Print reason for exiting unless rows exhausted.

Causes mk-archiver to print a message if it exits for any reason other than
running out of rows to archive.  This can be useful if you have a cron job with
L<"--run-time"> specified, for example, and you want to be sure mk-archiver is
finishing before running out of time.

If L<"--statistics"> is given, the behavior is changed slightly.  It will print
the reason for exiting even when it's just because there are no more rows.

This output prints even if L<"--quiet"> is given.  That's so you can put
C<mk-archiver> in a C<cron> job and get an email if there's an abnormal exit.

=back

=head1 DSN OPTIONS

These DSN options are used to create a DSN.  Each option is given like
C<option=value>.  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the C<=> and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the L<maatkit> manpage for full details.

=over

=item * a

copy: no

Database to USE when executing queries.

=item * A

dsn: charset; copy: yes

Default character set.

=item * b

copy: no

If true, disable binlog with SQL_LOG_BIN.

=item * D

dsn: database; copy: yes

Database that contains the table.

=item * F

dsn: mysql_read_default_file; copy: yes

Only read default options from the given file

=item * h

dsn: host; copy: yes

Connect to host.

=item * i

copy: yes

Index to use.

=item * m

copy: no

Plugin module name.

=item * p

dsn: password; copy: yes

Password to use when connecting.

=item * P

dsn: port; copy: yes

Port number to use for connection.

=item * S

dsn: mysql_socket; copy: yes

Socket file to use for connection.

=item * t

copy: yes

Table to archive from/to.

=item * u

dsn: user; copy: yes

User for login if not current user.

=back

=head1 EXTENDING

mk-archiver is extensible by plugging in external Perl modules to handle some
logic and/or actions.  You can specify a module for both the L<"--source"> and
the L<"--dest">, with the 'm' part of the specification.  For example:

   --source D=test,t=test1,m=My::Module1 --dest m=My::Module2,t=test2

This will cause mk-archiver to load the My::Module1 and My::Module2 packages,
create instances of them, and then make calls to them during the archiving
process.

You can also specify a plugin with L<"--plugin">.

The module must provide this interface:

=over

=item new(dbh => $dbh, db => $db_name, tbl => $tbl_name)

The plugin's constructor is passed a reference to the database handle, the
database name, and table name.  The plugin is created just after mk-archiver
opens the connection, and before it examines the table given in the arguments.
This gives the plugin a chance to create and populate temporary tables, or do
other setup work.

=item before_begin(cols => \@cols, allcols => \@allcols)

This method is called just before mk-archiver begins iterating through rows
and archiving them, but after it does all other setup work (examining table
structures, designing SQL queries, and so on).  This is the only time
mk-archiver tells the plugin column names for the rows it will pass the
plugin while archiving.

The C<cols> argument is the column names the user requested to be archived,
either by default or by the L<"--columns"> option.  The C<allcols> argument is
the list of column names for every row mk-archiver will fetch from the source
table.  It may fetch more columns than the user requested, because it needs some
columns for its own use.  When subsequent plugin functions receive a row, it is
the full row containing all the extra columns, if any, added to the end.

=item is_archivable(row => \@row)

This method is called for each row to determine whether it is archivable.  This
applies only to L<"--source">.  The argument is the row itself, as an arrayref.
If the method returns true, the row will be archived; otherwise it will be
skipped.

Skipping a row adds complications for non-unique indexes.  Normally
mk-archiver uses a WHERE clause designed to target the last processed row as
the place to start the scan for the next SELECT statement.  If you have skipped
the row by returning false from is_archivable(), mk-archiver could get into
an infinite loop because the row still exists.  Therefore, when you specify a
plugin for the L<"--source"> argument, mk-archiver will change its WHERE clause
slightly.  Instead of starting at "greater than or equal to" the last processed
row, it will start "strictly greater than."  This will work fine on unique
indexes such as primary keys, but it may skip rows (leave holes) on non-unique
indexes or when ascending only the first column of an index.

C<mk-archiver> will change the clause in the same way if you specify
L<"--no-delete">, because again an infinite loop is possible.

If you specify the L<"--bulk-delete"> option and return false from this method,
C<mk-archiver> may not do what you want.  The row won't be archived, but it will
be deleted, since bulk deletes operate on ranges of rows and don't know which
rows the plugin selected to keep.

If you specify the L<"--bulk-insert"> option, this method's return value will
influence whether the row is written to the temporary file for the bulk insert,
so bulk inserts will work as expected.  However, bulk inserts require bulk
deletes.

=item before_delete(row => \@row)

This method is called for each row just before it is deleted.  This applies only
to L<"--source">.  This is a good place for you to handle dependencies, such as
deleting things that are foreign-keyed to the row you are about to delete.  You
could also use this to recursively archive all dependent tables.

This plugin method is called even if L<"--no-delete"> is given, but not if
L<"--bulk-delete"> is given.

=item before_bulk_delete(first_row => \@row, last_row => \@row)

This method is called just before a bulk delete is executed.  It is similar to
the C<before_delete> method, except its arguments are the first and last row of
the range to be deleted.  It is called even if L<"--no-delete"> is given.

=item before_insert(row => \@row)

This method is called for each row just before it is inserted.  This applies
only to L<"--dest">.  You could use this to insert the row into multiple tables,
perhaps with an ON DUPLICATE KEY UPDATE clause to build summary tables in a data
warehouse.

This method is not called if L<"--bulk-insert"> is given.

=item before_bulk_insert(first_row => \@row, last_row => \@row, filename => bulk_insert_filename)

This method is called just before a bulk insert is executed.  It is similar to
the C<before_insert> method, except its arguments are the first and last row of
the range to be deleted.

=item custom_sth(row => \@row, sql => $sql)

This method is called just before inserting the row, but after
L<"before_insert()">.  It allows the plugin to specify different C<INSERT>
statement if desired.  The return value (if any) should be a DBI statement
handle.  The C<sql> parameter is the SQL text used to prepare the default
C<INSERT> statement.  This method is not called if you specify
L<"--bulk-insert">.

If no value is returned, the default C<INSERT> statement handle is used.

This method applies only to the plugin specified for L<"--dest">, so if your
plugin isn't doing what you expect, check that you've specified it for the
destination and not the source.

=item custom_sth_bulk(first_row => \@row, last_row => \@row, sql => $sql, filename => $bulk_insert_filename)

If you've specified L<"--bulk-insert">, this method is called just before the
bulk insert, but after L<"before_bulk_insert()">, and the arguments are
different.

This method's return value etc is similar to the L<"custom_sth()"> method.

=item after_finish()

This method is called after mk-archiver exits the archiving loop, commits all
database handles, closes L<"--file">, and prints the final statistics, but
before mk-archiver runs ANALYZE or OPTIMIZE (see L<"--analyze"> and
L<"--optimize">).

=back

If you specify a plugin for both L<"--source"> and L<"--dest">, mk-archiver
constructs, calls before_begin(), and calls after_finish() on the two plugins in
the order L<"--source">, L<"--dest">.

mk-archiver assumes it controls transactions, and that the plugin will NOT
commit or roll back the database handle.  The database handle passed to the
plugin's constructor is the same handle mk-archiver uses itself.  Remember
that L<"--source"> and L<"--dest"> are separate handles.

A sample module might look like this:

   package My::Module;

   sub new {
      my ( $class, %args ) = @_;
      return bless(\%args, $class);
   }

   sub before_begin {
      my ( $self, %args ) = @_;
      # Save column names for later
      $self->{cols} = $args{cols};
   }

   sub is_archivable {
      my ( $self, %args ) = @_;
      # Do some advanced logic with $args{row}
      return 1;
   }

   sub before_delete {} # Take no action
   sub before_insert {} # Take no action
   sub custom_sth    {} # Take no action
   sub after_finish  {} # Take no action

   1;

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

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-archiver>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 ACKNOWLEDGMENTS

Thanks to the following people, and apologies to anyone I've omitted:

Andrew O'Brien,

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

=head1 AUTHOR

Baron Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.27 Distrib 7540 $Revision: 7531 $.

=cut

__END__
:endofperl
