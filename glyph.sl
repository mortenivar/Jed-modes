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

ifnot (1 == file_status(Unicode_Data_File))
  throw ReadError, "$Unicode_Data_File not found"$;

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

% Show the description from the unicode character database for the
% character at the editing point.
public define glyph_show_description()
{
  variable pad_zeros, descr, hex_char_code;

  hex_char_code = pcre_matches("0x(.*?)/", count_chars());

  if (hex_char_code == NULL) return;

  hex_char_code = hex_char_code[1];

  % The unicode character database pads hexidecimal character codes at
  % four characters or less with leading zeros up to four characters.
  % Jed's count_chars() function does not, so align the latter to the
  % former.
  pad_zeros = 4 - strlen(hex_char_code);

  if (pad_zeros > 0)
  {
    loop (pad_zeros)
      hex_char_code = "0$hex_char_code"$;
  }

  hex_char_code = "^$hex_char_code;"$;

  ifnot (search_file (Unicode_Data_File, hex_char_code, 1))
    return flush("nothing matched");

  descr = __pop_list(1);
  descr = descr[0];

  if (is_substr(descr, "<control>"))
    descr = strchop(descr, ';', 0)[10];
  else
    descr = strchop(descr, ';', 0)[1];

  flush(descr);
}

add_completion("glyph");
add_completion("glyph_show_description");
