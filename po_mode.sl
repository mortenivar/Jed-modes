% -*- mode: slang; mode: fold -*-
% _debug_info=1;_traceback=1;_slangtrace=1;

%{{{ licence, presentation

%% po_mode.sl -- an Emacs-like Jed editing mode for
%% Gettext portable object files (*.po)
%%
%% License: http://www.fsf.org/copyleft/gpl.html
%% Author : Morten Bo Johansen <mbj@mbjnet.dk>
%%
%% Thanks to Paul Boekholt for some general hints relating to S-Lang
%% scripting and to Günter Milde for including it in the jed-extra
%% package in Debian.
%%
%% Tested with Jed 0.99.19 on Linux, compiled against slang 2.2
%% Superficially tested with emulations, cua, edt, emacs, ide, jed and
%% wordstar. You must edit several functions to make it usable on
%% non-Unix systems.
%%
%% Copy this file and po_mode.hlp to a directory in your jed library path,
%% e.g. /usr/share/jed/lib. For initialization, either use make_ini()
%% (from jedmodes.sf.net/mode/make_ini/) or copy the content of the
%% INITIALIZATION block to your .jedrc.
%%
%% For the rest, please refer to the po_mode.hlp file for the ins and outs
%% of this mode. There is some rather important information therein, so you
%% should read it ;-). If you copied it to the same place as this file, it
%% should be available in po_mode by typing '?'.
%%

define show_version_and_licence_info ()
{
  variable license =
    ["po-mode for Jed, version: $Version"$,
     "Copyright (C) 2015-: Morten Bo Johansen <mbj@mbjnet.dk>",
     "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>",
     "This is free software: you are free to change and redistribute it.",
     "There is ABSOLUTELY NO WARRANTY"];

  pop2buf ("***Version and License Information***");
  insert (strjoin (license, "\n"));
  set_buffer_modified_flag (0);
  most_mode ();
  bob ();
}

%}}}
%{{{ Prototypes

public define po_mode ();

%}}}
%{{{ debian initialization block

#<INITIALIZATION>
autoload ("po_mode", "po_mode");
add_mode_for_extension ("po", "po");
add_mode_for_extension ("po", "pot");
#</INITIALIZATION>

%}}}
%{{{ modules/autoloads/

import ("pcre");
autoload ("most_exit_most", "most");
autoload ("grep", "grep.sl");
() = evalfile ("keydefs");

%}}}
%{{{ user customization variables

%% Your name and email address as translator
custom_variable ("Translator", "");

%% Email address of your language team
custom_variable ("Team_Email", "");

%% Your language - use English adjective, e.g. "German", "Danish" etc.
custom_variable ("Language", "");

%% The two-letter code for your language.
%% See http://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
custom_variable ("LangCode", "");

%% The two-letter code for your country.
%% See http://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
custom_variable ("CountryCode", "");

% Default character encoding of po-file. utf-8, iso-8859-1, etc
custom_variable ("Encoding", "utf-8");

%% Path to directory where source archives are usually kept
custom_variable ("SrcBaseDir", expand_filename ("~/src"));

%% Language pair for machine translation system, Apertium
%% E.g. "en-es" will use the English-to-Spanish pair.
custom_variable ("Apertium_Langs", "");

%% Your chosen spell checker. Use "aspell" or "hunspell" (recomended)
custom_variable ("Spell_Prg", "");

%% po-files in languages that you want to compare your translations
%% with. A comma-separated string of iso language codes as listed in
%% http://en.wikipedia.org/wiki/List_of_ISO_639-1_codes. Change the
%% codes below to your liking. This example will compare with Swedish,
%% Norwegian Bokmål, German, French and Dutch.
custom_variable ("Compare_With_Languages", "");

%% Path to your translation compendium file
custom_variable ("Compendium", expand_filename ("~/.compendium_pomode"));
%}}}
%{{{ private variables

private variable
  Mode = "PO",
  Buf = "",
  Edit_Mode = "Po_Edit",
  Edit_Buf = " *Translate*",
  Msgid_Buf = "Msgid",
  Po_Comment_Buf = "*Edit User Comment*",
  Po_Tmpfile = make_tmp_file ("po_tmpfile"),
  gettext_err_msg = "/tmp/gettext_err_msg",
  Msgids = Array_Type,
  Msgstrs = Array_Type,
  Obsolete = Array_Type,
  Po_Dir = Null_String,
  Msgstr = Null_String,
  Last_Edited = Null_String,
  Msgstr_Copy = Null_String,
  Entry = Assoc_Type[String_Type, ""],
  CompHash = Assoc_Type[String_Type, ""],
  CompHash_Fuzzy = Assoc_Type[String_Type, ""],
  Trans_Hash = Assoc_Type[String_Type, ""],
  Po_Buf = "",
  Entry_No = 0,
  Multi_Line = 0,
  Gettext_Wrap = 0,
  Translation_Status = 0,
  StrsLists_Exists = 0,
  Trans_Hash_Exists = 0,
  Compendium_Is_Hashed = 0,
  Version = "1.2.1",
  Wrap = 79;

%}}}
%{{{ buffer local variables
%% Make all count variables local to the buffer
private define count (type)
{
  switch (type)
  { case "t": get_blocal_var ("translated"); }
  { case "u": get_blocal_var ("untranslated"); }
  { case "f": get_blocal_var ("fuzzy"); }
  { case "o": get_blocal_var ("obsolete"); }
  { case "t+": set_blocal_var (get_blocal_var ("translated") + 1, "translated"); }
  { case "t-": set_blocal_var (get_blocal_var ("translated") - 1, "translated"); }
  { case "u+": set_blocal_var (get_blocal_var ("untranslated") + 1, "untranslated"); }
  { case "u-": set_blocal_var (get_blocal_var ("untranslated") - 1, "untranslated"); }
  { case "f+": set_blocal_var (get_blocal_var ("fuzzy") + 1, "fuzzy"); }
  { case "f-": set_blocal_var (get_blocal_var ("fuzzy") - 1, "fuzzy"); }
  { case "o+": set_blocal_var (get_blocal_var ("obsolete") + 1, "obsolete"); }
  { case "o-": set_blocal_var (get_blocal_var ("obsolete") - 1, "obsolete"); }
}

%}}}
%{{{ dfa syntax and colors

#ifdef HAS_DFA_SYNTAX
% %%% DFA_CACHE_BEGIN %%%
create_syntax_table (Mode);
private define setup_dfa_callback (Mode)
{
  custom_color ("tokens", get_color ("keyword")); % msgstr, msgid keywords
  custom_color ("flagcomment", get_color ("comment")); % e.g. fuzzy flag comment
  custom_color ("usercomment", get_color ("string")); % translators note to entry
  custom_color ("begblank", get_color ("number"), exch ()); % whitespace at beg/end of line
  custom_color ("begblank1", get_color ("number"), exch ()); % whitespace at beg/end of line
  custom_color ("endblank", get_color ("number"), exch ()); % whitespace at beg/end of line
  custom_color ("srccomment", get_color ("number")); % source reference comments
  custom_color ("extrcomment", get_color ("comment")); % developer's notes to translator
  custom_color ("ctxcomment", get_color ("comment")); % context comments
  custom_color ("lbreak", get_color ("bold")); % newline literals "\n"
  custom_color ("pyvar", get_color ("string"));
  custom_color ("pyvar1", get_color ("string"));
  custom_color ("format_specifier", get_color ("string")); % "%d" "%s" "%f"

  % dfa_enable_highlight_cache ("po.dfa", Mode);
  dfa_define_highlight_rule ("^msg(id_?p?l?u?r?a?l?|str)", "tokens", Mode);
  dfa_define_highlight_rule ("^#, .*", "flagcomment", Mode);
  dfa_define_highlight_rule ("^\" +", "begblank", Mode);
  dfa_define_highlight_rule ("[^\\\\]\" +", "begblank1", Mode);
  dfa_define_highlight_rule ("[ \t]+\\\\?n?\"$", "endblank", Mode);
  dfa_define_highlight_rule ("\\\\n", "lbreak", Mode);
  dfa_define_highlight_rule ("^#: .*$", "srccomment", Mode); % src
  dfa_define_highlight_rule ("^msgctxt.*$", "extrcomment", Mode);
  dfa_define_highlight_rule ("^#\\| .*$", "ctxcomment", Mode);
  dfa_define_highlight_rule ("^#\\. ?.*$", "extrcomment", Mode);
  dfa_define_highlight_rule ("^# .*$", "usercomment", Mode);
  dfa_define_highlight_rule ("%\\([0-9A-Za-z_]+\\)", "pyvar", Mode);
  dfa_define_highlight_rule ("{.*}", "pyvar1", Mode);
  dfa_define_highlight_rule ("%[bBcdfFls]+", "format_specifier", Mode);
  dfa_build_highlight_table (Mode);
  enable_dfa_syntax_for_mode (Mode);
}
dfa_set_init_callback (&setup_dfa_callback, Mode);
%%% DFA_CACHE_END %%%
#endif

%}}}
%{{{ delimitation, navigation

% Find the beginning of an entry
private define find_entry_delim_beg ()
{
  if (eolp () && bolp () && not eobp () || bobp ())
    return;
  ifnot (bol_bsearch ("\n"))
    bob ();
}

% Find the end of an entry
private define find_entry_delim_end ()
{
  find_entry_delim_beg ();
  go_down_1 ();
  ifnot (bol_fsearch ("\n"))
    eob ();
}

%% Determine if an entry is untranslated.
private define is_untranslated ()
{
  push_spot ();
  ((down (1)) && (not looking_at ("\"")) && (up (1)) && (blooking_at (" \"\"")));
  pop_spot ();
}

private define is_translated ()
{
  not is_untranslated ();
}

% Does the entry have a "fuzzy" tag
private define is_fuzzy ()
{
  push_spot ();
  find_entry_delim_beg ();
  push_mark ();
  () = bol_fsearch ("msgid");
  variable str = bufsubstr ();
  ((is_substr (str, "#, fuzzy")) && (not (is_substr (str, "#~ "))));
  pop_spot ();
}

% Mark a whole entry
private define mark_entry ()
{
  find_entry_delim_beg ();
  ifnot (bobp ())
    go_right_1 ();
  push_visible_mark ();
  find_entry_delim_end ();
  ifnot (eobp)
    go_left_1 ();
}

private define get_current_entry_number ()
{
  variable i = 0;
  push_spot ();
  find_entry_delim_end ();
  while (bol_bsearch ("msgid"))
    i++;
  pop_spot ();
  return i;
}

% Jump to the msgstr keyword
private define find_msgstr_keyword ()
{
  bol ();

  if (looking_at ("#~"))
    throw UsageError, "obsolete entry";

  if (eolp () && bolp () || bobp ())
  {
    ifnot (bol_fsearch ("msgstr"))
    {
      () = bol_bsearch ("msgstr");
    }
    return;
  }
  if (re_looking_at ("^\""))
  {
    () = bol_bsearch ("msgid");
  }
  do
  {
    if (looking_at ("msgstr"))
      return;
    if (looking_at ("msgid "))
    {
      () = bol_fsearch ("msgstr");
      return;
    }
    if (looking_at ("msgid_plural"))
    {
      () = bol_fsearch ("msgstr[1]");
      return;
    }
  }
  while (down (1));
}

% Jump to the msgid keyword
private define find_msgid_keyword ()
{
  find_msgstr_keyword ();
  if ((looking_at ("msgstr ")) || (looking_at ("msgstr[0]")))
    () = bol_bsearch ("msgid ");
  else
    () = bol_bsearch ("msgid_plural");
}

private define mark_msgid ()
{
  find_msgid_keyword ();
  push_mark ();
  go_right_1 ();
  () = bol_fsearch ("msg");
  go_left_1 ();
}

private define mark_msgstr ()
{
  find_msgstr_keyword (); push_mark (); go_down_1 ();

  do
  {
    if ((looking_at ("\n")) || (looking_at ("msgstr")))
      break;
  }
  while (down (1));

  go_left_1 ();
}

%% Mark a word and return it
private define po_mark_word ()
{
  variable word = "";

  define_word ("-A-Za-zÀ-ÿ");
  push_spot ();
  bskip_word_chars ();
  push_mark ();
  skip_word_chars ();
  bufsubstr ();
  pop_spot ();
}

% Return the whole entry as a string
private define entry_as_str ()
{
. push_spot mark_entry bufsubstr pop_spot
}

% Return the msgid as a string
private define msgid_as_str ()
{
. push_spot mark_msgid bufsubstr pop_spot
}

% Return the msgstr as a string
private define msgstr_as_str ()
{
. push_spot mark_msgstr bufsubstr pop_spot
}

define show_current_entry_number ()
{
  variable n = get_current_entry_number ();

  flush ("# $n"$);
}

% Jump to the next entry
define po_next_entry ()
{
  find_msgid_keyword ();
  go_right_1 ();
  () = re_fsearch ("^msgid_?");
}

% Jump to the previous entry
define po_previous_entry ()
{
  push_mark (); find_entry_delim_beg ();
  if (bol_bsearch ("msgid"))
    return pop_mark_0 ();
  pop_mark_1 ();
}

% Put the entry in the top of the display
define top_justify_entry ()
{
  find_entry_delim_beg (); go_right_1 (); recenter (1);
}

define goto_entry (n)
{
  if (n < 0)
  {
    n = read_mini ("Go to entry number:", "", "");
    n = integer (n);
  }

  if (n > get_blocal_var ("total_entries")+1)
    throw UsageError, "no such entry";

  bob ();

  loop (n)
  {
    () = bol_fsearch ("msgid");
    eol ();
  }

  bol ();
}

%% Goto next or previous translated or untranslated message
define find_msgstr (dir, status)
{
  variable search_fun, move, translated;

  if (status > 0)
    translated = &is_translated ();
  else translated = &is_untranslated ();

  if (dir < 0)
  {
    search_fun = &bol_bsearch ();
    move = &go_left_1 ();
  }
  else
  {
    search_fun = &bol_fsearch ();
    move = &go_right_1 ();
  }

  push_mark ();
  @move ();
  while (@search_fun ("msgstr"))
  {
    if (@translated ())
    {
      if (status > 0)
      {
        if (is_fuzzy ())
        {
          @move ();
          continue;
        }
      }
      return pop_mark_0 ();
    }
    @move ();
  }
  flush ("no matches beyond this point");
  return pop_mark_1 ();
}

%% Find the previous entry with fuzzy flag.
define bfind_fuzzy ()
{
  find_entry_delim_beg ();

  while (bol_bsearch ("#, fuzzy"))
  {
    push_spot ();
    go_down_1 ();
    if (looking_at ("#~"))
    {
      pop_spot ();
      continue;
    }
    return pop_spot ();
  }
  flush ("no fuzzy entries above this point");
}

%% Find the next entry with fuzzy flag.
define find_fuzzy ()
{
  push_mark ();
  while (bol_fsearch ("#, fuzzy"))
  {
    go_down_1 ();
    if (looking_at ("#~"))
    {
      pop_mark_0;
      continue;
    }
    else return pop_mark_0;
  }
  flush ("wrapping search around buffer ...");
  bob ();
  ifnot (bol_fsearch ("#, fuzzy"))
  {
    flush ("no fuzzy entries");
    pop_mark_1;
  }
  pop_mark_0;
}

%% Find the next obsolete entry.
define find_obsolete ()
{
  push_mark ();
  while (fsearch ("#~ msgid "))
  {
    () = bol_fsearch ("#~ msgstr ");
    return pop_mark (0);
  }
  flush ("wrapping search around buffer ...");
  bob ();
  ifnot (fsearch ("#~ msgid "))
  {
    flush ("no obsolete entries");
    pop_mark_1 ();
  }
  pop_mark_0 ();
}

%% Go to next entry that is either fuzzy or untranslated
define any_next_unfinished ()
{
  push_mark ();
  go_right_1 ();
  while (bol_fsearch ("msgstr"))
  {
    if ((is_untranslated ()) || (is_fuzzy ()))
      return pop_mark_0 ();
    else
      go_right_1 ();
  }
  flush ("wrapping search around buffer ...");
  bob ();
  while (bol_fsearch ("msgstr"))
  {
    if ((is_untranslated ()) || (is_fuzzy ()))
      return pop_mark_0 ();
    else
      go_right_1 ();
  }
  flush ("no unfinished entries below this point");
  pop_mark_1 ();
}

% Jump to the next translator comment
define find_translator_comment ()
{
  push_mark ();
  find_entry_delim_end ();
  while (bol_fsearch ("# "))
  {
    () = bol_fsearch ("msgid");
    return pop_mark (0);
  }
  flush ("wrapping search around buffer");
  bob ();
  while (bol_fsearch ("# "))
  {
    () = bol_fsearch ("msgid");
    return pop_mark (0);
  }
  pop_mark (1);
  flush ("no more translator comments");
}

%}}}
%{{{ statistics

%% The status line that shows the counts for translated, untranslated, fuzzy
%% and obsolete entries
define set_po_status_line ()
{
  variable t, u, f, o, s, n, p, mode;

  ifnot ("PO" == get_mode_name ())
    return;

  if (get_blocal_var ("View_Limit", 1))
    return;

  t = count ("t"); u = count ("u"); f = count ("f"); o = count ("o");
  n = t + f + u;
  if (n == 0) n = 1;
  p = Sprintf ("(%S%s) ", (t*100)/n, "%%",  2);
  s = Sprintf ("%dt/%du/%df/%do", t, u, f, o, 4);
  set_status_line (" %b " + p + s + "  (%m%a%n%o)  %p   %t", 0);
}

%% The actual counting of the various entries.
private define po_statistics ()
{
  variable t, u, f, o, ct, cts, n = 0;

  ifnot ("PO" == get_mode_name ())
    return;

  cts = {"translated","untranslated","fuzzy","obsolete","total_entries"};

  foreach ct (cts)
  {
    create_blocal_var (ct);
    set_blocal_var (0, ct);
  }

  t = count ("t"); u = count ("u"); f = count ("f"); o = count ("o");

  push_spot_bob ();
  () = bol_fsearch ("\n");
  push_mark (); push_mark ();
  while (bol_fsearch ("msgstr"))
  {
    if (is_untranslated ())
      u++;
    else
      t++;
    eol ();
  }
  pop_mark_1 ();
  while (bol_fsearch ("#~ msgid"))
  {
    eol ();
    o++;
  }
  pop_mark_1 ();
  while (bol_fsearch ("#, fuzzy"))
  {
    () = down (2);
    if (looking_at ("#~")) break;
    if (looking_at ("msgid_plural"))
    {
      f++; f++;
    }
    else
      f++;
  }

  pop_spot ();

  t = t - f; % translated count includes fuzzies, so deduct them

  set_blocal_var (t, "translated");
  set_blocal_var (u, "untranslated");
  set_blocal_var (f, "fuzzy");
  set_blocal_var (o, "obsolete");
  set_blocal_var (t + u + f, "total_entries");

  set_po_status_line ();
}

%% Shows the counts in the message area, including total count and current
%% position
define show_po_statistics ()
{
  ifnot ("PO" == get_mode_name ())
    return;

  variable t, u, f, o;
  variable n = get_blocal_var ("total_entries");
  variable cn = get_current_entry_number ();
  t = count ("t"); u = count ("u"); f = count ("f"); o = count ("o");
  po_statistics ();
  flush ("Position: $cn/$n; $t translated, $u untranslated, $f fuzzy, $o obsolete"$);
}

%}}}
%{{{ auxillary functions

%% Catch output from a system cmd in a string.
private define syscmd_output_to_string ()
{
  variable exit_status = 0, str = "", fp, cmd = "";

  cmd = ();
  fp = popen (cmd, "r");

  if (fp == NULL)
    throw RunTimeError, "could not open pipe to process";

  str = strjoin (fgetslines (fp), "");
  exit_status = pclose (fp);
  str = strtrim (str);
  return (str, exit_status);
}

% Envelop every line in a string in double quotes
private define surround_in_quotes (str)
{
  str = strchop (str, '\n', 0);
  str = array_map (String_Type, &strcat, "\"", str, "\"");
  return strjoin (str, "\n");
}

%% Get the language/country code and charset from the enviroment,
define get_locale_info ()
{
  variable locale_values = array_map (String_Type, &getenv, ["LC_MESAGES","LANG","LC_ALL"]);
  variable i = where (strlen (locale_values));

  try
  {
    variable n = is_substr (locale_values[i][0], ".");
    variable lang = locale_values[i][0][[0:1]]; % e.g. "en"
    variable country = locale_values[i][0][[3:4]]; % e.g. "en"
    variable lang_COUNTRY = locale_values[i][0][[0:4]]; % e.g. "en_UK"
    variable encoding = locale_values[i][0][[n:]]; % e.g. utf8
  }
  catch AnyError:
    flush ("could not set aspell dictionary from environment!");

  return lang_COUNTRY, lang, country, encoding;
}

% Replace a string with another using pcre regular expressions
private define pcre_replace (str, pat, rep)
{
  variable enc = "", match, pos = 0;

  (,,,enc) = get_locale_info ();

  try
  {
    if (enc == "utf-8")
      pat = pcre_compile (pat, 0x20000000|PCRE_UTF8);
    else
      pat = pcre_compile (pat);
  }
  catch ParseError:
    return flush ("Invalid regular expression");

  while (pcre_exec (pat, str, pos))
  {
    match = pcre_nth_match (pat, 0);
    str = strcat (str[[0:match[0]-1]], rep, str[[match[1]:]]);
    pos = match[0] + strlen (rep);
  }

  return str;
}

% match against a string using pcre regular expressions
private define pcre_string_match (str, pat)
{
  pat = pcre_compile (pat);
  return pcre_exec (pat, str);
}

%% determine the type of file, regular, directory, etc.
private define file_type (file, type)
{
  variable st = stat_file (file);

  if (st == NULL)
    return 0;

  return stat_is (type, st.st_mode);
}

%% Probe for directory of source archive
private define init_src_dir (msg)
{
  variable cur_dir = "", srcdir = "", srcdir_name = "", srcdirs, k = 0;
  variable other = "", dir = "";%, msg = "";

  (,cur_dir,,) = getbuf_info (whatbuf ());
  srcdir_name = extract_element (whatbuf (), 0, '.');
  srcdirs = listdir (SrcBaseDir);
  srcdirs = array_map (String_Type, &dircat, SrcBaseDir, srcdirs);
  srcdirs = srcdirs[where (array_map (Int_Type, &file_type, srcdirs, "dir"))];
  srcdirs = srcdirs[where (array_map (Int_Type,
                                      &string_match, srcdirs, srcdir_name, 1))];
  if (length (srcdirs))
  {
    msg = "Choose directory with $msg"$;
    srcdir = srcdirs[0];
    k = get_mini_response ("$msg: 1) $srcdir, 2) $cur_dir, 3) other"$);
  }
  else
    k = get_mini_response ("$msg: 1) $cur_dir, 2) other"$);

  switch (k)
  { case '1': dir = read_with_completion ("$msg:"$, "", srcdir, 'f'); }
  { case '2': dir = read_with_completion ("$msg:"$, "", cur_dir, 'f'); }
  { case '3': dir = read_with_completion ("$msg:"$, "", SrcBaseDir, 'f'); }
  { throw UsageError, "no source directory selected"; }

  return dir;
}

%% Return a program in $PATH
private define check_for_prg (prg)
{
  variable path = getenv ("PATH"), res = "";

  res = search_path_for_file (path, prg);

  if (res == NULL)
    throw OpenError, "$prg is not installed"$;

  return res;
}

%% Check for po files in a directory
private define pofiles_in_dir (dir)
{
  variable files, exts, po_files, po_matches;

  files = listdir (dir);
  files = array_map (String_Type, &dircat, dir, files);
  files = files[where (array_map (Int_Type, &file_type, files, "reg"))];
  exts = array_map (String_Type, &path_extname, files);
  po_matches = where (exts == ".po");
  po_files = files[po_matches];

  return po_files;
}

%% The two window layout for editing msgstrs and comments
private define setup_win_layout (view_buf, view_str, edit_buf, edit_str)
{
  variable win_rows, nlines_msgid, msgid, delim, msgid_arr;

  recenter (1);
  Po_Buf = pop2buf_whatbuf (edit_buf);
  pop2buf (view_buf);
  insert (view_str);
  set_buffer_modified_flag (0);
  nlines_msgid = what_line ();
  bob ();
  win_rows = window_info ('r');
  otherwindow ();
  loop (win_rows - nlines_msgid-1)
    enlargewin ();
  insert (edit_str);
  ifnot (Multi_Line)
  {
    set_mode (Edit_Mode, 1); % wrap_mode
    WRAP=Wrap;
  }
  else
    set_mode (Edit_Mode, 0);

  bob ();
  set_buffer_modified_flag (0);
}

% Write current buffer to a temporary file
private define write_buf_to_tmpfile ()
{
  push_spot ();
  mark_buffer ();
  () = write_region_to_file (Po_Tmpfile);
  pop_spot ();
}

%% In order to preserve undo information, which erase_buffer() does not.
private define po_erase_buffer ()
{
  mark_buffer (); del_region ();
}

private define po_edit_wrap_hook ()
{
  push_spot (); bol (); go_left (1); insert (" "); pop_spot ();
}

%% The library function from jed
private define search_path_for_file ()
{
  variable path, f, delim = path_get_delimiter ();

  if (_NARGS == 3)
    delim = ();

  (path, f) = ();

  if (path == NULL)
    return NULL;

  foreach (strtok (path, char(delim)))
  {
    variable dir = ();
    variable file = strcat (dir, "/", f);

    if (file_type (file, "reg"))
      return file;
  }

  return NULL;
}

%% Look for a program from an array of programs and return the first
%% one found
private define find_prgs_use_first (prgs)
{
  variable prg, prgs_arr = strtok (prgs), path = getenv ("PATH");

  prgs_arr = prgs_arr[wherenot (_isnull (array_map (String_Type, &search_path_for_file, path, prgs_arr)))];

  ifnot (length (prgs_arr))
    throw OpenError, "Error: You must install one of $prgs"$;
  else
    prg = prgs_arr[0];

  return prg;
}

% Use a text browser to format html to text
private define html_to_txt (url)
{
  variable cmd, browser, browser_basename, output, status, enc, pingurl;
  variable ping_resp;

  (,,, enc) = get_locale_info ();
  browser = find_prgs_use_first ("lynx elinks w3m");
  browser_basename = path_basename (browser);

  switch (browser_basename)
  { case "lynx":
      cmd = "/usr/bin/lynx -dump -nolist -nonumbers -width 500 -display_charset=$enc"$;
  }
  { case "elinks":
      cmd = "$browser -dump -dump-charset $enc -no-references -no-numbering"$;
  }
  { case "w3m":
      cmd = "$browser -dump -cols 500 -O $enc"$;
  }

  pingurl = strchop (url, '/', 0)[2];
  (, ping_resp) =
    syscmd_output_to_string ("ping -W2 -q -c1 $pingurl >/dev/null 2>&1"$);

  ifnot (0 == ping_resp)
    return "";

  (output, status) = syscmd_output_to_string ("$cmd \"$url\" 2>/dev/null"$);

  if (0 == status)
    return output;
  else
    throw RunTimeError, "$cmd \"$url\" failed"$;
}

% How many lines is there in a string
private define lines_count (str)
{
  return length (strchop (strtrim (str), '\n', 0));
}

private define str_has_end_newline (str)
{
  return ((str[[-3:]] == "\\n\"") || (str == "msgid \"\""));
}

% If the first character in string is a newline
private define str_has_beg_newline (str)
{
  return (str[0] == '\n');
}

% If the string is a gettext multiline string
private define str_is_multiline (str)
{
  return ((is_substr (str, "\\n")) ||
          (pcre_string_match (str, "^msgid \"\"$")));
}

% Delete html tags
private define del_html_tags (str)
{
  return strtrim (str_uncomment_string (str, "<", ">"));
}

% Delete format specifiers
private define del_format_specifiers (str)
{
  variable letter, letters = [['A':'Z'], ['a':'z']];

  foreach (letters)
  {
    letter = char ();
    str = strreplace (str, strcat ("%", letter), "");
  }

  return str;
}

% This mode depends on each entry being separated by one blank line.
% Gettext, however, allows blank lines inserted randomly within entries.
% Make sure such lines are deleted.
private define parse_blank_lines ()
{
  bob ();
  while (bol_fsearch ("\n"))
  {
    ifnot ((looking_at ("\n#")) || (looking_at ("\nmsgid"))
           && (blooking_at ("\"\n")))
    {
      del ();
    }
    go_right_1 ();
  }
  bob ();
}

%% Check in file with RCS
define check_in_file ()
{
  variable file, dir, flags, rcsdir, rcsfile, cmd, buf_file, msg = "";
  variable ci_prg = check_for_prg ("ci"), logmsg = "";

  (file, dir,,) = getbuf_info ();
  buf_file = dircat (dir, file);
  rcsdir = dircat (dir, "RCS");
  rcsfile = dircat (rcsdir, strcat (file, ",v"));

  ifnot (file_status (rcsdir) == 2)
  {
    ifnot (0 == system ("mkdir -p \"$rcsdir\""$))
      throw IOError, "could not create directory \"$rcsdir\""$;
  }

  ifnot (1 == file_status (rcsfile)) % initial revision
    cmd = "ci -l -i -m -t- $buf_file 2>/dev/null"$;
  else
  {
    logmsg = read_mini ("Enter a log message:", "New revision", "");
    cmd = "ci -l -m\"$logmsg\" -t-\"\" $buf_file 2>/dev/null"$;
  }

  ifnot (0 == system (cmd))
    throw RunTimeError, "could not check in $buf_file"$;

  % If you have RCS expansion markers they will change
  % file on disk, in which case reload it
  check_buffers (); % check if disk file is newer and update buffer flags

  (,,,flags) = getbuf_info ();

  if (flags & 0x004)
  {
    delbuf (whatbuf ());
    () = find_file (buf_file);
  }

  flush ("file checked in");
}

define checkout_rcs_file (view)
{
  variable log = "", e, ver = "", fstr = "", dates, revs, lines, file = "";
  variable co_prg = check_for_prg ("co");
  variable rlog_prg = check_for_prg ("rlog");

  if (view)
    file = read_mini ("File to check out", buffer_filename, "");
  else
    file = buffer_filename ();

  ifnot (file_type (file, "reg"))
    throw RunTimeError, "$file not found"$;

  (log, e) = syscmd_output_to_string ("$rlog_prg $file 2>/dev/null"$);

  ifnot (0 == e)
    throw RunTimeError, "Could not obtain RCS log for $file"$;

  log = strreplace (log, "\t", " ");
  lines = strchop (log, '\n', 0);
  revs = lines[where (array_map (Int_Type, &string_match, lines, "^revision ", 1))];
  revs = array_map (String_Type, &extract_element, revs, 1, ' ');
  dates = lines[where (array_map (Int_Type, &string_match, lines, "^date: ", 1))];
  dates = array_map (String_Type, &extract_element, dates, 1, ' ' );
  revs = revs[*] + " " + dates[*];
  revs = strjoin (revs, ",");
  ver = read_with_completion (revs, "Choose version <TAB=view versions and complete>:", "", "", 's');
  ver = extract_element (ver, 0, ' ');
  (fstr, e) = syscmd_output_to_string ("$co_prg -q -p$ver $file 2>/dev/null"$);

  if (view)
  {
    pop2buf ("Viewing RCS version $ver of $file"$);
    onewindow ();
    insert (fstr);
    set_buffer_modified_flag (0);
    bob ();
    most_mode ();
  }
  else
    return fstr, ver;
}

define exit_po_mode ()
{
  no_mode ();
  use_keymap ("global");
  set_readonly (0);
  call ("redraw");
  set_status_line ("", 0);
  flush ("use \"M-x po_mode\" to return");
}

%% Display help window
define show_help ()
{
  variable file = expand_jedlib_file ("po_mode.hlp");

  if (strlen (file))
    jed_easy_help (file);
  else
    throw OpenError, "help file not found";
}

%% Send a bug report
define reportbug ()
{
  mail ();
  () = bol_bsearch ("To: ");
  eol ();
  insert ("Morten Bo Johansen <mbj@mbjnet.net>");
  () = bol_fsearch ("Subject:");
  eol ();
  insert ("[po_mode] ");
}

% An undo function adapted to this mode
define po_undo ()
{
  variable n = get_current_entry_number ();
  set_readonly (0);
  call ("undo");
  goto_entry (n);
  po_statistics ();
  set_readonly (1);
}

% Abort editing a translation
define cancel_edit ()
{
  po_erase_buffer ();
  set_buffer_modified_flag (0);
  delbuf (Msgid_Buf);
  bury_buffer (Edit_Buf);
  if (bufferp (Po_Comment_Buf))
    delbuf (Po_Comment_Buf);
  sw2buf (Po_Buf);
  widen (); onewindow ();
  find_entry_delim_beg ();
  recenter (1);
  () = bol_fsearch (Last_Edited);
}

% Return a file as a string
private define file_as_str (file)
{
  variable str = "";
  variable fp = fopen (file, "r");

  if (fp == NULL)
    throw IOError, "could not open \"$file\""$;

  str = strjoin (fgetslines (fp), "");
  () = fclose (fp);
  return str;
}

%}}}
%{{{ mark functions, string functions, hash functions

% Return the current buffer as a string
private define buf_as_str ()
{
  push_spot_bob ();
  mark_buffer ();
  bufsubstr ();
  pop_spot ();
}

private define return_msgid_linenos ()
{
  variable str_arr = strchop (buf_as_str, '\n', 0);
  return wherenot (array_map (Int_Type, &strncmp,  str_arr, "msgid", 5));
}

%% Return an entry as an array of its elements, comments, msgids, msgstrs ..
private define strchop_entry (entry)
{
  variable entry_arr, msgctxt, cmt, msgid, delim, strs;

  strreplace (entry, "\v", " ");
  strreplace ((), "\nmsg", "\vmsg");
  entry_arr = strchop ((), '\v', 0);
  return array_map (String_Type, &strtrim, entry_arr);
}

%% Return po-file as two arrays consisting of current and obsolete
%% entries respectively
private define po2arr (str)
{
  variable str_arr, current, obsolete;

  str = strtrim (str);
  str = strreplace (str, "\v", "");
  str = strreplace (str, "\n\n", "\v");
  str_arr = strchop (str, '\v', 0);
  str_arr = str_arr[where (array_map (Int_Type, &strlen, str_arr))];
  str_arr = array_map (String_Type, &strtrim, str_arr);
  obsolete = array_map (Int_Type, &string_match, str_arr, "#~ msgid", 1);
  obsolete = where (obsolete, &current);
  current = str_arr[current];
  Obsolete = str_arr[obsolete];
  return (current, Obsolete);
}

% Create three arrays of comments, msgids and msgstrs respectively
private define create_strs_arr (str)
{
  variable entry, str_arr, cmts = {}, msgids = {}, msgstrs = {};

  (str_arr,) = po2arr (str);
  str_arr = array_map (Array_Type, &strchop_entry, str_arr);

  foreach entry (str_arr)
  {
    ifnot (string_match (entry[0], "^#", 1))
      entry = ["", entry];

    if (string_match (entry[2], "msgid_plural", 1))
      list_append (cmts, entry[0]);

    list_append (cmts, entry[0]);
    list_append (msgids, entry[1]);

    if (length (entry) == 3)
      list_append (msgstrs, entry[2]);

    if (length (entry) == 4)  % asian forms like Japanese
      list_append (msgstrs, entry[3]);

    if (length (entry) > 4)
    {
      list_append (msgids, entry[2]);
      list_append (msgstrs, entry[3]);
      list_append (msgstrs, entry[4]);
    }
  }

  cmts = list_to_array (cmts);
  msgids = list_to_array (msgids);
  msgstrs = list_to_array (msgstrs);
  return (cmts, msgids, msgstrs);
}

% Separate the keyword and the string in an entry and return them
private define sep_kw_and_str (str)
{
  variable keyword = extract_element (str, 0, ' ');

  if (pcre_string_match (str, "\"\"\n\""))
    str = str[[strlen (keyword)+4:]];
  else
    str = str[[strlen (keyword)+1:]];

  return (keyword, str);
}

% Return a concatenated string of keyword and string
private define concat_kw_str (kw, str)
{
  str = strtrim (str);

  if ((strlen (kw + str) > Wrap) || (lines_count (str) > 1))
    str = strcat (kw, " \"\"\n", str);
  else
    str = strcat (kw, " ", str);

  return str;
}

% Trim a chosen number of characters from a string
private define trim_chars (str, beg, end)
{
  return str[[beg:strbytelen (str)-1-end]];
}

%% Trim the two single outermost double quotes from each line
private define trim_quotes (str)
{
  str = strreplace (str, "\"\n\"", "\n");
  return strtrim (str, "\"");
}

%% With this, every element in a po-file entry can be isolated.
private define hash_entry ()
{
  variable po = Assoc_Type[Array_Type];
  variable entry_hash = Assoc_Type[String_Type, ""];
  variable cmts_arr, key, value, entry_arr, entry;

  ifnot (_NARGS)
    entry = entry_as_str ();
  else
    entry = ();

  entry_arr = strchop_entry (entry);

  if (0 == strncmp (entry_arr[0], "#", 1))
  {
    cmts_arr = strchop (entry_arr[0], '\n', 0);

    po["trans_cmts"] =
      cmts_arr [wherenot (array_map (Int_Type, &strncmp, cmts_arr, "# ", 2))];
    po["extr_cmts"] =
      cmts_arr [wherenot (array_map (Int_Type, &strncmp, cmts_arr, "#.", 2))];
    po["ref_cmts"] =
      cmts_arr [wherenot (array_map (Int_Type, &strncmp, cmts_arr, "#:", 2))];
    po["flag_cmts"] =
      cmts_arr [wherenot (array_map (Int_Type, &strncmp, cmts_arr, "#,", 2))];
    po["ctx_cmts"] =
      cmts_arr [wherenot (array_map (Int_Type, &strncmp, cmts_arr, "#|", 2))];

    entry_arr = entry_arr[[1:]];
  }

  po["msgctxt"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgctxt", 7))];
  po["msgid"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgid ", 6))];
  po["msgid_plural"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgid_", 6))];
  po["msgstr"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr ", 7))];
  po["msgstr[0]"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr[0]", 9))];
  po["msgstr[1]"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr[1]", 9))];
  po["msgstr[2]"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr[2]", 9))];
  po["msgstr[3]"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr[3]", 9))];
  po["msgstr[4]"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr[4]", 9))];
  po["msgstr[5]"] =
    entry_arr[wherenot (array_map (Int_Type, &strncmp, entry_arr, "msgstr[5]", 9))];

  foreach key, value (po) using ("keys", "values")
  {
    if (length (value))
    {
      value = strjoin (value, "\n");
      entry_hash[key] = value;
    }
  }

  return entry_hash;
}

%% Create an array of hashed entries of a whole po-file
private define create_entries_hash (str)
{
  variable entries_arr, entries_arr_hash;

  (entries_arr,) = po2arr (str);
  entries_arr_hash = array_map (Assoc_Type, &hash_entry, entries_arr);
  return entries_arr_hash;
}

%% Extract the string keywords, "msgid", "msgstr"
private define extract_keyword ()
{
  variable kw;
  push_spot ();
  kw = extract_element (line_as_string, 0, ' ');
  pop_spot ();
  return kw;
}

private define end_char (str)
{
  try
    return str[[strbytelen (str)-1:strbytelen (str)-1]];
  catch IndexError:
    return str;
}

%% Gettext-like wrapping. Lines are wrapped with trailing blanks
private define po_wrap_str (str)
{
  variable wrappoint = Wrap, i = 0, wrappoint_prev = 0, line;
  variable list = {};

  ifnot (strbytelen (str) > Wrap)
    return str;

  str = strreplace (str, "\n", "");

  _for i (0, strbytelen (str)-1, 1)
  {
    if ((str[i] != ' ') && (i > wrappoint))
    {
      while ((str[i] != ' ') && (i >= 0))
        i--;
      line = str[[wrappoint_prev:i]];
      list_append (list, line);
      wrappoint_prev = i + 1;
      wrappoint = i + Wrap;
    }
  }

  list_append (list, str[[wrappoint_prev:]]);
  str = list_to_array (list);
  return strjoin (str, "\n");
}

%% Prepare the msgstr for editing
private define prep_str (str)
{
  variable kw = "";

  (kw, str) = sep_kw_and_str (str);
  str = trim_quotes (str);

  variable str_arr = strchop (str, '\n', 0);

  str_arr = str_arr [where (array_map (Integer_Type, &strlen, str_arr))];
  str = strjoin (str_arr, "\n");
  str = strreplace (str, "\\\"", "\"");

  if (Multi_Line)
  {
    str = str_delete_chars (str, "\n");
    str = strreplace (str, "\\n", "\n");
  }

  return kw, str;
}

% The formatting done to the edited msgstr before it is written back
% into the po buffer
private define post_prep_str (str)
{
  variable str_arr, i = 0;

  str = strreplace (str, "\"", "\\\"");
  if (Multi_Line)
  {
    str_arr = strchop (str, '\n', 0);
    str_arr = array_map (String_Type, &po_wrap_str, str_arr);
    str = strjoin (str_arr, "\\n\n");
  }
  else
    str = po_wrap_str (str);

  str_arr = strchop (str, '\n', 0);
  str_arr = str_arr [where (array_map (Integer_Type, &strlen, str_arr))];
  str = strjoin (str_arr, "\n");
  return surround_in_quotes (str);
}

private define replace_buffer (rep)
{
  variable n = get_current_entry_number ();

  set_readonly (0);
  po_erase_buffer ();
  insert (rep);
  set_readonly (1);
  po_statistics ();
  goto_entry (n);
  set_po_status_line ();
}

% Apply the result of a gettext command to the current buffer
private define apply_gettext_cmd_to_buffer ()
{
  variable prg = check_for_prg ("msgcat");
  variable output, exit_status, n, cmd = ();

  n = get_current_entry_number ();
  write_buf_to_tmpfile ();
  (output, exit_status) = syscmd_output_to_string (cmd);
  () = delete_file (Po_Tmpfile);

  if (0 == exit_status)
  {
    replace_buffer (output);
    goto_entry (n);
    flush ("cmd successful");
    return 1;
  }

  return 0;
}

% Return the character set from the po-file header
private define get_charset_from_header (file)
{
  variable
    header_charset = "",
    entries = [""],
    charset_pat = "",
    header = "";

  if (file == buffer_filename)
    (entries,) = po2arr (buf_as_str ());
  else
  {
    ifnot (file_type (file, "reg"))
      throw OpenError, "$file not found or is not a file"$;

    (entries,) = po2arr (file_as_str (file));
  }

  ifnot (length (entries))
    return "";

  header = entries[0];
  charset_pat = pcre_compile ("charset=(.*)\\\\n");

  if (pcre_exec (charset_pat, header))
    header_charset = pcre_nth_substr (charset_pat, header, 1);

  if (header_charset == "CHARSET")
    header_charset = "utf-8";

  return strlow (header_charset);
}

% Replace the character set in the po-file header with another
private define replace_header_charset (file, enc)
{
  variable str = file_as_str (file);
  str = pcre_replace (str, "\"Content-Type: text/plain; charset.*[^\"]+",
                      "\"Content-Type: text/plain; charset=$enc\\n\"\n"$);
  return str;

}

%% Use the file(1) program to determine the encoding
private define get_file_encoding (file)
{
  variable prg = check_for_prg ("file");
  variable cmd = "", output = "", filestr = "";

  ifnot (1 == file_status (file))
    throw ReadError, "$file not found"$;

  %% remove all control characters as they make file(1) see
  %% the file as "binary"
  filestr = str_delete_chars (file_as_str (file), "\\c");
  () = write_string_to_file (filestr, Po_Tmpfile);
  cmd = "$prg -i $Po_Tmpfile 2>/dev/null"$;
  (output,) = syscmd_output_to_string (cmd);
  () = delete_file (Po_Tmpfile);
  return strchop (output, '=', 0)[1];
}

%% Get all encodings that are known to iconv.
private define list_known_encodings ()
{
  variable encodings;
  (encodings,) = syscmd_output_to_string ("iconv -l");
  encodings = strreplace (encodings, "/", "");
  encodings = strlow (encodings);
  return strchop (encodings, '\n', 0);
}

%% Convert encoding to user's preferred character set.
define conv_charset ()
{
  variable filestr = "", filenc = "",  enc = "", cmd = "", file = "", e = 0;
  variable args = __pop_args(_NARGS);
  variable conv = check_for_prg ("iconv");

  EXIT_BLOCK
  {
    () = delete_file (Po_Tmpfile);
  }

  % _jed_find_file_after_hooks does not allow arguments to the function
  if (0 == length (args))
    file = buffer_filename ();
  else
    file = args[0].value;

  ifnot (file_type (file, "reg"))
    return 1;

  filenc = get_charset_from_header (file);

  ifnot (strlen (filenc))
    filenc = get_file_encoding (file);

  ifnot (any (filenc == list_known_encodings))
    filenc = get_file_encoding (file);

  (,,,enc) = get_locale_info ();

  if ((strlow (filenc) == strlow (enc)) || (filenc == "us-ascii"))
    return 1;

  flush (sprintf ("recoding %s ...", path_basename (file)));
  e = system ("$conv -o $Po_Tmpfile -c -f $filenc -t $enc $file 2>/dev/null"$);

  ifnot(e == 0)
  {
    flush ("$conv failed , try to (V)alidate"$);
    return 0;
  }

  filestr = replace_header_charset (Po_Tmpfile, enc);

  if (file == buffer_filename ())
  {
    replace_buffer (filestr);
    bob ();
  }
  else
    () = write_string_to_file (filestr, file);

  flush ("File succesfully recoded from $filenc to $enc"$);
  return 1;
}

%% Create an associative array between msgids and msgstrs
private define hash_msgids_msgstrs (pofile, fuzzy)
{
  variable strs = Assoc_Type[String_Type, ""];
  variable strs_fuzzy = Assoc_Type[String_Type, ""];
  variable msgids, msgids_fuzzy, msgstrs, i = 0;
  variable msg = "creating entry hash";

  (, msgids, msgstrs) = create_strs_arr (pofile);
  msgstrs = array_map (String_Type, &strtrim_end, msgstrs, "@");

  if (fuzzy)
  {
    flush ("preparing msgids for fuzzy matching ...");
    msgids_fuzzy = array_map (String_Type, &del_format_specifiers, msgids);
    msgids_fuzzy = array_map (String_Type, &str_delete_chars, msgids, "^\\w");
    msgids_fuzzy = array_map (String_Type, &strlow, msgids_fuzzy);

    _for i (0, length (msgids_fuzzy)-1, 1)
    {
      flush (sprintf ("%s (fuzzy matching): entry %d of %d", msg, i, length (msgids)-1));
      strs_fuzzy[msgids_fuzzy[i]] = msgstrs[i];
    }
  }

  _for i (0, length (msgids)-1, 1)
  {
    flush (sprintf ("%s: (exact matching) entry %d of %d", msg, i, length (msgids)-1));
    strs[msgids[i]] = msgstrs[i];
  }

  return strs, strs_fuzzy;
}

%% Return msgid and msgstr;
private define return_str_pair ()
{
  variable msgid, msgstr, msgid_kw, msgstr_kw, entry = hash_entry ();

  try
  {
    push_spot ();
    find_msgstr_keyword ();
    msgstr_kw = extract_keyword ();

    if ((msgstr_kw == "msgstr") || (msgstr_kw == "msgstr[0]"))
      msgid_kw = "msgid";
    else
      msgid_kw = "msgid_plural";

    msgid = entry[msgid_kw];
    msgstr = entry[msgstr_kw];
    return (msgid_kw, msgstr_kw, msgid, msgstr);
  }
  finally
  {
    pop_spot ();
  }

}

%% Assemble all the elements of a po-file entry according to the
%% section, "The Format of PO Files", in the gettext manual at:
%% http://www.gnu.org/software/hello/manual/gettext/PO-Files.html
private define assemble_entry (entry)
{
  variable entry_elems = {}, elem = "";
  variable elems = ["trans_cmts","extr_cmts","ref_cmts","flag_cmts",
                    "ctx_cmts","msgctxt","msgid","msgstr"];

  variable elems_pl = ["trans_cmts","extr_cmts","ref_cmts","flag_cmts",
                       "ctx_cmts","msgctxt","msgid","msgid_plural",
                       "msgstr[0]","msgstr[1]","msgstr[2]","msgstr[3]",
                       "msgstr[4]","msgstr[5]"];

  if (strlen (entry["msgid_plural"]))
  {
    foreach elem (elems_pl)
      list_append (entry_elems, entry[elem]);
  }
  else
  {
    foreach elem (elems)
      list_append (entry_elems, entry[elem]);
  }

  entry = list_to_array (entry_elems);
  entry = entry[where (array_map (Int_Type, &strlen, entry))];
  entry = array_map (String_Type, &strtrim, entry);
  entry = strjoin (entry, "\n");

  return entry;
}

%% Replace an element in a entry (cmt, msgid, msgstr)
private define replace_elem (entry, elem, rep)
{
  entry[elem] = rep;
}

%% Replace a whole entry with a modified one
private define replace_entry (new_entry)
{
  set_readonly (0);
  push_spot (); mark_entry (); del_region ();

  if (eobp)
    new_entry += "\n";

  insert (new_entry);
  set_readonly (1);
  pop_spot ();
  () = bol_fsearch ("msgstr");
  set_po_status_line ();
}

%% Align the lengths of two arrays
private define array_align_length (a, b)
{
  variable ldiff = length (a)-length (b);
  variable padarr;

  if (ldiff == 0)
    return a, b;
  if (ldiff < 0)
    padarr = String_Type[-ldiff];
  else
    padarr = String_Type[ldiff];

  padarr[*] = "";

  if (ldiff < 0)
    a = [a, padarr];
  else
    b = [b, padarr];

  return a, b;
}

% Tag an entry with the "fuzzy" flag in a string manipulation
private define flag_fuzzy (entry)
{
  if (string_match (entry["flag_cmts"], ", fuzzy", 1))
    return entry;

  ifnot (strlen (entry["flag_cmts"]))
    entry["flag_cmts"] = "#, fuzzy";
  else
    entry["flag_cmts"] = pcre_replace (entry["flag_cmts"],
                                       "#,", "#, fuzzy,");
  return entry;
}

%% Flag the current entry fuzzy in the buffer. Since each msgstr in a
%% plural string gets a count in the statistcis, make sure that the
%% number of translated messages in the statistcis get decremented by
%% the number of translated msgstrs in the plural entry.
define fuzzy_entry ()
{
  variable entry, msgstrs_all, msgstrs_translated, values;

  entry = hash_entry ();
  values = assoc_get_values (entry);
  msgstrs_all = values[where (array_map (Int_Type,
                                         &string_match, values, "^msgstr", 1))];
  msgstrs_translated =
    msgstrs_all[wherenot (array_map (Int_Type, &pcre_string_match,
                                     msgstrs_all, "^msgstr[\\[\\]0-9 ]*\"\"$"))];

  find_msgstr_keyword ();

  if (length (msgstrs_translated) == 0)
    return;

  entry = flag_fuzzy (entry);
  count ("f+");

  loop (length (msgstrs_translated))
    count ("t-");

  replace_entry (assemble_entry (entry));
  set_po_status_line ();
}

%% Remove fuzzy flag from an entry. Since each msgstr in a plural
%% string gets a count in the statistcis, make sure that the number of
%% translated messages in the statistcis get incremented by the number
%% of translated msgstrs in the plural entry. Also remove a possible
%% "previous-untranslated-string" context and a possible "[po-lint]"
%% comment
define remove_fuzzy_flag ()
{
  variable flags, msgstrs_all, msgstrs_translated, values;
  variable entry = hash_entry ();

  ifnot (string_match (entry["flag_cmts"], "#, fuzzy", 1))
    return;

  % remove a po-lint comment
  if (string_match (entry["trans_cmts"], "po-lint", 1))
  {
    variable trans_cmts = strchop (entry["trans_cmts"], '\n', 0);

    trans_cmts = trans_cmts[wherenot (array_map (Int_Type, &string_match, trans_cmts, "po-lint", 1))];
    trans_cmts = strjoin (trans_cmts, "\n");
    entry["trans_cmts"] = trans_cmts;
  }

  values = assoc_get_values (entry);
  msgstrs_all = values[where (array_map (Int_Type,
                                         &string_match, values, "^msgstr", 1))];
  msgstrs_translated =
    msgstrs_all[wherenot (array_map (Int_Type, &pcre_string_match,
                                     msgstrs_all, "^msgstr[\\[\\]0-9 ]*\"\"$"))];

  flags = entry["flag_cmts"];

  if (flags == "#, fuzzy")
    replace_elem (entry, "flag_cmts", Null_String);
  else
    replace_elem (entry, "flag_cmts", pcre_replace (flags, " fuzzy,", ""));

  % remove msgmerge "previous-msgid-string"
  replace_elem (entry, "ctx_cmts", Null_String);

  replace_entry (assemble_entry (entry));
  count ("f-");

  loop (length (msgstrs_translated))
    count ("t+");

  set_po_status_line ();
}

% Add a [po-lint] tag comment to an entry that was validated with the
% po-lint () function
private define add_lint_cmt_and_fuzzy (lint_cmt)
{
  variable entry = hash_entry ();

  if (strlen (entry["trans_cmts"]))
  {
    % avoid double tagging
    if (string_match (entry["trans_cmts"], "$lint_cmt"$, 1))
      return;

    % append lint comment to existing translator's comment
    entry["trans_cmts"] += "\n# [po-lint] $lint_cmt"$;
  }
  else
    entry["trans_cmts"] = "\n# [po-lint] $lint_cmt"$;

  replace_entry (assemble_entry (entry));
  fuzzy_entry ();
}

%% Remove all obsolete entries
define del_obsolete_entries ()
{
  ifnot (count ("o"))
    return flush ("no obsolete entries");

  ifnot (get_y_or_n ("Remove all obsolete entries"$))
    return;

  variable entries_arr, entries, n_obsolete = count ("o");
  (entries_arr,) = po2arr (buf_as_str);
  entries = strjoin (entries_arr, "\n\n");
  replace_buffer (entries + "\n");
  flush ("$n_obsolete obsolete entries removed"$);
}

% Cut the translation, leaving the entry untranslated
define cut_msgstr ()
{
  if (is_untranslated ())
    return;
  if (is_fuzzy ())
    remove_fuzzy_flag ();

  variable entry = hash_entry ();
  find_msgstr_keyword ();
  variable kw = extract_keyword ();
  replace_elem (entry, kw, kw + " \"\"");
  count ("t-"); count ("u+");
  replace_entry (assemble_entry (entry));
  set_po_status_line ();
}

% Copy the translation to a global variable, so it may be accessed by
% other functions.
define copy_msgstr ()
{
  push_spot ();
  find_msgstr_keyword ();
  Msgstr_Copy = msgstr_as_str ();
  (, Msgstr_Copy) = sep_kw_and_str (Msgstr_Copy);
  flush ("msgstr copied");
  pop_spot ();
}

% Insert a copied translation into the current entry
define insert_msgstr ()
{
  variable msgstr = "", kw = "", entry;

  entry = hash_entry ();
  find_msgstr_keyword ();
  kw = extract_keyword ();
  msgstr = concat_kw_str (kw, Msgstr_Copy);
  replace_elem (entry, kw, msgstr);

  if (is_untranslated ())
  {
    count ("u-"); count ("t+");
    set_po_status_line ();
  }
  else
    ifnot (get_y_or_n ("Overwrite previous translation"))
      return;

  replace_entry (assemble_entry (entry));
}

% Copy original message into the translation
define copy_msgid_to_msgstr ()
{
  variable msgid, msgstr, msgid_kw, msgstr_kw, entry;

  entry = hash_entry ();
  (msgid_kw, msgstr_kw, msgid, msgstr) = return_str_pair ();
  (, msgid) = sep_kw_and_str (msgid);
  msgid = concat_kw_str (msgstr_kw, msgid);
  replace_elem (entry, msgstr_kw, msgid);
  find_msgstr_keyword ();

  if (is_untranslated ())
  {
    count ("u-"); count ("t+");
    set_po_status_line ();
  }
  else
    ifnot (get_y_or_n ("Overwrite previous translation"))
      return;

  replace_entry (assemble_entry (entry));
}

%% Count words and characters in all msgstrs
define count_words_and_chars ()
{
  variable msgids, msgstrs, words_strs, words_ids, strs, ids;

  (, msgids, msgstrs) = create_strs_arr (buf_as_str ());
  msgstrs = msgstrs[[1:]];
  (, ids) = array_map (String_Type, String_Type, &prep_str, msgids);
  (, strs) = array_map (String_Type, String_Type, &prep_str, msgstrs);

  words_ids = strtok (strjoin (ids, ""), "^\\w");
  words_strs = strtok (strjoin (strs, ""),"^\\w");
  vmessage ("words/msgids: %d, words/msgstrs: %d, " +
            "chars/msgids: %d, chars/msgstrs: %d",
            length (words_ids), length (words_strs),
            strlen (strjoin (ids, "")), strlen (strjoin (strs, "")));
}

%}}}
%{{{ sources related functions

%% Return source references of current entry as a string array.
private define get_source_refs ()
{
  variable entry = hash_entry ();
  variable src_refs = entry["ref_cmts"];

  ifnot (strlen (src_refs))
    throw UsageError, "no source reference(s) for this entry";

  src_refs = strreplace (src_refs, "#: ", "");
  src_refs = strreplace (src_refs, "\n", " ");
  src_refs = strchop (src_refs, ' ', 0);

  return src_refs;
}

%% Set the path to source files
define set_source_path ()
{
  variable s = init_src_dir ("source files");

  ifnot (file_type (s, "dir"))
    throw OpenError, "$s does not exist or is not a directory"$;

  if (strlen (s))
  {
    create_blocal_var ("Source_Dir");
    set_blocal_var (s, "Source_Dir");
  }
  else
    throw UsageError, "No source directory selected";
}

%% Pop up windows containing files from source references for viewing
define view_source ()
{
  variable buf, oldbuf, src_file, src_line, src_refs, src_ref, alen;
  variable cnt = 1, i;

  src_refs = get_source_refs ();
  alen = length (src_refs);

  ifnot (alen)
    return flush ("no source reference");

  ifnot (blocal_var_exists ("Source_Dir"))
    set_source_path ();
  else
  {
    if (get_blocal_var ("Source_Dir") == NULL)
      set_source_path ();
  }

  foreach src_ref (src_refs)
  {
    src_ref = strchop (src_ref, ':', 0);
    src_file = src_ref[0];
    src_line = src_ref[1];
    src_file = path_concat (get_blocal_var ("Source_Dir"), src_file);
    buf = src_file;

    % sometimes source references contain a header file
    % extension ".h" which is not present in the actual
    % source file referenced. A bug in intltool?
    if ((0 == file_status (src_file)) && (path_extname (src_file) == ".h"))
      src_file = path_sans_extname (src_file);

    if (0 == file_status (src_file))
    {
      flush ("Source file not found");
      return set_blocal_var (NULL, "Source_Dir");
    }

    oldbuf = pop2buf_whatbuf (buf);
    () = insert_file (src_file);
    set_buffer_modified_flag (0);
    set_readonly (1);
    goto_line (integer (src_line));
    local_setkey ("close_file", "q");
    c_mode ();
    onewindow ();

    _for i (0, alen-1, 1)
    {
      if (alen > 1)
        flush ("Source reference $cnt of $alen "$ +
               "(space cycles, 'q' closes window, other key to scroll)");
      else
        flush ("Source reference $cnt of $alen "$ +
               "(space or 'q' closes window, other key to scroll)");
    }

    update (1);
    variable ch = getkey ();
    switch (ch)
    { ch == ' ': delbuf (buf); sw2buf (oldbuf); cnt++; }
    { ch == 'q': delbuf (buf); return; }
    { throw UsageError, "'q' closes source window"; }
  }
}

%% Grep for a string in the source directory. Requires grep.sl
%% from http://jedmodes.sourceforge.net/
define grep_src ()
{
  variable str, srcdir;

  ifnot (blocal_var_exists ("Source_Dir"))
    set_source_path ();

  if (markp ())
    str = bufsubstr ();
  else
    str = po_mark_word ();

  str = read_mini ("Search in sources:", str, "");
  str = "'" + str + "'";
  srcdir = get_blocal_var ("Source_Dir");
  grep (str, srcdir);
  call ("redraw");
}

%}}}
%{{{ po-header

%% Return the gettext plural forms header appropriate to the iso
%% language code
private define get_plural_forms ()
{
  variable iso_code = "", plural_form_str = "", lang = "";
  variable default = "nplurals=2; plural=(n != 1)";

  (, lang,,) = get_locale_info ();

  ifnot (strlen (lang))
    return default;

  % Asian forms
  variable one_form = ["ja","ka","km","ko","lo","ky","bo","dz","fa","hy",
                       "id", "ms","su","zh","th","tr","uz","vi","ayá"];

  % Two forms, singular used for one only
  variable two_forms_sgl = ["so","pt","ca","az","bg","bn","da","de","et",
                            "eu","el","en","eo","es","fi","fo","fy","gl",
                            "gu","hu","it","ha","he","hi","lb","ml","es_AR",
                            "mn","mr","nb","ne","nl","nn","no","or","ps",
                            "pa","sq","sv","ta","te","tg","tk","ur","sco",
                            "pap","pms","fur","nah","nap","af"];

  % Two forms, singular used for zero and one
  variable two_forms_sgl_zo = ["ak","am","wa","fr","ti","mg","mi",
                               "ln","br","fil","gun"];

  variable russian_fam = ["be","bs","ru","sr","uk","hr"];

  foreach iso_code (russian_fam)
  {
    if (0 == strcmp (iso_code, lang))
      plural_form_str = "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 or n%100>=20) ? 1 : 2)";
  }
  foreach iso_code (two_forms_sgl)
  {
    if (0 == strcmp (iso_code, lang))
      plural_form_str = "nplurals=2; plural=(n != 1)";
  }
  foreach iso_code (one_form)
  {
    if (0 == strcmp (iso_code, lang))
      plural_form_str = "nplurals=1; plural=0";
  }
  foreach iso_code (two_forms_sgl_zo)
  {
    if (0 == strcmp (iso_code, lang))
      plural_form_str = "nplurals=2; plural=(n > 1)";
  }

  % other forms

  if (lang == "ar") % arabic
    plural_form_str = "nplurals=6; plural= n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 && n%100<=99 ? 4 : 5;";
  if (lang == "ga")
    plural_form_str = "nplurals=5; plural=n==1 ? 0 : n==2 ? 1 : n<7 ? 2 : n<11 ? 3 : 4";
  if (lang == "is")
    plural_form_str = "nplurals=2; plural=(n%10!=1 or n%100==11)";
  if ((lang == "ku") || (lang == "kn"))
    plural_form_str = "nplurals=2; plural=(n!=1)";
  if (lang == "jv")
    plural_form_str = "nplurals=2; plural=n!=0";
  if (lang == "mk")
    plural_form_str = "nplurals=2; plural= n==1 or n%10==1 ? 0 : 1";
  if (lang == "cy")
    plural_form_str = "nplurals=4; plural= (n==1) ? 0 : (n==2) ? 1 : (n != 8 && n != 11) ? 2 : 3";
  if (lang == "kw")
    plural_form_str = "nplurals=4; plural= (n==1) ? 0 : (n==2) ? 1 : (n == 3) ? 2 : 3";
  if (lang == "mt")
    plural_form_str = "nplurals=4; plural=(n==1 ? 0 : n==0 or ( n%100>1 && n%100<11) ? 1 : (n%100>10 && n%100<20 ) ? 2 : 3)";
  if (lang == "sl")
    plural_form_str = "nplurals=4; plural=(n%100==1 ? 0 : n%100==2 ? 1 : n%100==3 or n%100==4 ? 2 : 3);";
  if (lang == "lv")
    plural_form_str = "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n != 0 ? 1 : 2)";
  if (lang == "lt")
    plural_form_str = "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && (n%100<10 or n%100>=20) ? 1 : 2)";
  if (lang == "pl")
    plural_form_str = "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10< =4 && (n%100<10 or n%100>=20) ? 1 : 2)";
  if ((lang == "cs") || (lang == "sk"))
    plural_form_str = "nplurals=3; plural=(n==1) ? 0 : (n>=2 && n< =4) ? 1 : 2";
  if (lang == "ro")
    plural_form_str = "nplurals=3; plural=(n==1 ? 0 : (n==0 or (n%100 > 0 && n%100 < 20)) ? 1 : 2);";
  if (lang == "csb")
    plural_form_str = "nplurals=3; n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 or n%100>=20) ? 1 : 2";

  return plural_form_str;
}

private define return_po_header_template ()
{
  variable plural_str = get_plural_forms ();
  variable header =
    "# SOME DESCRIPTIVE TITLE.\n" +
    "# Copyright (C) YEAR Free Software Foundation, Inc.\n" +
    "# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.\n" +
    "#\n" +
    "msgid \"\"\n" +
    "msgstr \"\"\n" +
    "\"Project-Id-Version: " + whatbuf () + "\\n\"\n" +
    "\"PO-Revision-Date: " + strftime ("%Y-%m-%d %R%z")+"\\n\"\n" +
    "\"Last-Translator: $Translator\\n\"\n"$ +
    "\"Language-Team: $Language <$Team_Email>\\n\"\n"$ +
    "\"MIME-Version: 1.0\\n\"\n" +
    "\"Content-Type: text/plain; charset=$Encoding\\n\"\n"$ +
    "\"Content-Transfer-Encoding: 8bit\\n\"\n" +
    "\"Plural-Forms: " + plural_str + "\\n\"\n" +
    "\"X-Generator: Jed w/po-mode\\n\"\n\n";

  return header;
}

%% Insert a default header
private define insert_po_header ()
{
  set_readonly (0);
  bob ();
  insert (return_po_header_template ());
  set_readonly (1);
}

% Adjust the timestamp in the "PO-Revision-Date" header.
private define set_po_revision_date ()
{
  ifnot (Mode == get_mode_name)
    return;

  variable rev_str, lines, header, rev_line, msgstr;

  rev_str = "\"PO-Revision-Date: " + strftime ("%Y-%m-%d %R%z")+"\\n\"";

  push_spot_bob ();
  header = hash_entry ();
  lines = strchop (header["msgstr"], '\n', 0);
  rev_line = where (array_map (Int_Type, &string_match, lines, "PO-Revision-Date", 1));
  lines[rev_line] = rev_str;
  msgstr = strjoin (lines, "\n");
  header["msgstr"] = msgstr;;
  replace_entry (assemble_entry (header));
  pop_spot ();
}

append_to_hook ("_jed_save_buffer_before_hooks", &set_po_revision_date);

%% Adjust the po-header to user's settings.
define replace_headers (ask)
{
  if (ask)
    ifnot (get_y_or_n ("Replace headers"))
      return;

  variable team, name, charset, jed_header, plural_header, header_arr, ln;
  variable header, i = 0, plural_str = get_plural_forms (), x_header = 0;
  variable lang = "", lang_code = "", enc, filenc = "";

  (, lang_code,, enc) = get_locale_info ();
  filenc = get_file_encoding (buffer_filename ());

  name = "\"Last-Translator: $Translator\\n\""$;
  lang = "\"Language: $lang_code\\n\""$;
  team = "\"Language-Team: $Language $Team_Email\\n\""$;
  charset = "\"Content-Type: text/plain; charset=$enc\\n\""$;
  plural_header = "\"Plural-Forms: $plural_str\\n\""$;
  jed_header = ("\"X-Generator: Jed w/po-mode: http://mbjnet.dk/po-mode/\\n\"");

  push_spot_bob ();
  header_arr = strchop (entry_as_str (), '\n', 0);

  _for i (0, length (header_arr)-1, 1)
  {
    ln = header_arr[i];
    if (string_match (ln, "^\\C\"Last-Translator.*", 1))
      ln = name;
    else if (string_match (ln, "^\\C\"Language-Team.*", 1))
      ln = team;
    else if (string_match (ln, "^\\C\"Language:.*", 1))
      ln = lang;
    else if (string_match (ln, "^\\C\"Content-Type.*", 1))
      ln = charset;
    else if (string_match (ln, "^\\C\"Plural-Forms.*", 1))
      ln = plural_header;
    else if (string_match (ln, "^\\C\"X-Generator.*", 1))
      x_header = 1;

    header_arr[i] = ln;
  }

  if (x_header == 0)
    header_arr = [header_arr, jed_header];

  header = strjoin (header_arr, "\n");
  replace_entry (header);
  pop_spot ();
}

%}}}
%{{{ gettext commands

%% Give entries that have errors the fuzzy flag
private define fuzzy_error_entries ()
{
  variable fp, lines, nos = {}, i;

  fp = fopen (gettext_err_msg, "r");

  if (fp == NULL)
    return NULL;

  lines = fgetslines (fp);
  lines = lines[where (array_map (Int_Type, &pcre_string_match, lines, ":[0-9]+:"))];
  lines = array_map (Array_Type, &strtok, lines, ":");

  _for i (0, length (lines)-1, 1)
  {
    goto_line (integer (lines[i][1]));
    fuzzy_entry ();
    find_entry_delim_end ();
  }

  set_po_status_line ();
}

private define popup_gettext_err_msg ()
{
  if (bufferp ("*** Errors ***"))
    delbuf ("*** Errors ***");

  recenter (1);
  pop2buf ("*** Errors ***"$);
  () = insert_file (gettext_err_msg);
  insert ("\nEntries where errors were found have been marked fuzzy.\n"+
          "You can now visit them in turn by typing 'f'. Type 'q' to close\n"+
          "this window.");
  set_buffer_modified_flag (0);
  most_mode ();
  bob ();
  flush ("errors were found, try to (V)alidate. Type 'q' to close this window");
}

% Wrap/unwrap po-file
define toggle_wrap ()
{
  variable wrap_flag = "", cmd = "";

  Gettext_Wrap = not (Gettext_Wrap);

  if (Gettext_Wrap)
    wrap_flag = "--no-wrap";

  cmd = "msgcat $wrap_flag"$;

  ifnot (1 == apply_gettext_cmd_to_buffer ("$cmd $Po_Tmpfile"$))
    flush ("$cmd failed, try to (V)alidate"$);

}

%% Compile the current buffer as *.mo
define po_compile ()
{
  variable prg = check_for_prg ("msgfmt"), file, mo_file, tmpfile, homedir;

  mo_file = path_sans_extname (path_basename (buffer_filename)) + ".mo";
  write_buf_to_tmpfile ();

  ifnot (0 == system ("$prg -o $mo_file $Po_Tmpfile 2>gettext_err_msg"$))
    popup_gettext_err_msg ();
  else
    flush (sprintf ("%s %s %s", path_basename (buffer_filename),
                    "compiled as", getcwd + mo_file));

  () = delete_file (Po_Tmpfile);
}

%% Use the gettext program 'msgunfmt' to decompile a *.mo file and read it
%% into the editor
define po_decompile ()
{
  variable prg = check_for_prg ("msgunfmt");
  variable po_filestr, mo_file, exit_status, fname;

  mo_file = read_file_from_mini ("[Decompile] path to *.mo-file:");
  ifnot (strlen (mo_file))
    return;

  fname = path_sans_extname (mo_file);

  (po_filestr, exit_status) =
    syscmd_output_to_string ("$prg $mo_file 2>$gettext_err_msg"$);

  if (0 == exit_status)
  {
    pop2buf (fname + "-decompiled" + ".po");
    onewindow;
    insert (po_filestr);
    po_mode ();
    bob ();
  }
  else
    popup_gettext_err_msg ();
}

%% Update a po-file with a newer message catalog.
define po_update ()
{
  variable prg = check_for_prg ("msgmerge"), newer_file, filenc = "", enc = "";
  variable file = buffer_filename (), oldfile = file + "~";

  newer_file = init_src_dir ("path to updated file");

  ifnot (file_type (newer_file, "reg"))
    throw OpenError, "$newer_file does not exist or is not a regular file"$;

  filenc = get_file_encoding (newer_file);
  (,,,enc) = get_locale_info ();

  ifnot (filenc == enc)
  {
    ifnot (conv_charset (newer_file))
      throw RunTimeError, "could not correct encoding for $newer_file"$;
  }

  ifnot (0 == system ("cp $file $oldfile"$))
    throw RunTimeError, "could not backup file";

  ifnot (0 == system (sprintf ("%s -U %s %s >/dev/null 2>&1",
                               prg, buffer_filename, newer_file)))
    throw RunTimeError, "update failed, try to (V)alidate files";

  delbuf (whatbuf ());
  () = find_file (file);
  flush ("old file backed up as $oldfile"$);
}

% Flag all entries fuzzy
define flag_fuzzy_all ()
{
  ifnot (get_y_or_n ("Flag all entries fuzzy"$))
    return;

  do
  {
    fuzzy_entry ();
    find_entry_delim_end ();
  }
  while (bol_fsearch ("msgid "));
}

%% Use msgids as translations for all untranslated entries
private define msgid_to_msgstr_all ()
{
  ifnot (apply_gettext_cmd_to_buffer ("msgen $Po_Tmpfile 2>/dev/null"$))
    throw RunTimeError, "could not copy msgids to msgstrs, try to (V)alidate";
}

%}}}
%{{{ validation

%% Check mismatch in end punctuation
private define match_endchar_punct (a, b)
{
  variable punct = ".,;:!?&|-+#%/";

  a = strtrim (a);
  b = strtrim (b);
  a = is_substr (punct, char (a[-1]));
  b = is_substr (punct, char (b[-1]));
  return ((a + b) == 0) || (a == b);
}

%% Check for double space between words. Words must be at least two characters long
private define dbl_space (str)
{
  return pcre_string_match (str, "[[:alpha:]]{2,}[ ]{2}[[:alpha:]]{2,}");
}

%% Check for two identical adjacent words, usually a writing error.
private define dbl_word (str)
{
  variable i = 0, word_prev = "";
  variable word_arr = strtok (str);

  _for i (0, length (word_arr)-1, 1)
  {
    % skip format specifiers like "%s" that are often juxtaposed
    if (string_match (word_arr[i], "[|%\\\\]", 1))
    {
      word_prev = "";
      continue;
    }

    if (word_arr[i] == word_prev)
      return 1;

    word_prev = word_arr[i];
  }

  return 0;
}

%% Check case mismatch between first letters of two strings.
private define match_case (a, b)
{
  ifnot (isalpha (a) && isalpha (b)) return 1; % skip if first characters in a and b are not both letters
  return islower (strtrim (a)) == islower (strtrim (b)); % returns '1' if true
}

%% Check for incongruity in number of begin and end blanks between
%% msgid and msgstr.
private define n_blanks_mismatch (a, b)
{
  variable neb_a, neb_b, nbb_a, nbb_b;
  variable end_blanks, beg_blanks;

  end_blanks = pcre_compile (" *$");
  beg_blanks = pcre_compile ("^ *");

  if (pcre_exec (end_blanks, a))
    neb_a = pcre_nth_substr (end_blanks, a, 0);
  if (pcre_exec (end_blanks, b))
    neb_b = pcre_nth_substr (end_blanks, b, 0);
  if (pcre_exec (beg_blanks, a))
    nbb_a = pcre_nth_substr (beg_blanks, a, 0);
  if (pcre_exec (beg_blanks, b))
    nbb_b = pcre_nth_substr (beg_blanks, b, 0);

  return ((strlen (nbb_a) != strlen (nbb_b)) ||
          (strlen (neb_a) != strlen (neb_b)));
}

%% Check po-file for several minor errors in the translations
private define po_lint ()
{
  variable kws, I, cmts, msgids, msgstrs, i = 0;

  (cmts, msgids, msgstrs) = create_strs_arr (buf_as_str ());
  (, msgids) = array_map (String_Type, String_Type, &sep_kw_and_str, msgids);
  (kws, msgstrs) = array_map (String_Type, String_Type, &sep_kw_and_str, msgstrs);
  msgids = array_map (String_Type, &trim_quotes, msgids);
  msgstrs = array_map (String_Type, &trim_quotes, msgstrs);

  _for i (1, length (msgids)-1, 1)
  {
    ifnot (strlen (msgstrs[i])) % skip untranslated
      continue;
    if (string_match (cmts[i], "#, fuzzy")) % skip fuzzies
      continue;

    if (pcre_string_match (msgids[i], "[[:alpha:]]\\|[[:alpha:]]"))
      continue;

    ifnot (match_endchar_punct (msgids[i], msgstrs[i]))
    {
      goto_entry (i+1);
      add_lint_cmt_and_fuzzy ("end character mismatch between msgid and msgstr");
    }
    ifnot (match_case (msgids[i], msgstrs[i]))
    {
      goto_entry (i+1);
      add_lint_cmt_and_fuzzy ("case mismatch between first letters in msgid and msgstr");
    }
    if (n_blanks_mismatch (msgids[i], msgstrs[i]))
    {
      goto_entry (i+1);
      add_lint_cmt_and_fuzzy ("mismatch in beginning or trailing blank space between msgid and msgstr");
    }
    if (dbl_space (msgstrs[i]))
    {
      goto_entry (i+1);
      add_lint_cmt_and_fuzzy ("double space in msgstr");
    }
    if (dbl_word (msgstrs[i]))
    {
      goto_entry (i+1);
      add_lint_cmt_and_fuzzy ("double word in msgstr");
    }
  }

  % code hereafter checks for translations that are not uniform for
  % otherwise identical msgids.

  % msgids = strtrim (msgids, "\n ");
  % msgstrs = strtrim (msgstrs, "\n ");

  _for i (0, length (msgids)-1, 1)
  {
    ifnot (strlen (msgstrs[i]))
      continue;

    % msgids in plural entries are often identical, but translations
    % vary ot vice versa, thus yielding false positives, so skip
    % plural entries for this test
    if (string_match (kws[i], "msgstr\\[", 1))
      continue;

    I = where (msgids == msgids[i]);

    if (length (I) > 1) % more than one identical msgid
    {
      % strip one or more newline escape sequences in comparison
      try
      {
        if (msgstrs[I][0][[-2:-1]] == "\\n")
          msgstrs[I][0] = strtrim (msgstrs[I][0], "\\\\n\n ");
        if (msgstrs[I][1][[-2:-1]] == "\\n")
          msgstrs[I][1] = strtrim (msgstrs[I][1], "\\\\n\n ");
      }
      catch IndexError;

      if (msgstrs[I[0]] != msgstrs[I[1]]) % translations differ for same msgid
      {
        goto_entry (I[0]+1);
        add_lint_cmt_and_fuzzy (sprintf ("translations for identical msgids in entries %d and %d are not uniform", I[0]+1, I[1]+1));
        goto_entry (I[1]+1);
        add_lint_cmt_and_fuzzy (sprintf ("translations for identical msgids in entries %d and %d are not uniform", I[0]+1, I[1]+1));
      }
    }
  }
}

%% Check for a variety of more or less cosmetic errors. Entries
%% where such are found are flagged fuzzy.
define parse_cosmetic_errors ()
{
  variable fb = count ("f"), fa;

  push_spot ();
  po_lint ();
  po_statistics ();
  fa = count ("f");
  pop_spot ();

  if (fb == fa)
    return flush ("no problems found");

  recenter (1);
  pop2buf ("Cosmetic errors marked fuzzy");
  insert ("The following errors have been checked for:\n\n" +
          "- case mismatch between the first letters of msgid and msgstr\n" +
          "- inconsistencies in end punctuation/trailing whitespace between\n" +
          "  msgid and msgstr\n" +
          "- double space between words in msgstr\n" +
          "- identical adjacent words in msgstr\n" +
          "- incongruity in length of whitespace at the beginning and end of msgid and msgstr\n" +
          "- differing translations of identical msgids\n\n" +
          "Entries with errors been marked fuzzy\n" +
          "You can now visit each entry in turn with the 'f' key to correct these errors.\n" +
          "Expect an occasional false positive!\n\n" +
          "A \"[po-lint]\" tag with an explanation of the error has been added\n" +
          "in the translator's comment. It will be removed when unfuzzying the entry.\n" +
          "Type 'q' to close this window");

  set_buffer_modified_flag (0);
  most_mode ();
  bob ();
}

% Validate the po-file with the msgfmt program from gettext
define po_validate_command ()
{
  variable cmd = "", enc_err = "", n = 1;

  n = get_current_entry_number ();
  write_buf_to_tmpfile ();
  cmd = "msgfmt -o /dev/null 2>&1 --check-accelerators -c -v";

  if (0 == system ("$cmd $Po_Tmpfile 2>$gettext_err_msg"$))
    flush ("validation successful");
  else
  {
    fuzzy_error_entries ();
    goto_entry (n);
    popup_gettext_err_msg ();
  }

  () = delete_file (Po_Tmpfile);
}

%}}}
%{{{ po user comments

private define po_comment_mode ()
{
  set_mode ("po_comment", 0);
  use_keymap ("po_comment");
  set_buffer_undo (1);
}

% Edit a translator's comment
define edit_comment ()
{
  variable msgid, user_cmts;

  Entry = hash_entry ();
  msgid = Entry["msgid"];
  user_cmts = Entry["trans_cmts"];
  user_cmts = strreplace (user_cmts, "\n# ", "\n");
  user_cmts = strtrim_beg (user_cmts, "# ");
  setup_win_layout (Msgid_Buf, msgid, Po_Comment_Buf, user_cmts);
  po_comment_mode ();
}

% Close the comment editing buffer and apply the comment to the entry
define finish_comment ()
{
  variable user_cmts = "";

  ifnot (buffer_modified )
    return cancel_edit ();

  bob ();

  ifnot (eobp && bobp ())
  {
    do
    {
      insert ("# ");
    }
    while (down_1 ());
  }

  mark_buffer ();
  user_cmts = bufsubstr_delete ();
  replace_elem (Entry, "trans_cmts", user_cmts);
  cancel_edit ();
  replace_entry (assemble_entry (Entry));
}

% Delete a translator's comment
define del_translator_comment ()
{
  variable entry = hash_entry ();
  replace_elem (entry, "trans_cmts", Null_String);
  replace_entry (assemble_entry (entry));
}

%}}}
%{{{ compendiums

%% Create compendium file if it does not exist.
private define touch_compendium ()
{
  variable fp;

  ifnot (1 == file_status (Compendium))
  {
    fp = fopen (Compendium, "a+");
    if (fp == NULL)
      throw IOError, "could not create $Compendium"$;
  }
}

private define hash_compendium ()
{
  ifnot (1 == file_status (Compendium))
    throw RunTimeError, "[hash_compendium] $Compendium does not exist"$;

  variable compstr = file_as_str (Compendium);

  ifnot (strlen (compstr))
    throw RunTimeError, "[hash_compendium] $Compendium is an empty file"$;

  flush ("hashing compendium ...");
  (CompHash,) = hash_msgids_msgstrs (compstr, 0);
  Compendium_Is_Hashed = 1;
}

private define write_compendium_from_hash (comp_hash)
{
  variable msgids, msgstrs, fp, i;

  flush ("writing compendium ...");
  msgids = assoc_get_keys (comp_hash);
  ifnot (length (msgids))
    return;
  msgstrs = assoc_get_values (comp_hash);
  i = array_sort (msgids);
  fp = fopen (Compendium, "w+");
  if (fp == NULL)
    throw WriteError, "could not open $Compendium"$;
  () = array_map (Int_Type, &fprintf, fp, "%s\n%s\n\n", msgids[i], msgstrs[i]);
  () = fclose (fp);
}

%% Remove duplicate entries from compendium while always preserving
%% the "immutable" translations
private define del_dups_and_write_comp (compstr)
{
  variable strs = Assoc_Type[String_Type, ""];
  variable msgids, msgstrs, i, enc, e, sz;

  ifnot (strlen (Encoding))
    (,,, enc) = get_locale_info ();

  compstr = strtrim (compstr);
  (, msgids, msgstrs) = create_strs_arr (compstr);

  flush ("...weeding out entries w/duplicate msgids in compendium ...");

  %% since every key (msgid) in an associative array must be unique,
  %% it is a fast way to remove duplicate msgid entries.
  _for i (0, length (msgids)-1, 1)
    strs[msgids[i]] = msgstrs[i];

  % make sure "immutable" translations are preserved
  _for i (0, length (msgstrs)-1, 1)
    if (string_match (msgstrs[i], "@$", 1)) % "@" = "immutable"
      strs[msgids[i]] = msgstrs[i];

  write_compendium_from_hash (strs);
}

define set_compendium ()
{
  Compendium = read_with_completion ("Compendium Name:", "", Compendium, 'f');
  Compendium_Is_Hashed = 0;
}

define edit_compendium ()
{
  ifnot (find_file (Compendium))
    throw IOError, "Could not open $Compendium";
  no_mode ();
  set_status_line ("", 0);
}

define add_buffer_to_compendium ()
{
  variable exit_status, filestr, msgids, msgstrs, i, entry, entries, comp;
  variable prg = check_for_prg ("msgattrib");

  touch_compendium ();
  write_buf_to_tmpfile ();
  (filestr, exit_status) =
    syscmd_output_to_string
    ("$prg --clear-obsolete --no-fuzzy --translated $Po_Tmpfile 2>/dev/null"$);

  () = delete_file (Po_Tmpfile);

  ifnot (0 == exit_status)
    throw RunTimeError, "file did not validate";

  (, msgids, msgstrs) = create_strs_arr (filestr);
  msgids = msgids[[1:]];
  msgstrs = msgstrs[[1:]];

  if (get_y_or_n ("mark all translations \"immutable\""))
    msgstrs = array_map (String_Type, &strcat, msgstrs, "@");

  entries = array_map (String_Type, &strcat, msgids, "\n", msgstrs);
  entries = array_map (String_Type, &strtrim, entries);
  entries = strtrim (strjoin (entries, "\n\n"));
  comp = strcat (entries, "\n\n", file_as_str (Compendium));
  del_dups_and_write_comp (comp);
  flush ("done");
}

%% Add a whole directory of po-files to the compendium.
define add_dir_to_compendium ()
{
  variable
    prg = check_for_prg ("msgattrib"),
    conv = check_for_prg ("iconv"),
    failed_files = [""],
    entries_arr = [""],
    conv_failed = [""],
    po_files = [""],
    msgstrs = [""],
    msgids = [""],
    idx_succ = Int_Type[0],
    idx_fail= Int_Type[0],
    conv_status = Int_Type[0],
    headers = Int_Type[0],
    filestr = "",
    compstr = "",
    file = "",
    dir = "",
    i = 0,
    e = 0;

  touch_compendium ();
  dir = read_with_completion ("Directory to add to compendium:", "", "", 'f');
  po_files = pofiles_in_dir (dir);
  po_files = po_files[array_sort (po_files)];

  ifnot (length (po_files))
    return flush ("No po files in directory");

  flush (sprintf ("checking encodings of %d files ...", length (po_files)));
  conv_status = array_map (Int_Type, &conv_charset, po_files);
  idx_succ = where (conv_status, &idx_fail);

  ifnot (length (idx_succ))
    throw RunTimeError, "No files were converted succesfully";

  conv_failed = po_files[idx_fail];
  po_files = po_files[idx_succ];

  if (length (conv_failed))
    conv_failed = array_map (String_Type, &strcat, conv_failed, ": [encoding errors]");

  _for i (0, length (po_files)-1, 1)
  {
    file = po_files[i];
    (filestr, e) =
      syscmd_output_to_string ("$prg --clear-obsolete --no-fuzzy --translated $file 2>/dev/null"$);

    ifnot (0 == e)
    {
      failed_files = [failed_files, file + ": [validation errors]"];
      continue;
    }
    ifnot (strlen (filestr))
    {
      failed_files = [failed_files, file + ": [no translated messages]"];
      continue;
    }

    filestr = strtrim (filestr);
    compstr += filestr + "\n\n";
    flush (sprintf ("adding %s (%d of %d file(s)) to compendium ...",
                    path_basename (po_files[i]), i+1, length (po_files)));
  }

  flush ("removing headers and comments ...");
  (, msgids, msgstrs) = create_strs_arr (compstr); % remove comments
  headers = where (msgids == "msgid \"\"");
  msgids[headers] = ""; % remove headers
  msgstrs[headers] = "";
  entries_arr = array_map (String_Type, &strcat, msgids, "\n", msgstrs);
  entries_arr = array_map (String_Type, &strtrim, entries_arr);
  compstr = strtrim (strjoin (entries_arr, "\n\n"));
  compstr = strcat (strtrim (file_as_str (Compendium)), "\n\n", compstr);

  if (strlen (compstr))
    del_dups_and_write_comp (compstr);
  failed_files = [failed_files, conv_failed];
  failed_files = strtrim (strjoin (failed_files, "\n"));
  if (strlen (failed_files))
  {
    pop2buf ("Failed to add these files");
    vinsert ("The file(s) below were not added to the " +
             "compendium,\neither because they contained " +
             "no translated messages\nor because they did " +
             "not validate:\n\n%s\n", failed_files);

    most_mode ();
    bob ();
    flush ("type 'q' to close this window");
  }
  else
    flush ("done");
}

%% Copy a translation from the compendium into the current msgstr
define copy_trans_from_comp ()
{
  variable msgid = "", msgid_fuzzy = "", msgstr_c = "", entry;

  ifnot (Compendium_Is_Hashed)
  {
    (CompHash, CompHash_Fuzzy) =
      hash_msgids_msgstrs (file_as_str (Compendium), 1);

    Compendium_Is_Hashed = 1;
  }

  entry = hash_entry ();
  msgid = entry["msgid"];
  msgid_fuzzy = del_format_specifiers (msgid);
  msgid_fuzzy = strlow (str_delete_chars (msgid_fuzzy, "^\\w"));

  if (assoc_key_exists (CompHash, msgid))
    msgstr_c = strtrim_end (CompHash[msgid], "@");
  else if (assoc_key_exists (CompHash_Fuzzy, msgid_fuzzy))
    msgstr_c = CompHash_Fuzzy[msgid_fuzzy];
  else
    return flush ("nothing matched");

  ifnot (string_match (entry["msgstr"], " \"\"$", 1))
  {
    ifnot (get_y_or_n ("overwrite existing translation"))
      return;
  }
  replace_elem (entry, "msgstr", msgstr_c);
  replace_entry (assemble_entry (entry));
  flush ("entry translated from compendium");
}

%% Copy the current entry to the compendium and mark its msgstr
%% "immutable"
define copy_entry_to_compendium ()
{
  variable msgid = "", msgstr = "", msgstr_c = "", entry = "";

  (,,msgid, msgstr) = return_str_pair ();
  entry = strcat ("\n", msgid, "\n", msgstr, "@\n");

  touch_compendium ();

  ifnot (strlen (file_as_str (Compendium)))
  {
    entry = strtrim (entry);
    () = append_string_to_file (entry, Compendium);
    return flush ("entry added to $Compendium"$);;
  }
  else
  {
    ifnot (Compendium_Is_Hashed)
      hash_compendium ();
  }

  if (assoc_key_exists (CompHash, msgid))
  {
    if (CompHash[msgid] == msgstr + "@")
      return flush ("an identical translation exists in compendium");

    if (get_y_or_n ("Overwrite compendium's translation"))
      CompHash[msgid] = msgstr + "@"; % @ = "immutable"
    else
      return;

    write_compendium_from_hash (CompHash);
  }
  else
  {
    ifnot (append_string_to_file (entry, Compendium))
      throw IOError, "could not add entry to $Compendium"$;
  }

  flush ("entry added to $Compendium"$);
}

%% Fill out all entries in the current po-file with translations of
%% corresponding msgids from compendium.
define init_with_compendium ()
{
  variable
    i = 1,
    overwrite = 1,
    entries_arr = [""],
    entries_arr_hash = Assoc_Type[Array_Type],
    comp_hash_fuzzy = Assoc_Type[String_Type],
    comp_hash = Assoc_Type[String_Type],
    msgstr_c_fuzzy = "",
    msgstr_c_pl = "",
    msgid_fuzzy = "",
    msgstr_c = "",
    msgid_pl = "",
    msgid = "",
    entries = "",
    kw_0 = "",
    kw = "";

  ifnot (1 == file_status (Compendium))
    throw OpenError, "$Compendium not found"$;

  ifnot (strlen (file_as_str (Compendium)))
    throw UsageError, "$Compendium is empty"$;

  if (count ("t"))
    overwrite = get_y_or_n ("overwrite existing translations");

  flush ("hashing po-file and compendium ...");
  (comp_hash, comp_hash_fuzzy) = hash_msgids_msgstrs (file_as_str (Compendium), 1);
  entries_arr_hash = create_entries_hash (buf_as_str ());
  flush ("filling out entries ...");

  _for i (1, length (entries_arr_hash)-1, 1) % start "1" = skip header
  {
    msgstr_c = "", msgstr_c_pl = "";

    flush (sprintf ("processing entry %d of %d entries ...",
                    i, length (entries_arr_hash)-1));
    ifnot (overwrite)
    {
      ifnot (string_match (entries_arr_hash[i]["msgstr"], " \"\"$", 1))
        continue;
    }
    msgid = entries_arr_hash[i]["msgid"];
    msgid_pl = entries_arr_hash[i]["msgid_plural"];
    (, msgstr_c) = sep_kw_and_str (comp_hash[msgid]);
    msgstr_c_pl = comp_hash[msgid_pl];
    (kw, ) = sep_kw_and_str (entries_arr_hash[i]["msgstr"]);
    (kw_0, ) = sep_kw_and_str (entries_arr_hash[i]["msgstr[0]"]);

    if (strlen (msgstr_c)) % exact matching
    {
      msgstr_c = concat_kw_str (kw, msgstr_c);
      entries_arr_hash[i]["msgstr"] = msgstr_c;
      msgstr_c = concat_kw_str (kw_0, msgstr_c);
      entries_arr_hash[i]["msgstr[0]"] = msgstr_c;
    }
    else % "fuzzy" matching
    {
      msgid_fuzzy = strlow (str_delete_chars (msgid, "^\\w"));
      msgid_fuzzy = del_format_specifiers (msgid_fuzzy);
      msgstr_c_fuzzy = comp_hash_fuzzy[msgid_fuzzy];
      ifnot (strlen (msgstr_c_fuzzy))
        continue;
      (, msgstr_c_fuzzy) = sep_kw_and_str (msgstr_c_fuzzy);
      entries_arr_hash[i]["msgstr"] =
        concat_kw_str (kw, msgstr_c_fuzzy);
      entries_arr_hash[i]["msgstr[0]"] =
        concat_kw_str (kw_0, msgstr_c_fuzzy);
      entries_arr_hash[i] = flag_fuzzy (entries_arr_hash[i]);
    }
    if (strlen (msgstr_c_pl))
      entries_arr_hash[i]["msgstr[1]"] = msgstr_c_pl;
  }

  entries_arr = array_map (String_Type, &assemble_entry, entries_arr_hash);

  if (length (Obsolete))
    entries_arr = [entries_arr, Obsolete];

  entries = strjoin (entries_arr, "\n\n");
  replace_buffer (entries + "\n");
  flush ("done");
}

%}}}
%{{{ wordlist

%% Danish users only
define hash_wordlist_danish ()
{
  variable url, pos, lines, list, i, anb, key, val;

  url = "http://www.klid.dk/dansk/ordlister/ordliste.html";
  list = html_to_txt (url);
  lines = strchop (list, '\n', 0);

  _for i (0, length (lines)-1, 1)
  {
    if (string_match (lines[i], "^    ", 1))
    {
      lines[i] = strtrim (lines[i]);
      lines[i-1] = strcat (lines[i-1], " ", lines[i]);
      lines[i] = "";
    }
  }

  lines = lines[where (array_map (Int_Type, &strlen, lines) > 2)];
  lines = lines[wherenot (array_map (Int_Type, &string_match, lines, "^ ", 1))];
  anb = where (array_map (Int_Type, &string_match, lines, "Anbefalede vendinger", 1));
  try
  {
    lines = lines[[:anb[0]-1]];

    _for i (0, length (lines)-1, 1)
    {
      pos = string_match (lines[i], "   ", 1);
      key = strtrim (lines[i][[:pos]]);
      val = strtrim (lines[i][[pos:]]);
      Trans_Hash[key] = val;
    }
  }
  catch IndexError;
  Trans_Hash_Exists = 1;
}

%% Try to get the stem of certain grammatical categories of words
private define uninflect (word)
{
  variable one, two, three, ending;

  word = strlow (word);

  if (string_match (word, "[^t]ied$", 1))
    word = word[[:strbytelen (word)-4]] + "y";

  one = ["s","[^akrt]eted","[^o]u[dnrtu]ed","[^eo][ao][dt]ed","created",
         "[^o]ided","[^i][cv]ited","uired","asted","[iy][sz]ed","[^aou]ined",
         "[ ^e][^l]o[dpsv]ed","[bcgdkptu]led","[^a]i[bckmrv]ed","[^a]iled",
         "[aiy]ped","[cvu]ed","[^e]ared","[lpz]oned","cached","seded",
         "[^o]oked","athed","[^i]a[sz]ed","[^einv]aled","t[er]ed",
         "[^cio][bclnt]ored","[^e][aeu]med","[^ie][a-rt-z]sed","[^i][a-z]ged"];

  two = ["[dhklmnprtwxy]ed","urbed","[ias]sed","inged","ffed"];

  three = ["bbed","edded","gged","kked","mmed","nned","pped","rred",
           "tted","[^a]ttened","[^hpr][bcdenop]lled",
           "ing"];

  foreach ending (three)
  {
    if (string_match (word, ending+"$", 1))
      word = word[[:strbytelen (word)-4]];
  }
  foreach ending (one)
  {
    if (string_match (word, ending+"$", 1))
      word = word[[:strbytelen (word)-2]];
  }
  foreach ending (two)
  {
    if (string_match (word, ending+"$", 1))
      word = word[[:strbytelen (word)-3]];
  }

  return word;
}

%% The iso codes for language/country cannot be used directly in the
%% word lookup-url on the Microsoft Language Portal. Only a number
%% representing an association to the iso codes can be used.
private define get_microsoft_langid ()
{
  variable locale = "";
  variable CH = Assoc_Type[String_Type, ""];
  variable p = pcre_compile ("[a-z]{2}_[A-Z]{2}");

  (locale,) = syscmd_output_to_string ("env | grep -E \"^LC_MESSAGES=|^LANG=\"");

  if (pcre_exec (p, locale))
    locale = pcre_nth_substr (p, locale, 0);

  CH["af_ZA"] = "6", CH["sq_AL"] = "12", CH["am_ET"] = "19", CH["ar_SA"] = "39"; CH["hy_AM"] = "49";
  CH["as_IN"] = "51"; CH["bn_BD"] = "67"; CH["bn_IN"] = "68"; CH["eu_ES"] = "74"; CH["be_BY"] = "76";
  CH["bg_BG"] = "93"; CH["ca_ES"] = "100"; CH["zh_CN"] = "124"; CH["zh_HK"] = "127"; CH["zh_TW"] = "129";
  CH["hr_HR"] = "137"; CH["cs_CZ"] = "140"; CH["da_DK"] = "142"; CH["prs_A"] = "145"; CH["nl_NL"] = "155";
  CH["en_GB"] = "262"; CH["et_EE"] = "273"; CH["fil_P"] = "283"; CH["fi_FI"] = "285"; CH["fr_FR"] = "303";
  CH["fr_CA"] = "293"; CH["gl_ES"] = "346"; CH["ka_GE"] = "350"; CH["de_DE"] = "354"; CH["el_GR"] = "361";
  CH["gu_IN"] = "367"; CH["ha_La"] = "374"; CH["he_IL"] = "378"; CH["hi_IN"] = "380"; CH["hu_HU"] = "382";
  CH["is_IS"] = "386"; CH["ig_NG"] = "388"; CH["id_ID"] = "391"; CH["iu_La"] = "397"; CH["ga_IE"] = "402";
  CH["xh_ZA"] = "404"; CH["zu_ZA"] = "406"; CH["it_IT"] = "408"; CH["ja_JP"] = "412"; CH["quc_L"] = "421";
  CH["kn_IN"] = "434"; CH["kk_KZ"] = "443"; CH["km_KH"] = "445"; CH["rw_RW"] = "449"; CH["sw_KE"] = "452";
  CH["kok_I"] = "455"; CH["ko_KR"] = "457"; CH["ky_KG"] = "467"; CH["lo_LA"] = "473"; CH["lv_LV"] = "477";
  CH["lt_LT"] = "484"; CH["lb_LU"] = "496"; CH["mk_MK"] = "500"; CH["ms_BN"] = "510"; CH["ms_MY"] = "512";
  CH["ml_IN"] = "514"; CH["mt_MT"] = "516"; CH["mi_NZ"] = "522"; CH["mr_IN"] = "526"; CH["mn_MN"] = "540";
  CH["ne_NP"] = "554"; CH["nb_NO"] = "568"; CH["nn_NO"] = "570"; CH["or_IN"] = "577"; CH["ps_AF"] = "587";
  CH["fa_IR"] = "589"; CH["pl_PL"] = "591"; CH["pt_BR"] = "594"; CH["pt_PT"] = "601"; CH["pa_IN"] = "613";
  CH["pa_Ar"] = "614"; CH["quz_P"] = "617"; CH["ro_RO"] = "623"; CH["ru_RU"] = "635"; CH["gd_GB"] = "662";
  CH["sr_Cy"] = "667"; CH["sr_Cy"] = "671"; CH["sr_La"] = "677"; CH["nso_Z"] = "682"; CH["tn_ZA"] = "685";
  CH["sd_Ar"] = "695"; CH["si_LK"] = "697"; CH["sk_SK"] = "700"; CH["sl_SI"] = "702"; CH["es_ES"] = "736";
  CH["es_MX"] = "729"; CH["sv_SE"] = "750"; CH["tg_Cy"] = "763"; CH["ta_IN"] = "766"; CH["tt_RU"] = "773";
  CH["te_IN"] = "775"; CH["th_TH"] = "780"; CH["ti_ET"] = "788"; CH["tr_TR"] = "795"; CH["tk_TM"] = "797";
  CH["uk_UA"] = "799"; CH["ur_PK"] = "804"; CH["ug_CN"] = "806"; CH["uz_La"] = "810"; CH["vi_VN"] = "823";
  CH["guc_VE"] = "831"; CH["cy_GB"] = "833"; CH["wo_SN"] = "837"; CH["yo_NG"] = "846";

  if (assoc_key_exists (CH, locale))
    return CH[locale];
  else
    throw RunTimeError, "no language id found, check your locale settings";
}

% Look up a translation for a word or string in the Microsoft Language Portal
private define lookup_microsoft_translation (word)
{
  variable data = "", pat = "", p, data_arr = [""], data_arr_uniq = [""], entry_prev = "", i = 0;
  variable elinks = check_for_prg ("elinks");
  variable langid = get_microsoft_langid ();
  variable elinks_cmd = "$elinks -no-numbering -no-references -dump"$;

  (data,) = syscmd_output_to_string ("$elinks_cmd \"https://www.microsoft.com/en-us/language/Search?&searchTerm=$word&langID=$langid&Source=true&productid=undefined\""$);
  pat = "Translations in Localized Microsoft Products.*Wrong terminology";
  p = pcre_compile (pat, PCRE_DOTALL); % fetch text from beg. to end in "pat"

  if (pcre_exec (p, data))
    data = pcre_nth_substr (p, data, 0);

  data_arr = strchop (data, '\n', 0);

  if (length (data_arr) >= 50) % limit output to 50 lines
    data_arr = data_arr[[0:49]];

  _for i (0, length (data_arr)-1, 1)
  {
    try
      data_arr = [data_arr, data_arr[i][[0:45]]];
    catch IndexError;
  }

  data_arr = array_map (String_Type, &pcre_replace, data_arr, " {2,}", " ::: ");
  data_arr = array_map (String_Type, &strlow, data_arr);
  data_arr = data_arr[where (array_map (Int_Type, &pcre_string_match, data_arr, word))];
  data_arr = data_arr[[2:]];
  data_arr = data_arr[array_sort (data_arr)];

  _for i (0, length (data_arr)-1, 1) % uniqify output
  {
    if (data_arr[i] == entry_prev) continue;
    data_arr_uniq = [data_arr_uniq, data_arr[i]];
    entry_prev = data_arr[i];
  }

  data_arr_uniq = data_arr_uniq[where (strlen (data_arr_uniq))];
  return strjoin (data_arr_uniq, "\n");
}

% Look up a Danish translation for a word
private define lookup_wordlist_danish (word)
{
  variable trans = "";

  ifnot (Trans_Hash_Exists)
    hash_wordlist_danish ();

  if (assoc_key_exists (Trans_Hash, word))
    trans = Trans_Hash[word];
  else if (assoc_key_exists (Trans_Hash, word))
    trans = Trans_Hash[word];

  return trans;
}

define lookup_word ()
{
  variable mw = "", cw = "", word = "", lang = "";
  variable transbuf = "*** Translations ***";
  variable dansk_header = "*** Fra Dansk-gruppens og KLIDs engelsk/dansk edb-ordliste ***";
  variable ms_header = "*** Translations in Localized Microsoft Products ***";

  if (bufferp (transbuf))
    delbuf (transbuf);

  (lang,,,) = get_locale_info ();

  if (markp ())
    word = bufsubstr ();
  else
    word = po_mark_word ();

  word = strlow (word);
  word = str_delete_chars (word, "^\\w");
  word = uninflect (word);

  if (lang == "da")
    cw = lookup_wordlist_danish (word);

  mw = lookup_microsoft_translation (word);

  ifnot (strlen (strtrim (cw + mw)))
    return flush ("no translations found for \"$word\""$);

  pop2buf (transbuf);

  if (lang == "da")
    vinsert ("%s\n\n%s\n\n%s\n\n%s", dansk_header, cw, ms_header, mw);
  else
    vinsert ("%s\n\n%s", ms_header, mw);

  bob ();
  set_buffer_modified_flag (0);
  most_mode ();
  set_status_line (" s:Search, q:Quit (%p)", 0);
}

private define po_mouse_2click_hook (line, col, but, shift)
{
  lookup_word ();
  sleep (2);
  return (0);
}

%}}}
%{{{ msgexec function that takes external commands

% Isolate all msgstrs in a single string
private define isolate_msgstrs ()
{
  variable
    msgstrs = [""],
    kws,
    i = 0;

  (,, msgstrs) = create_strs_arr (buf_as_str ());
  msgstrs = msgstrs[[1:]]; % don't work on header
  (kws, msgstrs) = array_map (String_Type, String_Type, &sep_kw_and_str, msgstrs);
  msgstrs = array_map (String_Type, &strtrim, msgstrs);

  _for i (0, length (msgstrs)-1, 1)
  {
    ifnot (msgstrs[i] == "\"\"")
      msgstrs[i] = trim_quotes (msgstrs[i]);
  }

  msgstrs = strjoin (msgstrs, "\n\n\n");
  return kws, msgstrs;
}

%% Read an array of possibly changed msgstrs back into the po-file
private define assemble_pofile (kws, msgstrs)
{
  variable
    entries_hash = Assoc_Type[Array_Type],
    entries = [""],
    msgstr_pl = "",
    msgstr = "",
    i = 0,
    n = 0;

  msgstrs = strreplace (msgstrs, "\v", " ");
  msgstrs = strreplace (msgstrs, "\n\n\n", "\v");
  msgstrs = strchop (msgstrs, '\v', 0);
  _for i (0, length (msgstrs)-1, 1)
  {
    ifnot (msgstrs[i] == "\"\"")
      msgstrs[i] = surround_in_quotes (msgstrs[i]);
  }

  ifnot (length (kws) == length (msgstrs))
    throw RunTimeError, "some error occured $file"$;

  msgstrs = array_map (String_Type, &concat_kw_str, kws, msgstrs);
  () = write_string_to_file (strjoin (msgstrs, "\n"), "/tmp/fil");
  entries_hash = create_entries_hash (buf_as_str ());

  _for i (1, length (entries_hash)-1, 1)
  {
    ifnot (strlen (entries_hash[i]["msgid_plural"]))
    {
      entries_hash[i]["msgstr"] = msgstrs[n];
      n++;
    }
    else
    {
      entries_hash[i]["msgstr[0]"] = msgstrs[n];
      entries_hash[i]["msgstr[1]"] = msgstrs[n+1];
      n++; n++;
    }
  }

  entries = array_map (String_Type, &assemble_entry, entries_hash);

  if (length (Obsolete))
    entries = [entries, Obsolete];

  entries = strjoin (entries, "\n\n");
  return entries + "\n";
}

%% Isolate all msgstrs in a single string, run a specified command on
%% them and then assemble them back into the po-file. It means that
%% the command needs only to be executed once. As far as I can tell,
%% gettext's msgfilter program runs the command once for every entry
%% in the po-file.
private define msgexec (cmd, interactive)
{
  variable
    cn = get_current_entry_number (),
    tmpfile = "",
    entries = "",
    msgstrs = "",
    kws = [""],
    e = 0;

  (kws, msgstrs) = isolate_msgstrs ();
  tmpfile = make_tmp_file ("/tmp/po_msgexec");
  () = write_string_to_file (msgstrs, tmpfile);

  if (interactive) % for use with e.g. an interactive spell checker
  {
    e = system ("$cmd $tmpfile"$);
    msgstrs = file_as_str (tmpfile);
  }
  else
    (msgstrs, e) = syscmd_output_to_string ("$cmd $tmpfile"$);

  () = delete_file (tmpfile);

  ifnot (0 == e)
    throw RunTimeError, "$cmd failed!"$;

  entries = assemble_pofile (kws, msgstrs);
  replace_buffer (entries);
  goto_entry (cn);
  update (1);
  flush ("done");
}

private define return_apertium_language_pairs ()
{
  variable pairs_l = [""], pairs = [""], exts, dir;

  if (2 == file_status ("/usr/share/apertium/modes"))
    pairs = listdir ("/usr/share/apertium/modes");
  if (2 == file_status ("/usr/local/share/apertium/modes"))
    pairs_l = listdir ("/usr/local/share/apertium/modes");

  pairs = [pairs, pairs_l];

  % if (0 == length (where (array_map (Int_Type, &strlen, pairs))))
  % {
  %   dir = read_with_completion ("", "Directory w/language pairs:", "", "", 'f');

  %   if (2 != file_status (dir))
  %     throw OpenError, "$dir does not exist"$;

  %   pairs = listdir (dir);
  % }

  exts = array_map (String_Type, &path_extname, pairs);
  pairs = pairs[wherenot (array_map (Int_Type, &strcmp, exts, ".mode"))];
  pairs = array_map (String_Type, &path_sans_extname, pairs);

  ifnot (length (pairs))
    throw RunTimeError, "Could not find any Apertium language pairs";

  strjoin (pairs, ",");
}

%% Use the machine translation system "Apertium" for translation
define apertium ()
{
  variable
    prg = check_for_prg ("apertium"),
    pairs = "",
    cmd = "";

  pairs = return_apertium_language_pairs ();

  if (get_y_or_n ("Translate file with Apertium"))
  {
    ungetkey ('\t');
    Apertium_Langs = read_with_completion (pairs, "Language pair :", "$Apertium_Langs"$, "", 's');
  }
  else return;

  if (strlen (Apertium_Langs))
  {
    ifnot (is_list_element (pairs, Apertium_Langs, ','))
      throw RunTimeError, "language pair $Apertium_Langs not found"$;
  }

  cmd = "$prg $Apertium_Langs -u <"$;

  if (count ("t"))
  {
    flush ("WARNING: Old translations may be modified!");
    sleep (1);
  }

  if (Apertium_Langs[[0:1]] == "en") % if translating from English, then
    msgid_to_msgstr_all ();          % copy msgids to msgstrs

  msgexec (cmd, 0);
}

%% Fetch translations for untranslated entries in the po-file to be
%% updated ("def") from a po-file in a language used as the
%% from-language in the language pair ("ref"), then translate those
%% entries with Apertium and merge them into "def", also flagging them
%% fuzzy. The "keep_fuzzy" option will transfer and translate fuzzy
%% entries from "ref" to "def".
define apertium_update (keep_fuzzy)
{
  variable
    tmpfile = make_tmp_file ("/tmp/apertium_update"),
    msgattrib = check_for_prg ("msgattrib"),
    cn = get_current_entry_number (),
    entries_hash_def = Assoc_Type[Array_Type],
    msgstrs_apertium = [""],
    matches = {},
    idx_def = {},
    msgstrs_ref = [""],
    msgids_ref = [""],
    msgid_def = "",
    ref_file = "",
    refstr = "",
    entries = [""],
    pairs = [""],
    entry = "",
    match = "",
    cmd = "",
    def = "",
    kws = [""],
    i = 0,
    n = 0,
    e = 0;

  EXIT_BLOCK
  {
    () = delete_file (tmpfile);
  }

  ref_file = init_src_dir ("reference_file");
  () = conv_charset (ref_file);
  pairs = return_apertium_language_pairs ();

  if (get_y_or_n (sprintf ("Update this file with translations from %s", path_basename (ref_file), "using Apertium")))
  {
    ungetkey ('\t');
    Apertium_Langs = read_with_completion (pairs, "Choose language pair for update:",
                                           "$Apertium_Langs"$, "", 's');
  }
  else return;

  if (strlen (Apertium_Langs))
  {
    ifnot (is_list_element (pairs, Apertium_Langs, ','))
      throw RunTimeError, "language pair $Apertium_Langs not found"$;
  }
  else
    throw UsageError, "no language pair chosen"$;

  if (keep_fuzzy)
    cmd = "$msgattrib --clear-fuzzy --translated --no-obsolete $ref_file 2>/dev/null"$;
  else
    cmd = "$msgattrib --translated --no-fuzzy --no-obsolete $ref_file 2>/dev/null"$;

  (refstr, e) = syscmd_output_to_string (cmd);

  ifnot (0 == e)
    throw RunTimeError, "$cmd failed!"$;

  def = buf_as_str ();
  entries_hash_def = create_entries_hash (def);
  (, msgids_ref, msgstrs_ref) = create_strs_arr (refstr);

  _for i (0, length (entries_hash_def)-1, 1)
  {
    msgid_def = entries_hash_def[i]["msgid"];
    match = wherefirst (msgid_def == msgids_ref);
    if (match)
    {
      % only fill out untranslated entries in "def"
      if (entries_hash_def[i]["msgstr"] == "msgstr \"\"")
      {
        list_append (matches, match);
        list_append (idx_def, i);
      }
    }
  }

  ifnot (length (matches))
    throw RunTimeError,
    "no identical msgids found or no untranslated messages"$;

  matches = list_to_array (matches);
  idx_def = list_to_array (idx_def);
  msgstrs_apertium = msgstrs_ref[matches];
  (kws, msgstrs_apertium) = array_map (String_Type, String_Type,
                                       &prep_str, msgstrs_apertium);
  msgstrs_apertium = array_map (String_Type, &strtrim, msgstrs_apertium);

  ifnot (length (kws) == length (msgstrs_apertium))
    throw IndexError, "some error occured";

  msgstrs_apertium = strjoin (msgstrs_apertium, "\n\n\n\n");
  write_string_to_file (msgstrs_apertium, tmpfile);
  (msgstrs_apertium,) =
    syscmd_output_to_string ("apertium $Apertium_Langs -u < $tmpfile 2>/dev/null"$);
  msgstrs_apertium = strreplace (msgstrs_apertium, "\n\n\n\n", "\v");
  msgstrs_apertium = strchop (msgstrs_apertium, '\v', 0);
  msgstrs_apertium = array_map (String_Type, &post_prep_str, msgstrs_apertium);

  ifnot (length (kws) == length (msgstrs_apertium))
    throw RunTimeError, sprintf("%S %S", length(kws), length(msgstrs_apertium));
    %throw RunTimeError, "some error occured";

  msgstrs_apertium = array_map (String_Type, &concat_kw_str, kws, msgstrs_apertium);

  _for i (0, length (idx_def)-1, 1)
  {
    entry = entries_hash_def[idx_def[i]];
    entry["msgstr"] = msgstrs_apertium[n];
    entry = flag_fuzzy (entry);
    entries_hash_def[idx_def[i]] = entry;
    n++;
  }

  entries = array_map (String_Type, &assemble_entry, entries_hash_def);

  if (length (Obsolete))
    entries = [entries, Obsolete];

  entries = strjoin (entries, "\n\n");
  replace_buffer (entries);
  goto_entry (cn);
  po_statistics ();
  update (1);
  flush ("done");
}

%% Replace a word/string with another in the msgstrs
define replace_in_msgstrs (old, new, ask)
{
  variable
    cn = get_current_entry_number (),
    msgstrs = "",
    entries = "",
    prompt = "",
    cmd = "",
    kws = [""];

  if (ask)
  {
    old = read_mini ("Replace in msgstrs:", Null_String, Null_String);
    prompt = "Replace $old with:"$;
    new = read_mini (prompt, "", "");
  }

  ifnot (strlen (new))
    return;

  (kws, msgstrs) = isolate_msgstrs ();
  msgstrs = strreplace (msgstrs, old, new);
  entries = assemble_pofile (kws, msgstrs);
  replace_buffer (entries);
}

%% Count the number of occurences of every word in the msgstrs of a
%% po-file.
define word_stats ()
{
  variable
    tmpfile = make_tmp_file ("/tmp/word_stats_sortfile"),
    word_prev = "",
    msgstrs = "",
    wlist = {},
    entry = "",
    words = "",
    word = "",
    cnt = Int_Type[0];

  EXIT_BLOCK
  {
    () = remove (tmpfile);
  }

  flush ("counting number of occurences of each word in the msgstrs ...");
  (, msgstrs) = isolate_msgstrs ();
  msgstrs = strlow (msgstrs);
  words = strtok (msgstrs, "^\\a");
  words = array_map (String_Type, &strtrim, words);
  words = words[where (array_map (Int_Type, &strlen, words) > 1)];
  words = words[array_sort (words)];

  foreach word (words)
  {
    if (word == word_prev) continue;
    cnt = where (word == words);
    entry = strcat (string (length (cnt)), ": ", word);
    list_append (wlist, entry);
    word_prev = word;
  }
  wlist = list_to_array (wlist);
  write_string_to_file (strjoin (wlist, "\n"), tmpfile);
  (wlist,) = syscmd_output_to_string ("sort -k 1n -k 2b $tmpfile"$);
  wlist = strchop (wlist, '\n', 0);
  array_reverse (wlist);
  pop2buf ("***Number of word occurences***");
  onewindow ();
  insert (strjoin (wlist, "\n"));
  most_mode ();
  set_buffer_modified_flag (0);
  bob ();
  flush ("type 'q' to close this window");
}

% Replace words in a po-file from a file with lines of colon separated
% entries where word to be replaced is on the left of the colon and
% the replacement on the right of the colon
define replace_from_list ()
{
  variable
    tmpfile = make_tmp_file ("/tmp/replace_from_list"),
    listfilestr = "",
    listfile = "",
    entries = "",
    msgstrs = "",
    word_rep = "",
    line_arr = [""],
    lines = [""],
    word = "",
    kws = [""],
    i = 0;

  EXIT_BLOCK
  {
    () = remove (tmpfile);
  }

  listfile = read_with_completion ("Listfile to replace from:", "","", 'f');
  listfilestr = file_as_str (listfile);
  (kws, msgstrs) = isolate_msgstrs ();
  write_string_to_file (msgstrs, tmpfile);
  lines = strchop (listfilestr, '\n', 0);
  lines = lines [where (array_map (Integer_Type, &strlen, lines))];
  lines = lines [where (array_map (Integer_Type,
                                   &string_match, lines, ":", 1))];
  line_arr = array_map (Array_Type, &strtok, lines, ":");
  line_arr = array_map (Array_Type, &strtrim, line_arr);

  _for i (0, length (line_arr)-1, 1)
  {
    word = line_arr[i][0];
    word_rep = line_arr[i][1];
    ifnot (0 == system ("sed -i 's/$word/$word_rep/gI' $tmpfile"$))
      throw RunTimeError, "replacing with sed failed";
  }

  msgstrs = file_as_str (tmpfile);
  entries = assemble_pofile (kws, msgstrs);
  replace_buffer (entries);
  flush ("done");
}

%% From a list of misspelled words, typing enter on a word will
%% replace it with a corrected one.
define replace_word_from_list ()
{
  variable old = po_mark_word ();
  variable new = read_mini ("Replace \"$old\" with:"$, "", old);

  ifnot (strlen (new))
    return;

  otherwindow ();
  replace_in_msgstrs (old, new, 0);
  otherwindow ();
  set_readonly (0);  delete_line (); set_readonly (1);
  set_buffer_modified_flag (0);
  flush ("\"$old\" replaced with \"$new\""$);
}

% Sort and weed out duplicate entries in the personal wordlists for
% aspell and hunspell.
private define sort_personal_wordlist (Spell_Prg)
{
  variable
    pers_dict = "",
    aspell_pers_dict_header = "",
    locale = "",
    words = "",
    lang = "",
    enc = "";

  (locale, lang,, enc) = get_locale_info ();

  if (Spell_Prg == "aspell")
  {
    pers_dict = expand_filename ("~/.aspell.$lang.pws"$);
    aspell_pers_dict_header = "personal_ws-1.1 $lang 0 $enc"$;
  }
  if (Spell_Prg == "hunspell")
    pers_dict = expand_filename ("~/.hunspell_$locale"$);

  ifnot (1 == file_status (pers_dict))
    return;

  if (Spell_Prg == "aspell")
  {
    (words,) = syscmd_output_to_string ("tail -n +2 $pers_dict | sort -fu"$);
    words = strcat (aspell_pers_dict_header, "\n", words);
  }
  else
    (words,) = syscmd_output_to_string ("sort -fu $pers_dict"$);

  () = write_string_to_file (words, pers_dict);
}

%% Function to let user add words to the spell checker's personal word list.
define add_word_to_personal_spell_dict ()
{
  variable
    aspell_pers_dict_header = "",
    hunspell_pers_dict = "",
    aspell_pers_dict = "",
    locale = "",
    lang = "",
    word = "",
    enc = "";

  (locale, lang,, enc) = get_locale_info ();

  if (eobp () and bobp ())
    return most_exit_most ();

  word = strlow (line_as_string ());
  set_readonly (0); delete_line; set_readonly (1);
  if (Spell_Prg == "aspell")
  {
    aspell_pers_dict_header = "personal_ws-1.1 $lang 0 $enc"$;
    aspell_pers_dict = expand_filename ("~/.aspell.$lang.pws"$);

    if (1 == file_status (aspell_pers_dict))
      () = append_string_to_file (word, aspell_pers_dict);
    else
      () = append_string_to_file (aspell_pers_dict_header +
                                  "\n" + word, aspell_pers_dict);

    flush ("\"$word\" added to $aspell_pers_dict"$);
  }
  if (Spell_Prg == "hunspell")
  {
    hunspell_pers_dict = expand_filename ("~/.hunspell_$locale"$);
    () = append_string_to_file (word, hunspell_pers_dict);
    flush ("\"$word\" added to $hunspell_pers_dict"$);
  }

  local_unsetkey ("q");
  local_setkey ("most_exit_most", "q");
}

%% Return an array of available spell checker dictionaries for the
%% chosen spell checker prg.
private define get_available_spell_dicts (spellprg)
{
  variable
    tmpfile = make_tmp_file ("/tmp/getspelldicts"),
    hunspell = "",
    aspell = "",
    dicts = "",
    e = 0;

  EXIT_BLOCK
  {
    () = delete_file (tmpfile);
  }

  if (spellprg == "aspell")
  {
    aspell = check_for_prg ("aspell");
    (dicts, e) = syscmd_output_to_string ("$aspell dump dicts"$);
    dicts = strchop (dicts, '\n', 0);
  }
  if (spellprg == "hunspell")
  {
    hunspell = check_for_prg ("hunspell");
    (dicts, e) =
      syscmd_output_to_string ("$hunspell -D </dev/null >$tmpfile 2>&1"$);
    dicts = file_as_str (tmpfile);
    dicts = strchop (dicts, '\n', 0);
    dicts = dicts[where (array_map (Int_Type, &string_match, dicts, "^/", 1))];
    dicts = array_map (String_Type, &path_basename, dicts);
    dicts = array_map (String_Type, &strlow, dicts);
  }

  ifnot (e == 0)
    throw RunTimeError, "Could not get available dictionaries";

  return dicts;
}

%% Use the spell checker programs' feature to list misspelled words and
%% from that list let user correct words in the po-file and add words
%% to the personal word list.
define spellcheck_from_list ()
{
  variable
    tmpfile = make_tmp_file ("po_list_misspelled"),
    brk_word_lst = [":","/",".","-"],
    del_lst = ["^","\\n"],
    hunspell_pers_dict = "",
    aspell_pers_dict = "",
    available_dicts = [""],
    misspelled = "",
    spell_cmd = "",
    msgstrs = [""],
    locale = "",
    words = [""],
    exit = 0,
    lang = "",
    cmd = "",
    d = "";

  EXIT_BLOCK
  {
    () = delete_file (tmpfile);
  }

  (locale, lang, , ) = get_locale_info ();

  ifnot (strlen (Spell_Prg))
    Spell_Prg = find_prgs_use_first ("hunspell aspell");

  Spell_Prg = path_basename (Spell_Prg);
  sort_personal_wordlist (Spell_Prg);

  if (Spell_Prg == "hunspell")
  {
    available_dicts = get_available_spell_dicts ("hunspell");

    ifnot (any (available_dicts == strlow (locale)))
      throw RunTimeError, "dictionary \"$locale\" not installed"$;

    cmd = "$Spell_Prg -l -d $locale,en_US,en_GB < $tmpfile | sort -u 2>/dev/null"$;
  }
  if (Spell_Prg == "aspell")
  {
    available_dicts = get_available_spell_dicts ("aspell");
    aspell_pers_dict = expand_filename ("~/.aspell.$lang.pws"$);

    ifnot (any ((available_dicts == strlow (lang)) or
                (any (available_dicts == strlow (locale)))))
      throw RunTimeError, "dictionary \"$lang\" not installed"$;

    if (any (available_dicts == "en"))
      cmd = "$Spell_Prg -W2 --ignore-case list -d $lang < $tmpfile | "$ +
      "$Spell_Prg -W3 --ignore-case list -d en | sort -fu 2>/dev/null"$;

    else
      cmd = "$Spell_Prg -W2 --ignore-case list -d $lang < $tmpfile | "$ +
      "sort -fu 2>/dev/null";
  }

  (,, msgstrs) = create_strs_arr (buf_as_str ());
  (, msgstrs) = array_map (String_Type, String_Type, &prep_str, msgstrs);
  msgstrs = strjoin (msgstrs, " ");
  msgstrs = del_html_tags (msgstrs);
  msgstrs = del_format_specifiers (msgstrs);

  foreach d (del_lst)
    msgstrs = strreplace (msgstrs, d,  "");

  foreach d (brk_word_lst)
    msgstrs = strreplace (msgstrs, d, "\n");

  words = strtok (msgstrs);
  words = words[wherenot (array_map (Int_Type, &string_match, words, "[-~\(\)&\\^_]", 1))];
  words = strjoin (words, " ");
  words = strtok (words, "^\\w");
  words = words[where (array_map (Int_Type, &strlen, words) > 3)];
  msgstrs = strjoin (words, "\n\n");
  () = write_string_to_file (msgstrs, tmpfile);
  (misspelled, exit) = syscmd_output_to_string (cmd);

  ifnot (0 == exit)
    throw RunTimeError, "$cmd failed!"$;

  ifnot (strlen (misspelled))
    return flush ("$Spell_Prg found no misspelled words"$);

  pop2buf ("***Misspelled Words***");
  insert (misspelled);
  bob ();
  most_mode ();
  set_buffer_modified_flag (0);
  local_setkey ("replace_word_from_list", "^M");
  local_setkey ("add_word_to_personal_spell_dict", "+");
  local_setkey ("set_readonly \(0\); delete_line; set_readonly \(1\);", "-");
  flush ("<enter> to replace word; '+' adds word to personal wordlist; '-' removes word; 'q' closes window");
}

%% Interactively spell check the msgstrs with a chosen spell program.
define spellcheck ()
{
  variable cmd = "", xterm = "", lang = "", locale = "";

  (locale, lang,,) = get_locale_info ();

  ifnot (strlen (Spell_Prg))
    Spell_Prg = find_prgs_use_first ("aspell hunspell");

  xterm = find_prgs_use_first
    ("xterm rxvt gnome-terminal konsole xfce4-termninal eterm aterm kterm");

  if (path_basename (Spell_Prg) == "hunspell")
    cmd = "$xterm -e hunspell -d $locale,en_US,en_GB -c "$;

  if (path_basename (Spell_Prg) == "aspell")
    cmd = "$xterm -e $Spell_Prg -W2 --ignore-case -d $lang -c "$;

  msgexec (cmd, 1);
}

%}}}
%{{{ po_diff, compare translations, limit view

%% Retain only user cmts, extracted cmts
private define filter_cmt (cmt)
{
  variable cmt_arr = strchop (cmt, '\n', 0);

  cmt_arr = cmt_arr[where (array_map (Int_Type, &pcre_string_match,
                                      cmt_arr, "^#[ ]|^#\\."))];
  cmt_arr = array_map (String_Type, &strtrim, cmt_arr);

  return strtrim (strjoin (cmt_arr, "\n"));
}

%% Use the wdiff prg to create a word diff between two strings
private define po_wdiff (old, new)
{
  variable
    tmp_a = make_tmp_file ("po_wdiff_a"),
    tmp_b = make_tmp_file ("po_wdiff_b"),
    prg = check_for_prg ("wdiff"),
    word_diff = "", exit_status;

  () = write_string_to_file (old, tmp_a);
  () = write_string_to_file (new, tmp_b);
  (word_diff, exit_status) =
    syscmd_output_to_string ("$prg -n $tmp_a $tmp_b 2>/dev/null"$);

  () = delete_file (tmp_a);
  () = delete_file (tmp_b);

  return word_diff;
}

private define diff_u (old, new)
{
  variable
    prg = check_for_prg ("diff"),
    tmp_a = make_tmp_file ("diffu_a"),
    tmp_b = make_tmp_file ("diffu_b"),
    cmd = "$prg --unified=100 $tmp_a $tmp_b | tail -n +4 2>/dev/null"$,
    exit_status = 0,
    diff = "";

  old += "\n";
  new += "\n";
  () = write_string_to_file (old, tmp_a);
  () = write_string_to_file (new, tmp_b);
  (diff, exit_status) = syscmd_output_to_string (cmd);

  ifnot (0 == exit_status)
    throw RunTimeError, "$cmd failed"$;

  () = delete_file (tmp_a);
  () = delete_file (tmp_b);

  return diff;
}

% Format a msgid or msgstr to prepare them for comparison
private define format_raw_str (str)
{
  variable kw = "";

  (kw, str) = prep_str (str);
  str = post_prep_str (str);
  return concat_kw_str (kw, str);
}

%% Determine the diff format of en entry in producing the diff, based
%% on the format of the strings.
private define create_diff (msgstr_old, msgstr_new)
{
  variable diff, kw;

  if ((lines_count (msgstr_new) == 1) && (strlen (msgstr_new) < Wrap))
  {
    diff = strcat ("-", msgstr_old, "\n+", msgstr_new);
  }
  else if ((Multi_Line) || (lines_count (msgstr_new) < 3) ||
           (strlen (msgstr_new) < Wrap))
  {
    diff = diff_u (msgstr_old, msgstr_new);
  }
  else %% use wdiff for others
  {
    (kw, msgstr_old) = prep_str (msgstr_old);
    (kw, msgstr_new) = prep_str (msgstr_new);
    diff = po_wdiff (msgstr_old, msgstr_new);

    %% only changes in whitespace. wdiff does not mark
    %% these up so use diff_u
    ifnot (pcre_string_match (diff, "{\\+|\\[-"))
    {
      msgstr_old = post_prep_str (msgstr_old);
      msgstr_new = post_prep_str (msgstr_new);
      diff = diff_u (msgstr_old, msgstr_new);
    }
    else
    {
      diff = post_prep_str (diff);
    }

    diff = concat_kw_str (kw, diff);
  }

  return diff;
}

%% Produce an easy-to-read diff between two po-files
define po_diff ()
{
  variable
    msgattrib = check_for_prg ("msgattrib"),
    wdiff_prg = check_for_prg ("wdiff"),
    linenos = return_msgid_linenos (),
    match_old = Int_Type[0],
    match_new = Int_Type[0],
    all_msgstrs_new = [""],
    all_msgstrs_old = [""],
    all_msgids_new = [""],
    all_msgids_old = [""],
    all_cmts_new = [""],
    all_cmts_old = [""],
    cmts_old = [""],
    cmts_new = [""],
    strs_old = [""],
    strs_new = [""],
    msgstr_new = "",
    msgstr_old = "",
    msgid_new = "",
    kw_msgstr = "",
    kw_msgid = "",
    thisfile = "",
    rcs_file = "",
    cmt_new = "",
    cmt_old = "",
    newfile = "",
    oldfile = "",
    header = "",
    oldstr = "",
    newstr = "",
    diff = "",
    diffs = {},
    wmsg = "",
    cmd = "",
    dir = "",
    ver = "",
    ch = Char_Type,
    mod_strs = 0,
    new_strs = 0,
    lineno = 0,
    e = 0,
    i = 0,
    n = 0;

  EXIT_BLOCK
  {
    () = delete_file (Po_Tmpfile);
  }

  if ((count ("u") || count ("f")))
  {
    wmsg =
      "\t(WARNING: New file contained fuzzy or untranslated entries.\n" +
      "\tLine and entry numbers are skewed)";
  }

  (thisfile, dir,,) = getbuf_info (whatbuf ());
  thisfile = dircat (dir, thisfile);
  write_buf_to_tmpfile ();
  newfile = Po_Tmpfile;
  cmd = "$msgattrib --no-wrap --translated --no-fuzzy --no-obsolete $newfile"$;
  (newstr, e) = syscmd_output_to_string (cmd);

  if ((e != 0) || (strlen (newstr) == 0))
    throw RunTimeError, "msgattrib cmd on $newfile failed, try to (V)alidate"$;

  ch = get_mini_response
    ("Diff against: 1. Other version, 2. version in RCS? [1 or 2]");
  if (ch == '2')
  {
    (rcs_file, ver) = checkout_rcs_file (0);
    oldfile = "/tmp/" + whatbuf () + ",v-$ver"$;
    () = write_string_to_file (rcs_file, oldfile);
  }
  else
    oldfile = read_file_from_mini ("[DIFF] Other file:");

  ifnot (file_type (oldfile, "reg"))
    throw ReadError, "$oldfile not found or is not a regular file"$;

  ifnot (conv_charset (oldfile))
    throw RunTimeError, "encoding conversion on $oldfile failed, try to (V)alidate"$;

  % The "no-fuzzy" flag here ensures that messages that had the fuzzy
  % flag in the old version are simply treated as new messages
  cmd = "$msgattrib --no-wrap --no-fuzzy --translated --no-obsolete $oldfile"$;
  (oldstr, e) = syscmd_output_to_string (cmd);

  if ((e != 0) || (strlen (oldstr) == 0))
    throw RunTimeError, "msgattrib cmd on $oldfile failed, try to (V)alidate"$;

  (all_cmts_old, all_msgids_old, all_msgstrs_old) = create_strs_arr (oldstr);
  (all_cmts_new, all_msgids_new, all_msgstrs_new) = create_strs_arr (newstr);
  all_cmts_old = array_map (String_Type, &filter_cmt, all_cmts_old);
  all_cmts_new = array_map (String_Type, &filter_cmt, all_cmts_new);

  _for i (0, length (all_msgids_new)-1, 1)
  {
    lineno = linenos[i];
    cmt_new = all_cmts_new[i];
    msgstr_new = all_msgstrs_new[i];
    msgid_new = all_msgids_new[i];

    % skip [[1:]] instances of identical msgids in the same file (msgctxt)
    if (msgid_new == NULL)
      continue;

    Multi_Line = str_is_multiline (msgid_new);

    % check for identical msgid in old and new
    match_old = where (msgid_new == all_msgids_old);
    match_new = where (msgid_new == all_msgids_new);
    msgid_new = format_raw_str (msgid_new);

    if (length (match_old))
    {
      cmts_old = all_cmts_old[match_old];
      cmts_new = all_cmts_new[match_new];
      strs_old = all_msgstrs_old[match_old];
      strs_new = all_msgstrs_new[match_new];

      % one or more identical msgids present in the same file
      % (msgctxt entries)
      if (length (match_old) > 1)
      {
        (strs_old, strs_new) = array_align_length (strs_old, strs_new);

        % process all identical msgids in the same file
        _for n (0, length (strs_new)-1, 1)
        {
          if (strs_old[n] != strs_new[n])
          {
            if (strlen (strs_old[n]))
            {
              diff = create_diff (strs_old[n], strs_new[n]);
              diff = strcat (cmts_new[n], "\n", msgid_new, "\n", diff);
              diff = strtrim (diff);
              diff = sprintf ("\t[modified: entry: %d / line: %d]\n\n%s", match_new[n], linenos[match_new[n]]+1, diff);
              mod_strs++;
            }
            else
            {
              diff = strcat (cmts_new[n], "\n", msgid_new, "\n", strs_new[n]);
              diff = strtrim (diff);
              diff = sprintf ("\t[new: entry: %d / line: %d]\n\n%s", i+1, lineno+1, diff);
              new_strs++;
            }

            list_append (diffs, diff);
          }
          else
          {
            % a new comment was added
            if (cmts_old[n] != cmts_new[n])
            {
              diff = strcat (cmts_new[n], "\n", msgid_new, "\n", msgstr_new);
              diff = strtrim (diff);
              diff = sprintf ("\t[new comment only: entry: %d / line: %d]\n\n%s", match_new[n], linenos[match_new[n]]+1, diff);
              list_append (diffs, diff);
            }
          }
        }

        % when encountered again identical msgid in same file
        % is skipped as per above
        all_msgids_new[match_new] = NULL;
        continue;
      }
      else % msgid is unique
      {
        msgstr_old = all_msgstrs_old[match_old[0]];

        if (msgstr_old != msgstr_new) % translation was modified
        {
          msgstr_old = format_raw_str (msgstr_old);
          msgstr_new = format_raw_str (msgstr_new);
          diff = create_diff (msgstr_old, msgstr_new);
          diff = strcat (cmt_new, "\n", msgid_new, "\n", diff);
          diff = strtrim (diff);
          diff = sprintf ("\t[modified: entry: %d / line: %d]\n\n%s", i+1, lineno+1, diff);
          mod_strs++;
          list_append (diffs, diff);
        }
        else
        {
          % neither changes in translation nor a new
          % message but a new translator comment was
          % added
          cmt_old = cmts_old[0];
          if ((cmt_old != cmt_new) && (strlen (cmt_new)))
          {
            diff = strcat (cmt_new, "\n", msgid_new, "\n", msgstr_new);
            diff = strtrim (diff);
            diff = sprintf ("\t[new comment only: entry: %d / line: %d]\n\n%s", i+1, lineno+1, diff);
            list_append (diffs, diff);
          }
        }
      }
    }
    else % msgid is new (not found in old file)
    {
      msgid_new = format_raw_str (msgid_new);
      msgstr_new = format_raw_str (msgstr_new);
      diff = strcat (cmt_new, "\n", msgid_new, "\n", msgstr_new);
      diff = strtrim (diff);
      diff = sprintf ("\t[new: entry: %d / line: %d]\n\n%s", i+1, lineno+1, diff);
      new_strs++;
      list_append (diffs, diff);
    }
  }

  if (length (diffs))
  {
    diffs = list_to_array (diffs);
    diffs = diffs [where (array_map (Integer_Type, &strlen, diffs))];
  }

  if (length (diffs) < 1) % if 1, only header has changed
    return flush ("no translations were changed");

  diffs = strjoin (diffs, "\n\n");
  diffs = strchop (diffs, '\n', 0);

  % some aesthetic indentation
  _for i (0, length (diffs)-1, 1)
  {
    ifnot (pcre_string_match (diffs[i], "^[ +-]+"))
      diffs[i] = strcat (" ", diffs[i]);
  }

  diffs = strjoin (diffs, "\n");
  header =
    "--- $oldfile\n+++ $thisfile\n\n$mod_strs translation(s) have been modified and "$ +
    "\n$new_strs translation(s) are new since the previous version.\n\n"$;

  if (strlen (wmsg))
    wmsg += "\n\n";

  diffs = strcat (header, wmsg, diffs, "\n");
  diff = read_with_completion ("Save diff to file:", "", whatbuf + ".diff", 'f');

  if (-1 == write_string_to_file (diffs, diff))
    throw WriteError, "writing diffs to $diff_file failed"$;

  delete_file (newfile);
  flush ("diff written as $diff"$);
}

%% Create lists of msgids and msgstrs for languages with which to
%% compare.
private define create_cmp_langs_strs_lists ()
{
  variable
    lang_arr = strchop (Compare_With_Languages, ',', 0),
    prg = check_for_prg ("msgcat"),
    po_files = [""],
    files = [""],
    msgids = [""],
    msgstrs = [""];

  Po_Dir = init_src_dir (0);

  ifnot (file_type (Po_Dir, "dir"))
    throw OpenError, "$Po_Dir does not exist or is not a directory"$;

  po_files = pofiles_in_dir (Po_Dir);

  ifnot (length (po_files))
    throw OpenError, "No po-files in $Po_Dir"$;

  files = array_map (String_Type, &strcat, lang_arr, "\.po");
  files = po_files [where (array_map (Int_Type, &pcre_string_match, po_files,
                                      strjoin (files, "|")))];

  ifnot (length (files))
    throw OpenError, "No po-files to compare with"$;

  files = array_map (String_Type, &file_as_str, files);
  files = strjoin (files, "\n\n");
  (, msgids, msgstrs) = create_strs_arr (files);
  StrsLists_Exists = 1;

  return (msgids, msgstrs);
}

%% Copy a translation for a chosen msgid from a po-file in another
%% language into the corresponding msgstr. This is bound to a
%% double-click with the mouse or the enter key.
define copy_comparative_trans ()
{
  variable msgstr, msgstr_kw, entry = hash_entry;

  ifnot (bol_bsearch ("·"))
    bob ();
  else
    go_down_1 ();

  push_mark ();

  ifnot (bol_fsearch ("·"))
    eob ();
  else
    go_left_1 ();

  msgstr = post_prep_str (bufsubstr ());
  sw2buf (Po_Buf);
  (, msgstr_kw,,) = return_str_pair ();
  replace_elem (entry, msgstr_kw, msgstr_kw + " " + msgstr);
  replace_entry (assemble_entry (entry));
  delbuf ("***Matching Translations***");
}

%% See how a msgid is translated in other languages
define compare_translations ()
{
  variable
    matches = Int_Type[0],
    msgstrs = [""],
    msgids = [""],
    trans = [""],
    msgid = "",
    tran = "",
    i = 0;

  ifnot (StrsLists_Exists)
    (Msgids, Msgstrs) = create_cmp_langs_strs_lists ();

  ifnot (Gettext_Wrap)
  {
    ifnot (apply_gettext_cmd_to_buffer ("msgcat $Po_Tmpfile 2>/dev/null"$))
      throw RunTimeError, "msgcat failed, try to (V)alidate";

    set_buffer_modified_flag (0);
    Gettext_Wrap = 1;
  }

  msgid = msgid_as_str ();
  matches = where (msgid == Msgids);
  msgids = Msgids[matches];
  msgstrs = Msgstrs[matches];
  trans = array_map (String_Type, &strcat, msgstrs, "\n·");
  trans = strjoin (trans, "\n");
  trans = strtrim (trans, "· \n");
  trans = msgid + "\n·\n" + trans;
  pop2buf ("***Matching Translations***");
  onewindow ();
  insert (trans);
  set_buffer_modified_flag (0);
  bob ();
  most_mode ();
  set_buffer_hook ("mouse_2click", &copy_comparative_trans ());
  local_setkey ("copy_comparative_trans", "^M");
  do
  {
    if (looking_at ("·"))
    {
      go_left_1;
      break;
    }
    set_line_color (7);
  }
  while (down_1);
  create_syntax_table ("comptrans");
  dfa_define_highlight_rule ("^·$", "keyword", "comptrans");
  dfa_build_highlight_table ("comptrans");
  use_syntax_table ("comptrans");
  use_dfa_syntax (1);
  flush ("type 'q' to close this window");
}

%% Toggle limitation of display to entries containing an expression
%% This will also limit to expressions that cross lines.
define limit_view ()
{
  variable pat, hits, entry_arr, miss, misses, expr = "";

  if (get_blocal_var ("View_Limit") == 0)
    Entry_No = get_current_entry_number ();

  if (get_blocal_var ("View_Limit") == 1)
  {
    mark_buffer ();
    set_region_hidden (0);
    set_blocal_var (0, "View_Limit");
    set_po_status_line ();
    return goto_entry (Entry_No);
  }

  if (markp ())
    expr = bufsubstr ();
  else
    expr = read_mini ("Limit to <regexp>:", expr, "");

  ifnot (strlen (expr))
    return;

  (entry_arr,) = po2arr (buf_as_str ());
  pat = array_map (Int_Type, &string_match, entry_arr, "\\C" + expr, 1);
  hits = where (pat, &misses);

  ifnot (length (hits))
    return flush ("no entries match \"$expr\""$);

  ifnot (length (misses))
    return flush ("all entries match \"$expr\""$);

  foreach miss (misses)
  {
    bob ();
    loop (miss+1)
    {
      () = bol_fsearch ("msgid ");
      eol ();
    }
    find_entry_delim_beg ();
    push_visible_mark ();
    find_entry_delim_end ();
    go_left_1 ();
    set_region_hidden (1);
  }

  push_mark,eob ();
  set_region_hidden (1);
  set_blocal_var (1, "View_Limit");
  set_status_line (sprintf ("(PO) Limit: %d entries matching \"%s\" ('l' unlimits)", length (hits), expr), 0);
  bob ();
  flush ("Limit view is active, type 'l' to unlimit");
}

%}}}
%{{{ menu

private define po_menu (menu)
{
  menu_append_popup (menu, "&Navigate");
  $0 = menu + ".&Navigate";
  {
    menu_append_item ($0, "Next Entry", "po_next_entry");
    menu_append_item ($0, "Previous Entry", "po_previous_entry");
    menu_append_item ($0, "Any Next Unfinished", "any_next_unfinished");
    menu_append_item ($0, "Next Untranslated", "find_msgstr (1, 0)");
    menu_append_item ($0, "Previous Untranslated", "find_msgstr (-1, 0)");
    menu_append_item ($0, "Next Translated", "find_msgstr (1, 1)");
    menu_append_item ($0, "Previous Translated", "find_msgstr (-1, 1)");
    menu_append_item ($0, "Next Fuzzy", "find_fuzzy");
    menu_append_item ($0, "Previous Fuzzy", "bfind_fuzzy");
    menu_append_item ($0, "Next Obsolete", "find_obsolete");
    menu_append_item ($0, "Next Translator Comment", "find_translator_comment");
    menu_append_item ($0, "Go to Entry Number", "goto_entry (-1)");
    menu_append_item ($0, "Show Current Entry Number", "show_current_entry_number");
    menu_append_item ($0, "Top Justify Entry", "top_justify_entry");
  }
  menu_append_popup (menu, "&Modify");
  $1 = menu + ".&Modify";
  {
    menu_append_item ($1, "Undo",  "po_undo");
    menu_append_item ($1, "Edit Msgstr", "po_edit");
    menu_append_item ($1, "Replace Headers", "replace_headers (1)");
    menu_append_item ($1, "Copy Msgstr", "copy_msgstr");
    menu_append_item ($1, "Insert Msgstr", "insert_msgstr");
    menu_append_item ($1, "Copy Msgid To Msgstr", "copy_msgid_to_msgstr");
    menu_append_item ($1, "Cut Msgstr", "cut_msgstr");
    menu_append_item ($1, "Flag Entry As Fuzzy", "fuzzy_entry ()");
    menu_append_item ($1, "Flag All Entries Fuzzy", "flag_fuzzy_all");
    menu_append_item ($1, "Remove Fuzzy Flag", "remove_fuzzy_flag");
    menu_append_item ($1, "Delete Obsolete Entries", "del_obsolete_entries");
    menu_append_item ($1, "Edit Comment", "edit_comment");
    menu_append_item ($1, "Delete Comment", "del_translator_comment");
    menu_append_item ($1, "Edit Entire File", "exit_po_mode");
    menu_append_item ($1, "Interactive Spell Check", "spellcheck");
    menu_append_item ($1, "List and Correct Mispelled Words", "spellcheck_from_list");
    menu_append_item ($1, "Replace in Msgstrs", "replace_in_msgstrs (Null_String, Null_String, 1)");
    menu_append_item ($1, "Replace From List", "replace_from_list");
    menu_append_item ($1, "Translate w/Apertium", "apertium");
    menu_append_item ($1, "Update Untranslated w/Apertium", "apertium_update (0)");
    menu_append_item ($1, "Update Untranslated/Use Fuzzy w/Apertium", "apertium_update (1)");
  }
  menu_append_popup (menu, "&Gettext functions");
  $2 = menu + ".&Gettext functions";
  {
    menu_append_item ($2, "Compile *.po -> *.mo", "po_compile");
    menu_append_item ($2, "Decompile *.mo -> *.po", "po_decompile");
    menu_append_item ($2, "Validate", "po_validate_command");
    menu_append_item ($2, "Update", "po_update");
    menu_append_item ($2, "Toggle wrap", "toggle_wrap");
  }
  menu_append_popup (menu, "&Compendiums and Wordlists");
  $3 = menu + ".&Compendiums and Wordlists";
  {
    menu_append_item ($3, "Add Buffer To Compendium(s)", "add_buffer_to_compendium");
    menu_append_item ($3, "Add Dir to Compendium(s)", "add_dir_to_compendium");
    menu_append_item ($3, "Initialize w/Compendium(s)", "init_with_compendium");
    menu_append_item ($3, "Fill Trans From Gettext Compendium (exact match)", "copy_trans_from_comp");
    menu_append_item ($3, "Copy Entry to Compendium", "copy_entry_to_compendium");
    menu_append_item ($3, "Set Compendium", "set_compendium");
    menu_append_item ($3, "Edit Compendium", "edit_compendium");
    menu_append_item ($3, "Look up word in wordlist", "lookup_word");
  }
  menu_append_item (menu, "Show Help",  "show_help");
  menu_append_item (menu, "Statistics", "show_po_statistics");
  menu_append_item (menu, "Set Source Path", "set_source_path");
  menu_append_item (menu, "View Source Reference", "view_source");
  menu_append_item (menu, "Grep In Source Directory", "grep_src");
  menu_append_item (menu, "Compare Translation To Others", "compare_translations");
  menu_append_item (menu, "Parse Cosmetic Errors", "parse_cosmetic_errors");
  menu_append_item (menu, "Toggle Limited View", "limit_view");
  menu_append_item (menu, "Write Diff", "po_diff");
  menu_append_item (menu, "Check In File w/RCS", "check_in_file");
  menu_append_item (menu, "Check Out File w/RCS", "checkout_rcs_file (1)");
  menu_append_item (menu, "Count Words & Characters", "count_words_and_chars");
  menu_append_item (menu, "Count Occurences of Words", "word_stats");
  menu_append_item (menu, "Send Bug Report", "reportbug");
  menu_append_item (menu, "Show Version and Licence", "show_version_and_licence_info");
}

private define po_edit_menu (menu)
{
  menu_append_item (menu, "Finish Editing",         "po_end_edit");
  menu_append_item (menu, "Discard Changes",        "del_editbuf");
}

%}}}
%{{{ mode definitions

%% Environment for the editing buffer.
private define po_edit_mode ()
{
  set_abbrev_mode (1);
  if (abbrev_table_p (Edit_Mode)) use_abbrev_table (Edit_Mode);
  mode_set_mode_info (Edit_Mode, "init_mode_menu", &po_edit_menu);
  set_buffer_modified_flag (0);
  set_buffer_undo (1);
  use_keymap (Edit_Mode);
  run_mode_hooks ("po_edit_mode_hook");
  set_buffer_hook ("wrap_hook", &po_edit_wrap_hook);
}

private define create_edit_buf ()
{
  Po_Buf = whatbuf ();
  if (bufferp (Edit_Buf))
    return;
  setbuf (Edit_Buf);
  po_edit_mode ();
  setbuf (Po_Buf);
}

% The major mode
public define po_mode ()
{
  no_mode ();
  set_mode (Mode, 0);
  use_keymap (Mode);
  use_syntax_table (Mode);
  use_dfa_syntax (1);
  mode_set_mode_info (Mode, "init_mode_menu", &po_menu);
  create_blocal_var ("View_Limit");
  set_blocal_var (0, "View_Limit");
  % parse_blank_lines ();

  if (eobp () and bobp ())
    insert_po_header ();

  set_readonly (1);
  create_edit_buf ();
  set_buffer_modified_flag (0);
  po_statistics ();
  set_buffer_hook("mouse_2click", &po_mouse_2click_hook ());
  run_mode_hooks ("po_mode_hook");
  flush ("F10 -> Mode, gives you access to menu functions. Type '?' for help");
}

add_to_hook ("_jed_find_file_after_hooks", &conv_charset);

%}}}
%{{{ po_edit, po_end_edit

% Setup the editing environment for the translation
define po_edit ()
{
  variable msgid, msgstr, msgstr_kw;

  Entry = hash_entry ();
  Buf = whatbuf ();

  ifnot (bufferp (Edit_Buf))
    create_edit_buf ();

  (,, msgid, msgstr) = return_str_pair ();
  Multi_Line = str_is_multiline (msgid);

  ifnot (strlen (msgid))
    throw UsageError, "not on a valid entry";

  (Last_Edited, Msgstr) = prep_str (msgstr);
  (, msgid) = prep_str (msgid);
  setup_win_layout (Msgid_Buf, msgid, Edit_Buf, Msgstr);
  setbuf (Msgid_Buf);
  setbuf (Edit_Buf);

  if (bobp () && eobp ())
    Translation_Status = 0;
  else
    Translation_Status = 1;
}

%% This function is run after finishing the translation
define po_end_edit ()
{
  variable msgstr, status = 0;

  if (eobp () && bobp () && 0 == Translation_Status)
    return cancel_edit ();

  if (eobp () && bobp () && 1 == Translation_Status)
    status = -1;
  if (not (eobp () && bobp ()) && 0 == Translation_Status)
    status = 1;

  mark_buffer ();
  msgstr = bufsubstr_delete ();

  if (msgstr == Msgstr) % msgstr not modified
    return cancel_edit ();

  msgstr = post_prep_str (msgstr);
  replace_elem (Entry, Last_Edited, concat_kw_str (Last_Edited, msgstr));
  cancel_edit ();

  if (status == -1)
  {
    count ("t-");
    count ("u+");
  }
  if (status == 1)
  {
    count ("t+");
    if (count ("u") > 0) count ("u-");
  }

  sw2buf (Buf);
  replace_entry (assemble_entry (Entry));
}

%}}}
%{{{ keymaps

ifnot (keymap_p ("po_comment"))
{
  make_keymap ("po_comment");
  definekey ("finish_comment", "\t", "po_comment");
  definekey_reserved ("finish_comment", "^C", "po_comment");
  definekey_reserved ("cancel_edit", "^K", "po_comment");
}

ifnot (keymap_p (Mode))
{
  make_keymap (Mode);
  definekey ("copy_entry_to_compendium", "+", Mode);
  definekey ("copy_trans_from_comp", "/", Mode);
  definekey ("lookup_word", "d", Mode);
  definekey ("po_decompile", "C", Mode);
  definekey ("find_translator_comment", "\e#", Mode);
  definekey ("apertium", "A", Mode);
  definekey ("show_current_entry_number", "@", Mode);
  definekey ("top_justify_entry", ".", Mode);
  definekey ("po_undo", "_", Mode);
  definekey ("edit_comment", "#", Mode);
  definekey ("show_po_statistics", "=", Mode);
  definekey ("show_help", "?", Mode);
  definekey ("find_fuzzy", "f", Mode);
  definekey ("bfind_fuzzy", "F", Mode);
  definekey ("goto_entry (-1)", "g", Mode);
  definekey ("grep_src", "G", Mode);
  definekey ("count_words_and_chars", "I", Mode);
  definekey ("limit_view", "l", Mode);
  definekey ("compare_translations", "m", Mode);
  definekey ("po_next_entry", "n", Mode);
  definekey ("any_next_unfinished", " ", Mode);
  definekey ("po_previous_entry", "p", Mode);
  definekey ("po_compile", "c", Mode);
  definekey ("copy_msgstr", "w", Mode);
  definekey ("insert_msgstr", "y", Mode);
  definekey ("po_diff", "D", Mode);
  definekey ("exit_po_mode", "E", Mode);
  definekey ("replace_headers (1)", "H", Mode);
  definekey ("find_obsolete", "o", Mode);
  definekey ("view_source", "s", Mode);
  definekey ("replace_in_msgstrs (Null_String, Null_String, 1)", "R", Mode);
  definekey ("spellcheck_from_list", "L", Mode);
  definekey ("set_source_path", "S", Mode);
  definekey ("find_msgstr (1, 1)", "t", Mode);
  definekey ("find_msgstr (-1, 1)", "T", Mode);
  definekey ("find_msgstr (1, 0)", "u", Mode);
  definekey ("find_msgstr (-1, 0)", "U", Mode);
  definekey ("po_validate_command", "V", Mode);
  definekey ("po_edit", "\t", Mode); % tab
  definekey ("po_edit", "^M", Mode); % enter
  definekey ("fuzzy_entry ()", Key_BS, Mode); % backspace
  definekey ("remove_fuzzy_flag", Key_Alt_BS, Mode);
  definekey ("copy_msgid_to_msgstr", "\e^m", Mode);
  definekey ("toggle_wrap", "\\", Mode);
  definekey_reserved ("check_in_file", "i", Mode);
  definekey_reserved ("checkout_rcs_file (1)", "o", Mode);
  definekey_reserved ("set_compendium", "p", Mode);
  definekey_reserved ("init_with_compendium", "c", Mode);
  definekey_reserved ("edit_compendium", "E", Mode);
  definekey_reserved ("add_buffer_to_compendium", "a", Mode);
  definekey_reserved ("apertium_update (0)", "A", Mode);
  definekey_reserved ("apertium_update (1)", "F", Mode);
  definekey_reserved ("add_dir_to_compendium", "d", Mode);
  definekey_reserved ("del_translator_comment", "#", Mode);
  definekey_reserved ("parse_cosmetic_errors", ".", Mode);
  definekey_reserved ("cut_msgstr", "k", Mode);
  definekey_reserved ("replace_from_list", "l", Mode);
  definekey_reserved ("spellcheck", "s", Mode);
  definekey_reserved ("word_stats", "t", Mode);
  definekey_reserved ("conv_charset", "e", Mode);
  definekey_reserved ("flag_fuzzy_all", "z", Mode);
  definekey_reserved ("show_version_and_licence_info", "v", Mode);
  definekey_reserved ("po_update", "u", Mode);
  definekey_reserved ("del_obsolete_entries", "O", Mode);
}

ifnot (keymap_p ("Po_Edit"))
{
  make_keymap ("Po_Edit");
  definekey ("cancel_edit", "^c^k", Edit_Mode); % emacs-like
  definekey ("po_end_edit", "^c^c", Edit_Mode); % emacs-like
  definekey ("po_end_edit", "\t", Edit_Mode);
}

%}}}

provide (Mode);
