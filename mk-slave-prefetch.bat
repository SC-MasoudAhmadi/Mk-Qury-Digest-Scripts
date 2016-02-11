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

# This is mk-slave-prefetch, a program to pipeline relay logs on a MySQL slave.
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

our $VERSION = '1.0.21';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7531 $ =~ m/(\d+)/g, 0));

use English qw(-no_match_vars);
$OUTPUT_AUTOFLUSH = 1;

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
# BinaryLogParser package 7522
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/BinaryLogParser.pm
#   trunk/common/t/BinaryLogParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package BinaryLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $binlog_line_1 = qr/at (\d+)$/m;
my $binlog_line_2 = qr/^#(\d{6}\s+\d{1,2}:\d\d:\d\d)\s+server\s+id\s+(\d+)\s+end_log_pos\s+(\d+)\s+(\S+)\s*([^\n]*)$/m;
my $binlog_line_2_rest = qr/thread_id=(\d+)\s+exec_time=(\d+)\s+error_code=(\d+)/m;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      delim     => undef,
      delim_len => 0,
   };
   return bless $self, $class;
}


sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   local $INPUT_RECORD_SEPARATOR = ";\n#";
   my $pos_in_log = $tell->();
   my $stmt;
   my ($delim, $delim_len) = ($self->{delim}, $self->{delim_len});

   EVENT:
   while ( defined($stmt = $next_event->()) ) {
      my @properties = ('pos_in_log', $pos_in_log);
      my ($ts, $sid, $end, $type, $rest);
      $pos_in_log = $tell->();
      $stmt =~ s/;\n#?\Z//;

      my ( $got_offset, $got_hdr );
      my $pos = 0;
      my $len = length($stmt);
      my $found_arg = 0;
      LINE:
      while ( $stmt =~ m/^(.*)$/mg ) { # /g requires scalar match.
         $pos     = pos($stmt);  # Be careful not to mess this up!
         my $line = $1;          # Necessary for /g and pos() to work.
         $line    =~ s/$delim// if $delim;
         MKDEBUG && _d($line);

         if ( $line =~ m/^\/\*.+\*\/;/ ) {
            MKDEBUG && _d('Comment line');
            next LINE;
         }
 
         if ( $line =~ m/^DELIMITER/m ) {
            my ( $del ) = $line =~ m/^DELIMITER (\S*)$/m;
            if ( $del ) {
               $self->{delim_len} = $delim_len = length $del;
               $self->{delim}     = $delim     = quotemeta $del;
               MKDEBUG && _d('delimiter:', $delim);
            }
            else {
               MKDEBUG && _d('Delimiter reset to ;');
               $self->{delim}     = $delim     = undef;
               $self->{delim_len} = $delim_len = 0;
            }
            next LINE;
         }

         next LINE if $line =~ m/End of log file/;

         if ( !$got_offset && (my ( $offset ) = $line =~ m/$binlog_line_1/m) ) {
            MKDEBUG && _d('Got the at offset line');
            push @properties, 'offset', $offset;
            $got_offset++;
         }

         elsif ( !$got_hdr && $line =~ m/^#(\d{6}\s+\d{1,2}:\d\d:\d\d)/ ) {
            ($ts, $sid, $end, $type, $rest) = $line =~ m/$binlog_line_2/m;
            MKDEBUG && _d('Got the header line; type:', $type, 'rest:', $rest);
            push @properties, 'cmd', 'Query', 'ts', $ts, 'server_id', $sid,
               'end_log_pos', $end;
            $got_hdr++;
         }

         elsif ( $line =~ m/^(?:#|use |SET)/i ) {

            if ( my ( $db ) = $line =~ m/^use ([^;]+)/ ) {
               MKDEBUG && _d("Got a default database:", $db);
               push @properties, 'db', $db;
            }

            elsif ( my ($setting) = $line =~ m/^SET\s+([^;]*)/ ) {
               MKDEBUG && _d("Got some setting:", $setting);
               push @properties, map { s/\s+//; lc } split(/,|\s*=\s*/, $setting);
            }

         }
         else {
            MKDEBUG && _d("Got the query/arg line at pos", $pos);
            $found_arg++;
            if ( $got_offset && $got_hdr ) {
               if ( $type eq 'Xid' ) {
                  my ($xid) = $rest =~ m/(\d+)/;
                  push @properties, 'Xid', $xid;
               }
               elsif ( $type eq 'Query' ) {
                  my ($i, $t, $c) = $rest =~ m/$binlog_line_2_rest/m;
                  push @properties, 'Thread_id', $i, 'Query_time', $t,
                                    'error_code', $c;
               }
               elsif ( $type eq 'Start:' ) {
                  MKDEBUG && _d("Binlog start");
               }
               else {
                  MKDEBUG && _d('Unknown event type:', $type);
                  next EVENT;
               }
            }
            else {
               MKDEBUG && _d("It's not a query/arg, it's just some SQL fluff");
               push @properties, 'cmd', 'Query', 'ts', undef;
            }

            my $delim_len = ($pos == length($stmt) ? $delim_len : 0);
            my $arg = substr($stmt, $pos - length($line) - $delim_len);

            $arg =~ s/$delim// if $delim; # Remove the delimiter.

            if ( $arg =~ m/^DELIMITER/m ) {
               my ( $del ) = $arg =~ m/^DELIMITER (\S*)$/m;
               if ( $del ) {
                  $self->{delim_len} = $delim_len = length $del;
                  $self->{delim}     = $delim     = quotemeta $del;
                  MKDEBUG && _d('delimiter:', $delim);
               }
               else {
                  MKDEBUG && _d('Delimiter reset to ;');
                  $del       = ';';
                  $self->{delim}     = $delim     = undef;
                  $self->{delim_len} = $delim_len = 0;
               }

               $arg =~ s/^DELIMITER.*$//m;  # Remove DELIMITER from arg.
            }

            $arg =~ s/;$//gm;  # Ensure ending ; are gone.
            $arg =~ s/\s+$//;  # Remove trailing spaces and newlines.

            push @properties, 'arg', $arg, 'bytes', length($arg);
            last LINE;
         }
      } # LINE

      if ( $found_arg ) {
         MKDEBUG && _d('Properties of event:', Dumper(\@properties));
         my $event = { @properties };
         if ( $args{stats} ) {
            $args{stats}->{events_read}++;
            $args{stats}->{events_parsed}++;
         }
         return $event;
      }
      else {
         MKDEBUG && _d('Event had no arg');
      }
   } # EVENT

   $args{oktorun}->(0) if $args{oktorun};
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
# End BinaryLogParser package
# ###########################################################################

# ###########################################################################
# QueryRewriter package 7473
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/QueryRewriter.pm
#   trunk/common/t/QueryRewriter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
use strict;
use warnings FATAL => 'all';

package QueryRewriter;

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

our $verbs   = qr{^SHOW|^FLUSH|^COMMIT|^ROLLBACK|^BEGIN|SELECT|INSERT
                  |UPDATE|DELETE|REPLACE|^SET|UNION|^START|^LOCK}xi;
my $quote_re = qr/"(?:(?!(?<!\\)").)*"|'(?:(?!(?<!\\)').)*'/; # Costly!
my $bal;
$bal         = qr/
                  \(
                  (?:
                     (?> [^()]+ )    # Non-parens without backtracking
                     |
                     (??{ $bal })    # Group with matching parens
                  )*
                  \)
                 /x;

my $olc_re = qr/(?:--|#)[^'"\r\n]*(?=[\r\n]|\Z)/;  # One-line comments
my $mlc_re = qr#/\*[^!].*?\*/#sm;                  # But not /*!version */
my $vlc_re = qr#/\*.*?[0-9+].*?\*/#sm;             # For SHOW + /*!version */
my $vlc_rf = qr#^(SHOW).*?/\*![0-9+].*?\*/#sm;     # Variation for SHOW


sub new {
   my ( $class, %args ) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub strip_comments {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s/$olc_re//go;
   $query =~ s/$mlc_re//go;
   if ( $query =~ m/$vlc_rf/i ) { # contains show + version
      $query =~ s/$vlc_re//go;
   }
   return $query;
}

sub shorten {
   my ( $self, $query, $length ) = @_;
   $query =~ s{
      \A(
         (?:INSERT|REPLACE)
         (?:\s+LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)?
         (?:\s\w+)*\s+\S+\s+VALUES\s*\(.*?\)
      )
      \s*,\s*\(.*?(ON\s+DUPLICATE|\Z)}
      {$1 /*... omitted ...*/$2}xsi;

   return $query unless $query =~ m/IN\s*\(\s*(?!select)/i;

   my $last_length  = 0;
   my $query_length = length($query);
   while (
      $length          > 0
      && $query_length > $length
      && $query_length < ( $last_length || $query_length + 1 )
   ) {
      $last_length = $query_length;
      $query =~ s{
         (\bIN\s*\()    # The opening of an IN list
         ([^\)]+)       # Contents of the list, assuming no item contains paren
         (?=\))           # Close of the list
      }
      {
         $1 . __shorten($2)
      }gexsi;
   }

   return $query;
}

sub __shorten {
   my ( $snippet ) = @_;
   my @vals = split(/,/, $snippet);
   return $snippet unless @vals > 20;
   my @keep = splice(@vals, 0, 20);  # Remove and save the first 20 items
   return
      join(',', @keep)
      . "/*... omitted "
      . scalar(@vals)
      . " items ...*/";
}

sub fingerprint {
   my ( $self, $query ) = @_;

   $query =~ m#\ASELECT /\*!40001 SQL_NO_CACHE \*/ \* FROM `# # mysqldump query
      && return 'mysqldump';
   $query =~ m#/\*\w+\.\w+:[0-9]/[0-9]\*/#     # mk-table-checksum, etc query
      && return 'maatkit';
   $query =~ m/\Aadministrator command: /
      && return $query;
   $query =~ m/\A\s*(call\s+\S+)\(/i
      && return lc($1); # Warning! $1 used, be careful.
   if ( my ($beginning) = $query =~ m/\A((?:INSERT|REPLACE)(?: IGNORE)?\s+INTO.+?VALUES\s*\(.*?\))\s*,\s*\(/is ) {
      $query = $beginning; # Shorten multi-value INSERT statements ASAP
   }
  
   $query =~ s/$olc_re//go;
   $query =~ s/$mlc_re//go;
   $query =~ s/\Ause \S+\Z/use ?/i       # Abstract the DB in USE
      && return $query;

   $query =~ s/\\["']//g;                # quoted strings
   $query =~ s/".*?"/?/sg;               # quoted strings
   $query =~ s/'.*?'/?/sg;               # quoted strings
   $query =~ s/[0-9+-][0-9a-f.xb+-]*/?/g;# Anything vaguely resembling numbers
   $query =~ s/[xb.+-]\?/?/g;            # Clean up leftovers
   $query =~ s/\A\s+//;                  # Chop off leading whitespace
   chomp $query;                         # Kill trailing whitespace
   $query =~ tr[ \n\t\r\f][ ]s;          # Collapse whitespace
   $query = lc $query;
   $query =~ s/\bnull\b/?/g;             # Get rid of NULLs
   $query =~ s{                          # Collapse IN and VALUES lists
               \b(in|values?)(?:[\s,]*\([\s?,]*\))+
              }
              {$1(?+)}gx;
   $query =~ s{                          # Collapse UNION
               \b(select\s.*?)(?:(\sunion(?:\sall)?)\s\1)+
              }
              {$1 /*repeat$2*/}xg;
   $query =~ s/\blimit \?(?:, ?\?| offset \?)?/limit ?/; # LIMIT

   if ( $query =~ m/\bORDER BY /gi ) {  # Find, anchor on ORDER BY clause
      1 while $query =~ s/\G(.+?)\s+ASC/$1/gi && pos $query;
   }

   return $query;
}

sub distill_verbs {
   my ( $self, $query ) = @_;

   $query =~ m/\A\s*call\s+(\S+)\(/i && return "CALL $1";
   $query =~ m/\A\s*use\s+/          && return "USE";
   $query =~ m/\A\s*UNLOCK TABLES/i  && return "UNLOCK";
   $query =~ m/\A\s*xa\s+(\S+)/i     && return "XA_$1";

   if ( $query =~ m/\Aadministrator command:/ ) {
      $query =~ s/administrator command:/ADMIN/;
      $query = uc $query;
      return $query;
   }

   $query = $self->strip_comments($query);

   if ( $query =~ m/\A\s*SHOW\s+/i ) {
      MKDEBUG && _d($query);

      $query = uc $query;
      $query =~ s/\s+(?:GLOBAL|SESSION|FULL|STORAGE|ENGINE)\b/ /g;
      $query =~ s/\s+COUNT[^)]+\)//g;

      $query =~ s/\s+(?:FOR|FROM|LIKE|WHERE|LIMIT|IN)\b.+//ms;

      $query =~ s/\A(SHOW(?:\s+\S+){1,2}).*\Z/$1/s;
      $query =~ s/\s+/ /g;
      MKDEBUG && _d($query);
      return $query;
   }

   eval $QueryParser::data_def_stmts;
   eval $QueryParser::tbl_ident;
   my ( $dds ) = $query =~ /^\s*($QueryParser::data_def_stmts)\b/i;
   if ( $dds) {
      my ( $obj ) = $query =~ m/$dds.+(DATABASE|TABLE)\b/i;
      $obj = uc $obj if $obj;
      MKDEBUG && _d('Data def statment:', $dds, 'obj:', $obj);
      my ($db_or_tbl)
         = $query =~ m/(?:TABLE|DATABASE)\s+($QueryParser::tbl_ident)(\s+.*)?/i;
      MKDEBUG && _d('Matches db or table:', $db_or_tbl);
      return uc($dds . ($obj ? " $obj" : '')), $db_or_tbl;
   }

   my @verbs = $query =~ m/\b($verbs)\b/gio;
   @verbs    = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } map { uc } @verbs;
   };

   if ( ($verbs[0] || '') eq 'SELECT' && @verbs > 1 ) {
      MKDEBUG && _d("False-positive verbs after SELECT:", @verbs[1..$#verbs]);
      my $union = grep { $_ eq 'UNION' } @verbs;
      @verbs    = $union ? qw(SELECT UNION) : qw(SELECT);
   }

   my $verb_str = join(q{ }, @verbs);
   return $verb_str;
}

sub __distill_tables {
   my ( $self, $query, $table, %args ) = @_;
   my $qp = $args{QueryParser} || $self->{QueryParser};
   die "I need a QueryParser argument" unless $qp;

   my @tables = map {
      $_ =~ s/`//g;
      $_ =~ s/(_?)[0-9]+/$1?/g;
      $_;
   } grep { defined $_ } $qp->get_tables($query);

   push @tables, $table if $table;

   @tables = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } @tables;
   };

   return @tables;
}

sub distill {
   my ( $self, $query, %args ) = @_;

   if ( $args{generic} ) {
      my ($cmd, $arg) = $query =~ m/^(\S+)\s+(\S+)/;
      return '' unless $cmd;
      $query = (uc $cmd) . ($arg ? " $arg" : '');
   }
   else {
      my ($verbs, $table)  = $self->distill_verbs($query, %args);

      if ( $verbs && $verbs =~ m/^SHOW/ ) {
         my %alias_for = qw(
            SCHEMA   DATABASE
            KEYS     INDEX
            INDEXES  INDEX
         );
         map { $verbs =~ s/$_/$alias_for{$_}/ } keys %alias_for;
         $query = $verbs;
      }
      else {
         my @tables = $self->__distill_tables($query, $table, %args);
         $query     = join(q{ }, $verbs, @tables); 
      } 
   }

   if ( $args{trf} ) {
      $query = $args{trf}->($query, %args);
   }

   return $query;
}

sub convert_to_select {
   my ( $self, $query ) = @_;
   return unless $query;

   return if $query =~ m/=\s*\(\s*SELECT /i;

   $query =~ s{
                 \A.*?
                 update(?:\s+(?:low_priority|ignore))?\s+(.*?)
                 \s+set\b(.*?)
                 (?:\s*where\b(.*?))?
                 (limit\s*[0-9]+(?:\s*,\s*[0-9]+)?)?
                 \Z
              }
              {__update_to_select($1, $2, $3, $4)}exsi
      || $query =~ s{
                    \A.*?
                    (?:insert(?:\s+ignore)?|replace)\s+
                    .*?\binto\b(.*?)\(([^\)]+)\)\s*
                    values?\s*(\(.*?\))\s*
                    (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                    \Z
                 }
                 {__insert_to_select($1, $2, $3)}exsi
      || $query =~ s{
                    \A.*?
                    (?:insert(?:\s+ignore)?|replace)\s+
                    (?:.*?\binto)\b(.*?)\s*
                    set\s+(.*?)\s*
                    (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                    \Z
                 }
                 {__insert_to_select_with_set($1, $2)}exsi
      || $query =~ s{
                    \A.*?
                    delete\s+(.*?)
                    \bfrom\b(.*)
                    \Z
                 }
                 {__delete_to_select($1, $2)}exsi;
   $query =~ s/\s*on\s+duplicate\s+key\s+update.*\Z//si;
   $query =~ s/\A.*?(?=\bSELECT\s*\b)//ism;
   return $query;
}

sub convert_select_list {
   my ( $self, $query ) = @_;
   $query =~ s{
               \A\s*select(.*?)\bfrom\b
              }
              {$1 =~ m/\*/ ? "select 1 from" : "select isnull(coalesce($1)) from"}exi;
   return $query;
}

sub __delete_to_select {
   my ( $delete, $join ) = @_;
   if ( $join =~ m/\bjoin\b/ ) {
      return "select 1 from $join";
   }
   return "select * from $join";
}

sub __insert_to_select {
   my ( $tbl, $cols, $vals ) = @_;
   MKDEBUG && _d('Args:', @_);
   my @cols = split(/,/, $cols);
   MKDEBUG && _d('Cols:', @cols);
   $vals =~ s/^\(|\)$//g; # Strip leading/trailing parens
   my @vals = $vals =~ m/($quote_re|[^,]*${bal}[^,]*|[^,]+)/g;
   MKDEBUG && _d('Vals:', @vals);
   if ( @cols == @vals ) {
      return "select * from $tbl where "
         . join(' and ', map { "$cols[$_]=$vals[$_]" } (0..$#cols));
   }
   else {
      return "select * from $tbl limit 1";
   }
}

sub __insert_to_select_with_set {
   my ( $from, $set ) = @_;
   $set =~ s/,/ and /g;
   return "select * from $from where $set ";
}

sub __update_to_select {
   my ( $from, $set, $where, $limit ) = @_;
   return "select $set from $from "
      . ( $where ? "where $where" : '' )
      . ( $limit ? " $limit "      : '' );
}

sub wrap_in_derived {
   my ( $self, $query ) = @_;
   return unless $query;
   return $query =~ m/\A\s*select/i
      ? "select 1 from ($query) as x limit 1"
      : $query;
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
# End QueryRewriter package
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
# QueryParser package 7452
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/QueryParser.pm
#   trunk/common/t/QueryParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package QueryParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;
our $tbl_ident = qr/(?:`[^`]+`|\w+)(?:\.(?:`[^`]+`|\w+))?/;
our $tbl_regex = qr{
         \b(?:FROM|JOIN|(?<!KEY\s)UPDATE|INTO) # Words that precede table names
         \b\s*
         \(?                                   # Optional paren around tables
         ($tbl_ident
            (?: (?:\s+ (?:AS\s+)? \w+)?, \s*$tbl_ident )*
         )
      }xio;
our $has_derived = qr{
      \b(?:FROM|JOIN|,)
      \s*\(\s*SELECT
   }xi;

our $data_def_stmts = qr/(?:CREATE|ALTER|TRUNCATE|DROP|RENAME)/i;

our $data_manip_stmts = qr/(?:INSERT|UPDATE|DELETE|REPLACE)/i;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub get_tables {
   my ( $self, $query ) = @_;
   return unless $query;
   MKDEBUG && _d('Getting tables for', $query);

   my ( $ddl_stmt ) = $query =~ m/^\s*($data_def_stmts)\b/i;
   if ( $ddl_stmt ) {
      MKDEBUG && _d('Special table type:', $ddl_stmt);
      $query =~ s/IF\s+(?:NOT\s+)?EXISTS//i;
      if ( $query =~ m/$ddl_stmt DATABASE\b/i ) {
         MKDEBUG && _d('Query alters a database, not a table');
         return ();
      }
      if ( $ddl_stmt =~ m/CREATE/i && $query =~ m/$ddl_stmt\b.+?\bSELECT\b/i ) {
         my ($select) = $query =~ m/\b(SELECT\b.+)/is;
         MKDEBUG && _d('CREATE TABLE ... SELECT:', $select);
         return $self->get_tables($select);
      }
      my ($tbl) = $query =~ m/TABLE\s+($tbl_ident)(\s+.*)?/i;
      MKDEBUG && _d('Matches table:', $tbl);
      return ($tbl);
   }

   $query =~ s/ (?:LOW_PRIORITY|IGNORE|STRAIGHT_JOIN)//ig;

   if ( $query =~ /^\s*LOCK TABLES/i ) {
      MKDEBUG && _d('Special table type: LOCK TABLES');
      $query =~ s/^(\s*LOCK TABLES\s+)//;
      $query =~ s/\s+(?:READ|WRITE|LOCAL)+\s*//g;
      MKDEBUG && _d('Locked tables:', $query);
      $query = "FROM $query";
   }

   $query =~ s/\\["']//g;                # quoted strings
   $query =~ s/".*?"/?/sg;               # quoted strings
   $query =~ s/'.*?'/?/sg;               # quoted strings

   my @tables;
   foreach my $tbls ( $query =~ m/$tbl_regex/gio ) {
      MKDEBUG && _d('Match tables:', $tbls);

      next if $tbls =~ m/\ASELECT\b/i;

      foreach my $tbl ( split(',', $tbls) ) {
         $tbl =~ s/\s*($tbl_ident)(\s+.*)?/$1/gio;

         if ( $tbl !~ m/[a-zA-Z]/ ) {
            MKDEBUG && _d('Skipping suspicious table name:', $tbl);
            next;
         }

         push @tables, $tbl;
      }
   }
   return @tables;
}

sub has_derived_table {
   my ( $self, $query ) = @_;
   my $match = $query =~ m/$has_derived/;
   MKDEBUG && _d($query, 'has ' . ($match ? 'a' : 'no') . ' derived table');
   return $match;
}

sub get_aliases {
   my ( $self, $query, $list ) = @_;

   my $result = {
      DATABASE => {},
      TABLE    => {},
   };
   return $result unless $query;

   $query =~ s/ (?:LOW_PRIORITY|IGNORE|STRAIGHT_JOIN)//ig;

   $query =~ s/ (?:INNER|OUTER|CROSS|LEFT|RIGHT|NATURAL)//ig;

   my @tbl_refs;
   my ($tbl_refs, $from) = $query =~ m{
      (
         (FROM|INTO|UPDATE)\b\s*   # Keyword before table refs
         .+?                       # Table refs
      )
      (?:\s+|\z)                   # If the query does not end with the table
      (?:WHERE|ORDER|LIMIT|HAVING|SET|VALUES|\z) # Keyword after table refs
   }ix;

   if ( $tbl_refs ) {

      if ( $query =~ m/^(?:INSERT|REPLACE)/i ) {
         $tbl_refs =~ s/\([^\)]+\)\s*//;
      }

      MKDEBUG && _d('tbl refs:', $tbl_refs);

      my $before_tbl = qr/(?:,|JOIN|\s|$from)+/i;

      my $after_tbl  = qr/(?:,|JOIN|ON|USING|\z)/i;

      $tbl_refs =~ s/ = /=/g;

      while (
         $tbl_refs =~ m{
            $before_tbl\b\s*
               ( ($tbl_ident) (?:\s+ (?:AS\s+)? (\w+))? )
            \s*$after_tbl
         }xgio )
      {
         my ( $tbl_ref, $db_tbl, $alias ) = ($1, $2, $3);
         MKDEBUG && _d('Match table:', $tbl_ref);
         push @tbl_refs, $tbl_ref;
         $alias = $self->trim_identifier($alias);

         if ( $tbl_ref =~ m/^AS\s+\w+/i ) {
            MKDEBUG && _d('Subquery', $tbl_ref);
            $result->{TABLE}->{$alias} = undef;
            next;
         }

         my ( $db, $tbl ) = $db_tbl =~ m/^(?:(.*?)\.)?(.*)/;
         $db  = $self->trim_identifier($db);
         $tbl = $self->trim_identifier($tbl);
         $result->{TABLE}->{$alias || $tbl} = $tbl;
         $result->{DATABASE}->{$tbl}        = $db if $db;
      }
   }
   else {
      MKDEBUG && _d("No tables ref in", $query);
   }

   if ( $list ) {
      return \@tbl_refs;
   }
   else {
      return $result;
   }
}

sub split {
   my ( $self, $query ) = @_;
   return unless $query;
   $query = $self->clean_query($query);
   MKDEBUG && _d('Splitting', $query);

   my $verbs = qr{SELECT|INSERT|UPDATE|DELETE|REPLACE|UNION|CREATE}i;

   my @split_statements = grep { $_ } split(m/\b($verbs\b(?!(?:\s*\()))/io, $query);

   my @statements;
   if ( @split_statements == 1 ) {
      push @statements, $query;
   }
   else {
      for ( my $i = 0; $i <= $#split_statements; $i += 2 ) {
         push @statements, $split_statements[$i].$split_statements[$i+1];

         if ( $statements[-2] && $statements[-2] =~ m/on duplicate key\s+$/i ) {
            $statements[-2] .= pop @statements;
         }
      }
   }

   MKDEBUG && _d('statements:', map { $_ ? "<$_>" : 'none' } @statements);
   return @statements;
}

sub clean_query {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s!/\*.*?\*/! !g;  # Remove /* comment blocks */
   $query =~ s/^\s+//;         # Remove leading spaces
   $query =~ s/\s+$//;         # Remove trailing spaces
   $query =~ s/\s{2,}/ /g;     # Remove extra spaces
   return $query;
}

sub split_subquery {
   my ( $self, $query ) = @_;
   return unless $query;
   $query = $self->clean_query($query);
   $query =~ s/;$//;

   my @subqueries;
   my $sqno = 0;  # subquery number
   my $pos  = 0;
   while ( $query =~ m/(\S+)(?:\s+|\Z)/g ) {
      $pos = pos($query);
      my $word = $1;
      MKDEBUG && _d($word, $sqno);
      if ( $word =~ m/^\(?SELECT\b/i ) {
         my $start_pos = $pos - length($word) - 1;
         if ( $start_pos ) {
            $sqno++;
            MKDEBUG && _d('Subquery', $sqno, 'starts at', $start_pos);
            $subqueries[$sqno] = {
               start_pos => $start_pos,
               end_pos   => 0,
               len       => 0,
               words     => [$word],
               lp        => 1, # left parentheses
               rp        => 0, # right parentheses
               done      => 0,
            };
         }
         else {
            MKDEBUG && _d('Main SELECT at pos 0');
         }
      }
      else {
         next unless $sqno;  # next unless we're in a subquery
         MKDEBUG && _d('In subquery', $sqno);
         my $sq = $subqueries[$sqno];
         if ( $sq->{done} ) {
            MKDEBUG && _d('This subquery is done; SQL is for',
               ($sqno - 1 ? "subquery $sqno" : "the main SELECT"));
            next;
         }
         push @{$sq->{words}}, $word;
         my $lp = ($word =~ tr/\(//) || 0;
         my $rp = ($word =~ tr/\)//) || 0;
         MKDEBUG && _d('parentheses left', $lp, 'right', $rp);
         if ( ($sq->{lp} + $lp) - ($sq->{rp} + $rp) == 0 ) {
            my $end_pos = $pos - 1;
            MKDEBUG && _d('Subquery', $sqno, 'ends at', $end_pos);
            $sq->{end_pos} = $end_pos;
            $sq->{len}     = $end_pos - $sq->{start_pos};
         }
      }
   }

   for my $i ( 1..$#subqueries ) {
      my $sq = $subqueries[$i];
      next unless $sq;
      $sq->{sql} = join(' ', @{$sq->{words}});
      substr $query,
         $sq->{start_pos} + 1,  # +1 for (
         $sq->{len} - 1,        # -1 for )
         "__subquery_$i";
   }

   return $query, map { $_->{sql} } grep { defined $_ } @subqueries;
}

sub query_type {
   my ( $self, $query, $qr ) = @_;
   my ($type, undef) = $qr->distill_verbs($query);
   my $rw;
   if ( $type =~ m/^SELECT\b/ ) {
      $rw = 'read';
   }
   elsif ( $type =~ m/^$data_manip_stmts\b/
           || $type =~ m/^$data_def_stmts\b/  ) {
      $rw = 'write'
   }

   return {
      type => $type,
      rw   => $rw,
   }
}

sub get_columns {
   my ( $self, $query ) = @_;
   my $cols = [];
   return $cols unless $query;
   my $cols_def;

   if ( $query =~ m/^SELECT/i ) {
      $query =~ s/
         ^SELECT\s+
           (?:ALL
              |DISTINCT
              |DISTINCTROW
              |HIGH_PRIORITY
              |STRAIGHT_JOIN
              |SQL_SMALL_RESULT
              |SQL_BIG_RESULT
              |SQL_BUFFER_RESULT
              |SQL_CACHE
              |SQL_NO_CACHE
              |SQL_CALC_FOUND_ROWS
           )\s+
      /SELECT /xgi;
      ($cols_def) = $query =~ m/^SELECT\s+(.+?)\s+FROM/i;
   }
   elsif ( $query =~ m/^(?:INSERT|REPLACE)/i ) {
      ($cols_def) = $query =~ m/\(([^\)]+)\)\s*VALUE/i;
   }

   MKDEBUG && _d('Columns:', $cols_def);
   if ( $cols_def ) {
      @$cols = split(',', $cols_def);
      map {
         my $col = $_;
         $col = s/^\s+//g;
         $col = s/\s+$//g;
         $col;
      } @$cols;
   }

   return $cols;
}

sub parse {
   my ( $self, $query ) = @_;
   return unless $query;
   my $parsed = {};

   $query =~ s/\n/ /g;
   $query = $self->clean_query($query);

   $parsed->{query}   = $query,
   $parsed->{tables}  = $self->get_aliases($query, 1);
   $parsed->{columns} = $self->get_columns($query);

   my ($type) = $query =~ m/^(\w+)/;
   $parsed->{type} = lc $type;


   $parsed->{sub_queries} = [];

   return $parsed;
}

sub extract_tables {
   my ( $self, %args ) = @_;
   my $query      = $args{query};
   my $default_db = $args{default_db};
   my $q          = $self->{Quoter} || $args{Quoter};
   return unless $query;
   MKDEBUG && _d('Extracting tables');
   my @tables;
   my %seen;
   foreach my $db_tbl ( $self->get_tables($query) ) {
      next unless $db_tbl;
      next if $seen{$db_tbl}++; # Unique-ify for issue 337.
      my ( $db, $tbl ) = $q->split_unquote($db_tbl);
      push @tables, [ $db || $default_db, $tbl ];
   }
   return @tables;
}

sub trim_identifier {
   my ($self, $str) = @_;
   return unless defined $str;
   $str =~ s/`//g;
   $str =~ s/^\s+//;
   $str =~ s/\s+$//;
   return $str;
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
# End QueryParser package
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
# SlavePrefetch package 6725
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SlavePrefetch.pm
#   trunk/common/t/SlavePrefetch.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SlavePrefetch;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use List::Util qw(min max sum);
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(dbh oktorun chk_int chk_min chk_max QueryRewriter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      offset              => 128,
      window              => 4_096,
      'io-lag'            => 1_024,
      'query-sample-size' => 4,
      'max-query-time'    => 1,
      mysqlbinlog         => 'mysqlbinlog',

      %args,

      pos          => 0,
      next         => 0,
      last_ts      => 0,
      slave        => undef,
      last_chk     => 0,
      query_stats  => {},
      query_errors => {},
      tbl_cols     => {},
      callbacks    => {
         show_slave_status => sub {
            my ( $dbh ) = @_;
            return $dbh->selectrow_hashref("SHOW SLAVE STATUS");
         }, 
         use_db            => sub {
            my ( $dbh, $db ) = @_;
            eval {
               MKDEBUG && _d('USE', $db);
               $dbh->do("USE `$db`");
            };
            MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
            return;
         },
         wait_for_master   => \&_wait_for_master,
      },
   };

   init_stats($self->{stats}, $args{stats_file}, $args{'query-sample-size'})
      if $args{stats_file};

   return bless $self, $class;
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

sub init_stats {
   my ( $stats, $file, $n_samples ) = @_;
   open my $fh, "<", $file or die $OS_ERROR;
   MKDEBUG && _d('Reading saved stats from', $file);
   my ($type, $rest);
   while ( my $line = <$fh> ) {
      ($type, $rest) = $line =~ m/^# (query|stats): (.*)$/;
      next unless $type;
      if ( $type eq 'query' ) {
         $stats->{$rest} = { seen => 1, samples => [] };
      }
      else {
         my ( $seen, $exec, $sum, $avg )
            = $rest =~ m/seen=(\S+) exec=(\S+) sum=(\S+) avg=(\S+)/;
         if ( $seen ) {
            $stats->{$rest}->{samples}
               = [ map { $avg } (1..$n_samples) ];
            $stats->{$rest}->{avg} = $avg;
         }
      }
   }
   close $fh or die $OS_ERROR;
   return;
}

sub get_stats {
   my ( $self ) = @_;
   return $self->{stats}, $self->{query_stats}, $self->{query_errors};
}

sub reset_stats {
   my ( $self, %args ) = @_;
   $self->{stats} = { events => 0, } if $args{all} || $args{stats};
   $self->{query_stats}  = {}        if $args{all} || $args{query_stats};
   $self->{query_errors} = {}        if $args{all} || $args{query_errors};
   return;
}


sub open_relay_log {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(relay_log) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   if ( !-r $args{relay_log} ) {
      die "Relay log $args{relay_log} does not exist or is not readable";
   }

   my $cmd = $self->_mysqlbinlog_cmd(%args);

   my $mysqlbinlog_pid = open my $fh, "$cmd |"
      or die $OS_ERROR; # succeeds even on error
   if ( $CHILD_ERROR >> 8 ) {
      die "$cmd returned exit code " . ($CHILD_ERROR >> 8)
         . '.  Try running the command manually or using MKDEBUG=1' ;
   }
   MKDEBUG && _d("mysqlbinlog pid:", $mysqlbinlog_pid);
   $self->{mysqlbinlog_pid} = $mysqlbinlog_pid;
   $self->{stats}->{mysqlbinlog}++;
   return $fh;
}

sub _mysqlbinlog_cmd {
   my ( $self, %args ) = @_;
   my $cmd = "$self->{mysqlbinlog} "
           . ($args{tmpdir}    ? "--local-load=$args{tmpdir} "   : '')
           . ($args{start_pos} ? "--start-pos=$args{start_pos} " : '')
           . $args{relay_log};
   MKDEBUG && _d($cmd);
   return $cmd;
}

sub close_relay_log {
   my ( $self, $fh ) = @_;
   MKDEBUG && _d('Closing relay log');

   if ( my $pid = $self->{mysqlbinlog_pid} ) {
      MKDEBUG && _d("Killing mysqlbinlog pid:", $pid);
      kill(15, $pid) if $pid;
      $self->{mysqlbinlog_pid} = undef;
   }
   else {
      MKDEBUG && _d("No mysqlbinlog pid to kill");
   }

   close $fh or warn "Error closing mysqlbinlog pipe: $OS_ERROR";
   MKDEBUG && _d('mysqlbinlog exit status:', $CHILD_ERROR >> 8);

   return;
}

sub _check_slave_status {
   my ( $self ) = @_;
   return 1 unless defined $self->{slave};
   return
      $self->{pos} > $self->{slave}->{pos}
      && ($self->{stats}->{events} - $self->{last_chk}) >= $self->{chk_int}
         ? 1 : 0;
}

sub _get_next_chk_int {
   my ( $self ) = @_;
   if ( $self->{pos} <= $self->{slave}->{pos} ) {
      return max($self->{chk_min}, $self->{chk_int} / 2);
   }
   else {
      return min($self->{chk_max}, $self->{chk_int} * 2);
   }
}

sub _get_slave_status {
   my ( $self ) = @_;
   $self->{stats}->{show_slave_status}++;


   my $show_slave_status = $self->{callbacks}->{show_slave_status};
   my $status            = $show_slave_status->($self->{dbh}); 
   if ( !$status || !%$status ) {
      die "No output from SHOW SLAVE STATUS";
   }
   my %status = (
      running => ($status->{slave_sql_running} || '') eq 'Yes' ? 1 : 0,
      file    => $status->{relay_log_file},
      pos     => $status->{relay_log_pos},
      lag   => $status->{master_log_file} eq $status->{relay_master_log_file}
             ? $status->{read_master_log_pos} - $status->{exec_master_log_pos}
             : 0,
      mfile => $status->{relay_master_log_file},
      mpos  => $status->{exec_master_log_pos},
   );

   $self->{slave}    = \%status;
   $self->{last_chk} = $self->{stats}->{events};
   MKDEBUG && _d('Slave status:', Dumper($self->{slave}));
   return;
}

sub get_slave_status {
   my ( $self ) = @_;
   $self->_get_slave_status();
   return $self->{slave};
}

sub slave_is_running {
   my ( $self, $dbh ) = @_;
   $self->_get_slave_status() unless defined $self->{slave};
   return $self->{slave}->{running};
}

sub get_interval {
   my ( $self ) = @_;
   return $self->{stats}->{events}, $self->{last_chk};
}

sub get_pipeline_pos {
   my ( $self ) = @_;
   return $self->{pos}, $self->{next}, $self->{last_ts};
}

sub set_pipeline_pos {
   my ( $self, $pos, $next, $ts ) = @_;
   die "pos must be >= 0"  unless defined $pos && $pos >= 0;
   die "next must be >= 0" unless defined $pos && $pos >= 0;
   $self->{pos}     = $pos;
   $self->{next}    = $next;
   $self->{last_ts} = $ts || 0;  # undef same as zero
   MKDEBUG && _d('Set pipeline pos', @_);
   return;
}

sub reset_pipeline_pos {
   my ( $self ) = @_;
   $self->{pos}     = 0; # Current position we're reading in relay log.
   $self->{next}    = 0; # Start of next relay log event.
   $self->{last_ts} = 0; # Last seen timestamp.
   MKDEBUG && _d('Reset pipeline');
   return;
}

sub in_window {
   my ( $self, %args ) = @_;
   my ($event, $oktorun) = @args{qw(event oktorun)};


   if ( !$event->{offset} ) {
      MKDEBUG && _d('Event has no offset, skipping');
      $self->{stats}->{no_offset}++;
      return;
   }

   $self->{pos}  = $event->{offset} if $event->{offset};
   $self->{next} = max($self->{next},$self->{pos}+($event->{end_log_pos} || 0));

   if ( $self->{progress}
        && $self->{stats}->{events} % $self->{progress} == 0 ) {
      print("# $self->{slave}->{file} $self->{pos} ",
         join(' ', map { "$_:$self->{stats}->{$_}" } keys %{$self->{stats}}),
         "\n");
   }

   if ( $self->_check_slave_status() ) { 
      MKDEBUG && _d('Checking slave status at interval',
         $self->{stats}->{events});
      my $current_relay_log = $self->{slave}->{file};
      $self->_get_slave_status();
      if (    $current_relay_log
           && $current_relay_log ne $self->{slave}->{file} ) {
         MKDEBUG && _d('Relay log file has changed from',
            $current_relay_log, 'to', $self->{slave}->{file});
         $self->reset_pipeline_pos();
         $args{oktorun}->(0) if $args{oktorun};
         return;
      }
      $self->{chk_int} = $self->_get_next_chk_int();
      MKDEBUG && _d('Next check interval:', $self->{chk_int});
   }

   return $event if $self->_in_window();
}

sub rewrite_query { 
   my ( $self, $event, %args ) = @_;

   if ( !$event->{arg} ) {
      $self->{stats}->{no_arg}++;
      return;
   }

   if ( my ($file) = $event->{arg} =~ m/INFILE ('[^']+')/i ) {
      $self->{stats}->{load_data_infile}++;
      if ( !unlink($file) ) {
         MKDEBUG && _d('Could not unlink', $file);
         $self->{stats}->{could_not_unlink}++;
      }
      return;
   }

   my ($query, $fingerprint) = $self->prepare_query($event->{arg});

   if ( !$query
        && $event->{arg} =~ m/^INSERT|REPLACE/i
        && $self->{TableParser}
        && $self->{QueryParser} )
   {
      my $new_arg = $self->inject_columns_list($event->{arg}, %args);
      return unless $new_arg;
      $event->{arg} = $new_arg;
      return $self->rewrite_query($event);
   }

   if ( !$query ) {
      MKDEBUG && _d('Failed to prepare query, skipping');
      return;
   }
   $event->{arg_original} = $event->{arg};
   $event->{arg}          = $query;  # SELECT query
   $event->{fingerprint}  = $fingerprint;

   return $event;
}

sub inject_columns_list {
   my ( $self, $query, %args ) = @_; 
   my $tp   = $self->{TableParser};
   my $qp   = $self->{QueryParser};
   my $q    = $self->{Quoter};
   my $dbh  = $self->{dbh};
   return unless $tp && $qp;
   MKDEBUG && _d('Attempting to inject columns list into query');

   my $default_db = $args{default_db};

   my @tbls = $qp->get_tables($query);
   if ( !@tbls ) {
      MKDEBUG && _d("Can't get tables from query");
      return;
   }
   if ( @tbls > 1 ) {
      MKDEBUG && _d("Query has more than one table");
      return;
   }

   if ( $q ) {
      my ($db, $tbl) = $q->split_unquote($tbls[0]);
      if ( !$db && $default_db ) {
         MKDEBUG && _d('Using default db:', $default_db);
         $tbls[0] = "$default_db.$tbl";
      }
   }

   my $tbl_cols = $self->{tbl_cols}->{$tbls[0]};
   if ( !$tbl_cols ) {
      my $sql = "SHOW CREATE TABLE $tbls[0]";
      MKDEBUG && _d($sql);
      eval {
         my $show_create = $dbh->selectrow_arrayref($sql)->[1];
         if ( !$show_create ) {
            MKDEBUG && _d("Failed to", $sql);
            return;
         }
         my $tbl_struct = $tp->parse($show_create);
         if ( !$tbl_struct ) {
            MKDEBUG && _d("Failed to parse table struct");
            return;
         }
         $tbl_cols = join(',', map { "`$_`" } @{$tbl_struct->{cols}});
         $self->{tbl_cols}->{$tbls[0]} = $tbl_cols;
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d($EVAL_ERROR);
         return;
      }
   }
   else {
      MKDEBUG && _d('Using cached columns for', $tbls[0]);
   }

   if ( !($query =~ s/ VALUES?/ ($tbl_cols) VALUES/i) ) {
      MKDEBUG && _d("Failed to inject columns list");
      return;
   }

   MKDEBUG && _d('Successfully inject columns list:',
      substr($query, 0, 100), '...');

   return $query;
}

sub get_window {
   my ( $self ) = @_;
   return $self->{offset}, $self->{window};
}

sub set_window {
   my ( $self, $offset, $window ) = @_;
   die "offset must be > 0" unless $offset;
   die "window must be > 0" unless $window;
   $self->{offset} = $offset;
   $self->{window} = $window;
   MKDEBUG && _d('Set window', @_);
   return;
}

sub _in_window {
   my ( $self ) = @_;
   MKDEBUG && _d('Checking window, pos:', $self->{pos},
      'next', $self->{next},
      'slave pos:', $self->{slave}->{pos},
      'master pos', $self->{slave}->{mpos});

   return 0 unless $self->_far_enough_ahead();

   my $wait_for_master = $self->{callbacks}->{wait_for_master};
   my %wait_args       = (
      dbh       => $self->{dbh},
      mfile     => $self->{slave}->{mfile},
      until_pos => $self->next_window(),
   );

   my $oktorun = $self->{oktorun};
   while ( $oktorun->()
           && $self->{slave}->{running}
           && ($self->_too_far_ahead() || $self->_too_close_to_io()) ) {
      $self->{stats}->{master_pos_wait}++;
      if ( $wait_for_master->(%wait_args) > 0 ) {
         if ( $self->_too_far_ahead() ) {
            $self->{stats}->{too_far_ahead}++;
         }
         elsif ( $self->_too_close_to_io() ) {
            $self->{stats}->{too_close_to_io_thread}++;
         }
      }
      else {
         MKDEBUG && _d('SQL thread did not advance');
      }
      $self->_get_slave_status();
   }

   if (     $self->{slave}->{running}
        &&  $self->_far_enough_ahead()
        && !$self->_too_far_ahead()
        && !$self->_too_close_to_io() )
   {
      MKDEBUG && _d('Event', $self->{stats}->{events}, 'is in the window');
      return 1;
   }

   MKDEBUG && _d('Event', $self->{stats}->{events}, 'is not in the window');
   return 0;
}

sub _far_enough_ahead {
   my ( $self ) = @_;
   if ( $self->{pos} < $self->{slave}->{pos} + $self->{offset} ) {
      MKDEBUG && _d($self->{pos}, 'is not',
         $self->{offset}, 'ahead of', $self->{slave}->{pos});
      $self->{stats}->{not_far_enough_ahead}++;
      return 0;
   }
   return 1;
}

sub _too_far_ahead {
   my ( $self ) = @_;
   my $too_far =
      $self->{pos}
         > $self->{slave}->{pos} + $self->{offset} + $self->{window} ? 1 : 0;
   MKDEBUG && _d('pos', $self->{pos}, 'too far ahead of',
      'slave pos', $self->{slave}->{pos}, ':', $too_far ? 'yes' : 'no');
   return $too_far;
}

sub _too_close_to_io {
   my ( $self ) = @_;
   my $too_close= $self->{slave}->{lag}
      && $self->{pos}
         >= $self->{slave}->{pos} + $self->{slave}->{lag} - $self->{'io-lag'};
   MKDEBUG && _d('pos', $self->{pos},
      'too close to I/O thread pos', $self->{slave}->{pos}, '+',
      $self->{slave}->{lag}, ':', $too_close ? 'yes' : 'no');
   return $too_close;
}

sub _wait_for_master {
   my ( %args ) = @_;
   my @required_args = qw(dbh mfile until_pos);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $timeout = $args{timeout} || 1;
   my ($dbh, $mfile, $until_pos) = @args{@required_args};
   my $sql = "SELECT COALESCE(MASTER_POS_WAIT('$mfile',$until_pos,$timeout),0)";
   MKDEBUG && _d('Waiting for master:', $sql);
   my $start = gettimeofday();
   my ($events) = $dbh->selectrow_array($sql);
   MKDEBUG && _d('Waited', (gettimeofday - $start), 'and got', $events);
   return $events;
}

sub next_window {
   my ( $self ) = @_;
   my $next_window = 
         $self->{slave}->{mpos}                    # master pos
         + ($self->{pos} - $self->{slave}->{pos})  # how far we're ahead
         - $self->{offset};                        # offset;
   MKDEBUG && _d('Next window, master pos:', $self->{slave}->{mpos},
      'next window:', $next_window,
      'bytes left:', $next_window - $self->{offset} - $self->{slave}->{mpos});
   return $next_window;
}

sub prepare_query {
   my ( $self, $query ) = @_;
   my $qr = $self->{QueryRewriter};

   $query = $qr->strip_comments($query);

   return unless $self->query_is_allowed($query);

   if ( (my ($new_ts) = $query =~ m/SET timestamp=(\d+)/) ) {
      MKDEBUG && _d('timestamp query:', $query);
      if ( $new_ts == $self->{last_ts} ) {
         MKDEBUG && _d('Already saw timestamp', $new_ts);
         $self->{stats}->{same_timestamp}++;
         return;
      }
      else {
         $self->{last_ts} = $new_ts;
      }
   }

   my $select = $qr->convert_to_select($query);
   if ( $select !~ m/\A\s*(?:set|select|use)/i ) {
      MKDEBUG && _d('Cannot rewrite query as SELECT:',
         (length $query > 240 ? substr($query, 0, 237) . '...' : $query));
      _d("Not rewritten: $query") if $self->{'print-nonrewritten'};
      $self->{stats}->{query_not_rewritten}++;
      return;
   }

   my $fingerprint = $qr->fingerprint(
      $select,
      { prefixes => $self->{'num-prefix'} }
   );

   if ((my $avg = $self->get_avg($fingerprint)) >= $self->{'max-query-time'}) {
      MKDEBUG && _d('Avg time', $avg, 'too long for', $fingerprint);
      $self->{stats}->{query_too_long}++;
      return $self->_wait_skip_query($avg);
   }

   $select = $qr->convert_select_list($select);


   return $select, $fingerprint;
}

sub _wait_skip_query {
   my ( $self, $wait ) = @_;
   my $wait_for_master = $self->{callbacks}->{wait_for_master};
   my $until_pos = 
         $self->{slave}->{mpos}                    # master pos
         + ($self->{pos} - $self->{slave}->{pos})  # how far we're ahead
         + 1;                                      # 1 past this query
   my %wait_args       = (
      dbh       => $self->{dbh},
      mfile     => $self->{slave}->{mfile},
      until_pos => $until_pos,
      timeout   => $wait,
   );
   my $start = gettimeofday();
   while ( $self->{slave}->{running}
           && ($self->{slave}->{pos} <= $self->{pos}) ) {
      $self->{stats}->{master_pos_wait}++;
      $wait_for_master->(%wait_args);
      $self->_get_slave_status();
      MKDEBUG && _d('Bytes until slave reaches wait-skip query:',
         $self->{pos} - $self->{slave}->{pos});
   }
   MKDEBUG && _d('Waited', (gettimeofday - $start), 'to skip query');
   $self->_get_slave_status();
   return;
}

sub query_is_allowed {
   my ( $self, $query ) = @_;
   return unless $query;
   if ( $query =~ m/\A\s*(?:set [t@]|use|insert|update|delete|replace)/i ) {
      my $reject_regexp = $self->{reject_regexp};
      my $permit_regexp = $self->{permit_regexp};
      if ( ($reject_regexp && $query =~ m/$reject_regexp/o)
           || ($permit_regexp && $query !~ m/$permit_regexp/o) )
      {
         MKDEBUG && _d('Query is not allowed, fails permit/reject regexp');
         $self->{stats}->{event_filtered_out}++;
         return 0;
      }
      return 1;
   }
   MKDEBUG && _d('Query is not allowed, wrong type');
   $self->{stats}->{event_not_allowed}++;
   return 0;
}

sub exec {
   my ( $self, %args ) = @_;
   my $query       = $args{query};
   my $fingerprint = $args{fingerprint};
   eval {
      my $start = gettimeofday();
      $self->{dbh}->do($query);
      $self->__store_avg($fingerprint, gettimeofday() - $start);
   };
   if ( $EVAL_ERROR ) {
      $self->{stats}->{query_error}++;
      $self->{query_errors}->{$fingerprint}++;
      if ( (($self->{errors} || 0) == 2) || MKDEBUG ) {
         _d($EVAL_ERROR);
         _d('SQL was:', $query);
      }
   }
   return;
}

sub __store_avg {
   my ( $self, $fingerprint, $time ) = @_;
   MKDEBUG && _d('Execution time:', $fingerprint, $time);
   my $query_stats = $self->{query_stats}->{$fingerprint} ||= {};
   my $samples     = $query_stats->{samples} ||= [];
   push @$samples, $time;
   if ( @$samples > $self->{'query-sample-size'} ) {
      shift @$samples;
   }
   $query_stats->{avg} = sum(@$samples) / $self->{'query-sample-size'};
   $query_stats->{exec}++;
   $query_stats->{sum} += $time;
   MKDEBUG && _d('Average time:', $query_stats->{avg});
   return;
}

sub get_avg {
   my ( $self, $fingerprint ) = @_;
   $self->{query_stats}->{$fingerprint}->{seen}++;
   return $self->{query_stats}->{$fingerprint}->{avg} || 0;
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
# End SlavePrefetch package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_slave_prefetch;

use English qw(-no_match_vars);
use threads;
use Thread::Queue;
use List::Util qw(max sum);
use Time::HiRes qw(sleep);
use File::Basename qw(dirname);
use sigtrap qw(handler finish untrapped normal-signals);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# $oktorun must be global so finish() can access it if we catch a signal.
my $oktorun  = 1;
my $sentinel;
my $run_time;
my $end;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # Reset global vars.
   $oktorun   = 1;
   $sentinel  = undef;
   $run_time  = undef;
   $end       = undef;

   # ##########################################################################
   # Get configuration information.
   # ##########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   if ( $o->get('run-time') ) {
      $o->set('run-time', max($o->get('run-time'), 1));
   }

   my ($chk_int, $chk_min, $chk_max) = @{$o->get('check-interval')};
   if ( grep { !defined $_ || $_ !~ m/^\d+$/ } ($chk_int, $chk_min, $chk_max) )
   {
      $o->save_error("You must specify three elements for --check-interval");
   }
   elsif ( $chk_int > $chk_max || $chk_int < $chk_min
           || $chk_max < $chk_min || $chk_min < 0 ) {
      $o->save_error("You specified an invalid range for --check-interval");
   }

   $o->set('sleep', 0) if $o->get('relay-log') && $o->get('dry-run');

   if ( @ARGV > 1 ) {
      $o->save_error("You can specify only one FILE");
   }

   $o->usage_or_errors();

   # ########################################################################
   # First things first: if --stop was given, create the sentinel file.
   # ########################################################################
   $sentinel = $o->get('sentinel');
   if ( $o->get('stop') ) {
      open my $file, ">", $sentinel
         or die "Cannot open $sentinel: $OS_ERROR\n";
      print $file "Remove this file to permit mk-slave-prefetch to run\n"
         or die "Cannot write to $sentinel: $OS_ERROR\n";
      close $file
         or die "Cannot close $sentinel: $OS_ERROR\n";
      print "Successfully created file $sentinel\n";
      return 0;
   }

   # ########################################################################
   # Get the database connection and set it up as desired: Lowercase all
   # column names for fetchrow_hashref. Don't disconnect on fork.  Disable
   # the query cache.
   # ########################################################################
   if ( $o->get('ask-pass') ) {
      $o->set('password', OptionParser::prompt_noecho("Enter password: "));
   }
   my $dsn = $dp->parse_options($o);
   my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), { AutoCommit => 1 });
   $dbh->{InactiveDestroy}  = 1;
   $dbh->{FetchHashKeyName} = 'NAME_lc';

   # ########################################################################
   # Disable query cache.
   # http://code.google.com/p/maatkit/issues/detail?id=992
   # ########################################################################
   my $sql = "SHOW VARIABLES LIKE 'have_query_cache'";
   MKDEBUG && _d($dbh, $sql);
   if ( my $have_qcache = $dbh->selectrow_hashref($sql) ) {
      if ( $have_qcache->{value} ) {
         $sql = '/*!40001 SET @@session.query_cache_type=OFF */';
         MKDEBUG && _d($dbh, $sql);
         $dbh->do($sql);
      }
   }

   # ########################################################################
   # Daemonize only after (potentially) asking for passwords.
   # ########################################################################
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

   # ########################################################################
   # Make common modules.
   # ########################################################################
   my $stats   = {
      events       => 0,
      query_stats  => {},
      query_errors => {},
   };
   my $relay_log_dir = $o->get('relay-log-dir');
   if ( !$relay_log_dir ) {
      my $dir = File::Basename::dirname(
         $dbh->selectrow_arrayref('SHOW VARIABLES LIKE "relay_log"')->[1]
      );
      # dirname() return . if the file has no path but this doesn't
      # mean MySQL is reading relay logs from . so we ignore this
      # and fall back to datadir next.
      $relay_log_dir = $dir unless $dir eq '.';
   }
   if ( !$relay_log_dir ) {
      $relay_log_dir
         = $dbh->selectrow_arrayref('SHOW VARIABLES LIKE "datadir"')->[1];
   }
   MKDEBUG && _d('relay log dir:', $relay_log_dir);

   my $q   = new Quoter();
   my $tp  = new TableParser(Quoter => $q);
   my $du  = new MySQLDump(cache => 0);
   my $lp  = new BinaryLogParser();
   my $qp  = new QueryParser();
   my $qr  = new QueryRewriter(QueryParser => $qp);
   my $vp  = new VersionParser();
   my $spf = new SlavePrefetch(
      dbh                  => $dbh,
      oktorun              => \&oktorun,
      chk_int              => $chk_int,
      chk_min              => $chk_min,
      chk_max              => $chk_max,
      have_subqueries      => $vp->version_ge($dbh,'4.1.0'),
      stats                => $stats,
      stats_file           => shift @ARGV,
      offset               => $o->get('offset'),
      window               => $o->get('window'),
      'io-lag'             => $o->get('io-lag'),
      'query-sample-size'  => $o->get('query-sample-size'),
      errors               => $o->get('errors'),
      'num-prefix'         => $o->get('num-prefix'),
      'max-query-time'     => $o->get('max-query-time'),
      'print-nonrewritten' => $o->get('print-nonrewritten'),
      'reject-regexp'      => $o->get('reject-regexp'),
      'permit-regexp'      => $o->get('permit-regexp'),
      progress             => $o->get('progress'),
      TableParser          => $o->get('inject-columns') ? $tp : undef,
      QueryParser          => $qp,
      QueryRewriter        => $qr,
      Quoter               => $q,
   );


   # ########################################################################
   # Create threads to execute and/or print primary and secondary queries.
   # ########################################################################
   # A pipeline process will enqueue rewritten queries which these threads
   # then either execute or print.  They're also responsible for doing
   # secondary index queries for --secondary-indexes.
   my $query_queue   = new Thread::Queue;
   my $n_threads     = $o->get('threads') || 1;

   # These don't change so no need to get() them every time.
   my $execute       = $o->get('execute');
   my $print         = $o->get('print');
   my $secondary_idx = $o->get('secondary-indexes');
   my $default_db    = $o->get('database');

   my @thrs;
   MKDEBUG && _d('Creating', $n_threads, 'threads');
   for ( 1..$n_threads ) {
      my $thr = threads::async {
         my $tdbh = $dp->get_dbh($dp->get_cxn_params($dsn), {AutoCommit => 1});
         $tdbh->{InactiveDestroy}  = 1;
         $tdbh->{FetchHashKeyName} = 'NAME_lc';
         $tdbh->do('/*!40001 SEt @@session.query_cache_type=OFF */');

         my $curdb = '';
         my $tid    = threads->self()->tid();
         MKDEBUG && _d('Thread', $tid, 'is alive');

         # Originally I wanted to enqueue the dbh with the query but
         # dequeue(COUNT) only works with Thread::Queue v2.01+ but
         # Perl v5.10.0 has v2.00; Perl 5.10.1 is needed which has v2.11.
         # So this is the more backwards-compatible solution (it should
         # work in Perl 5.8+). I also wanted to enqueue a hashref
         # (i.e. the event) but this isn't possible until v2.08/v5.10.1.
         while( my $event = $query_queue->dequeue() ) {
            my ($db, $query) = @$event;
            last if !$db && !$query;
            my @sql;
            if ( $db && (!$curdb || $curdb ne $db) ) {
               push @sql, "USE `$db`";
               $curdb = $db;
            }
            push @sql, $query;  # primary query
            if ( $secondary_idx ) {
               push @sql, get_secondary_index_queries(
                  query       => $query,
                  dbh         => $tdbh,
                  MySQLDump   => $du,
                  TableParser => $tp,
                  Quoter      => $q,
                  QueryParser => $qp,
                  default_db  => $curdb || $default_db,
               );
            }
            foreach my $sql ( @sql ) {
               if ( $execute ) {
                  eval {
                     $tdbh->do($sql);
                  };
                   warn "Thread $tid failed to executed query: $EVAL_ERROR"
                     if $EVAL_ERROR;
               }
               print "$sql /*tid$tid*/\n" if $print;
            }
         }  # dequeue
         $tdbh->disconnect();
         MKDEBUG && _d('Thread', $tid, 'is done');
      };  # thread code

      push @thrs, $thr;
      MKDEBUG && _d('Thread', $thr->tid(), 'created');
   }

   # ########################################################################
   # Create the pipeline of processes.
   # ########################################################################
   my @pipeline;

   if ( !$o->get('dry-run') ) {
      push @pipeline, sub {
      my ( %args ) = @_;
         # TODO: is this effective?
         if ( !$spf->slave_is_running() ) {
            MKDEBUG && _d('Slave is not running');
            sleep 1;
            $spf->get_slave_status();
            return;
         }
         return $args{event};
      };
   }

   # Parse events from relay log.
   push @pipeline, sub {
      my ( %args ) = @_;
      my $event = $lp->parse_event(%args);
      # SlavePrefetch requires $stats->{events} so we must keep it accurate.
      $stats->{events}++ if $event;
      return $event;
   };

   # Carry forward last known database.
   my $last_db;
   push @pipeline, sub {
      my ( %args ) = @_;
      my $event    = $args{event};
      $event->{db} = $last_db unless $event->{db};
      $last_db     = $event->{db} if ($last_db || '') ne ($event->{db} || '');
      return $event;
   };

   # Check that we're in the window for execution.
   if ( !$o->get('dry-run') ) {
      push @pipeline, sub {
         my ( %args ) = @_;
         return $spf->in_window(%args);
      }
   }

   # Enqueue the rewritten query, processed by the threads.
   push @pipeline, sub {
      my ( %args ) = @_;
      my $event = $spf->rewrite_query(
         $args{event},
         default_db => $args{event}->{db} || $default_db,
      );
      if ( $event ) {
         # See comments above dequeue() regarding why we cannot
         # enqueue a hashref.
         my @event :shared = (
            $event->{db},
            $event->{arg},
         );
         $query_queue->enqueue(\@event);
         MKDEBUG && _d('Enqueued query');
         return $event;
      }
      return;
   };

   # ########################################################################
   # The main work.
   # ########################################################################
   my $fh;
   my $next_event;
   my $tell;
   my $relay_logs = [ $o->get('relay-log') ];  # only reads 1 file for now
   my $more_events;
   my $oktorun_sub = sub { $more_events = $_[0]; };

   $run_time = $o->get('run-time');
   $end      = time + ($run_time || 0);  # When we should exit

   EVENT:
   while ( oktorun() ) {
      if ( !$fh ) {
         if ( $o->got('relay-log') ) {
            my $file = shift @$relay_logs;
            if ( !$file ) {
               MKDEBUG && _d('No more relay logs to parse');
               last EVENT;
            }
            if ( $file eq '-' ) {
               $fh = *STDIN;
               MKDEBUG && _d('Reading STDIN');
            }
            else {
               MKDEBUG && _d('Opening', $file);
               if ( !open $fh, '<', $file ) {
                  warn "Cannot open $file: $OS_ERROR";
                  $fh = undef;
                  next EVENT;
               }
            }
         }
         else {
            my $slave_status = $spf->get_slave_status();
            if ( !$slave_status->{running} ) {
               _d("Slave is not running; retry in 1s");
               sleep 1;
               next EVENT;
            }
            my $relay_log = "$relay_log_dir/$slave_status->{file}";
            eval {
               die "File does not exist" unless -f $relay_log;
               $fh = $spf->open_relay_log(
                  relay_log => $relay_log,
                  start_pos => $slave_status->{pos},
                  tmpdir    => $o->get('tmpdir'),
               );
            };
            if ( $EVAL_ERROR ) {
               if ( $o->get('continue-on-error') ) {
                  chomp $EVAL_ERROR;
                  warn "Cannot open relay log $relay_log: $EVAL_ERROR; "
                     . "retry in 1s";
                  sleep 1;
                  next EVENT;
               }
               else {
                  warn "Failed to open relay log $relay_log: $EVAL_ERROR";
                  last EVENT;
               }
            }
         }
         $next_event  = sub { return <$fh>;    };
         $tell        = sub { return tell $fh; };
         $more_events = 1;
      }

      eval {
         my $event = {};
         foreach my $process ( @pipeline ) {
            $event = $process->(
               event      => $event,
               next_event => $next_event,
               tell       => $tell,
               oktorun    => $oktorun_sub,
               fh         => $fh,
               dbh        => $dbh,
            );
            last unless $event;
         }
         if ( !$more_events ) {
            # If running live, no more events means we've parsed the
            # entire relay log and there's nothing left for us or the
            # slave to do.  So wait a second to see if the slave receives
            # more replicated statements.
            MKDEBUG && _d('No more events');
            $fh = $spf->close_relay_log($fh);
            sleep $o->get('sleep');
         }
      };
      if ( $EVAL_ERROR ) {
         warn $EVAL_ERROR;
         _d($EVAL_ERROR);
         $fh = $spf->close_relay_log($fh);
         next EVENT if $o->get('continue-on-error');
         last EVENT;
      }
   }  # EVENT

   # Print statistics
   my $query_stats  = $stats->{query_stats};
   my $query_errors = $stats->{query_errors};
   delete $stats->{query_stats};
   delete $stats->{query_errors};
   if ( $o->get('statistics') ) {
      # Print operations in order of descending count, with percentage.
      my $maxlen = max(0, map { length($_) } keys %$stats);
      my $total  = sum(0, ($stats->{events} || 1));
      printf("# %-${maxlen}s \%10s %10s\n", qw(Action Count Pct));
      my $fmt = "# %-${maxlen}s \%10d %10.2f\n";
      foreach my $key (
         reverse sort { $stats->{$a} <=> $stats->{$b} } keys %$stats )
      {
         printf($fmt, $key, $stats->{$key}, $stats->{$key} / $total * 100);
      }

      # Print normalized queries, their average exec times, times seen and
      # times executed.  Sort in order of times seen descending.
      foreach my $query (
         reverse sort {
            $query_stats->{$a}->{seen} <=> $query_stats->{$b}->{seen}
         } keys %$query_stats )
      {
         my $stats = $query_stats->{$query};
         print
            "# query: ", $query, "\n# stats: ",
            join(' ',
               (map { "$_=" . ($stats->{$_} || '0') } qw(seen exec sum avg))),
            "\n";
      }
   }

   # Print normalized versions of the queries that caused errors.
   if ( $o->get('errors') == 1 ) {
      foreach my $query (
         reverse sort {
            $query_errors->{$a} <=> $query_errors->{$b} } keys %$query_errors
      ) {
         print "# error $query_errors->{$query} times: ", $query, "\n";
      }
   }

   # The threads are blocking on dequeue().  They should stop when
   # they receive (undef, undef).  Then we can join them and exit.
   # kill -9 is required to terminate a blocked join(); we avoid that.
   for ( 1..$n_threads ) {
      my @done :shared = (undef, undef);
      $query_queue->enqueue(\@done);
   }
   while ( defined(my $thr = shift @thrs) ) {
      MKDEBUG && _d('Joining thread', $thr->tid());
      $thr->join();
   }

   return 0;
}

# ############################################################################
# Subroutines
# ############################################################################

# Catches signals so we can exit gracefully.
sub finish {
   my ( $signal ) = @_;
   print STDERR "Exiting on SIG$signal.\n";
   $oktorun = 0;
   return;
}

# Return true if it's still ok to run, else return false.
sub oktorun {
   my ( %args ) = @_;
   return                             # oktorun if
      !-f $sentinel                   # no sentinel file and
      && (!$run_time || time < $end)  # no runtime or before end time and
      && $oktorun;                    # oktorun
}

sub get_secondary_index_queries {
   my ( %args ) = @_;
   my @required_args = qw(dbh query MySQLDump TableParser Quoter QueryParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $query, $du, $tp, $q, $qp) = @args{@required_args};

   # The "current db" just for the puprose of making secondary index queries
   # is, first, the db parsed from the query query then, two, failing that
   # the default db (where the default db is $event->{db} || --database).
   # This is so cases like,
   #   USE foo;  DELETE FROM bar.tbl WHERE 1;
   # are handled correctly.  If the default db were used first, then we'd
   # incorrectly get the foo.tbl struct.  If the query's table wasn't db-
   # qualified then we'd use the default/current db, foo, to get the table
   # struct and this would probably be correct.
   my $default_db = $args{default_db};

   if ( $query !~ m/select [1\*] from/ ) {
      MKDEBUG && _d("Query doesn't 'select 1 from'; is it a rewritten query?");
      return;
   }
   $query =~ s/select 1 from/select * from/;

   MKDEBUG && _d('Getting secondary index queries for', $query);

   my @tbls   = $qp->get_tables($query);
   my $db_tbl = $tbls[0];
   if ( !$db_tbl ) {
      MKDEBUG && _d('Cannot parse tables from query');
      return;
   }
   my ($db, $tbl) = $q->split_unquote($db_tbl);
   $db ||= $default_db;
   MKDEBUG && _d('Query uses db.table', $db, '.', $tbl);
   if ( !$db ) {
      MKDEBUG && _d('No db from table or default db, skipping query');
      return;
   }

   my $tbl_struct;
   eval {
      $tbl_struct = $tp->parse($du->get_create_table($dbh, $q, $db, $tbl));
   };
   if ( $EVAL_ERROR || !$tbl_struct ) {
      MKDEBUG && _d('Failed to get', $tbl, 'struct:', $EVAL_ERROR);
      return;
   }

   my $rows;
   eval {
      $rows = $dbh->selectall_arrayref($query, { Slice => {} });
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('Error executing query:', $EVAL_ERROR);
      return;
   }
   if ( @$rows == 0 ) {
      MKDEBUG && _d("Query didn't return any rows");
      return;
   }

   return make_secondary_index_queries(
      %args,
      rows       => $rows,
      db_tbl     => $q->quote($db, $tbl),
      tbl_struct => $tbl_struct,
   );
}

sub make_secondary_index_queries {
   my ( %args ) = @_;
   my @required_args = qw(rows db_tbl tbl_struct Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($rows, $db_tbl, $tbl_struct, $q) = @args{@required_args};

   my $ck = $tbl_struct->{clustered_key} || '';
   my @sec_indexes = grep { $_ ne $ck } keys %{$tbl_struct->{keys}};
   MKDEBUG && _d('Secondary indexes:', join(', ', @sec_indexes)); 

   my @queries;
   foreach my $sec_index ( @sec_indexes ) {
      my @selects;
      my @cols     = @{$tbl_struct->{keys}->{$sec_index}->{cols}};
      my $sel_cols = join(', ', map { $q->quote($_) } @cols);
      my %seen_clause;
      foreach my $row ( @$rows ) {
         my $all_clauses = '';
         my @clauses = map {
            my $val = $row->{$_};
            my $sep = defined $val ? '=' : ' IS ';
            my $clause = $q->quote($_) . $sep . $q->quote_val($val);
            $all_clauses .= $clause;
            $clause;
         } @cols;
         next if $seen_clause{$all_clauses}++;
         next unless scalar @clauses;
         my $sql = "SELECT $sel_cols FROM $db_tbl "
                 . "FORCE INDEX(`$sec_index`) "
                 . "WHERE " . join(' AND ', @clauses)
                 . " LIMIT 1";
         push @selects, $sql;
      }
      my $union_sql = join("\nUNION ALL ", @selects);
      MKDEBUG && _d('Queries for', $sec_index, 'index:', $union_sql);
      push @queries, $union_sql; 
   }

   return @queries;
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

mk-slave-prefetch - Pipeline relay logs on a MySQL slave to pre-warm caches.

=head1 SYNOPSIS

Usage: mk-slave-prefetch [OPTION...] [FILE]

mk-slave-prefetch pipelines relay logs to pre-warm the slave's caches.

Example:

  mk-slave-prefetch

  mk-slave-prefetch --statistics > /path/to/saved/statistics

  mk-slave-prefetch /path/to/saved/statistics

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-slave-prefetch is read-only by default, and is generally low-risk.  It does
execute SQL statements, but these should be SELECT only.  Despite this, it might
be a good idea to make it connect to MySQL with a user account that has minimal
privileges.  Here is an example of how to grant the necessary privileges:

   GRANT SELECT, REPLICATION CLIENT, REPLICATION SLAVE ON *.*
      TO 'prefetch'@'%' IDENTIFIED BY 'sp33dmeup!';

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-slave-prefetch>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-slave-prefetch reads the slave's relay log slightly ahead of where the
slave's SQL thread is reading, converts statements into C<SELECT>, and
executes them.  In theory, this should help alleviate the effects of the
slave's single-threaded SQL execution.  It will help take advantage of
multiple CPUs and disks by pre-reading the data from disk, so the data is
already in the cache when the slave SQL thread executes the un-modified
version of the statement.

C<mk-slave-prefetch> learns how long it takes statements to execute, and doesn't
try to execute those that take a very long time.  You can ask it to print what
it has learned after it executes.  You can also specify a filename on the
command line.  The file should contain the statistics printed by a previous
run.  These will be used to pre-populate the statistics so it doesn't have to
re-learn.

This program is based on concepts I heard Paul Tuckfield explain at the November
2006 MySQL Camp un-conference.  However, the code is my own work.  I have not
seen any other implementation of Paul's idea.

=head1 DOES IT WORK?

Does it work?  Does it actually speed up the slave?

That depends on your workload, hardware, and other factors.  It might work when
the following are true:

=over

=item *

The slave's data is much larger than memory, and the workload is mostly randomly
scattered small (single-row is ideal) changes.

=item *

There are lots of high-concurrency C<UPDATE> and C<DELETE> statements on the
master.

=item *

The slave SQL thread is I/O-bound, but the slave overall has plenty of spare I/O
capacity (definitely more than one disk spindle).

=item *

The slave uses InnoDB or another storage engine with row-level locking.

=back

It does B<not> speed up replication on my slaves, which mostly have large
queries like C<INSERT .. SELECT .. GROUP BY>.  In my benchmarks it seemed to
make no difference at all, positive or negative.

On the wrong workload or slave configuration, this technique might actually make
the slaves slower.  Your mileage will vary.

User-contributed benchmarks are welcome.

=head1 OPTIONS

Specify at least one of L<"--print">, L<"--execute"> or L<"--stop">.

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

=item --check-interval

type: Array; default: 16,1,1024

How often to check the slave: init,min,max.  This many relay log events should
pass before checking the output of C<SHOW SLAVE STATUS>.  The syntax is a
three-number range: initial, minimum, and maximum.  You should be able to leave
this at the defaults.

C<mk-slave-prefetch> varies the check interval in powers of two, depending on
whether it decides the check was necessary.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --[no]continue-on-error

default: yes

Continue parsing even if there is an error.

=item --daemonize

Fork to the background and detach from the shell.  POSIX
operating systems only.

=item --database

short form: -D; type: string

The database to use for the connection.  The initial connection will be to this
database, but mk-slave-prefetch will issue C<USE> statements as required by the
binary log events.

This database is also used as the default database for L<"--secondary-indexes">
if the database cannot automatically be determined from the query.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --dry-run

Ignore replication checks and just read and rewrite the relay log events.

This option make mk-slave-prefetch ignore all relay log related checks
for position, slave lag, etc. and simply causes the tool to read and rewrite
all the events in the relay log.  A connection to the slave server is still
required.

=item --errors

cumulative: yes

Print queries that caused errors.  If specified once, at exit; if twice, in
realtime.

If you specify this option once, you will see a report at the end of the script
execution, showing the normalized queries and the number of times they were
seen.  If you specify this option twice, you will see the errors printed out as
they occur, but no normalized report at the end of execution.

=item --execute

Execute the transformed queries to warm the caches.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --[no]inject-columns

default: yes

Inject C<(columns)> into INSERT/REPLACE that don't specify them.

Normally this query cannot be rewritten because mk-slave-prefetch doesn't
know which columns the values refer to: C<INSERT INTO tbl VALUES (1,2)>.
This option causes mk-slave-prefetch to C<SHOW CREATE TABLE> the table
from the query, get its columns and inject these columns into the query,
like: C<INSERT INTO tbl (`col1`,`col2`) VALUES (1,2)>.  This allows the
query to be written as a SELECT and prefetched.

Columns for each unique database.table are cached, so this operation
may fail if an C<ALTER TABLE> statement changes the order or name of
any columns.

=item --io-lag

type: size; default: 1k

How many bytes to lag the slave I/O thread.  This helps avoid C<mysqlbinlog>
reading right off the end of the relay log file.

=item --log

type: string

Print all output to this file when daemonized.

=item --max-query-time

type: float; default: 1

Do not run queries longer than this many seconds; fractions allowed.  If
C<mk-slave-prefetch> predicts the query will take longer to execute, it will
skip the query.  This is based on the theory that pre-warming the cache is most
beneficial for short queries.

C<mk-slave-prefetch> learns how long queries require to execute.  It keeps an
average over the last L<"--query-sample-size"> samples of each query.  The
averages are based on an abstracted version of the query, with specific
parameters replaced by placeholders.  The result is a sort of "fingerprint"
for the query, not executable SQL.  You can see the learned statistics with the
L<"--statistics"> option.

You can pre-load query fingerprints, and average execution times, from a file.
This way you don't have to wait for C<mk-slave-prefetch> to learn all over
every time you start it.  Just specify the file on the command line.  The
format should be the same as the output from L<"--statistics">.

You might also want to filter out some statements completely, or let only some
statements through.  See the L<"--reject-regexp"> and L<"--permit-regexp">
options.

If C<mk-slave-prefetch> hasn't seen a query's fingerprint before, and thus
doesn't know how long it will take to execute, it wraps it in a subquery, like
this:

   SELECT 1 FROM ( <query> ) AS X LIMIT 1;

This helps avoid fetching a lot of data back to the client when a query is
very large.  It requires a version of MySQL that supports subqueries (version
4.1 and newer).  If yours doesn't, the subquery trick can't be used, so the
query might fetch a lot of data back to the client.

Once a query's fingerprint has been seen, so it's known that the query isn't
enormously slow, C<mk-slave-prefetch> just rewrites the C<SELECT> list for
efficiency.  (Avoiding the subquery reduces the query's overhead for short
queries).  The rewritten query will then look like the following;

   SELECT ISNULL(COALESCE(<columns>)) FROM ...

=item --num-prefix

Abstract away numeric table name prefixes.  This causes the following two
queries to "fingerprint" to the same thing:

  select from 1_2_users;
  select from 2_3_users;

=item --offset

type: size; default: 128

How many bytes C<mk-slave-prefetch> will try to stay in front of the slave SQL
thread.  It will not execute log events it doesn't think are at least this far
ahead of the SQL thread.  See also L<"--window">.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --permit-regexp

type: string

Permit queries matching this Perl regexp.  This is a filter for log events.  The
regular expression is matched against the raw log event, before any
transformations are applied.  If specified, this option will permit only log
events matching the regular expression.

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

=item --print

Print the transformed relay log events to standard output.

=item --print-nonrewritten

Print queries that could not be transformed into C<SELECT>.

=item --progress

type: int

Print progress information every X events.  The information is the current log
file and position, plus a summary of the statistics gathered.

=item --query-sample-size

type: int; default: 4

Average query exec time over this many queries.  The last C<N> queries with a
given fingerprint are averaged together to get the average query execution time
(see L<"--max-query-time">).  

=item --reject-regexp

type: string

Reject queries matching this Perl regexp.  Similar to L<"--permit-regexp">, but
has the opposite effect: log events must B<not> match the regular expression.

=item --relay-log

type: string

Read only the specified relay log file; - to read from STDIN.

By default mk-slave-prefetch reads the C<Relay_Log_File> reported by
C<SHOW SLAVE STATUS>.  This option allows you to specify a relay
log file that has already be converted to text by C<mysqlbinlog>.
The tool will exit after reading and parsing this file.

This option is useful with L<"--dry-run"> and L<"--print"> if you want to
see how the tool would rewrite the relay log's events without executing
them or having to wait for a lagged slave.

=item --relay-log-dir

type: string

Open the slave's C<Relay_Log_File> relative to this directory.

Unless this option is specified, mk-slave-prefetch automatically determines
the directory that relay logs are in by first looking at the C<relay_log>
system variable to see if it specifies a path.  If it does, this path is
used; if it does not, then the C<datadir> variable value is used.

This option is ignored if an explicit L<"--relay-log"> is specified.

=item --run-time

type: time

How long C<mk-slave-prefetch> should run before exiting.  The default is to run forever.

=item --secondary-indexes

Prefetch secondary indexes for pipelined queries.

=item --sentinel

type: string; default: /tmp/mk-slave-prefetch-sentinel

Exit if this file exists.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --sleep

type: time; default: 1s

Sleep time before checking for new events.

When mk-slave-prefetch is done reading all the events in a relay log, it sleeps
this amount of time before checking for new events.

This option is automatically set to zero if both L<"--relay-log"> and
L<"--dry-run"> are specified.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --statistics

Print execution statistics after exiting.  The statistics are in two sections:
counters, and queries.  The counters simply count the number of times events
occur.  You may see the following counters:

   NAME                    MEANING
   ======================  =======================================
   mysqlbinlog             Executed mysqlbinlog to read log events.
   events                  The total number of relay log events.
   not_far_enough_ahead    An event was not at least L<"--offset">
                           bytes ahead of the SQL thread.
   too_far_ahead           An event was more than L<"--offset">
                           + L<"--window"> bytes ahead of the SQL thread.
   too_close_to_io_thread  An event was less than L<"--io-lag"> bytes
                           away from the I/O thread's position.
   event_not_allowed       An event wasn't a SET, USE, INSERT,
                           UPDATE, DELETE or REPLACE query.
   event_filtered_out      An event was filtered out because of
                           L<"--permit-regexp"> or L<"--reject-regexp">.
   same_timestamp          A SET TIMESTAMP event was ignored because
                           it had the same timestamp as the last one.
   do_query                A transformed event was executed
                           or printed.
   query_error             An executed query had an error.
   query_too_long          An event was not executed because its
                           average query length exceeded
                           L<"--max-query-time">.
   query_not_rewritten     A query could not be rewritten to a
                           SELECT.
   master_pos_wait         The tool waited for the SQL thread to
                           catch up.
   show_slave_status       The tool queried SHOW SLAVE STATUS.
   load_data_infile        The tool found a LOAD DATA INFILE query
                           and unlinked (deleted) the temp file.
   could_not_unlink        The tool failed to unlink a temp file.
   sleep                   The tool slept for a second because the 
                           slave's SQL thread was not running, or
                           because it read past the end of the log.

After the counters, C<mk-slave-prefetch> prints information about each query
fingerprint it has seen, two lines per fingerprint.  The first line contains
the query's fingerprint.  The second line contains the number of times the
fingerprint was seen, number of times executed, the sum of the execution
times, and the average execution time over the last L<"--query-sample-size">
samples.

=item --stop

Stop running instances by creating the L<"--sentinel"> file.

=item --threads

type: int; default: 2

Number of concurrent threads to use for pipelining queries.

=item --tmpdir

type: string; default: /dev/null

Where to create temp files for C<LOAD DATA INFILE> queries.  The default will
cause C<mysqlbinlog> to skip the file and the associated C<LOAD DATA INFILE>
command entirely.

If C<mk-slave-prefetch> sees a C<LOAD DATA INFILE> command (which it won't if
this is left at the default), it will try to remove the temporary file, then
skip the event.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

=item --window

type: size; default: 4k

The max bytes ahead of the slave C<mk-slave-prefetch> should get.  Defines the
window within which C<mk-slave-prefetch> considers a query OK to execute.  The
window begins at the slave SQL thread's last known position plus L<"--offset">
bytes, and extends for the specified number of bytes.

If C<mk-slave-prefetch> sees a log event that is too far in the future, it will
increment the C<too_far_ahead> counter and wait for the slave SQL thread to
catch up (which increments the C<master_pos_wait> counter).  If an event isn't
far enough ahead of the SQL thread, it will be discarded and the
C<not_far_enough_ahead> counter increments.

Watching the mentioned statistics can help you understand how to tune the
window.  You want C<mk-slave-prefetch> to run just ahead of the SQL thread, not
throwing out a lot of events for being too far ahead or not far enough ahead.

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

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-slave-prefetch>.

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

=head1 AUTHOR

Baron Schwartz, Daniel Nichter

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.21 Distrib 7540 $Revision: 7531 $.

=cut

__END__
:endofperl
