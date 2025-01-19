glyph.sl - a small utility to insert a character from the
unicode-character-database. It is mostly aimed at inserting glyphs or
ideograms like color emojis and the like that cannot easily be typed from a
keyboard.

Installation: Copy this file to a place where Jed will see it and in your
~/.jedrc insert the lines:

   autoload ("glyph", "glyph");
   autoload ("glyph_show_description", "glyph");
   add_completion ("glyph");
   add_completion ("glyph_show_description");

Requirements: The unicode-character-database must be installed and the
terminal and font you use must support glyphs or ideograms if that is what
you want to use it for. It is tested and works with the terminal version of
Jed and the Foot, Kitty and St terminals under Wayland. Under Xorg, not much
apparently works: xterm and Jed can show an ideogram of e.g. an apple but
the color is wrong. Urxvt, Gnome-terminal, Xfce4-terminal and Xjed, no luck.

The location of the unicode-character-database is hardcoded as
"/usr/share/unicode/UnicodeData.txt". If it is in some other place, then edit
the value of the variable, "Unicode_Data_File" in glyph.sl

Usage: Invoke with Alt-x glyph - or from the menu
F10 -> Edit -> Insert Glyph

From the prompt enter some search string to get a listing of
matching glyphs with their accompanying descriptions. Place the
editing point flush on the chosen glyph and hit <enter> to have it
inserted into the buffer.

Morten Bo Johansen, mortenbo at hotmail dot com
Licence: GPL, version 2 or later.

