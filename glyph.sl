% glyph.sl - a small utility to insert a character from the
% unicode-character-database. It is mostly aimed at inserting glyphs
% or ideograms like emoticons and the like that cannot be typed from a
% keyboard.
% 
% Author: Morten Bo Johansen, listmail at mbj dot dk
% Licence: GPL, version 2 or later.
%
% Installation: Copy this file to a place where Jed will see it and in
% your ~/.jedrc insert the line:
%
%    require("glyph");
%
% Requirements: The unicode-character-database must be installed and
% the terminal and font you use must support glyphs or ideograms if
% that is what you want to use it for.
% 
% The location of the unicode-character-database is hardcoded as
% "/usr/share/unicode/UnicodeData.txt". If it is in some other place,
% then edit the value of the variable, "Unicode_Data_File", below.
% 
% Usage: Invoke with Alt-x glyph - or from the menu
% F10 -> Edit -> Insert Glyph
% 
% From the prompt enter some search string to get a listing of
% matching glyphs with their accompanying descriptions. Place the
% editing point flush on the chosen glyph and hit <enter> to have it
% inserted into the buffer.
% 
require("pcre");

private variable Unicode_Data_File = "/usr/share/unicode/UnicodeData.txt";
private variable OldBuf;

define insert_char_other_buffer()
{
  variable char = what_char();
  delbuf(whatbuf());
  sw2buf(OldBuf);
  onewindow();
  insert_char(char);
}

private define glyph_load_popup_hook (menubar)
{
  menu_insert_item ("Re&gion Ops", "Global.&Edit", "&Insert Glyph", "glyph");
}
append_to_hook ("load_popup_hooks", &glyph_load_popup_hook);

public define glyph()
{
  ifnot (1 == file_status(Unicode_Data_File))
    throw OpenError, "$Unicode_Data_File not found"$;

  variable name, pat, glyph_hex, match_lines, match_line, i = 0;
  variable re = read_mini("Search for glyph:", "", "");

  ifnot (search_file (Unicode_Data_File, re, 200))
    return flush("nothing matched");

  _stk_reverse(_stkdepth);
  match_lines = __pop_list(_stkdepth());

  ifnot (length(match_lines))
    return flush("nothing matched");

  OldBuf = pop2buf_whatbuf (sprintf("%d glyphs matching \"%s\"",
                                    length(match_lines), re));

  _for i (0, length(match_lines)-1, 1)
  {
    match_line = strtrim(match_lines[i]);
    glyph_hex = pcre_matches("[A-Z0-9]{4,}", match_line)[-1];
    name = pcre_matches(";(.*?);", match_line)[-1];
    ifnot (NULL == glyph_hex)
    {
      glyph_hex = strcat("0x", glyph_hex);
      if (Integer_Type == _slang_guess_type(glyph_hex))
      {
        glyph_hex = char(integer(glyph_hex));
        vinsert("%s %s\n", glyph_hex, name);
      }
    }
  }

  bob();
  set_buffer_modified_flag(0);
  most_mode();
  local_setkey("insert_char_other_buffer", "\r");
}

add_completion("glyph");
