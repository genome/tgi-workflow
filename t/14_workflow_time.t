#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;
use above 'Cord';

require_ok('Cord::Time');

sub test_compare_dates {
    my ($a, $b, $c, $undef);
    $a = "2010-10-11 16:20:32.000000";
    $b = "2011-03-17 10:52:29.000000";
    $c = "2011-04-01 10:33:37.000000";
    ok(Cord::Time->compare_dates($a, $b) == -1, '1st smaller than 2nd ok');
    ok(Cord::Time->compare_dates($c, $a) == 1, '1st bigger than 2nd ok');
    ok(Cord::Time->compare_dates(undef, undef) == 0, 'Two undefs are equal');
    ok(Cord::Time->compare_dates(undef, $a) == -1, 'Undef is before defined ate');
    ok(Cord::Time->compare_dates($a, undef) == 1, 'Undef date is before defined date 2');
    my $d = "2010-07-03 07:20:00.000000";
    my $e = "2010-04-08 14:35:17.000000";
    ok(Cord::Time->compare_dates($d, $e) == 1, 'Previously broken date production works');
}

# for use in comparing Cord::Time->datetime_to_numbers output.
# iterate through the two provided lists
# return 1 if equal, 0 otherwise
sub __datetime_compare_lists {
    my ($list1_ref, $list2_ref) = @_;
    my @list1 = @$list1_ref;
    my @list2 = @$list2_ref;
    foreach (@list1) {
        my $l2val = shift @list2;
        unless ($_ == $l2val) {
            warn("Vals $_ and $l2val are not equal!");
            return 0;
        }
    }
    return 1;
}

sub test_datetime_to_numbers {
    my $a = "2010-07-03 07:20:00.000000";
    my @agoal = (0, 20, 7, 3, 7, 2010);
    my $b = "2010-04-08 14:35:17.000000";
    my @bgoal = (17, 35, 14, 8, 4, 2010);
    my $c = "2010-10-11 16:20:32.000000";
    my @cgoal = (32, 20, 16, 11, 10, 2010);
    my $d = "2011-04-01 10:33:37.000000";
    my @dgoal = (37, 33, 10, 1, 4, 2011);
    
    my @aresult = Cord::Time->datetime_to_numbers($a);
    ok(__datetime_compare_lists(\@agoal, \@aresult) == 1, "$a parsed successfully");
    
    my @bresult = Cord::Time->datetime_to_numbers($b);
    ok(__datetime_compare_lists(\@bgoal, \@bresult) == 1, "$b parsed successfully");

    my @cresult = Cord::Time->datetime_to_numbers($c);
    ok(__datetime_compare_lists(\@cgoal, \@cresult) == 1, "$c parsed successfully");

    my @dresult = Cord::Time->datetime_to_numbers($d);
    ok(__datetime_compare_lists(\@dgoal, \@dresult) == 1, "$d parsed successfully");
}

# run tests
test_compare_dates;
test_datetime_to_numbers;
