#!/usr/bin/perl

#  Copyright (c) 2013-2014 Yoran Heling
#
#  Permission is hereby granted, free of charge, to any person obtaining
#  a copy of this software and associated documentation files (the
#  "Software"), to deal in the Software without restriction, including
#  without limitation the rights to use, copy, modify, merge, publish,
#  distribute, sublicense, and/or sell copies of the Software, and to
#  permit persons to whom the Software is furnished to do so, subject to
#  the following conditions:
#
#  The above copyright notice and this permission notice shall be included
#  in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
#  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
#  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
#  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

use strict;
use warnings;

my $machine_fn = 'yxml-states';
my $code_fn = 'yxml.c.in';
my $out_fn = 'yxml.c';


my %states;


sub condtoc {
  local $_ = shift;
  return "yxml_is$1(ch)" if /^([a-zA-Z]+)$/;
  return join ' || ', map "ch == (unsigned char)$_", split /\|/ if /^'/;
  return "x->$1 == ch" if /^\$(.+)$/;
  die "Unknown condition: $_\n";
}


sub acttoc {
  my $next = shift;
  my(@c, @r);
  # XXX: Return values of function calls are or'ed together to create the
  # return value of yxml_parse(). This only works when the function do not
  # return an error code. Functions that may return an error should NOT be
  # called in the same state as other functions.
  for(@_) {
    push @r, "yxml_$1(x, ch)" if /^([a-z0-9_]+)$/;
    push @c, "x->$1 = ch" if /^\$(.+)$/;
    if(/^"/) {
      push @c, (
        "x->nextstate = YXMLS_$$next",
        "x->string = (unsigned char *)$_"
      );
      $$next = 'string';
    }
    push @c, "x->nextstate = YXMLS_$_" if s/^@//;
  }
  (
    map("$_;", @c),
    'return ' . (@r ? join('|', @r) : 'YXML_OK') . ';'
  )
}


sub gencode {
  my($state, @desc) = @_;

  my @code = ("case YXMLS_$state:");
  for(@desc) {
    my($cond, @act) = split / /;
    die "Invalid state description for $state\n" if !@act;
    my $next = pop @act;
    $cond = condtoc $cond;
    @act = acttoc \$next, @act;
    my $needbrack = $next ne $state || @act > 1;
    push @code,
      "\tif($cond)".($needbrack ? ' {':''),
      $next eq '@'    ? "\t\tx->state = x->nextstate;" :
      $next ne $state ? "\t\tx->state = YXMLS_$next;" : (),
      map("\t\t$_", @act),
      ($needbrack ? "\t}" : ());
  }
  push @code, "\tbreak;";
  return join "\n", map "\t$_", @code;
}


sub readmachine {
  local @ARGV = ($machine_fn);
  while(<>) {
    chomp;
    s/[ \t]+/ /g;
    s/^ //;
    s/ $//;
    next if !$_ || /^#/;
    die "Unrecognized line: $_\n" and next if !/^([a-z0-9]+) (.+)$/;
    my($state, @desc) = ($1, split / *; */, $2);
    die "State '$state' specified more than once.\n" if $states{$state};
    $states{$state} = gencode $state, @desc;
  }
}


sub writeout {
  local @ARGV = ($code_fn);
  open my $F, '>', $out_fn or die $!;
  print $F "/* THIS FILE IS AUTOMATICALLY GENERATED, DO NOT EDIT! */\n\n";
  while(<>) {
    s#/\*=STATES=\*/#join ",\n", map "\tYXMLS_$_", sort keys %states#e;
    s#/\*=SWITCH=\*/#join "\n", map $states{$_}, sort keys %states#e;
    print $F $_;
  }
}


readmachine;
writeout;
