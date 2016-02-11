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

# This is mk-loadavg, a program to measure the load on a MySQL server and take
# action when it exceeds boundaries.
#
# This program is copyright 2008-2011 Baron Schwartz.
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

our $VERSION = '0.9.7';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7460 $ =~ m/(\d+)/g, 0));

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
# InnoDBStatusParser package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/InnoDBStatusParser.pm
#   trunk/common/t/InnoDBStatusParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package InnoDBStatusParser;


use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;


my $d  = qr/(\d+)/;                    # Digit
my $f  = qr/(\d+\.\d+)/;               # Float
my $t  = qr/(\d+ \d+)/;                # Transaction ID
my $i  = qr/((?:\d{1,3}\.){3}\d+)/;    # IP address
my $n  = qr/([^`\s]+)/;                # MySQL object name
my $w  = qr/(\w+)/;                    # Words
my $fl = qr/([\w\.\/]+) line $d/;      # Filename and line number
my $h  = qr/((?:0x)?[0-9a-f]*)/;       # Hex
my $s  = qr/(\d{6} .\d:\d\d:\d\d)/;    # InnoDB timestamp

sub ts_to_time {
   my ( $ts ) = @_;
   sprintf('200%d-%02d-%02d %02d:%02d:%02d',
      $ts =~ m/(\d\d)(\d\d)(\d\d) +(\d+):(\d+):(\d+)/);
}

my %is_proc_info = (
   'After create'                 => 1,
   'Execution of init_command'    => 1,
   'FULLTEXT initialization'      => 1,
   'Reopen tables'                => 1,
   'Repair done'                  => 1,
   'Repair with keycache'         => 1,
   'System lock'                  => 1,
   'Table lock'                   => 1,
   'Thread initialized'           => 1,
   'User lock'                    => 1,
   'copy to tmp table'            => 1,
   'discard_or_import_tablespace' => 1,
   'end'                          => 1,
   'got handler lock'             => 1,
   'got old table'                => 1,
   'init'                         => 1,
   'key cache'                    => 1,
   'locks'                        => 1,
   'malloc'                       => 1,
   'query end'                    => 1,
   'rename result table'          => 1,
   'rename'                       => 1,
   'setup'                        => 1,
   'statistics'                   => 1,
   'status'                       => 1,
   'table cache'                  => 1,
   'update'                       => 1,
);

my ( $COLS, $PATTERN ) = (0, 1);
my %parse_rules_for = (

   "BACKGROUND THREAD" => {
      rules => [
         [
            [qw(
               Innodb_srv_main_1_second_loops
               Innodb_srv_main_sleeps
               Innodb_srv_main_10_second_loops
               Innodb_srv_main_background_loops
               Innodb_srv_main_flush_loops
            )],
            qr/^srv_master_thread loops: $d 1_second, $d sleeps, $d 10_second, $d background, $d flush$/m,
         ],
         [
            [qw(
               Innodb_srv_sync_flush
               Innodb_srv_async_flush
            )],
            qr/^srv_master_thread log flush: $d sync, $d async$/m,
         ],
         [
            [qw(
               Innodb_flush_from_dirty_buffer
               Innodb_flush_from_other
               Innodb_flush_from_checkpoint
               Innodb_flush_from_log_io_complete
               Innodb_flush_from_log_write_up_to
               Innodb_flush_from_archive
            )],
            qr/^fsync callers: $d buffer pool, $d other, $d checkpoint, $d log aio, $d log sync, $d archive$/m,
         ],
      ],
      customcode => sub{},
   },

   "SEMAPHORES" => {
      rules => [
         [
            [qw(
               Innodb_lock_wait_timeouts
            )],
            qr/^Lock wait timeouts $d$/m,
         ],
         [
            [qw(
               Innodb_wait_array_reservation_count
               Innodb_wait_array_signal_count
            )],
            qr/^OS WAIT ARRAY INFO: reservation count $d, signal count $d$/m,
         ],
         [
            [qw(
               Innodb_mutex_spin_waits
               Innodb_mutex_spin_rounds
               Innodb_mutex_os_waits
            )],
            qr/^Mutex spin waits $d, rounds $d, OS waits $d$/m,
         ],
         [
            [qw(
               Innodb_mutex_rw_shared_spins
               Innodb_mutex_rw_shared_os_waits
               Innodb_mutex_rw_excl_spins
               Innodb_mutex_rw_excl_os_waits
            )],
            qr/^RW-shared spins $d, OS waits $d; RW-excl spins $d, OS waits $d$/m,
         ],
      ],
      customcode => sub {},
   },

   'LATEST FOREIGN KEY ERROR' => {
      rules => [
         [
            [qw(
               Innodb_fk_time
            )],
            qr/^$s/m,
         ],
         [
            [qw(
               Innodb_fk_child_db
               Innodb_fk_child_table
            )],
            qr{oreign key constraint (?:fails for|of) table `?(.*?)`?/`?(.*?)`?:$}m,
         ],
         [
            [qw(
               Innodb_fk_name
               Innodb_fk_child_cols
               Innodb_fk_parent_db
               Innodb_fk_parent_table
               Innodb_fk_parent_cols
            )],
            qr/CONSTRAINT `?$n`? FOREIGN KEY \((.+?)\) REFERENCES (?:`?$n`?\.)?`?$n`? \((.+?)\)/m,
         ],
         [
            [qw(
               Innodb_fk_child_index
            )],
            qr/(?:in child table, in index|foreign key in table is) `?$n`?/m,
         ],
         [
            [qw(
               Innodb_fk_parent_index
            )],
            qr/in parent table \S+ in index `$n`/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $status->{Innodb_fk_time} ) {
            $status->{Innodb_fk_time} = ts_to_time($status->{Innodb_fk_time});
         }
         $status->{Innodb_fk_parent_db} ||= $status->{Innodb_fk_child_db};
         if ( $text =~ m/^there is no index/m ) {
            $status->{Innodb_fk_reason} = 'No index or type mismatch';
         }
         elsif ( $text =~ m/closest match we can find/ ) {
            $status->{Innodb_fk_reason} = 'No matching row';
         }
         elsif ( $text =~ m/, there is a record/ ) {
            $status->{Innodb_fk_reason} = 'Orphan row';
         }
         elsif ( $text =~ m/Cannot resolve table name|nor its .ibd file/ ) {
            $status->{Innodb_fk_reason} = 'No such parent table';
         }
         elsif ( $text =~ m/Cannot (?:DISCARD|drop)/ ) {
            $status->{Innodb_fk_reason} = 'Table is referenced';
            @{$status}{qw(
               Innodb_fk_parent_db Innodb_fk_parent_table
               Innodb_fk_child_db Innodb_fk_child_table
            )}
            = $text =~ m{table `$n/$n`\nbecause it is referenced by `$n/$n`};
         }
      },
   },

   'LATEST DETECTED DEADLOCK' => {
      rules => [
         [
            [qw(
               Innodb_deadlock_time
            )],
            qr/^$s$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $status->{Innodb_deadlock_time} ) {
            $status->{Innodb_deadlock_time}
               = ts_to_time($status->{Innodb_deadlock_time});
         }
      },
   },

   'TRANSACTIONS' => {
      rules => [
         [
            [qw(Innodb_transaction_counter)],
            qr/^Trx id counter $t$/m,
         ],
         [
            [qw(
               Innodb_purged_to
               Innodb_undo_log_record
            )],
            qr/^Purge done for trx's n:o < $t undo n:o < $t$/m,
         ],
         [
            [qw(Innodb_history_list_length)],
            qr/^History list length $d$/m,
         ],
         [
            [qw(Innodb_lock_struct_count)],
            qr/^Total number of lock structs in row lock hash table $d$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         $status->{Innodb_transactions_truncated}
            = $text =~ m/^\.\.\. truncated\.\.\.$/m ? 1 : 0;
         my @txns = $text =~ m/(^---TRANSACTION)/mg;
         $status->{Innodb_transactions} = scalar(@txns);
      },
   },

   'FILE I/O' => {
      rules => [
         [
            [qw(
               Innodb_pending_aio_reads
               Innodb_pending_aio_writes
            )],
            qr/^Pending normal aio reads: $d, aio writes: $d,$/m,
         ],
         [
            [qw(
               Innodb_insert_buffer_pending_reads
               Innodb_log_pending_io
               Innodb_pending_sync_io
            )],
            qr{^ ibuf aio reads: $d, log i/o's: $d, sync i/o's: $d$}m,
         ],
         [
            [qw(
               Innodb_os_log_pending_fsyncs
               Innodb_buffer_pool_pending_fsyncs
            )],
            qr/^Pending flushes \(fsync\) log: $d; buffer pool: $d$/m,
         ],
         [
            [qw(
               Innodb_data_reads
               Innodb_data_writes
               Innodb_data_fsyncs
            )],
            qr/^$d OS file reads, $d OS file writes, $d OS fsyncs$/m,
         ],
         [
            [qw(
               Innodb_data_reads_sec
               Innodb_data_bytes_per_read
               Innodb_data_writes_sec
               Innodb_data_fsyncs_sec
            )],
            qr{^$f reads/s, $d avg bytes/read, $f writes/s, $f fsyncs/s$}m,
         ],
         [
            [qw(
               Innodb_data_pending_preads
               Innodb_data_pending_pwrites
            )],
            qr/$d pending preads, $d pending pwrites$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         my @thds = $text =~ m/^I.O thread $d state:/gm;
         $status->{Innodb_num_io_threads} = scalar(@thds);
         $status->{Innodb_data_pending_fsyncs}
            = $status->{Innodb_os_log_pending_fsyncs}
            + $status->{Innodb_buffer_pool_pending_fsyncs};
      },
   },

   'INSERT BUFFER AND ADAPTIVE HASH INDEX' => {
      rules => [
         [
            [qw(
               Innodb_insert_buffer_size
               Innodb_insert_buffer_free_list_length
               Innodb_insert_buffer_segment_size
            )],
            qr/^Ibuf(?: for space 0)?: size $d, free list len $d, seg size $d,$/m,
         ],
         [
            [qw(
               Innodb_insert_buffer_inserts
               Innodb_insert_buffer_merged_records
               Innodb_insert_buffer_merges
            )],
            qr/^$d inserts, $d merged recs, $d merges$/m,
         ],
         [
            [qw(
               Innodb_hash_table_size
               Innodb_hash_table_used_cells
               Innodb_hash_table_buf_frames_reserved
            )],
            qr/^Hash table size $d, used cells $d, node heap has $d buffer\(s\)$/m,
         ],
         [
            [qw(
               Innodb_hash_searches_sec
               Innodb_nonhash_searches_sec
            )],
            qr{^$f hash searches/s, $f non-hash searches/s$}m,
         ],
      ],
      customcode => sub {},
   },

   'LOG' => {
      rules => [
         [
            [qw(
               Innodb_log_sequence_no
            )],
            qr/Log sequence number \s*(\d.*)$/m,
         ],
         [
            [qw(
               Innodb_log_flushed_to
            )],
            qr/Log flushed up to \s*(\d.*)$/m,
         ],
         [
            [qw(
               Innodb_log_last_checkpoint
            )],
            qr/Last checkpoint at \s*(\d.*)$/m,
         ],
         [
            [qw(
               Innodb_log_pending_writes
               Innodb_log_pending_chkp_writes
            )],
            qr/$d pending log writes, $d pending chkp writes/m,
         ],
         [
            [qw(
               Innodb_log_ios
               Innodb_log_ios_sec
            )],
            qr{$d log i/o's done, $f log i/o's/second}m,
         ],
         [
            [qw(
               Innodb_log_caller_write_buffer_pool
               Innodb_log_caller_write_background_sync
               Innodb_log_caller_write_background_async
               Innodb_log_caller_write_internal
               Innodb_log_caller_write_checkpoint_sync
               Innodb_log_caller_write_checkpoint_async
               Innodb_log_caller_write_log_archive
               Innodb_log_caller_write_commit_sync
               Innodb_log_caller_write_commit_async
            )],
            qr/^log sync callers: $d buffer pool, background $d sync and $d async, $d internal, checkpoint $d sync and $d async, $d archive, commit $d sync and $d async$/m,
         ],
         [
            [qw(
               Innodb_log_syncer_write_buffer_pool
               Innodb_log_syncer_write_background_sync
               Innodb_log_syncer_write_background_async
               Innodb_log_syncer_write_internal
               Innodb_log_syncer_write_checkpoint_sync
               Innodb_log_syncer_write_checkpoint_async
               Innodb_log_syncer_write_log_archive
               Innodb_log_syncer_write_commit_sync
               Innodb_log_syncer_write_commit_async
            )],
            qr/^log sync syncers: $d buffer pool, background $d sync and $d async, $d internal, checkpoint $d sync and $d async, $d archive, commit $d sync and $d async$/m,
         ],
      ],
      customcode => sub {},
   },

   'BUFFER POOL AND MEMORY' => {
      rules => [
         [
            [qw(
               Innodb_total_memory_allocated
               Innodb_common_memory_allocated
            )],
            qr/^Total memory allocated $d; in additional pool allocated $d$/m,
         ],
         [
            [qw(
               Innodb_dictionary_memory_allocated
            )],
            qr/Dictionary memory allocated $d/m,
         ],
         [
            [qw(
               Innodb_awe_memory_allocated
            )],
            qr/$d MB of AWE memory/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_awe_memory_frames
            )],
            qr/AWE: Buffer pool memory frames\s+$d/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_awe_mapped
            )],
            qr/AWE: Database pages and free buffers mapped in frames\s+$d/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_total
            )],
            qr/^Buffer pool size\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_free
            )],
            qr/^Free buffers\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_data
            )],
            qr/^Database pages\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_dirty
            )],
            qr/^Modified db pages\s*$d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pending_reads
            )],
            qr/^Pending reads $d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pending_data_writes
               Innodb_buffer_pool_pending_dirty_writes
               Innodb_buffer_pool_pending_single_writes
            )],
            qr/Pending writes: LRU $d, flush list $d, single page $d/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_read
               Innodb_buffer_pool_pages_created
               Innodb_buffer_pool_pages_written
            )],
            qr/^Pages read $d, created $d, written $d$/m,
         ],
         [
            [qw(
               Innodb_buffer_pool_pages_read_sec
               Innodb_buffer_pool_pages_created_sec
               Innodb_buffer_pool_pages_written_sec
            )],
            qr{^$f reads/s, $f creates/s, $f writes/s$}m,
         ],
         [
            [qw(
               Innodb_buffer_pool_awe_pages_remapped_sec
            )],
            qr{^AWE: $f page remaps/s$}m,
         ],
         [
            [qw(
               Innodb_buffer_pool_hit_rate
            )],
            qr/^Buffer pool hit rate $d/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( defined $status->{Innodb_buffer_pool_hit_rate} ) {
            $status->{Innodb_buffer_pool_hit_rate} /= 1000;
         }
         else {
            $status->{Innodb_buffer_pool_hit_rate} = 1;
         }
      },
   },

   'ROW OPERATIONS' => {
      rules => [
         [
            [qw(
               Innodb_threads_inside_kernel
               Innodb_threads_queued
            )],
            qr/^$d queries inside InnoDB, $d queries in queue$/m,
         ],
         [
            [qw(
               Innodb_read_views_open
            )],
            qr/^$d read views open inside InnoDB$/m,
         ],
         [
            [qw(
               Innodb_reserved_extent_count
            )],
            qr/^$d tablespace extents now reserved for B-tree/m,
         ],
         [
            [qw(
               Innodb_main_thread_proc_no
               Innodb_main_thread_id
               Innodb_main_thread_state
            )],
            qr/^Main thread (?:process no. $d, )?id $d, state: (.*)$/m,
         ],
         [
            [qw(
               Innodb_rows_inserted
               Innodb_rows_updated
               Innodb_rows_deleted
               Innodb_rows_read
            )],
            qr/^Number of rows inserted $d, updated $d, deleted $d, read $d$/m,
         ],
         [
            [qw(
               Innodb_rows_inserted_sec
               Innodb_rows_updated_sec
               Innodb_rows_deleted_sec
               Innodb_rows_read_sec
            )],
            qr{^$f inserts/s, $f updates/s, $f deletes/s, $f reads/s$}m,
         ],
      ],
      customcode => sub {},
   },

   top_level => {
      rules => [
         [
            [qw(
               Innodb_status_time
            )],
            qr/^$s INNODB MONITOR OUTPUT$/m,
         ],
         [
            [qw(
               Innodb_status_interval
            )],
            qr/Per second averages calculated from the last $d seconds/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         $status->{Innodb_status_time}
            = ts_to_time($status->{Innodb_status_time});
         $status->{Innodb_status_truncated}
            = $text =~ m/END OF INNODB MONITOR OUTPUT/ ? 0 : 1;
      },
   },

   transaction => {
      rules => [
         [
            [qw(
               txn_id
               txn_status
               active_secs
               proc_no
               os_thread_id
            )],
            qr/^(?:---)?TRANSACTION $t, (\D*?)(?: $d sec)?, (?:process no $d, )?OS thread id $d/m,
         ],
         [
            [qw(
               thread_status
               tickets
            )],
            qr/OS thread id \d+(?: ([^,]+?))?(?:, thread declared inside InnoDB $d)?$/m,
         ],
         [
            [qw(
               txn_query_status
               lock_structs
               heap_size
               row_locks
               undo_log_entries
            )],
            qr/^(?:(\D*) )?$d lock struct\(s\), heap size $d(?:, $d row lock\(s\))?(?:, undo log entries $d)?$/m,
         ],
         [
            [qw(
               lock_wait_time
            )],
            qr/^------- TRX HAS BEEN WAITING $d SEC/m,
         ],
         [
            [qw(
               mysql_tables_used
               mysql_tables_locked
            )],
            qr/^mysql tables in use $d, locked $d$/m,
         ],
         [
            [qw(
               read_view_lower_limit
               read_view_upper_limit
            )],
            qr/^Trx read view will not see trx with id >= $t, sees < $t$/m,
         ],
         [
            [qw(
               query_text
            )],
            qr{
               ^MySQL\sthread\sid\s[^\n]+\n           # This comes before the query text
               (.*?)                                  # The query text
               (?=                                    # Followed by any of...
                  ^Trx\sread\sview
                  |^-------\sTRX\sHAS\sBEEN\sWAITING
                  |^TABLE\sLOCK
                  |^RECORD\sLOCKS\sspace\sid
                  |^(?:---)?TRANSACTION
                  |^\*\*\*\s\(\d\)
                  |\Z
               )
            }xms,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $status->{query_text} ) {
            $status->{query_text} =~ s/\n*$//;
         }
      },
   },

   lock => {
      rules => [
         [
            [qw(
               type space_id page_no num_bits index database table txn_id mode
            )],
            qr{^(RECORD|TABLE) LOCKS? (?:space id $d page no $d n bits $d index `?$n`? of )?table `$n(?:/|`\.`)$n` trx id $t lock.mode (\S+)}m,
         ],
         [
            [qw(
               gap
            )],
            qr/^(?:RECORD|TABLE) .*? locks (rec but not gap|gap before rec)/m,
         ],
         [
            [qw(
               insert_intent
            )],
            qr/^(?:RECORD|TABLE) .*? (insert intention)/m,
         ],
         [
            [qw(
               waiting
            )],
            qr/^(?:RECORD|TABLE) .*? (waiting)/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

   io_thread => {
      rules => [
         [
            [qw(
               id
               state
               purpose

               event_set
            )],
            qr{^I/O thread $d state: (.+?) \((.*)\)}m,
         ],
         [
            [qw(
               io_reads
               io_writes
               io_requests
               io_wait
               io_avg_wait
               max_io_wait
            )],
            qr{reads $d writes $d requests $d io secs $f io msecs/request $f max_io_wait $f}m,
         ],
         [
            [qw(
               event_set
            )],
            qr/ ev (set)/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

   mutex_wait => {
      rules => [
         [
            [qw(
               thread_id
               mutex_file
               mutex_line
               wait_secs
            )],
            qr/^--Thread $d has waited at $fl for $f seconds/m,
         ],
         [
            [qw(
               wait_has_ended
            )],
            qr/^wait has ended$/m,
         ],
         [
            [qw(
               cell_event_set
            )],
            qr/^wait is ending$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
         if ( $text =~ m/^Mutex at/m ) {
            InnoDBParser::apply_rules(undef, $status, $text, 'sync_mutex');
         }
         else {
            InnoDBParser::apply_rules(undef, $status, $text, 'rw_lock');
         }
      },
   },

   sync_mutex => {
      rules => [
         [
            [qw(
               type 
               lock_mem_addr
               lock_cfile_name
               lock_cline
               lock_word
            )],
            qr/^(M)utex at $h created file $fl, lock var $d$/m,
         ],
         [
            [qw(
               lock_file_name
               lock_file_line
               num_waiters
            )],
            qr/^(?:Last time reserved in file $fl, )?waiters flag $d$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

   rw_lock => {
      rules => [
         [
            [qw(
               type 
               lock_cfile_name
               lock_cline
            )],
            qr/^(.)-lock on RW-latch at $h created in file $fl$/m,
         ],
         [
            [qw(
               writer_thread
               writer_lock_mode
            )],
            qr/^a writer \(thread id $d\) has reserved it in mode  (.*)$/m,
         ],
         [
            [qw(
               num_readers
               num_waiters
            )],
            qr/^number of readers $d, waiters flag $d$/m,
         ],
         [
            [qw(
               last_s_file_name
               last_s_line
            )],
            qr/^Last time read locked in file $fl$/m,
         ],
         [
            [qw(
               last_x_file_name
               last_x_line
            )],
            qr/^Last time write locked in file $fl$/m,
         ],
      ],
      customcode => sub {
         my ( $status, $text ) = @_;
      },
   },

);

sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

sub parse {
   my ( $self, $text ) = @_;

   my %result = (
      status                => [{}], # Non-repeating data
      deadlock_transactions => [],   # The transactions only
      deadlock_locks        => [],   # Both held and waited-for
      transactions          => [],
      transaction_locks     => [],   # Both held and waited-for
      io_threads            => [],
      mutex_waits           => [],
      insert_buffer_pages   => [],   # Only if InnoDB built with UNIV_IBUF_DEBUG
   );
   my $status = $result{status}[0];

   my %innodb_sections;
   my @matches = $text
      =~ m#\n(---+)\n([A-Z /]+)\n\1\n(.*?)(?=\n(---+)\n[A-Z /]+\n\4\n|$)#gs;
   while ( my ($start, $name, $section_text, $end) = splice(@matches, 0, 4) ) {
      $innodb_sections{$name} = $section_text;
   }

   $self->apply_rules($status, $text, 'top_level');

   foreach my $section ( keys %innodb_sections ) {
      my $section_text = $innodb_sections{$section};
      next unless defined $section_text; # No point in trying to parse further.
      $self->apply_rules($status, $section_text, $section);
   }

   if ( $innodb_sections{'LATEST DETECTED DEADLOCK'} ) {
      @result{qw(deadlock_transactions deadlock_locks)}
         = $self->parse_deadlocks($innodb_sections{'LATEST DETECTED DEADLOCK'});
   }
   if ( $innodb_sections{'INSERT BUFFER AND ADAPTIVE HASH INDEX'} ) {
      $result{insert_buffer_pages} = [
         map {
            my %page;
            @page{qw(page buffer_count)}
               = $_ =~ m/Ibuf count for page $d is $d$/;
            \%page;
         } $innodb_sections{'INSERT BUFFER AND ADAPTIVE HASH INDEX'}
            =~ m/(^Ibuf count for page.*$)/gs
      ];
   }
   if ( $innodb_sections{'TRANSACTIONS'} ) {
      $result{transactions} = [
         map { $self->parse_txn($_) }
            $innodb_sections{'TRANSACTIONS'}
            =~ m/(---TRANSACTION \d.*?)(?=\n---TRANSACTION|$)/gs
      ];
      $result{transaction_locks} = [
         map {
            my $lock = {};
            $self->apply_rules($lock, $_, 'lock');
            $lock;
         }
         $innodb_sections{'TRANSACTIONS'} =~ m/(^(?:RECORD|TABLE) LOCKS?.*$)/gm
      ];
   }
   if ( $innodb_sections{'FILE I/O'} ) {
      $result{io_threads} = [
         map {
            my $thread = {};
            $self->apply_rules($thread, $_, 'io_thread');
            $thread;
         }
         $innodb_sections{'FILE I/O'} =~ m{^(I/O thread \d+ .*)$}gm
      ];
   }
   if ( $innodb_sections{SEMAPHORES} ) {
      $result{mutex_waits} = [
         map {
            my $cell = {};
            $self->apply_rules($cell, $_, 'mutex_wait');
            $cell;
         }
         $innodb_sections{SEMAPHORES} =~ m/^(--Thread.*?)^(?=Mutex spin|--Thread)/gms
      ];
   }

   return \%result;
}

sub apply_rules {
   my ($self, $hashref, $text, $rulename) = @_;
   my $rules = $parse_rules_for{$rulename}
      or die "There are no parse rules for '$rulename'";
   foreach my $rule ( @{$rules->{rules}} ) {
      @{$hashref}{ @{$rule->[$COLS]} } = $text =~ m/$rule->[$PATTERN]/m;
   }
   $rules->{customcode}->($hashref, $text);
}

sub parse_deadlocks {
   my ($self, $text) = @_;
   my (@txns, @locks);

   my @sections = $text
      =~ m{
         ^\*{3}\s([^\n]*)  # *** (1) WAITING FOR THIS...
         (.*?)             # Followed by anything, non-greedy
         (?=(?:^\*{3})|\z) # Followed by another three stars or EOF
      }gmsx;

   while ( my ($header, $body) = splice(@sections, 0, 2) ) {
      my ( $num, $what ) = $header =~ m/^\($d\) (.*):$/
         or next; # For the WE ROLL BACK case

      if ( $what eq 'TRANSACTION' ) {
         push @txns, $self->parse_txn($body);
      }
      else {
         my $lock = {};
         $self->apply_rules($lock, $body, 'lock');
         push @locks, $lock;
      }
   }

   my ( $rolled_back ) = $text =~ m/^\*\*\* WE ROLL BACK TRANSACTION \($d\)$/m;
   if ( $rolled_back ) {
      $txns[ $rolled_back - 1 ]->{victim} = 1;
   }

   return (\@txns, \@locks);
}

sub parse_txn {
   my ($self, $text) = @_;

   my $txn = {};
   $self->apply_rules($txn, $text, 'transaction');

   my ( $thread_line ) = $text =~ m/^(MySQL thread id .*)$/m;
   my ( $mysql_thread_id, $query_id, $hostname, $ip, $user, $query_status );

   if ( $thread_line ) {
      ( $mysql_thread_id, $query_id )
         = $thread_line =~ m/^MySQL thread id $d, query id $d/m;

      ( $query_status ) = $thread_line =~ m/(Has (?:read|sent) all .*$)/m;
      if ( defined($query_status) ) {
         $user = 'system user';
      }

      elsif ( $thread_line =~ m/query id \d+ / ) {
         ( $hostname, $ip ) = $thread_line =~ m/query id \d+(?: ([A-Za-z]\S+))? $i/m;
         if ( defined $ip ) {
            ( $user, $query_status ) = $thread_line =~ m/$ip $w(?: (.*))?$/;
         }
         else { # OK, there wasn't an IP address.
            ( $query_status ) = $thread_line =~ m/query id \d+ (.*)$/;
            if ( $query_status !~ m/^\w+ing/ && !exists($is_proc_info{$query_status}) ) {
               ( $hostname, $user, $query_status ) = $thread_line
                  =~ m/query id \d+(?: ([A-Za-z]\S+))?(?: $w(?: (.*))?)?$/m;
            }
            else {
               $user = 'system user';
            }
         }
      }
   }

   @{$txn}{qw(mysql_thread_id query_id hostname ip user query_status)}
      = ( $mysql_thread_id, $query_id, $hostname, $ip, $user, $query_status);

   return $txn;
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
# End InnoDBStatusParser package
# ###########################################################################

# ###########################################################################
# Transformers package 7226
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Transformers.pm
#   trunk/common/t/Transformers.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Transformers;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::Local qw(timegm timelocal);
use Digest::MD5 qw(md5_hex);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ();
our @EXPORT      = ();
our @EXPORT_OK   = qw(
   micro_t
   percentage_of
   secs_to_time
   time_to_secs
   shorten
   ts
   parse_timestamp
   unix_timestamp
   any_unix_timestamp
   make_checksum
   crc32
);

our $mysql_ts  = qr/(\d\d)(\d\d)(\d\d) +(\d+):(\d+):(\d+)(\.\d+)?/;
our $proper_ts = qr/(\d\d\d\d)-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(\.\d+)?/;
our $n_ts      = qr/(\d{1,5})([shmd]?)/; # Limit \d{1,5} because \d{6} looks

sub micro_t {
   my ( $t, %args ) = @_;
   my $p_ms = defined $args{p_ms} ? $args{p_ms} : 0;  # precision for ms vals
   my $p_s  = defined $args{p_s}  ? $args{p_s}  : 0;  # precision for s vals
   my $f;

   $t = 0 if $t < 0;

   $t = sprintf('%.17f', $t) if $t =~ /e/;

   $t =~ s/\.(\d{1,6})\d*/\.$1/;

   if ($t > 0 && $t <= 0.000999) {
      $f = ($t * 1000000) . 'us';
   }
   elsif ($t >= 0.001000 && $t <= 0.999999) {
      $f = sprintf("%.${p_ms}f", $t * 1000);
      $f = ($f * 1) . 'ms'; # * 1 to remove insignificant zeros
   }
   elsif ($t >= 1) {
      $f = sprintf("%.${p_s}f", $t);
      $f = ($f * 1) . 's'; # * 1 to remove insignificant zeros
   }
   else {
      $f = 0;  # $t should = 0 at this point
   }

   return $f;
}

sub percentage_of {
   my ( $is, $of, %args ) = @_;
   my $p   = $args{p} || 0; # float precision
   my $fmt = $p ? "%.${p}f" : "%d";
   return sprintf $fmt, ($is * 100) / ($of ||= 1);
}

sub secs_to_time {
   my ( $secs, $fmt ) = @_;
   $secs ||= 0;
   return '00:00' unless $secs;

   $fmt ||= $secs >= 86_400 ? 'd'
          : $secs >= 3_600  ? 'h'
          :                   'm';

   return
      $fmt eq 'd' ? sprintf(
         "%d+%02d:%02d:%02d",
         int($secs / 86_400),
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : $fmt eq 'h' ? sprintf(
         "%02d:%02d:%02d",
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : sprintf(
         "%02d:%02d",
         int(($secs % 3_600) / 60),
         $secs % 60);
}

sub time_to_secs {
   my ( $val, $default_suffix ) = @_;
   die "I need a val argument" unless defined $val;
   my $t = 0;
   my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
   $suffix = $suffix || $default_suffix || 's';
   if ( $suffix =~ m/[smhd]/ ) {
      $t = $suffix eq 's' ? $num * 1        # Seconds
         : $suffix eq 'm' ? $num * 60       # Minutes
         : $suffix eq 'h' ? $num * 3600     # Hours
         :                  $num * 86400;   # Days

      $t *= -1 if $prefix && $prefix eq '-';
   }
   else {
      die "Invalid suffix for $val: $suffix";
   }
   return $t;
}

sub shorten {
   my ( $num, %args ) = @_;
   my $p = defined $args{p} ? $args{p} : 2;     # float precision
   my $d = defined $args{d} ? $args{d} : 1_024; # divisor
   my $n = 0;
   my @units = ('', qw(k M G T P E Z Y));
   while ( $num >= $d && $n < @units - 1 ) {
      $num /= $d;
      ++$n;
   }
   return sprintf(
      $num =~ m/\./ || $n
         ? "%.${p}f%s"
         : '%d',
      $num, $units[$n]);
}

sub ts {
   my ( $time, $gmt ) = @_;
   my ( $sec, $min, $hour, $mday, $mon, $year )
      = $gmt ? gmtime($time) : localtime($time);
   $mon  += 1;
   $year += 1900;
   my $val = sprintf("%d-%02d-%02dT%02d:%02d:%02d",
      $year, $mon, $mday, $hour, $min, $sec);
   if ( my ($us) = $time =~ m/(\.\d+)$/ ) {
      $us = sprintf("%.6f", $us);
      $us =~ s/^0\././;
      $val .= $us;
   }
   return $val;
}

sub parse_timestamp {
   my ( $val ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $f)
         = $val =~ m/^$mysql_ts$/ )
   {
      return sprintf "%d-%02d-%02d %02d:%02d:"
                     . (defined $f ? '%09.6f' : '%02d'),
                     $y + 2000, $m, $d, $h, $i, (defined $f ? $s + $f : $s);
   }
   return $val;
}

sub unix_timestamp {
   my ( $val, $gmt ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $us) = $val =~ m/^$proper_ts$/ ) {
      $val = $gmt
         ? timegm($s, $i, $h, $d, $m - 1, $y)
         : timelocal($s, $i, $h, $d, $m - 1, $y);
      if ( defined $us ) {
         $us = sprintf('%.6f', $us);
         $us =~ s/^0\././;
         $val .= $us;
      }
   }
   return $val;
}

sub any_unix_timestamp {
   my ( $val, $callback ) = @_;

   if ( my ($n, $suffix) = $val =~ m/^$n_ts$/ ) {
      $n = $suffix eq 's' ? $n            # Seconds
         : $suffix eq 'm' ? $n * 60       # Minutes
         : $suffix eq 'h' ? $n * 3600     # Hours
         : $suffix eq 'd' ? $n * 86400    # Days
         :                  $n;           # default: Seconds
      MKDEBUG && _d('ts is now - N[shmd]:', $n);
      return time - $n;
   }
   elsif ( $val =~ m/^\d{9,}/ ) {
      MKDEBUG && _d('ts is already a unix timestamp');
      return $val;
   }
   elsif ( my ($ymd, $hms) = $val =~ m/^(\d{6})(?:\s+(\d+:\d+:\d+))?/ ) {
      MKDEBUG && _d('ts is MySQL slow log timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp(parse_timestamp($val));
   }
   elsif ( ($ymd, $hms) = $val =~ m/^(\d{4}-\d\d-\d\d)(?:[T ](\d+:\d+:\d+))?/) {
      MKDEBUG && _d('ts is properly formatted timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp($val);
   }
   else {
      MKDEBUG && _d('ts is MySQL expression');
      return $callback->($val) if $callback && ref $callback eq 'CODE';
   }

   MKDEBUG && _d('Unknown ts type:', $val);
   return;
}

sub make_checksum {
   my ( $val ) = @_;
   my $checksum = uc substr(md5_hex($val), -16);
   MKDEBUG && _d($checksum, 'checksum for', $val);
   return $checksum;
}

sub crc32 {
   my ( $string ) = @_;
   return unless $string;
   my $poly = 0xEDB88320;
   my $crc  = 0xFFFFFFFF;
   foreach my $char ( split(//, $string) ) {
      my $comp = ($crc ^ ord($char)) & 0xFF;
      for ( 1 .. 8 ) {
         $comp = $comp & 1 ? $poly ^ ($comp >> 1) : $comp >> 1;
      }
      $crc = (($crc >> 8) & 0x00FFFFFF) ^ $comp;
   }
   return $crc ^ 0xFFFFFFFF;
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
# End Transformers package
# ###########################################################################

# ###########################################################################
# ProcesslistAggregator package 6590
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/ProcesslistAggregator.pm
#   trunk/common/t/ProcesslistAggregator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package ProcesslistAggregator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      undef_val => $args{undef_val} || 'NULL',
   };
   return bless $self, $class;
}

sub aggregate {
   my ( $self, $proclist ) = @_;
   my $aggregate = {};
   foreach my $proc ( @{$proclist} ) {
      foreach my $field ( keys %{ $proc } ) {
         next if $field eq 'Id';
         next if $field eq 'Info';
         next if $field eq 'Time';

         my $val  = $proc->{ $field };
            $val  = $self->{undef_val} if !defined $val;
            $val  = lc $val if ( $field eq 'Command' || $field eq 'State' );
            $val  =~ s/:.*// if $field eq 'Host';

         my $time = $proc->{Time};
            $time = 0 if !$time || $time eq 'NULL';

         $field = lc $field;

         $aggregate->{ $field }->{ $val }->{time}  += $time;
         $aggregate->{ $field }->{ $val }->{count} += 1;
      }
   }
   return $aggregate;
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
# End ProcesslistAggregator package
# ###########################################################################

# ###########################################################################
# WatchStatus package 7133
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/WatchStatus.pm
#   trunk/common/t/WatchStatus.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package WatchStatus;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(params) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $check_sub;
   my %extra_args;
   eval {
      ($check_sub, %extra_args) = parse_params($args{params});
   };
   die "Error parsing parameters $args{params}: $EVAL_ERROR" if $EVAL_ERROR;

   my $self = {
      %extra_args,
      %args,
      check_sub => $check_sub,
      callbacks => {
         show_status        => \&_show_status,
         show_innodb_status => \&_show_innodb_status,
         show_slave_status  => \&_show_slave_status,
      },
   };
   return bless $self, $class;
}

sub parse_params {
   my ( $params ) = @_;
   my ( $stats, $var, $cmp, $thresh ) = split(':', $params);
   $stats = lc $stats;
   MKDEBUG && _d('Parsed', $params, 'as', $stats, $var, $cmp, $thresh);
   die "No stats parameter; expected status, innodb or slave" unless $stats;
   die "Invalid stats: $stats; expected status, innodb or slave"
      unless $stats eq 'status' || $stats eq 'innodb' || $stats eq 'slave';
   die "No var parameter" unless $var;
   die "No comparison parameter; expected >, < or =" unless $cmp;
   die "Invalid comparison: $cmp; expected >, < or ="
      unless $cmp eq '<' || $cmp eq '>' || $cmp eq '=';
   die "No threshold value (N)" unless defined $thresh;

   $cmp = '==' if $cmp eq '=';

   my @lines = (
      'sub {',
      '   my ( $self, %args ) = @_;',
      "   my \$val = \$self->_get_val_from_$stats('$var', %args);",
      "   MKDEBUG && _d('Current $stats:$var =', \$val);",
      "   \$self->_save_last_check(\$val, '$cmp', '$thresh');",
      "   return \$val $cmp $thresh ? 1 : 0;",
      '}',
   );

   my $code = join("\n", @lines);
   MKDEBUG && _d('OK sub:', @lines);
   my $check_sub = eval $code
      or die "Error compiling subroutine code:\n$code\n$EVAL_ERROR";

   my %args;
   my $innodb_status_parser;
   if ( $stats eq 'innodb' ) {
      eval {
         $innodb_status_parser = new InnoDBStatusParser();
      };
      MKDEBUG && $EVAL_ERROR && _d('Cannot create an InnoDBStatusParser object:', $EVAL_ERROR);
      $args{InnoDBStatusParser} = $innodb_status_parser;
   }

   return $check_sub, %args;
}

sub uses_dbh {
   return 1;
}

sub set_dbh {
   my ( $self, $dbh ) = @_;
   $self->{dbh} = $dbh;
}

sub set_callbacks {
   my ( $self, %callbacks ) = @_;
   foreach my $func ( keys %callbacks ) {
      die "Callback $func does not exist"
         unless exists $self->{callbacks}->{$func};
      $self->{callbacks}->{$func} = $callbacks{$func};
      MKDEBUG && _d('Set new callback for', $func);
   }
   return;
}

sub check {
   my ( $self, %args ) = @_;
   return $self->{check_sub}->(@_);
}

sub _show_status {
   my ( $dbh, $var, %args ) = @_;
   if ( $var ) {
      my (undef, $val)
         = $dbh->selectrow_array("SHOW /*!50002 GLOBAL*/ STATUS LIKE '$var'");
      return $val;
   }
   else {
      return $dbh->selectall_hashref("SHOW /*!50002 GLOBAL*/ STATUS", 'Variable_name');
   }
}

sub _get_val_from_status {
   my ( $self, $var, %args ) = @_;
   die "I need a var argument" unless $var;
   return $self->{callbacks}->{show_status}->($self->{dbh}, $var, %args);


}

sub _show_innodb_status {
   my ( $dbh, %args ) = @_;
   my @text = $dbh->selectrow_array("SHOW /*!40100 ENGINE*/ INNODB STATUS");
   return $text[2] || $text[0];
}

sub _get_val_from_innodb {
   my ( $self, $var, %args ) = @_;
   die "I need a var argument" unless $var;
   my $is = $self->{InnoDBStatusParser};
   die "No InnoDBStatusParser object" unless $is;

   my $status_text = $self->{callbacks}->{show_innodb_status}->($self->{dbh}, %args);
   my $idb_stats   = $is->parse($status_text);

   my $val = 0;
   SECTION:
   foreach my $section ( keys %$idb_stats ) {
      next SECTION unless exists $idb_stats->{$section}->[0]->{$var};
      MKDEBUG && _d('Found', $var, 'in section', $section);

      foreach my $vars ( @{$idb_stats->{$section}} ) {
         MKDEBUG && _d($var, '=', $vars->{$var});
         $val = $vars->{$var} && $vars->{$var} > $val ? $vars->{$var} : $val;
      }
      MKDEBUG && _d('Highest', $var, '=', $val);
      last SECTION;
   }
   return $val;
}

sub _show_slave_status {
   my ( $dbh, $var, %args ) = @_;
   return $dbh->selectrow_hashref("SHOW SLAVE STATUS")->{$var};
}

sub _get_val_from_slave {
   my ( $self, $var, %args ) = @_;
   die "I need a var argument" unless $var;
   return $self->{callbacks}->{show_slave_status}->($self->{dbh}, $var, %args);
}

sub trevorprice {
   my ( $self, $dbh, %args ) = @_;
   die "I need a dbh argument" unless $dbh;
   my $num_samples = $args{samples} || 100;
   my $num_running = 0;
   my $start = time();
   my (undef, $status1)
      = $dbh->selectrow_array('SHOW /*!50002 GLOBAL*/ STATUS LIKE "Questions"');
   for ( 1 .. $num_samples ) {
      my $pl = $dbh->selectall_arrayref('SHOW PROCESSLIST', { Slice => {} });
      my $running = grep { ($_->{Command} || '') eq 'Query' } @$pl;
      $num_running += $running - 1;
   }
   my $time = time() - $start;
   return 0 unless $time;
   my (undef, $status2)
      = $dbh->selectrow_array('SHOW /*!50002 GLOBAL*/ STATUS LIKE "Questions"');
   my $qps = ($status2 - $status1) / $time;
   return 0 unless $qps;
   return ($num_running / $num_samples) / $qps;
}

sub _save_last_check {
   my ( $self, @args ) = @_;
   $self->{last_check} = [ @args ];
   return;
}

sub get_last_check {
   my ( $self ) = @_;
   return @{ $self->{last_check} };
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
# End WatchStatus package
# ###########################################################################

# ###########################################################################
# WatchProcesslist package 5266
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/WatchProcesslist.pm
#   trunk/common/t/WatchProcesslist.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package WatchProcesslist;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(params) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $check_sub;
   my %extra_args;
   eval {
      ($check_sub, %extra_args) = parse_params($args{params});
   };
   die "Error parsing parameters $args{params}: $EVAL_ERROR" if $EVAL_ERROR;

   my $self = {
      %extra_args,
      %args,
      check_sub => $check_sub,
      callbacks => {
         show_processlist => \&_show_processlist,
      },
   };
   return bless $self, $class;
}

sub parse_params {
   my ( $params ) = @_;
   my ( $col, $val, $agg, $cmp, $thresh ) = split(':', $params);
   $col = lc $col;
   $val = lc $val;
   $agg = lc $agg;
   MKDEBUG && _d('Parsed', $params, 'as', $col, $val, $agg, $cmp, $thresh);
   die "No column parameter; expected db, user, host, state or command"
      unless $col;
   die "Invalid column: $col; expected db, user, host, state or command"
      unless $col eq 'db' || $col eq 'user' || $col eq 'host' 
          || $col eq 'state' || $col eq 'command';
   die "No value parameter" unless $val;
   die "No aggregate; expected count or time" unless $agg;
   die "Invalid aggregate: $agg; expected count or time"
      unless $agg eq 'count' || $agg eq 'time';
   die "No comparison parameter; expected >, < or =" unless $cmp;
   die "Invalid comparison: $cmp; expected >, < or ="
      unless $cmp eq '<' || $cmp eq '>' || $cmp eq '=';
   die "No threshold value (N)" unless defined $thresh;

   $cmp = '==' if $cmp eq '=';

   my @lines = (
      'sub {',
      '   my ( $self, %args ) = @_;',
      '   my $proc = $self->{callbacks}->{show_processlist}->($self->{dbh});',
      '   if ( !$proc ) {',
      "      \$self->_save_last_check('processlist was empty');",
      '      return 0;',
      '   }',
      '   my $apl  = $self->{ProcesslistAggregator}->aggregate($proc);',
      "   my \$val = \$apl->{$col}->{'$val'}->{$agg} || 0;",
      "   MKDEBUG && _d('Current $col $val $agg =', \$val);",
      "   \$self->_save_last_check(\$val, '$cmp', '$thresh');",
      "   return \$val $cmp $thresh ? 1 : 0;",
      '}',
   );

   my $code = join("\n", @lines);
   MKDEBUG && _d('OK sub:', @lines);
   my $check_sub = eval $code
      or die "Error compiling subroutine code:\n$code\n$EVAL_ERROR";

   my %args;
   my $pla;
   eval {
      $pla = new ProcesslistAggregator();
   };
   MKDEBUG && $EVAL_ERROR && _d('Cannot create a ProcesslistAggregator object:',
      $EVAL_ERROR);
   $args{ProcesslistAggregator} = $pla;

   return $check_sub, %args;
}

sub uses_dbh {
   return 1;
}

sub set_dbh {
   my ( $self, $dbh ) = @_;
   $self->{dbh} = $dbh;
}

sub set_callbacks {
   my ( $self, %callbacks ) = @_;
   foreach my $func ( keys %callbacks ) {
      die "Callback $func does not exist"
         unless exists $self->{callbacks}->{$func};
      $self->{callbacks}->{$func} = $callbacks{$func};
      MKDEBUG && _d('Set new callback for', $func);
   }
   return;
}

sub check {
   my ( $self, %args ) = @_;
   return $self->{check_sub}->(@_);
}

sub _show_processlist {
   my ( $dbh, %args ) = @_;
   return $dbh->selectall_arrayref('SHOW PROCESSLIST', { Slice => {} } );
}

sub _save_last_check {
   my ( $self, @args ) = @_;
   $self->{last_check} = [ @args ];
   return;
}

sub get_last_check {
   my ( $self ) = @_;
   return @{ $self->{last_check} };
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
# End WatchProcesslist package
# ###########################################################################

# ###########################################################################
# WatchServer package 6590
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/WatchServer.pm
#   trunk/common/t/WatchServer.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package WatchServer;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(params) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $check_sub;
   my %extra_args;
   eval {
      ($check_sub, %extra_args) = parse_params($args{params});
   };
   die "Error parsing parameters $args{params}: $EVAL_ERROR" if $EVAL_ERROR;

   my $self = {
      %extra_args,
      %args,
      check_sub => $check_sub,
      callbacks => {
         uptime => \&_uptime,
         vmstat => \&_vmstat,
      },
   };
   return bless $self, $class;
}

sub parse_params {
   my ( $params ) = @_;
   my ( $cmd, $cmd_arg, $cmp, $thresh ) = split(':', $params);
   MKDEBUG && _d('Parsed', $params, 'as', $cmd, $cmd_arg, $cmp, $thresh);
   die "No command parameter" unless $cmd;
   die "Invalid command: $cmd; expected loadavg or uptime"
      unless $cmd eq 'loadavg' || $cmd eq 'vmstat';
   if ( $cmd eq 'loadavg' ) {
      die "Invalid $cmd argument: $cmd_arg; expected 1, 5 or 15"
         unless $cmd_arg eq '1' || $cmd_arg eq '5' || $cmd_arg eq '15';
   }
   elsif ( $cmd eq 'vmstat' ) {
      my @vmstat_args = qw(r b swpd free buff cache si so bi bo in cs us sy id wa);
      die "Invalid $cmd argument: $cmd_arg; expected one of "
         . join(',', @vmstat_args)
         unless grep { $cmd_arg eq $_ } @vmstat_args;
   }
   die "No comparison parameter; expected >, < or =" unless $cmp;
   die "Invalid comparison parameter: $cmp; expected >, < or ="
      unless $cmp eq '<' || $cmp eq '>' || $cmp eq '=';
   die "No threshold value (N)" unless defined $thresh;

   $cmp = '==' if $cmp eq '=';

   my @lines = (
      'sub {',
      '   my ( $self, %args ) = @_;',
      "   my \$val = \$self->_get_val_from_$cmd('$cmd_arg', %args);",
      "   MKDEBUG && _d('Current $cmd $cmd_arg =', \$val);",
      "   \$self->_save_last_check(\$val, '$cmp', '$thresh');",
      "   return \$val $cmp $thresh ? 1 : 0;",
      '}',
   );

   my $code = join("\n", @lines);
   MKDEBUG && _d('OK sub:', @lines);
   my $check_sub = eval $code
      or die "Error compiling subroutine code:\n$code\n$EVAL_ERROR";

   return $check_sub;
}

sub uses_dbh {
   return 0;
}

sub set_dbh {
   return;
}

sub set_callbacks {
   my ( $self, %callbacks ) = @_;
   foreach my $func ( keys %callbacks ) {
      die "Callback $func does not exist"
         unless exists $self->{callbacks}->{$func};
      $self->{callbacks}->{$func} = $callbacks{$func};
      MKDEBUG && _d('Set new callback for', $func);
   }
   return;
}

sub check {
   my ( $self, %args ) = @_;
   return $self->{check_sub}->(@_);
}

sub _uptime {
   return `uptime`;
}

sub _get_val_from_loadavg {
   my ( $self, $cmd_arg, %args ) = @_;
   my $uptime = $self->{callbacks}->{uptime}->();
   chomp $uptime;
   return 0 unless $uptime;
   my @loadavgs = $uptime =~ m/load average:\s+(\S+),\s+(\S+),\s+(\S+)/;
   MKDEBUG && _d('Load averages:', @loadavgs);
   my $i = $cmd_arg == 1 ? 0
         : $cmd_arg == 5 ? 1
         :                 2;
   return $loadavgs[$i] || 0;
}

sub _vmstat {
   return `vmstat`;
}

sub _parse_vmstat {
   my ( $vmstat_output ) = @_;
   MKDEBUG && _d('vmstat output:', $vmstat_output);
   my @lines =
      map {
         my $line = $_;
         my @vals = split(/\s+/, $line);
         \@vals;
      } split(/\n/, $vmstat_output);
   my %vmstat;
   my $n_vals = scalar @{$lines[1]};
   for my $i ( 0..$n_vals-1 ) {
      next unless $lines[1]->[$i];
      $vmstat{$lines[1]->[$i]} = $lines[-1]->[$i];
   }
   return \%vmstat;
}

sub _get_val_from_vmstat {
   my ( $self, $cmd_arg, %args ) = @_;
   my $vmstat_output = $self->{callbacks}->{vmstat}->();
   return _parse_vmstat($vmstat_output)->{$cmd_arg} || 0;
}

sub _save_last_check {
   my ( $self, @args ) = @_;
   $self->{last_check} = [ @args ];
   return;
}

sub get_last_check {
   my ( $self ) = @_;
   return @{ $self->{last_check} };
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
# End WatchServer package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_loadavg;

use English qw(-no_match_vars);
use IO::File;
use POSIX qw(setsid);
use sigtrap qw(handler finish untrapped normal-signals);

Transformers->import qw(ts);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

$OUTPUT_AUTOFLUSH = 1;

my $oktorun = 1;

$SIG{CHLD} = 'IGNORE';

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $vp = new VersionParser();
   my $o  = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   $o->usage_or_errors();

   # ########################################################################
   # First things first: if --stop was given, create the sentinel file.
   # ########################################################################
   if ( $o->get('stop') ) {
      my $sentinel = $o->get('sentinel');
      MKDEBUG && _d('Creating sentinel file', $sentinel);
      my $file = IO::File->new($sentinel, ">>")
         or die "Cannot open $sentinel: $OS_ERROR\n";
      print $file "Remove this file to permit mk-loadavg to run\n"
         or die "Cannot write to $sentinel: $OS_ERROR\n";
      close $file
         or die "Cannot close $sentinel: $OS_ERROR\n";
      print "Successfully created file $sentinel\n";
      return 0;
   }

   # ########################################################################
   # Parse --watch and load the Watch* modules.
   # ########################################################################
   my @plugins = parse_watch($o->get('watch'));
   my @watches;
   my $dsn_defaults = $dp->parse_options($o);
   my $dsn;
   my $dbh;
   foreach my $plugin ( @plugins ) {
      my $module = "Watch" . ($plugin->[0] || '');
      my $params = $plugin->[1];
      MKDEBUG && _d('Loading', $module, 'with params', $params);
      my $watch;
      eval {
         $watch = $module->new(
            params => $params,
         );
      };
      die "Failed to load --watch $module: $EVAL_ERROR" if $EVAL_ERROR;

      if ( $watch->uses_dbh() ) {
         if ( !$dbh ) {
            if ( $o->get('ask-pass') ) {
               $o->set('password', OptionParser::prompt_noecho("Enter password: "));
            }
            $dsn = @ARGV ? $dp->parse(shift @ARGV, $dsn_defaults)
                 :         $dsn_defaults;
            $dbh = $dp->get_dbh($dp->get_cxn_params($dsn),{ AutoCommit => 1, });
            $dbh->{InactiveDestroy}  = 1;         # Don't die on fork().
         }
         $watch->set_dbh($dbh);
      }

      # Set any callbacks.
      if ( (my $vmstat = $o->get('vmstat')) && $module eq 'WatchServer' ) {
         $watch->set_callbacks( vmstat => sub { return `$vmstat`; } );
      }

      push @watches, { name => "$plugin->[0]:$plugin->[1]", module => $watch, };
   }

   # In case no watch module used a dbh, set this manually.
   $dsn ||= { h => 'localhost' };

   # Daemonize only after connecting and doing --ask-pass.
   my $daemon;
   if ( $o->get('daemonize') ) {
      $daemon = new Daemon(o=>$o);
      $daemon->daemonize();
      MKDEBUG && _d('I am a daemon now');
   }
   elsif ( $o->get('pid') ) {
      # We're not daemoninzing, it just handles PID stuff.
      $daemon = new Daemon(o=>$o);
      $daemon->make_PID_file();
   }

   _log($o, "mk-loadavg started with:\n"
      . '#  --watch ' . $o->get('watch') . "\n"
      . ($o->get('execute-command')
            ? '#  --execute-command ' . $o->get('execute-command') . "\n" : '')
      . ($o->get('and')
            ? '#  --and' . "\n" : '')
      . '#  --interval ' . $o->get('interval')
   );
   watch_server(
      dsn => $dsn,
      dbh => $dbh,
      o   => $o,
      dp  => $dp,
      vp  => $vp,
      watches => \@watches,
   );

   $dp->disconnect($dbh) if $dbh;
   return 0;
}

# ############################################################################
# Subroutines.
# ############################################################################

sub parse_watch {
   my ( $watch ) = @_;
   return unless $watch;
   my @watch_defs = split(/,/, $watch);
   my @watches = map {
      my $def = $_;
      my ($module, $args) = $def =~ m/(\w+):(.+)/;
      [ $module, $args ];
   } @watch_defs;
   return @watches;
}

sub watch_server {
   my ( %args ) = @_;
   foreach my $arg ( qw(dsn o dp vp) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dbh     = $args{dbh};
   my $dsn     = $args{dsn};
   my $o       = $args{o};
   my $dp      = $args{dp};
   my $vp      = $args{vp};
   my $watches = $args{watches};

   _log($o, 'Watching server ' . $dp->as_string($dsn));

   my $exit_time = time() + ($o->get('run-time') || 0);
   while ( (!$o->get('run-time') || time() < $exit_time)
           && !-f $o->get('sentinel')
           && $oktorun ) {

      # If there's a dbh then we're connect to MySQL.  Make sure its
      # responding, wait and retry forever it's not.
      if ( $dbh ) {
         while ( !$dbh->ping ) {
            my $wait = $o->get('wait');
            _log($o, "MySQL not responding; waiting ${wait}s to reconnect");
            sleep $wait;
            eval {
               $dbh = $dp->get_dbh(
                  $dp->get_cxn_params($dsn), { AutoCommit => 1 });
            };
            if ( $EVAL_ERROR ) {
               _log($o, 'Could not reconnect to MySQL server:', $EVAL_ERROR);
            }
            else {
               _log($o, 'Reconnected to MySQL');
               $dbh->{InactiveDestroy} = 1;  # Don't die on fork().
               next;  # Redo the oktorun checks after waiting.
            }
         }
      }

      my $n_failed = 0;
      foreach my $watch ( @$watches ) {
         my $watch_name = $watch->{name};
         _log($o, "Checking $watch_name");

         $watch->{module}->set_dbh($dbh);  # Reset this in case we reconnected.

         my $check_status = $watch->{module}->check();  # Check it!
         my @last_test    = map {
            defined $_ ? $_ : 'undef'  # Shouldn't happen, but just in case.
         } $watch->{module}->get_last_check();
         if ( $check_status == 0 ) {
            # The check is not triggered.
            _log($o, "PASS: @last_test");
         }
         else {
            # The check is triggered.
            $n_failed++;
            _log($o, "FAIL: @last_test");
            if ( !$o->get('and') ) {
               if ( my $cmd = $o->get('execute-command') ) {
                  _log($o, "Executing $cmd");
                  exec_cmd($cmd);
               }
            }
         }
      }

      if ( $o->get('and') && $n_failed == scalar @$watches ) {
         _log($o, 'All watches failed');
         if ( my $cmd = $o->get('execute-command') ) {
            _d("Executing $cmd");
            exec_cmd($cmd);
         }
      }

      _log($o, 'Sleeping ' . $o->get('interval'));
      sleep $o->get('interval');
   }

   _log($o, 'Done watching server ' . $dp->as_string($dsn));

   return;
}

# Forks and detaches from parent to execute the given command;
# does not block parent.
sub exec_cmd {
   my ( $cmd ) = @_;
   MKDEBUG && _d('exec cmd:', $cmd);
   return unless $cmd;

   my $pid = fork();
   if ( $pid ) {
      # parent
      MKDEBUG && _d('child pid:', $pid);
      return $pid;
   }

   # child
   POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
   open STDOUT, '>/dev/null';
   open STDERR, '>&STDOUT';
   open STDIN,  '/dev/null';
   exec $cmd;
   exit;
}

# Catches signals for exiting gracefully.
sub finish {
   my ($signal) = @_;
   my $msg = "Exiting on SIG$signal.";
   print STDERR "$msg\n";
   _log(undef, $msg); 
   $oktorun = 0;
   return 1;
}

sub _log {
   my ( $o, $msg ) = @_;
   # If called by finish(), we won't have an $o.
   print '# ', ts(time), " $msg\n" if !$o || ($o && $o->get('verbose'));
   MKDEBUG && _d($msg);
   return;
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

mk-loadavg - Watch MySQL load and take action when it gets too high.

=head1 SYNOPSIS

Usage: mk-loadavg [OPTION...] [DSN]

mk-loadavg watches the load on a MySQL server and takes action if it is too
high.

Execute my_script.sh when Threads_running exceeds 10:

  mk-loadavg --watch "Status:status:Threads_running:>:10" \
    --execute-command my_script.sh

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-loadavg merely reads and prints information by default, and is very low-risk.
The L<"--execute-command"> option can execute user-specified commands.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-loadavg>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-loadavg watches a MySQL server and takes action when a defined threshold
is exceeded.  One or more items can be watched including MySQL status values
from SHOW STATUS, SHOW INNODB STATUS and SHOW SLAVE STATUS, the three system
load averages from C<uptime>, and values from C<vmstat>.  Watched items and
their threshold values are specified by L<"--watch">.  Every item is checked
at intervals (see L<"--interval">).  By default, if any one item's check returns
true (i.e. its threshold is exceeded), then L<"--execute-command"> is executed.
Specifying L<"--and"> requires that every item has exceeded its threshold before
L<"--execute-command"> is executed.

=head1 OUTPUT

If you specify L<"--verbose">, mk-loadavg prints information to STDOUT
about each check for each watched item.  Else, it prints nothing and
L<"--execute-command"> (if specified) is responsible for logging any
information you want.

=head1 EXIT STATUS

An exit status of 0 (sometimes also called a return value or return code)
indicates success.  Any other value represents the exit status of the Perl
process itself, or of the last forked process that exited if there were multiple
servers to monitor.

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --and

group: Action

Trigger the actions only when all L<"--watch"> items exceed their thresholds.

The default is to trigger the actions when any one of the watched items
exceeds its threshold.  This option requires that all watched items exceed
their thresholds before any action is triggered.

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
without the utf8 layer, and runs SET NAMES after connecting to MySQL.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --daemonize

Fork to the background and detach from the shell.  POSIX
operating systems only.

=item --database

short form: -D; type: string

Database to use.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --execute-command

type: string; group: Action

Execute this command when watched items exceed their threshold values

This command will be executed every time a L<"--watch"> item (or all items if
L<"--and"> is specified) exceeds its threshold.  For example, if you specify
C<--watch "Server:vmstat:swpd:>:0">, then this command will be executed
when the server begins to swap and it will be executed again at each
L<"--interval"> so long as the server is still swapping.

After the command is executed, mk-loadavg has no control over it, so it is
responsible for its own info gathering, logging, interval, etc.  Since the
command is spawned from mk-loadavg, its STDOUT, STDERR and STDIN are closed
so it doesn't interfere with mk-loadavg.  Therefore, the command must redirect
its output to files or some other destination.  For example, if you
specify C<--execute-command 'echo Hello'>, you will not see "Hello" printed
anywhere (neither to screen nor L<"--log">) because STDOUT is closed for
the command.

No information from mk-loadavg is passed to the command.

See also L<"--and">.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --interval

type: time; default: 60s; group: Watch

How long to sleep between each check.

=item --log

type: string

Print all output to this file when daemonized.

Output from L<"--execute-command"> is not printed to this file.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file when daemonized.  The file contains the process
ID of the daemonized instance.  The PID file is removed when the
daemonized instance exits.  The program checks for the existence of the
PID file when starting; if it exists and the process with the matching PID
exists, the program exits.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --run-time

type: time

Time to run before exiting.

Causes C<mk-loadavg> to stop after the specified time has elapsed.
Optional suffix: s=seconds, m=minutes, h=hours, d=days; if no suffix, s is used.

=item --sentinel

type: string; default: /tmp/mk-loadavg-sentinel

Exit if this file exists.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this string
will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --stop

Stop running instances by creating the L<"--sentinel"> file.

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v

Print information to STDOUT about what is being done.

This can be used as a heartbeat to see that mk-loadavg is still
properly watching all its values.  If L<"--log"> is specified, this information
will be printed to that file instead.

=item --version

Show version and exit.

=item --vmstat

type: string; default: vmstat 1 2; group: Watch

vmstat command for L<"--watch"> Server:vmstat:...

The vmstat output should look like:

 procs -----------memory---------- ---swap-- -----io---- -system-- ----cpu----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa
 0  0      0 590380 143756 571852    0    0     6     9  228  340  4  1 94  1
 0  0      0 590400 143764 571852    0    0     0    28  751  818  4  2 90  3

The second line from the top needs to be column headers for subsequent lines.
Values are taken from the last line.

The default, C<vmstat 1 2>,  gets current values.  Running just C<vmstat>
would get average values since last reboot.

=item --wait

short form: -w; type: time; default: 60s

Wait this long to reconnect to MySQL.

If the MySQL server goes away between L<"--interval"> checks, mk-loadavg
will attempt to reconnect to MySQL forever, sleeping this amount of time
in between attempts.

=item --watch

type: string; group: Watch

A comma-separated list of watched items and their thresholds (required).

Each watched item is string of arguments separated by colons (like arg:arg).
Each argument defines the watch item: what particular value is watched and how
to compare the current value to a threshold value (N).  Multiple watched
items can be given by separating them with a comma, and the same watched
item can be given multiple times (but, of course, it only makes sense to
do this if the comparison and/or threshold values are different).

The first argument is the most important and is case-sensitive.  It
defines the module responsible for watching the value.  For example,

  --watch Status:...

causes the WatchStatus module to be loaded.  The second and subsequent
arguments are passed to the WatchStatus module which parses them.  Each
watch module requires different arguments.  The watch modules included
in mk-loadavg and what arguments they require are listed below.

This is a common error when specifying L<"--watch"> on the command line:

   mk-loadavg --watch Server:vmstat:swpd:>:0

   Failed to load --watch WatchServer: Error parsing parameters vmstat:swpd:: No comparison parameter; expected >, < or = at ./mk-loadavg line 3100.

The L<"--watch"> values need to be quoted:

   mk-loadavg --watch "Server:vmstat:swpd:>:0"

=over

=item Status

Watch SHOW STATUS, SHOW INNODB STATUS, and SHOW SLAVE STATUS values.
The value argument is case-sensitive.

  --watch Status:[status|innodb|slave]:value:[><=]:N

Examples:

  --watch "Status:status:Threads_connected:>:16"
  --watch "Status:innodb:Innodb_buffer_pool_hit_rate:<:0.98"
  --watch "Status:slave:Seconds_behind_master:>:300"

You can easily see what values are available for SHOW STATUS and SHOW SLAVE
STATUS, but the values for SHOW INNODB STATUS are not apparent.  Some common
values are:

  Innodb_buffer_pool_hit_rate
  Innodb_buffer_pool_pages_created_sec
  Innodb_buffer_pool_pages_dirty
  Innodb_buffer_pool_pages_read_sec
  Innodb_buffer_pool_pages_written_sec
  Innodb_buffer_pool_pending_data_writes
  Innodb_buffer_pool_pending_dirty_writes
  Innodb_buffer_pool_pending_fsyncs
  Innodb_buffer_pool_pending_reads
  Innodb_buffer_pool_pending_single_writes
  Innodb_common_memory_allocated
  Innodb_data_fsyncs_sec
  Innodb_data_pending_fsyncs
  Innodb_data_pending_preads
  Innodb_data_pending_pwrites
  Innodb_data_reads_sec
  Innodb_data_writes_sec
  Innodb_insert_buffer_pending_reads
  Innodb_rows_read_sec
  Innodb_rows_updated_sec
  lock_wait_time
  mysql_tables_locked
  mysql_tables_used
  row_locks
  io_avg_wait
  io_wait
  max_io_wait

Several of those values can appear multiple times in the SHOW INNODB STATUS
output.  The value used for comparison is always the highest value.  So the
value for io_wait is the highest io_wait value for all the IO threads.

=item Processlist

Watch aggregated SHOW PROCESSLIST values.

   --watch Processlist:[db|user|host|state|command]:value:[count|time]:[><=]:N

Examples:

  --watch "Processlist:state:Locked:count:>:5"
  --watch "Processlist:command:Query:time:<:1"

=item Server

Watch server values.

   --watch Server:loadavg:[1|5|15]:[><=]:N
   --watch Server:vmstat:[r|b|swpd|free|buff|cache|si|so|bi|bo|in|cs|us|sy|id|wa]:[><=]:N

Examples:

  --watch "Server:loadavg:5:>:4.00"
  --watch "Server:vmstat:swpd:>:0"
  --watch "Server:vmstat:free:=:0"

See L<"--vmstat">.

=back

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

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-loadavg>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2008-2011 Baron Schwartz.
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

Baron Schwartz, Daniel Nichter

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 0.9.7 Distrib 7540 $Revision: 7460 $.

=cut

__END__
:endofperl
