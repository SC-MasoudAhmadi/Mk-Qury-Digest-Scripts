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

# This program is copyright 2007-2011 Percona Inc.
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

our $VERSION = '1.0.1';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7536 $ =~ m/(\d+)/g, 0));

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
# Transformers package 7226
# ###########################################################################

# Transformers - Common transformation and beautification subroutines
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
                                         # like a MySQL YYMMDD without hh:mm:ss.

sub micro_t {
   my ( $t, %args ) = @_;
   my $p_ms = defined $args{p_ms} ? $args{p_ms} : 0;  # precision for ms vals
   my $p_s  = defined $args{p_s}  ? $args{p_s}  : 0;  # precision for s vals
   my $f;

   $t = 0 if $t < 0;

   # "Remove" scientific notation so the regex below does not make
   # 6.123456e+18 into 6.123456.
   $t = sprintf('%.17f', $t) if $t =~ /e/;

   # Truncate after 6 decimal places to avoid 0.9999997 becoming 1
   # because sprintf() rounds.
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

# Returns what percentage $is of $of.
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

   # Decide what format to use, if not given
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

# Convert time values to number of seconds:
# 1s = 1, 1m = 60, 1h = 3600, 1d = 86400.
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

# Turns a unix timestamp into an ISO8601 formatted date and time.  $gmt makes
# this relative to GMT, for test determinism.
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

# Turns MySQL's 071015 21:43:52 into a properly formatted timestamp.  Also
# handles a timestamp with fractions after it.
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

# Turns a properly formatted timestamp like 2007-10-15 01:43:52
# into an int (seconds since epoch).  Optional microseconds are printed.  $gmt
# makes it use GMT time instead of local time (to make tests deterministic).
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

# Turns several different types of timestamps into a unix timestamp.
# Each type is auto-detected.  Supported types are:
#   * N[shdm]                Now - N[shdm]
#   * 071015 21:43:52        MySQL slow log timestamp
#   * 2009-07-01 [3:43:01]   Proper timestamp with options HH:MM:SS
#   * NOW()                  A MySQL time express
# For the last type, the callback arg is required.  It is passed the
# given value/expression and is expected to return a single value
# (the result of the expression).
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
      # unix timestamp 100000000 is roughly March, 1973, so older
      # dates won't be caught here; they'll probably be mistaken
      # for a MySQL slow log timestamp.
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

# Returns the rightmost 64 bits of an MD5 checksum of the value.
sub make_checksum {
   my ( $val ) = @_;
   my $checksum = uc substr(md5_hex($val), -16);
   MKDEBUG && _d($checksum, 'checksum for', $val);
   return $checksum;
}

# Perl implementation of CRC32, ripped off from Digest::Crc32.  The results
# ought to match what you get from any standard CRC32 implementation, such as
# that inside MySQL.
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
# Progress package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Progress.pm
#   trunk/common/t/Progress.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package Progress;

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
   foreach my $arg (qw(jobsize)) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   if ( (!$args{report} || !$args{interval}) ) {
      if ( $args{spec} && @{$args{spec}} == 2 ) {
         @args{qw(report interval)} = @{$args{spec}};
      }
      else {
         die "I need either report and interval arguments, or a spec";
      }
   }

   my $name  = $args{name} || "Progress";
   $args{start} ||= time();
   my $self;
   $self = {
      last_reported => $args{start},
      fraction      => 0,       # How complete the job is
      callback      => sub {
         my ($fraction, $elapsed, $remaining, $eta) = @_;
         printf STDERR "$name: %3d%% %s remain\n",
            $fraction * 100,
            Transformers::secs_to_time($remaining),
            Transformers::ts($eta);
      },
      %args,
   };
   return bless $self, $class;
}

sub validate_spec {
   shift @_ if $_[0] eq 'Progress'; # Permit calling as Progress-> or Progress::
   my ( $spec ) = @_;
   if ( @$spec != 2 ) {
      die "spec array requires a two-part argument\n";
   }
   if ( $spec->[0] !~ m/^(?:percentage|time|iterations)$/ ) {
      die "spec array's first element must be one of "
        . "percentage,time,iterations\n";
   }
   if ( $spec->[1] !~ m/^\d+$/ ) {
      die "spec array's second element must be an integer\n";
   }
}

sub set_callback {
   my ( $self, $callback ) = @_;
   $self->{callback} = $callback;
}

sub start {
   my ( $self, $start ) = @_;
   $self->{start} = $self->{last_reported} = $start || time();
}

sub update {
   my ( $self, $callback, $now ) = @_;
   my $jobsize   = $self->{jobsize};
   $now        ||= time();
   $self->{iterations}++; # How many updates have happened;

   if ( $self->{report} eq 'time'
         && $self->{interval} > $now - $self->{last_reported}
   ) {
      return;
   }
   elsif ( $self->{report} eq 'iterations'
         && ($self->{iterations} - 1) % $self->{interval} > 0
   ) {
      return;
   }
   $self->{last_reported} = $now;

   my $completed = $callback->();
   $self->{updates}++; # How many times we have run the update callback

   return if $completed > $jobsize;

   my $fraction = $completed > 0 ? $completed / $jobsize : 0;

   if ( $self->{report} eq 'percentage'
         && $self->fraction_modulo($self->{fraction})
            >= $self->fraction_modulo($fraction)
   ) {
      $self->{fraction} = $fraction;
      return;
   }
   $self->{fraction} = $fraction;

   my $elapsed   = $now - $self->{start};
   my $remaining = 0;
   my $eta       = $now;
   if ( $completed > 0 && $completed <= $jobsize && $elapsed > 0 ) {
      my $rate = $completed / $elapsed;
      if ( $rate > 0 ) {
         $remaining = ($jobsize - $completed) / $rate;
         $eta       = $now + int($remaining);
      }
   }
   $self->{callback}->($fraction, $elapsed, $remaining, $eta, $completed);
}

sub fraction_modulo {
   my ( $self, $num ) = @_;
   $num *= 100; # Convert from fraction to percentage
   return sprintf('%d',
      sprintf('%d', $num / $self->{interval}) * $self->{interval});
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
# End Progress package
# ###########################################################################

# ###########################################################################
# FileIterator package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/FileIterator.pm
#   trunk/common/t/FileIterator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package FileIterator;

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
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub get_file_itr {
   my ( $self, @filenames ) = @_;

   my @final_filenames;
   FILENAME:
   foreach my $fn ( @filenames ) {
      if ( !defined $fn ) {
         warn "Skipping undefined filename";
         next FILENAME;
      }
      if ( $fn ne '-' ) {
         if ( !-e $fn || !-r $fn ) {
            warn "$fn does not exist or is not readable";
            next FILENAME;
         }
      }
      push @final_filenames, $fn;
   }

   if ( !@filenames ) {
      push @final_filenames, '-';
      MKDEBUG && _d('Auto-adding "-" to the list of filenames');
   }

   MKDEBUG && _d('Final filenames:', @final_filenames);
   return sub {
      while ( @final_filenames ) {
         my $fn = shift @final_filenames;
         MKDEBUG && _d('Filename:', $fn);
         if ( $fn eq '-' ) { # Magical STDIN filename.
            return (*STDIN, undef, undef);
         }
         open my $fh, '<', $fn or warn "Cannot open $fn: $OS_ERROR";
         if ( $fh ) {
            return ( $fh, $fn, -s $fn );
         }
      }
      return (); # Avoids $f being set to 0 in list context.
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
# End FileIterator package
# ###########################################################################

# ###########################################################################
# SimpleTCPDumpParser package 7515
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SimpleTCPDumpParser.pm
#   trunk/common/t/SimpleTCPDumpParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SimpleTCPDumpParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::Local qw(timelocal);
use Data::Dumper;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my ($ip, $port) = split(/:/, $args{watch});
   my $self = {
      sessions => {},
      requests => 0,
      port     => $port || 3306,
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

   my $sessions   = $self->{sessions};
   my $pos_in_log = $tell->();
   my $line;

   EVENT:
   while ( defined($line = $next_event->()) ) {
      my ( $ts, $us, $src, $dst )
         = $line =~ m/([0-9-]{10} [0-9:]{8})(\.\d{6}) IP (\S+) > (\S+):/;
      next unless $ts;
      my $unix_timestamp = make_ts($ts) . $us;

      if ( $dst =~ m/\.$self->{port}$/o ) {
         my $event;
         if ( exists $sessions->{$src} && $sessions->{$src}->{status} eq 'R' ) {
            $event = $self->make_event($src);
         }
         if ( exists $sessions->{$src} ) {
            $sessions->{$src}->{ts} = $unix_timestamp;
         }
         else {
            $sessions->{$src} ||= {
               pos_in_log => $pos_in_log,
               ts         => $unix_timestamp,
               ts0        => $unix_timestamp,
               id         => $self->{requests}++,
               status     => 'Q',
            };
         }
         return $event if $event;
      }

      elsif (defined (my $event = $sessions->{$dst}) ) {
         $event->{status} = 'R',
         $event->{end}  ||= $unix_timestamp;
         $event->{end1}   = $unix_timestamp;
      }
      $pos_in_log = $tell->();
   } # EVENT

   foreach my $src ( keys %$sessions ) {
      my $event = $self->make_event($src);
      return $event if $event;
   }

   $args{oktorun}->(0) if $args{oktorun};
   return;
}

sub make_event {
   my ( $self, $src ) = @_;
   my $event = $self->{sessions}->{$src};
   delete $self->{sessions}->{$src};
   if ( $event->{status} eq 'R' ) {
      my ( $src_host, $src_port ) = $src =~ m/^(.*)\.(\d+)$/;
      $event->{host} = $src_host;
      $event->{port} = $src_port;
      $event->{arg}  = undef;
      delete $event->{status};
      MKDEBUG && _d('Properties of event:', Dumper($event));
      return $event;
   }
   return undef;
}

{
   my ($last, $result);
   sub make_ts {
      my ($arg) = @_;
      if ( !$last || $last ne $arg ) {
         my ($year, $mon, $mday, $hour, $min, $sec) = split(/\D/, $arg);
         $result = timelocal($sec, $min, $hour, $mday, $mon - 1, $year);
         $last   = $arg;
      }
      return $result;
   }
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
# End SimpleTCPDumpParser package
# ###########################################################################

# ###########################################################################
# TCPRequestAggregator package 7515
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TCPRequestAggregator.pm
#   trunk/common/t/TCPRequestAggregator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TCPRequestAggregator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use List::Util qw(sum);
use Data::Dumper;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(interval quantile);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      buffer             => [],
      last_weighted_time => 0,
      last_busy_time     => 0,
      last_completions   => 0,
      current_ts         => 0,
      %args,
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

   my $pos_in_log = $tell->();
   my $buffer = $self->{buffer};
   $self->{last_pos_in_log} ||= $pos_in_log;

   EVENT:
   while ( 1 ) {
      MKDEBUG && _d("Beginning a loop at pos", $pos_in_log);
      my ( $id, $start, $elapsed );

      my ($timestamp, $direction);
      if ( $self->{pending} ) {
         ( $id, $start, $elapsed ) = @{$self->{pending}};
         MKDEBUG && _d("Pulled from pending", @{$self->{pending}});
      }
      elsif ( defined(my $line = $next_event->()) ) {
         my ($end, $host_port);
         ( $id, $start, $end, $elapsed, $host_port ) = $line =~ m/(\S+)/g;
         @$buffer = sort { $a <=> $b } ( @$buffer, $end );
         MKDEBUG && _d("Read from the file", $id, $start, $end, $elapsed, $host_port);
         MKDEBUG && _d("Buffer is now", @$buffer);
      }
      if ( $start ) { # Test that we got a line; $id can be 0.
         if ( @$buffer && $buffer->[0] < $start ) {
            $direction       = 'C'; # Completion
            $timestamp       = shift @$buffer;
            $self->{pending} = [ $id, $start, $elapsed ];
            $id = $start = $elapsed = undef;
            MKDEBUG && _d("Completion: using buffered end value", $timestamp);
            MKDEBUG && _d("Saving line to pending", @{$self->{pending}});
         }
         else {
            $direction       = 'A'; # Arrival
            $timestamp       = $start;
            $self->{pending} = undef;
            MKDEBUG && _d("Deleting pending line");
            MKDEBUG && _d("Arrival: using the line");
         }
      }
      elsif ( @$buffer ) {
         $direction = 'C';
         $timestamp = shift @$buffer;
         MKDEBUG && _d("No more lines, reading from buffer", $timestamp);
      }
      else { # We hit EOF.
         MKDEBUG && _d("No more lines, no more buffered end times");
         if ( $self->{in_prg} ) {
            die "Error: no more lines, but in_prg = $self->{in_prg}";
         }
         if ( $self->{t_start} < $self->{current_ts} ) {
            MKDEBUG && _d("Returning event based on what's been seen");
            return $self->make_event($self->{t_start}, $self->{current_ts});
         }
         else {
            MKDEBUG && _d("No further events to make");
            return;
         }
      }

      my $t_start = int($timestamp / $self->{interval}) * $self->{interval};
      $self->{t_start} ||= $timestamp; # Not $t_start; that'd skew 1st interval.
      MKDEBUG && _d("Timestamp", $timestamp, "interval start time", $t_start);

      if ( $t_start > $self->{t_start} ) {
         MKDEBUG && _d("Timestamp doesn't belong to this interval");
         if ( $self->{in_prg} ) {
            MKDEBUG && _d("Computing from", $self->{current_ts}, "to", $t_start);
            $self->{busy_time}     += $t_start - $self->{current_ts};
            $self->{weighted_time} += ($t_start - $self->{current_ts}) * $self->{in_prg};
         }

         if ( @$buffer && $buffer->[0] < $t_start ) {
            die "Error: completions for interval remain unprocessed";
         }

         my $event                = $self->make_event($self->{t_start}, $t_start);
         $self->{last_pos_in_log} = $pos_in_log;
         if ( $start ) {
            $self->{pending} = [ $id, $start, $elapsed ];
         }
         else {
            unshift @$buffer, $timestamp;
         }
         return $event;
      }

      else {
         if ( $self->{in_prg} ) {
            MKDEBUG && _d("Computing from", $self->{current_ts}, "to", $timestamp);
            $self->{busy_time}     += $timestamp - $self->{current_ts};
            $self->{weighted_time} += ($timestamp - $self->{current_ts}) * $self->{in_prg};
         }
         $self->{current_ts} = $timestamp;
         if ( $direction eq 'A' ) {
            MKDEBUG && _d("Direction A", $timestamp);
            ++$self->{in_prg};
            if ( defined $elapsed ) {
               push @{$self->{response_times}}, $elapsed;
            }
         }
         else {
            MKDEBUG && _d("Direction C", $timestamp);
            --$self->{in_prg};
            ++$self->{completions};
         }
      }

      $pos_in_log = $tell->();
   } # EVENT

   $args{oktorun}->(0) if $args{oktorun};
   return;
}

sub make_event {
   my ( $self, $t_start, $t_end ) = @_;

   my $quantile_cutoff = sprintf( "%.0f", # Round to nearest int
      scalar( @{ $self->{response_times} } ) * $self->{quantile} );
   my @times = sort { $a <=> $b } @{ $self->{response_times} };
   my $arrivals = scalar(@times);
   my $sum_times = sum( @times );
   my $mean_times = ($sum_times || 0) / ($arrivals || 1);
   my $var_times = 0;
   if ( @times ) {
      $var_times = sum( map { ($_ - $mean_times) **2 } @times ) / $arrivals;
   }

   my $e_ts
      = int( $self->{current_ts} / $self->{interval} ) * $self->{interval};
   my $e_concurrency = sprintf( "%.6f",
           ( $self->{weighted_time} - $self->{last_weighted_time} )
         / ( $t_end - $t_start ) );
   my $e_arrivals   = $arrivals;
   my $e_throughput = sprintf( "%.6f", $e_arrivals / ( $t_end - $t_start ) );
   my $e_completions
      = ( $self->{completions} - $self->{last_completions} );
   my $e_busy_time
      = sprintf( "%.6f", $self->{busy_time} - $self->{last_busy_time} );
   my $e_weighted_time = sprintf( "%.6f",
      $self->{weighted_time} - $self->{last_weighted_time} );
   my $e_sum_time = sprintf("%.6f", $sum_times || 0);
   my $e_variance_mean = sprintf("%.6f", $var_times / ($mean_times || 1));
   my $e_quantile_time = sprintf("%.6f", $times[ $quantile_cutoff - 1 ] || 0);

   my $event = {
      ts            => $e_ts,
      concurrency   => $e_concurrency,
      throughput    => $e_throughput,
      arrivals      => $e_arrivals,
      completions   => $e_completions,
      busy_time     => $e_busy_time,
      weighted_time => $e_weighted_time,
      sum_time      => $e_sum_time,
      variance_mean => $e_variance_mean,
      quantile_time => $e_quantile_time,
      pos_in_log    => $self->{last_pos_in_log},
      obs_time      => sprintf("%.6f", $t_end - $t_start),
   };

   $self->{t_start}            = $t_end;  # Not current_timestamp!
   $self->{current_ts}         = $t_end;  # Next iteration will begin at boundary
   $self->{last_weighted_time} = $self->{weighted_time};
   $self->{last_busy_time}     = $self->{busy_time};
   $self->{last_completions}   = $self->{completions};
   $self->{response_times}     = [];

   MKDEBUG && _d("Event is", Dumper($event));
   return $event;
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
# End TCPRequestAggregator package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_tcp_model;

use English qw(-no_match_vars);
use Time::Local qw(timelocal);
use Time::HiRes qw(time usleep);
use List::Util qw(max);
use POSIX qw(signal_h);
use Data::Dumper;
$Data::Dumper::Indent = 1;
$OUTPUT_AUTOFLUSH     = 1;

use constant MKDEBUG        => $ENV{MKDEBUG}        || 0;

use sigtrap 'handler', \&sig_int, 'normal-signals';

# Global variables.  Only really essential variables should be here.
my $oktorun = 1;

sub main {
   @ARGV    = @_;  # set global ARGV for this package
   $oktorun = 1;   # reset between tests else pipeline won't run

   # ##########################################################################
   # Get configuration information.
   # ##########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();
   if ( !$o->get('help') ) {
      if ( $o->get('progress') ) {
         eval { Progress->validate_spec($o->get('progress')) };
         if ( $EVAL_ERROR ) {
            chomp $EVAL_ERROR;
            $o->save_error("--progress $EVAL_ERROR");
         }
      }
      if ( $o->get('type') !~ m/^(tcpdump|requests)$/ ) {
         $o->save_error("--type must be tcpdump or requests");
      }
   }
   $o->usage_or_errors();

   # ########################################################################
   # Set up objects and variables.
   # ########################################################################
   my $fi     = new FileIterator();
   my $parser;
   if ( $o->get('type') eq 'tcpdump' ) { # Default: parse tcpdump
      $parser = new SimpleTCPDumpParser(watch => $o->get('watch-server'));
   }
   else {
      $parser = new TCPRequestAggregator(
         interval => $o->get('run-time'),
         quantile => $o->get('quantile')
      );
   }

   # ########################################################################
   # This is the main loop over the input filenames.
   # ########################################################################
   my $next_file = $fi->get_file_itr(@ARGV);
   my ( $fh, $filename, $filesize ) = $next_file->();
   FILE:
   while ( defined $fh ) {

      # Create a callback to get events from the input.
      my $next_event = sub { return <$fh>; };
      my $tell       = sub { return tell $fh; };
      my $event;
      my $get_event = sub {
         return $parser->parse_event(
            event      => $event,
            next_event => $next_event,
            tell       => $tell,
            oktorun    => sub { return 1 },
            misc       => {},
            stats      => {},
         );
      };

      # #####################################################################
      # Set up a progress reporter.  For right now, we just do one per file.
      # Maybe someday we can do a global progress report?
      # #####################################################################
      my $pr;
      if ( $o->get('progress') && $filename && -e $filename ) {
         $pr = new Progress(
            jobsize => -s $filename,
            spec    => $o->get('progress'),
            name    => $filename,
         );
      }

      # #####################################################################
      # This is the main loop over the events in the input file.
      # #####################################################################
      my ($ts, $end) = @{$o->get('start-end')};
      EVENT:
      while ( $event = $get_event->() ) {
         if ( $o->get('type') eq 'tcpdump' ) {
            printf "%6d %.6f %.6f %9.6f %s:%s\n",
               $event->{id},
               $event->{$ts},
               $event->{$end},
               $event->{$end} - $event->{$ts},
               $event->{host},
               $event->{port};
         }
         else {
            printf "%s %5.2f %9.3f %5d %5d %.6f %.6f %.6f %.6f %.6f %.6f\n",
               @{$event}{qw(
                ts concurrency throughput arrivals completions res_time
                weighted_time sum_time variance_mean quantile_time obs_time)};
         }
         $pr->update($tell) if $pr;
      } # EVENT

      ( $fh, $filename, $filesize ) = $next_file->();
   } # FILE

   return 0;
} # End main()

# ############################################################################
# Subroutines.
# ############################################################################

# Catches signals so we can exit gracefully.
sub sig_int {
   my ( $signal ) = @_;
   if ( $oktorun ) {
      print STDERR "# Caught SIG$signal.\n";
      $oktorun = 0;
   }
   else {
      print STDERR "# Exiting on SIG$signal.\n";
      exit(1);
   }
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
exit main(@ARGV) unless caller;

1; # Because this is a module as well as a script.

# #############################################################################
# Documentation.
# #############################################################################

=pod

=head1 NAME

mk-tcp-model - Transform tcpdump into metrics that permit performance and
scalability modeling.

=head1 SYNOPSIS

Usage: mk-tcp-model [OPTION...] [FILE]

mk-tcp-model parses and analyzes tcpdump files.  With no FILE, or when
FILE is -, it read standard input.

Dump TCP requests and responses to a file, capturing only the packet headers to
avoid dropped packets, and ignoring any packets without a payload (such as
ack-only packets).  Capture port 3306 (MySQL database traffic).  Note that to
avoid line breaking in terminals and man pages, the TCP filtering expression
that follows has a line break at the end of the second line; you should omit
this from your tcpdump command.

 tcpdump -s 384 -i any -nnq -tttt \
	'tcp port 3306 and (((ip[2:2] - ((ip[0]&0xf)<<2)) 
      - ((tcp[12]&0xf0)>>2)) != 0)' \
   > /path/to/tcp-file.txt

Extract individual response times, sorted by end time:

 mk-tcp-model /path/to/tcp-file.txt > requests.txt

Sort the result by arrival time, for input to the next step:

 sort -n -k1,1 requests.txt > sorted.txt

Slice the result into 10-second intervals and emit throughput, concurrency, and
response time metrics for each interval:

 mk-tcp-model --type=requests --run-time=10 sorted.txt > sliced.txt

Transform the result for modeling with Aspersa's usl tool, discarding the first
and last line of each file if you specify multiple files (the first and last
line are normally incomplete observation periods and are aberrant):

 for f in sliced.txt; do
    tail -n +2 "$f" | head -n -1 | awk '{print $2, $3, $7/$4}'
 done > usl-input.txt

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-tcp-model merely reads and transforms its input, printing it to the output.
It should be very low risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-tcp-model>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

This tool recognizes requests and responses in a TCP stream, and extracts the
"conversations".  You can use it to capture the response times of individual
queries to a database, for example.  It expects the TCP input to be in the
following format, which should result from the sample shown in the SYNOPSIS:

 <date> <time.microseconds> IP <IP.port> > <IP.port>: <junk>

The tool watches for "incoming" packets to the port you specify with the
L<"--watch-server"> option.  This begins a request.  If multiple inbound packets
follow each other, then by default the last inbound packet seen determines the
time at which the request is assumed to begin.  This is logical if one assumes
that a server must receive the whole SQL statement before beginning execution,
for example.

When the first outbound packet is seen, the server is considered to have
responded to the request.  The tool might see an inbound packet, but never see a
response.  This can happen when the kernel drops packets, for example.  As a
result, the tool never prints a request unless it sees the response to it.
However, the tool actually does not print any request until it sees the "last"
outbound packet.  It determines this by waiting for either another inbound
packet, or EOF, and then considers the previous inbound/outbound pair to be
complete.  As a result, the tool prints requests in a relatively random order.
Most types of analysis require processing in either arrival or completion order.
Therefore, the second type of processing this tool can do requires that you sort
the output from the first stage and supply it as input.

The second type of processing is selected with the L<"--type"> option set to
"requests".  In this mode, the tool reads a group of requests and aggregates
them, then emits the aggregated metrics.

=head1 OUTPUT

In the default mode (parsing tcpdump output), requests are printed out one per
line, in the following format:

 <id> <start> <end> <elapsed> <IP:port>

The ID is an incrementing number, assigned in arrival order in the original TCP
traffic.  The start and end timestamps, and the elapsed time, can be customized
with the L<"--start-end"> option.

In "--type=requests" mode, the tool prints out one line per time interval as
defined by L<"--run-time">, with the following columns: ts, concurrency,
throughput, arrivals, completions, busy_time, weighted_time, sum_time,
variance_mean, quantile_time, obs_time.  A detailed explanation follows:

=over

=item ts

The timestamp that defines the beginning of the interval.

=item concurrency

The average number of requests resident in the server during the interval.

=item throughput

The number of arrivals per second during the interval.

=item arrivals

The number of arrivals during the interval.

=item completions

The number of completions during the interval.

=item busy_time

The total amount of time during which at least one request was resident in
the server during the interval.

=item weighted_time

The total response time of all the requests resident in the server during the
interval, including requests that neither arrived nor completed during the
interval.

=item sum_time

The total response time of all the requests that arrived in the interval.

=item variance_mean

The variance-to-mean ratio (index of dispersion) of the response times of the
requests that arrived in the interval.

=item quantile_time

The Nth percentile response time for all the requests that arrived in the
interval.  See also L<"--quantile">.

=item obs_time

The length of the observation time window.  This will usually be the same as the
interval length, except for the first and last intervals in a file, which might
have a shorter observation time.

=back

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --help

Show help and exit.

=item --progress

type: array; default: time,30

Print progress reports to STDERR.  The value is a comma-separated list with two
parts.  The first part can be percentage, time, or iterations; the second part
specifies how often an update should be printed, in percentage, seconds, or
number of iterations.

=item --quantile

type: float

The percentile for the last column when L<"--type"> is "requests" (default .99).

=item --run-time

type: float

The size of the aggregation interval in seconds when L<"--type"> is "requests"
(default 1).  Fractional values are permitted.

=item --start-end

type: Array; default: ts,end

Define how the arrival and completion timestamps of a query, and thus its
response time (elapsed time) are computed.  Recall that there may be multiple
inbound and outbound packets per request and response, and refer to the
following ASCII diagram.  Suppose that a client sends a series of three inbound
(I) packets to the server, whch computes the result and then sends two outbound
(O) packets back:

  I I    I ..................... O    O
  |<---->|<---response time----->|<-->|
  ts0    ts                      end  end1

By default, the query is considered to arrive at time ts, and complete at time
end.  However, this might not be what you want.  Perhaps you do not want to
consider the query to have completed until time end1.  You can accomplish this
by setting this option to C<ts,end1>.

=item --type

type: string

The type of input to parse (default tcpdump).  The permitted types are

=over

=item tcpdump

The parser expects the input to be formatted with the following options: C<-x -n
-q -tttt>.  For example, if you want to capture output from your local machine,
you can do something like the following (the port must come last on FreeBSD):

  tcpdump -s 65535 -x -nn -q -tttt -i any -c 1000 port 3306 \
    > mysql.tcp.txt
  mk-query-digest --type tcpdump mysql.tcp.txt

The other tcpdump parameters, such as -s, -c, and -i, are up to you.  Just make
sure the output looks like this (there is a line break in the first line to
avoid man-page problems):

  2009-04-12 09:50:16.804849 IP 127.0.0.1.42167
         > 127.0.0.1.3306: tcp 37

All MySQL servers running on port 3306 are automatically detected in the
tcpdump output.  Therefore, if the tcpdump out contains packets from
multiple servers on port 3306 (for example, 10.0.0.1:3306, 10.0.0.2:3306,
etc.), all packets/queries from all these servers will be analyzed
together as if they were one server.

If you're analyzing traffic for a protocol that is not running on port
3306, see L<"--watch-server">.

=back

=item --version

Show version and exit.

=item --watch-server

type: string; default: 10.10.10.10:3306

This option tells mk-tcp-model which server IP address and port (such as
"10.0.0.1:3306") to watch when parsing tcpdump for L<"--type"> tcpdump.  If you
don't specify it, the tool watches all servers by looking for any IP address
using port 3306.  If you're watching a server with a non-standard port, this
won't work, so you must specify the IP address and port to watch.

Currently, IP address filtering isn't implemented; so even though you must
specify the option in IP:port form, it ignores the IP and only looks at the port
number.

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

You need Perl and some core packages that ought to be installed in any
reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-tcp-model>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2011 Baron Schwartz.
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

This manual page documents Ver 1.0.1 Distrib 7540 $Revision: 7536 $.

=cut

__END__
:endofperl
