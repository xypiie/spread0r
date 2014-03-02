#!/usr/bin/perl
#
# Copyright (C) 2014 Peter Feuerer <peter@piie.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

use strict;
use utf8;
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use Getopt::Long;
use Pod::Usage;

# defines
my $font = "courier new 24";


# global variables
my $gtk_text;
my $gtk_sentence_text;
my $gtk_timer;
my $timeout;
my $pause_button;
my $pause = 0;
my $back_ptr = -1;
my $prev_back_ptr = -1;
my $sentence_cnt = 0;
my $fastforward = 0;


my @words;
my @backbuffer;
sub get_word
{
	my $line;
	$/ = '.';
	@words = () if ($back_ptr != $prev_back_ptr);
	$back_ptr = -1 if ($back_ptr < -1);
	$prev_back_ptr = $back_ptr;


	$gtk_sentence_text->set_markup("sentence nr: ".($sentence_cnt - ($back_ptr +1)));

	for (;$fastforward; $fastforward--) {
		$line = <FILE>;
		$line =~ s/[\n\r]/ /g;
		@words = split(' ', $line);
		$sentence_cnt++ if ($#words >= 0);
		if ($fastforward < 10) {
			unshift(@backbuffer, $line);
			pop(@backbuffer) if ($#backbuffer > 10);
			printf("new sentence: @words, buff: $#backbuffer\n");
		}
	}


	if ($back_ptr <= -1) {
		if ($#words < 0) {
			while ($#words < 0) {
				$line = <FILE>;
				$line =~ s/[\n\r]/ /g;
				@words = split(' ', $line);
			}
			$sentence_cnt++;
			unshift(@backbuffer, $line);
			pop(@backbuffer) if ($#backbuffer > 10);
			printf("new sentence: @words, buff: $#backbuffer\n");
		}
	} else {
		if ($#words < 0) {
			@words = split(' ', $backbuffer[$back_ptr]);
			printf("old sentence: @words, buff: $#backbuffer\n");
		}
		$back_ptr-- if ($#words <= 0);
	}

	return shift(@words);
}

sub quit
{
	Gtk2->main_quit;
	close(FILE);
	return TRUE;
}

sub back
{
	$back_ptr++ if ($back_ptr < 10);
	return TRUE;
}

sub forward
{
	$back_ptr-- if ($back_ptr > -2);
	return TRUE;
}

sub pause 
{
	if ($pause) {
		$gtk_timer = Glib::Timeout->add($timeout, \&set_text);
		$pause = 0;
		$pause_button->set_label(" || ");
	} else {
		$pause = 1;
		$pause_button->set_label(" |> ");
	}
	return TRUE;
}

sub set_text
{
	my $word = get_word();
	my $next_shot = $timeout;
	my $word_length = length($word);
	my $word_start = "";
	my $word_mid = "";
	my $word_end = "";
	my $span_black_open = "<span background='white' foreground='black' font_desc='".$font."'><big>";
	my $span_red_open = "<span background='white' foreground='red' font_desc='".$font."'><big>";
	my $span_close = "</big></span>";
	my $prev_vowel = -1;
	my $i = 0;
	my $width = 28;
	my $add_to_end = 0;

	
	#$next_shot += ($timeout / 30) * $word_length - 6 if ($word_length > 6);
	$next_shot += $timeout / 2 if ($word_length > 10);
	$next_shot += $timeout / 2 if ($word_length > 14);
	$next_shot += $timeout / 2 if ($word_length > 18);
	$next_shot += $timeout * 1.5 if ($word =~ /.*[\.!?;]$/);
	$next_shot += $timeout / 2 if ($word =~ /.*,$/);

	for ($i = 0; $i < $word_length / 2; ++$i) {
		if (substr($word, $i, 1) =~ /[aeuioöäü]/i) {
			$prev_vowel = $i;
		}
	}

	$prev_vowel = $word_length / 2 if ($prev_vowel == -1);

	for ($i = 0; $i < ($width / 2) - $prev_vowel; ++$i)
	{
		$word_start .= " ";
	}

	$word_start .= substr($word, 0, $prev_vowel);
	$word_mid = substr($word, $prev_vowel , 1);
	$word_end = substr($word, $prev_vowel + 1);
	$add_to_end = $width / 2  - length($word_end);

	for ($i = 0; $i < $add_to_end ; ++$i)
	{
		$word_end .= " ";
	}
	$word = $span_black_open.$word_start.$span_close.$span_red_open.$word_mid.$span_close.$span_black_open.$word_end.$span_close;


	$gtk_text->set_markup($word);
	Glib::Source->remove($gtk_timer);
	if (!$pause) {
		$gtk_timer = Glib::Timeout->add($next_shot,\&set_text);
	}
	return TRUE;
}

sub main
{
	my $window;
	my $quit_button;
	my $back_button;
	my $forward_button;
	my $vbox;
	my $hbox;
	my $wpm = 200;
	my $file = "infile.txt";
	my $length = 24;
	my $help = 0;
	my $man = 0;

	GetOptions (	"wpm|w=i" => \$wpm,
			"fastforward|f=i" => \$fastforward,
			"help|h" => \$help,
			"man|m" => \$man)
		or die("Error in command line arguments\n");

	pod2usage(1) if $help;
	pod2usage(-verbose => 2) if $man;
	pod2usage("$0: No file given.")  if (@ARGV == 0);

	$file = $ARGV[0];
	printf("file: $file\n");

	open(FILE, "<:encoding(UTF-8)", $file) || die "can't open UTF-8 encoded filename: $!";

	printf("using words per minute = $wpm\n");

	$timeout = 60000 / $wpm;
	$gtk_timer = Glib::Timeout->add(2000,\&set_text);

	$window = Gtk2::Window->new;
	$window->signal_connect(delete_event => \&quit);
	$window->signal_connect(destroy =>  \&quit);
	$window->set_border_width(10);

	$quit_button = Gtk2::Button->new("Quit");
	$quit_button->signal_connect(clicked => \&quit, $window);
	$quit_button->show;

	$back_button = Gtk2::Button->new(" << ");
	$back_button->signal_connect(clicked => \&back, $window);
	$back_button->show;

	$forward_button = Gtk2::Button->new(" >> ");
	$forward_button->signal_connect(clicked => \&forward, $window);
	$forward_button->show;

	$pause_button = Gtk2::Button->new(" || ");
	$pause_button->signal_connect(clicked => \&pause, $window);
	$pause_button->show;

	$gtk_text = Gtk2::Label->new();
	$gtk_text->show;
	
	$gtk_sentence_text = Gtk2::Label->new();
	$gtk_sentence_text->show;

	$vbox = Gtk2::VBox->new(FALSE, 10);
	$hbox = Gtk2::HBox->new(FALSE, 10);
	$hbox->pack_start($back_button, FALSE, FALSE, 0);
	$hbox->pack_start($pause_button, FALSE, FALSE, 0);
	$hbox->pack_start($forward_button, FALSE, FALSE, 0);
	$hbox->pack_start($gtk_sentence_text, FALSE, FALSE, 0);
	$vbox->pack_start($hbox,FALSE,FALSE,4);
	$vbox->pack_start(Gtk2::HSeparator->new(),FALSE,FALSE,4);
	$vbox->pack_start($gtk_text, FALSE, TRUE, 5);
	$vbox->pack_start(Gtk2::HSeparator->new(),FALSE,FALSE,4);
	$vbox->pack_start($quit_button, FALSE, FALSE, 0);
	$vbox->show;
	$window->add($vbox);

	$window->show_all;
	Gtk2->main;

	return TRUE;
}


main();


__END__

=head1 NAME

gritz - high performance txt reader

=head1 SYNOPSIS

gritz [options] file

	Options:
	-h, --help			print brief help message
	-m, --man			print the full documentation
	-w <num>, --wpm <num>		reading speed in words per minute
	-f <num>, --fastforward <num>	seek to <num>. sentence


=head1 OPTIONS

=over 8

=item B<-h, --help>

Print a brief help message and exits.

=item B<-m, --man>

print the full documentation

=item B<-w, --wpm>

Set the reading speed to the given amount of words per minute.
For beginners a good starting rate is around 250

=item B<-f, --fastforward>

Skip all sentences until it reaches given sentence

=back

=head1 DESCRIPTION

B<gritz> will read the given utf8 encoded input file and present
it to you word by word, so you can read the text without manually
refocusing.  This can double your reading speed!

=cut
