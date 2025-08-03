% -*- mode: slang; mode: fold; -*-
%{{{ Description, license, etc
% tabcomplete.sl -- a word or "snippet" completion function with an
% additional possible help, mini help and apropos interface.
%
% Version 0.9.8.5 2025/08/03
%
% Author : Morten Bo Johansen <mortenbo at hotmail dot com>
% License: http://www.fsf.org/copyleft/gpl.html
%
% Thanks to John E. Davis for some substantial speed increases in
% hashing completion files, as well as some other improvements and
% corrections
%
%                        *** INSTALLATION ***
%
% Copy this file to a directory in your jed library path, usually
% /usr/share/jed/lib or /usr/local/share/jed/lib
% Add this line to your ~/.jedrc:
%
%   autoload ("init_tabcomplete", "tabcomplete");
%
% For the rest, please read the supplied README.tabcomplete
%
%                     *** BEGIN CUSTOMIZATION ***
%
%}}}
%{{{ Custom variables
% Use the help interface or not
custom_variable ("Tabcomplete_Use_Help", 1);

% Set this to '0' to avoid having the help line shown in the
% minibuffer upon final completion.
custom_variable ("Show_Help_Upon_Completion", 0);

% The completion key. Default is TAB
custom_variable ("Completion_Key", "\t");

% What characters may constitute a word
custom_variable ("Wordchars", "\\w");

% What other characters may constitute a word?
custom_variable ("Extended_Wordchars", "");

% Insert completion word itself or not
custom_variable ("Insert_Completion_Word", 1);

% The delimiter for expanding newlines in aliases and syntaxes
custom_variable ("Newl_Delim", "\\n");

% The completion interface: 0 = at editing point or 1 = with menu
custom_variable ("Use_Completion_Menu", 0);

% Should there be a space between function name and opening parenthesis?
% E.g. strtok () vs. strtok(). Looping or conditional keywords will
% always have a space.
custom_variable ("Sep_Fun_Par_With_Space", 1);

% If set to '1', completion will be enabled at the minibuffer's
% S-Lang> cli prompt
custom_variable ("SLang_Completion_In_Minibuffer", 0);

% Limit completion candidates to words of sizes greater than or
% equal to value.
custom_variable ("Minimum_Completion_Word_Size", 2);

% By typing one of the characters, '(', '[', or '"' will insert "()", "[]"
% and '""' into the buffer and place the editing point between the
% two characters. Set to '1' to enable.
custom_variable ("Tabcomplete_Compl_Delims", 0);

% When matching the letters before the editing point to the possible
% completion candidates, should the matching be case insensitive?
% Set to '1' to enable.
custom_variable ("Match_Is_Case_Insensitive", 0);

%}}}
%{{{ Autoloads and evalfiles
% In Debian, require.sl is in a separate package, slsh, which the user
% may not have installed, so use evalfile () instead.
ifnot (is_defined ("Key_F1"))
 () = evalfile ("keydefs");
%}}}
%{{{ Variables
private variable
  Loop_Cond_Kws = ["loop","forever","while","define","if","ifnot","!if",
                   "do","foreach","for","_for","switch"],
  Completions_File = "",
  mini_hlpfun = NULL,
  hlpfun = NULL,
  F = NULL;

public variable Words;

%}}}
%{{{ Private functions
private define tabcomplete_fit_window()
{
  variable win_nlines, endline_pos, nlines_diff;

  win_nlines = window_info('r');
  eob(); bskip_white();
  endline_pos = what_line();
  nlines_diff = win_nlines-endline_pos;
  otherwindow();

  loop(nlines_diff)
    enlargewin();

  otherwindow; bob();
}

% contributed by Guenter Milde, fixed by cpbotha@debian.org
private define indent_region_or_line ()
{
  ifnot (is_visible_mark)
    indent_line;
  else
  {
    check_region (1);                  % make sure the mark comes first
    variable End_Line = what_line - 1;
    exchange_point_and_mark();         % now point is at start of region

    do
    {
      indent_line;
    }
    while (what_line <= End_Line and down_1);

    pop_spot();
    pop_mark_0();
  }
}

% What mode are we in
private define detect_mode ()
{
  return (strlow (what_mode (), pop ()));
}

% Return the word under or before the cursor.
private define get_word ()
{
  variable wchars = Wordchars + Extended_Wordchars;

  if (blocal_var_exists("Wordchars") && blocal_var_exists("Extended_Wordchars"))
    wchars = get_blocal_var ("Extended_Wordchars") + get_blocal_var ("Wordchars");

  push_spot ();
  bskip_chars (wchars); push_mark (); skip_chars (wchars);
  strtrim (bufsubstr ());
  pop_spot ();
}

% Return a key press as a string
define get_keystr (delay)
{
  variable s = char (getkey());

  while (input_pending (delay))
    s += char (getkey ());

  return s;
}

% Use a string delimiter instead of a character delimiter to chop up a
% string - from a JED post on jed-users
private define strchop2 (str, delim)
{
  variable list = {};
  variable len = strbytelen (delim);
  variable i0 = 1, i;

  while (i = is_substrbytes (str, delim, i0), i != 0)
  {
    list_append (list, substrbytes (str, i0, i-i0));
    i0 = i + len;
  }

  list_append (list, substrbytes (str, i0, -1));
  return list_to_array (list);
}

% Like fgetslines () but also strips newline characters (JED).
private define read_file_lines (file)
{
  file = expand_filename(file);

  variable st = stat_file (file);
  if (st == NULL) return NULL;
  variable bytes;
  () = fread_bytes (&bytes, st.st_size, fopen (file, "r"));
  return strtok (bytes, "\n");
}

% Return if a line matches a regular expression
private define re_line_match (pat, trim)
{
  push_spot ();
  variable line = line_as_string ();

  if (trim)
    line = strtrim (line);

  string_match (line, pat, 1);
  pop_spot ();
}

% Count the number of case insensitive occurrences of a string.
private define count_strings(str, expr)
{
  variable len, matches_n = 0, pos = 1;
  while (string_match(str, "\\C$expr"$, pos))
  {
    (pos, len) = string_match_nth(0);
    pos += len + 1;
    matches_n++;
  }

  return matches_n;
}

% Balance the left and right delimiters, [ ] ( ) { }, by inserting or
% deleting ']', ')' or '}' before the editing point.
private define align_delims ()
{
  variable rval, delim;

  ifnot (isspace(what_char())) return;

  forever
  {
    push_spot(); go_left_1();
    delim = what_char();

    ifnot (any(delim == [')','}',']'])) return pop_spot();

    rval = find_matching_delimiter(delim);
    pop_spot();

    if (rval == 1)
      insert_char(delim);
    else
      return call("backward_delete_char_untabify");

    flush("right and left delimiters balanced");
  }
}

% Delete buffers with a name that matches an expression
private define kill_buffers_by_expr (expr)
{
  variable  buffers = [buffer_list (), pop];

  buffers = buffers[where (array_map (Int_Type, &is_substr, buffers, expr))];

  if (length (buffers))
    array_map (Void_Type, &delbuf, buffers);
}

% Get the remaining part of a word where "stub" forms its beginning
private define get_completion (str, stub)
{
  return str[[strbytelen (stub):]];
}

%% Produce the hash of words to complete from.
%% Note: Words contains all of the words defined in the input files
%% F contains only those words with non-empty values.
%% But, F has been defined such that F[ANYTHING] will produce
%% an array.
private define make_completions_hash (Completions_File)
{
  % In slang_mode, if no completions file, then generate one
  if ((0 == file_status (Completions_File)) && ("slang" == detect_mode ()))
  {
    variable funs = _apropos ("Global", ".", 15);
    Words = funs[array_sort (funs)];
    () = write_string_to_file (strjoin (Words, "\n"), Completions_File);
  }

  variable
    include_files,
    inc_lines,
    lines,
    include_file,
    i = 0, j;

  if ((F == NULL) || length (F)) % purge a possibly existing hash
    F = Assoc_Type[Array_Type, String_Type[0]];

  flush ("hashing $Completions_File ..."$);
  lines = read_file_lines (Completions_File);

  if (lines == NULL)
    throw OpenError, "could not open completions file, $Completions_File"$;

  include_files = lines [where (0 == strncmp ("#INC", lines, 4), &i)]; % include other files
  lines = lines[i];           % don't include #INC lines

  variable lines_list = {lines};
  foreach include_file (include_files)
  {
    include_file = strtok (include_file)[1];
    include_file = strtrim (include_file, "\"");
    lines = read_file_lines (include_file); 
    if (lines == NULL)
    {
      flush ("Could not open \"$include_file\""$);
      sleep (2);
      continue;
    }

    i = where (strncmp (lines, "#", 1));
    if (length (i) != length (lines)) lines = lines [i];
    list_append (lines_list, lines);
  }

  lines = [__push_list(lines_list)];

  foreach i (where (is_substr (lines, ":: "), &j))
  {
    variable line_array = strtrim (strchop2 (lines[i], ":: "));
    variable key = line_array[0];
    F[key] = line_array[[1:]];
    lines[i] = key;
  }

  Words = lines;
  flush ("completing from $Completions_File ..."$);
}

% Return the language_COUNTRY or language part of some locale environment variables
private define get_locale ()
{
  variable locale = "";
  variable locale_values = array_map (String_Type, &getenv, ["LC_MESSAGES","LC_ALL","LANG"]);

  locale_values = locale_values[where (strlen (locale_values) >= 2)]; % filter out "C"

  if (length (locale_values))
  {
    foreach (locale_values)
    {
      variable locale_value = ();

      try
      {
        if (strlen (locale_value[[0:4]]) == 5) % e.g. "de_AT"
          locale = locale_value[[0:4]];
        else if (strlen (locale_value[[0:1]]) == 2) % e,g. "de"
          locale = locale_value[[0:1]];
        else
          continue;
      }
      catch IndexError;
    }
  }

  return locale;
}

private variable Completed_Word = "";

% Insert e.g. a keyword and its syntax, also expanding
% newline escapes in the syntax, if any.
private define insert_and_expand_construct (kw, syntax)
{
  variable exec_fun = 0;

  strchop (syntax, '\n', 0);
  syntax = strtrim ();
  syntax = strjoin (syntax, "\n");

  if (MINIBUFFER_ACTIVE) % no newlines in the minibuffer
    syntax = strreplace (syntax, Newl_Delim, "");
  else
  {
    if (C_BRA_NEWLINE == 0)
    {
      if (is_substr(syntax, "\)$Newl_Delim{"$))
	syntax = strreplace(syntax, "\)$Newl_Delim{"$, "\) {");
    }

    syntax = strreplace (syntax, Newl_Delim, "\n"); % expand newline delimiter in completions file
  }
  

  kw = strtrim (kw);
  smart_set_mark_cmd ();

  if (char(syntax[0]) == "&") % "syntax" is instead a function to be executed
  {
    syntax = strtrim_beg(syntax, "&");
    exec_fun = 1;
  }

  if (kw[-1] == '@' or 0 == Insert_Completion_Word) % alias
  {
    bdelete_word ();
    if (exec_fun) eval(syntax);
    else insert (syntax);
  }
  else
  {
    if (exec_fun)
    {
      pop_mark_0;
      insert ("$kw "$);
      return eval(syntax);
    }
    if (any(Completed_Word == Loop_Cond_Kws) ||
        1 == Sep_Fun_Par_With_Space ||
        0 == is_substr(syntax, "("))
      insert ("$kw $syntax"$);
    else
      insert (strcat (kw, syntax));
  }

  indent_region_or_line ();

  % position the cursor at the "@@" place holder"
  if (is_substr (syntax, "@@"))
  {
    () = re_bsearch ("@@");
    () = replace_match("", 1);
  }
}

private define cmp_fun(a, b)
{
  return strbytelen(a) > strbytelen(b);
}

% If Use_Completion_Menu = 1, format word candidates for completion in
% nicely aligned columns. over at most 20 lines. If there are words
% with multibyte characters, the alignment is alas not 100% correct.
private define format_and_insert_completion_menu(words_arr)
{
  variable i = 0, remainder = 0, cols = 1, words_n = length(words_arr);
  variable col_offset, longest_word, pad_n, rows_n = 20;

  % sort words by size in ascending order.
  words_arr = words_arr[array_sort(words_arr, &cmp_fun)];
  longest_word = words_arr[-1];
  % the space offset between columns
  col_offset = strbytelen(longest_word) + 2;

  % number of completion candidates > 20
  if (words_n > rows_n)
  {
    % the remaining number of words after division between total
    % number of words and number of rows
    remainder = words_n mod rows_n;

    % a positive number of remaining words was returned
    if (remainder > 0)
    {
      % number of paddings needed to equal number of rows
      pad_n = rows_n - remainder;

      % pad words array with empty strings to make its length suitable
      % for reshaping.
      loop (pad_n)
        words_arr = [words_arr, ""];
    }

    % how many columns do we need?
    cols = length(words_arr)/rows_n;

    % create a 2D array with the computed number of columns and 20 rows
    reshape (words_arr, [rows_n, cols]);

    % insert words in whole rows with columns aligned under one
    % another at the designated column offset.
    _for i (0, rows_n-1, 1)
    {
      ifnot (strlen(strtrim(strjoin(words_arr[i, *])))) continue;
      array_map(Void_Type, &vinsert, "%-${col_offset}s"$, words_arr[i, *]);
      insert("\n");
    }
  }
  else % number of completion candidates < 20
    insert(strjoin(words_arr, "\n"));
}

% Sort an array of strings in descending order according to how many
% times a particular word or expression occurs within them.
private define sort_by_relevancy(str_arr, expr)
{
  variable A = Assoc_Type[Int_Type], values, strs_sorted, i = 0;

  % populate the hash with strings to be sorted as the keys and its
  % corresponding number of occurrences of <expr> as the values.
  _for i (0, length(str_arr)-1, 1)
    A[str_arr[i]] = count_strings(str_arr[i], expr);

  values = assoc_get_values(A);
  i = array_sort(values);
  strs_sorted = assoc_get_keys(A)[i];
  array_reverse(strs_sorted);
  return strs_sorted;
}

%}}}
%{{{ User functions

%% Complete the word behind the editing point from words in a file
define tabcomplete ()
{
  variable
    completion_words = [""],
    completions = [""],
    completed_word = "",
    aliases = [""],
    completion = "",
    keystr = "",
    syntax = "",
    stub = "",
    hlp = "",
    i = 0;

  % balance [], (), {}
  if ((blooking_at(")")) || (blooking_at("]")) || (blooking_at("}")))
    return align_delims();

  if (looking_at("\",")) return skip_chars("\",");
  if (looking_at(" =")) return skip_chars(" =");
  if (is_visible_mark()) return indent_region_or_line();

  stub = strtrim (get_word ()); % "stub" is the word before the editing point to be completed

  if (strlen(stub))
  {
    ifnot (re_looking_at("[ \t\n,\)]") || eobp())
      return indent_region_or_line();
  }
  else
    return indent_region_or_line();

  % get all words where stub forms the beginning of the words. Match is case
  % insensitive.
  if (Match_Is_Case_Insensitive)
    completion_words = Words [where (0 == strnbytecmp (strlow(stub), strlow(Words),
						       strbytelen (stub)))];
  else % match is case sensitive,
    completion_words = Words [where (0 == strnbytecmp (stub, Words,
						       strbytelen (stub)))];

  % isolate aliases
  aliases = completion_words[where(array_map(Int_Type, &string_match,
                                             completion_words, "@$", 1))];

  % only return words of sizes greater than or equal to $Minimum_Completion_Word_Size
  completion_words = completion_words[where(array_map(Int_Type, &strlen,
                                            completion_words) >=
                                            Minimum_Completion_Word_Size)];

  % include stub as a completion target if it has a syntax attached,
  % so that syntax can be expanded with space or enter. Otherwise show
  % first completion right away. With a hash that contains both single
  % words as completion targets and completion targets with syntaxes
  % stub will always be a completion target.
  ifnot (length (F))
    completion_words = completion_words [wherenot (completion_words == stub)];

  % get all possible completions
  completions = array_map (String_Type, &get_completion, completion_words, stub);
  completions = completions[array_sort(completions, &cmp_fun)];

  % This pops up a buffer with a menu of all completion candidates if
  % the custom variable, Use_Completion_Menu = 1
  ifnot (MINIBUFFER_ACTIVE)
  {
    if (Use_Completion_Menu)
    {
      variable completed_words, I, entries, buf = whatbuf, mbuf = "***Completions***";

      stub = strtrim (get_word ());
      completed_words = array_map (String_Type, &strcat, stub, completions);

      ifnot (length(completed_words))
	return flush("no completions");
      
      I = array_map (String_Type, &string, [0:length (completed_words)-1]);
      entries = array_map (String_Type, &strcat, I, "|", completed_words);
      pop2buf (mbuf);
      format_and_insert_completion_menu(entries);
      bob ();
      set_buffer_modified_flag (0);
      tabcomplete_fit_window();
      update_sans_update_hook (1);
      most_mode ();
      keystr = get_keystr (6);
      sw2buf (buf);

      if (any (keystr == I))
      {
        Completed_Word = completed_words[integer (keystr)];
        ifnot (Completed_Word[-1] == '@' or 0 == Insert_Completion_Word)
          bdelete_word ();

        if (length (F[Completed_Word]) > 0)
        {
          syntax = F[Completed_Word][0];
          insert_and_expand_construct (Completed_Word, syntax);
        }
        else
          insert(Completed_Word);
      }

      delbuf (mbuf);
      sw2buf (buf);
      return onewindow ();
    }
  }

  % completion at editing point
  if (length (completions))
  {
    buffer_keystring (Completion_Key); % ungetkey for strings

    forever
    {
      if (i == length (completions))
      {
        if (i == 1) % only one possible completion
        {
	  del_region ();
          break;
        }
        else
        {
          ifnot (MINIBUFFER_ACTIVE)
            flush ("no more completions");

          update_sans_update_hook(0);
          i = 0; % restart cycle
        }
      }

      keystr = get_keystr (0);

      if (is_visible_mark())
        del_region ();

      switch (keystr)
      { case Completion_Key: % cycle through the possible completions
        {
          completion = completions[i];
          push_visible_mark ();
          insert (completion);
          update_sans_update_hook (0);
          i++;
        }
      }
      { case Key_BS: return; } % backspace breaks cycle and returns to stub
      { case " " || case "\r" || case "\eOC": break; } % space or enter inserts completion and breaks cycle
      { return insert (completion + keystr);} % all other keys stops and inserts completion + character pressed
    } % forever
  }

  Completed_Word = strcat (stub, completion);

  try
  {
    if (length (F))
    {
      if (length (F[Completed_Word]) > 0)
        syntax = F[Completed_Word][0];
      if (length (F[Completed_Word]) > 1)
        hlp = F[Completed_Word][1];
    }
  }
  catch IndexError;

  if (strlen(syntax))
  {
    if (re_line_match("array_map", 0))
      insert(completion);
    else
      insert_and_expand_construct (completion, syntax);
  }
  else
  {
    if (any(keystr == ["\r","\eOC", Completion_Key]))
      insert (completion);
    else
      insert (completion + keystr);
  }

  completion = "", stub = "", i = 0;

  if (Show_Help_Upon_Completion)
  {
    % in slang_mode if "hyperhelp" is installed, use its minibuffer
    % help message, otherwise show a user specified help line, if any.
    if ("slang" == detect_mode ())
    {
      ifnot (NULL == mini_hlpfun)
      {
        if (is_substr (@mini_hlpfun (completed_word), "Undocumented"))
        {
          if (strlen (hlp))
            return flush (hlp);
        }
        else
          flush (@mini_hlpfun (completed_word));
      }
    }
    else
    {
       % no help message with minibuffer tabcompletion
      ifnot (MINIBUFFER_ACTIVE)
        flush (hlp);
    }
  }
}

define move_down_and_indent ()
{
  if (C_BRA_NEWLINE == 0)
    go_down_1();
  else
    () = down(2);

  call ("indent_line");
}

%% Show the help line in the completions file, if any, for the word
%% near the editing point. If in slang mode and hyperhelp from jedmodes
%% is installed, its help interface will be used.
define show_hlp_for_word_at_point ()
{
  variable hlpmsg = "", word = get_word ();

  ifnot (strlen (word))
    word = read_mini ("Search for:", "", "");

  % If hyperhelp from jedmodes is present, use its help interface else
  % use jed's native interface. If function or word is undocumented
  % instead show user's own help from the completions file if any.
  if ("slang" == detect_mode ())
    return (@hlpfun (word));

  % A lot of C-functions have a manual or info page
  if ("c" == detect_mode())
  {
    if (0 != run_program("info --index-search=$word libc"$))
      if (0 != run_program("man $word 2>/dev/null"$))
	return flush("no help for \"$word\""$);

    return;
  }
  
  if (assoc_key_exists (F, word))
  {
    if (length (F[word]) > 1)
      hlpmsg = F[word][1];

    if (strlen (hlpmsg) >= window_info ('w'))
      {
        kill_buffers_by_expr ("*** Help for ");
        pop2buf ("*** Help for \"$word\" ***"$);
        insert_and_expand_construct(word + " ", hlpmsg);
        tabcomplete_fit_window();
        set_buffer_modified_flag (0);
        most_mode ();
        bob ();
      }
    else
    {
      hlpmsg = strreplace(hlpmsg, Newl_Delim, " ");
      flush (hlpmsg);
    }
  }
}

% Return entries in the completion file that have a search string in
% keyword and/or help text.
define compl_apropos ()
{
  variable
    values = assoc_get_values (F),
    kws = String_Type[0],
    hlp_strs = String_Type[0],
    matches = String_Type[0],
    hlp = "",
    expr = "";

  Completions_File = get_blocal_var ("Completions_File");

  ifnot (any (array_map (Int_Type, &length, values) > 1))
    throw RunTimeError, "$Completions_File contains no help or apropos messages"$;

  if ("slang" == detect_mode ()) return apropos;
  else expr = read_mini ("Apropos:", "", "");

  variable key, val;

  foreach key, val (F)
  {
    try
    {
      hlp = val[1];
      hlp = strreplace (hlp, Newl_Delim, "\n");
    }
    catch IndexError: hlp = "";

    if (string_match (key, "\\C$expr"$, 1))
      kws = [kws, strcat (key, ": ", hlp)];
    else if (string_match (hlp, "\\C$expr"$, 1))
      hlp_strs = [hlp_strs, strcat (key, ": ", hlp)];
  }

  % Matching of the search string is performed on both the keyword and
  % the help string (if any). Matches are sorted such that if the
  % keyword contains the search string, it is listed first. Matches
  % where the search string is contained in the help string are then
  % sorted by relevancy, which in this context means by the number of
  % occurrences of the search string within the help strings. Matching
  % is case insensitive.
  hlp_strs = sort_by_relevancy(hlp_strs, expr);
  matches = [matches, kws, hlp_strs];

  ifnot (length (matches))
    return flush ("nothing relevant found for \"$expr\""$);

  matches = strjoin(matches, " \n\n--------------------------------------------------------------------------\n\n");
  kill_buffers_by_expr ("*** Apropos");
  pop2buf ("*** Apropos \"$str\" ***"$);
  insert (matches);
  onewindow;
  local_setkey ("show_hlp_for_word_at_point", "^M");
  set_buffer_modified_flag (0);
  most_mode ();
  bob ();
  flush("Type 'q' to quit");
}

% Select a new file with completions
define select_completions_file ()
{
  ifnot (_NARGS)
    Completions_File = read_with_completion ("Completions File:", "", "", 'f');
  else
    Completions_File = ();

  if (0 == file_status (Completions_File))
    throw OpenError, "could not open $Completions_File"$;

  F = Assoc_Type[Array_Type, String_Type[0]];  % purge the old hash
  init_tabcomplete (Completions_File);
  Words = get_blocal_var ("Words");
}

% Add a word to completions file
define append_word_to_completions_file ()
{
  variable word = "";

  if (markp ())
    word = bufsubstr ();
  else
    word = get_word ();

  ifnot (strlen (word)) return;

  if (length (where (get_blocal_var ("Words") == strlow (word))))
    return flush (sprintf ("\"%s\" already exists in %s", word, get_blocal_var ("Completions_File")));

  if (get_y_or_n(sprintf("add \"%s\" to %s", word, get_blocal_var ("Completions_File"))))
  {
    ifnot (-1 == append_string_to_file (word, get_blocal_var ("Completions_File")))
    {
      Words = [Words, word];
      update_sans_update_hook (1);
      call ("redraw");
      flush ("\"$word\" written to $Completions_File"$);
    }
    else
      throw WriteError, "could not append \"$word\"to $Completions_File"$;
  }
}

private variable Wordchars_Old = get_word_chars ();

% This ensures that characters that define a word is local to the
% buffer and that the arrays of words to complete from are also
% local to the buffer.
private define tabcomplete_switch_buffer_hook (old_buffer)
{
  if (blocal_var_exists ("Completions_File"))
    Completions_File = get_blocal_var ("Completions_File");

  if (blocal_var_exists ("Use_Completion_Menu"))
    Use_Completion_Menu = get_blocal_var ("Use_Completion_Menu");

  if (blocal_var_exists ("Wordchars") && blocal_var_exists ("Extended_Wordchars"))
    define_word (get_blocal_var ("Extended_Wordchars") + get_blocal_var ("Wordchars"));
  else
    define_word (Wordchars_Old);

  if (blocal_var_exists ("Words"))
    Words = get_blocal_var ("Words");
  if (blocal_var_exists ("F"))
    F = get_blocal_var ("F");
}
add_to_hook ("_jed_switch_active_buffer_hooks", &tabcomplete_switch_buffer_hook);

% Return a key (sequence) bound to the "evaluate_cmd" function.
define get_evaluate_cmd_key()
{
  variable n, key;

  n = which_key("evaluate_cmd");

  if (n == 0) return "^X\e"; % the default from emacs.sl

  loop (n)
    key = ();

  return key;
}

% This is a stand-in for the S-Lang> cli prompt to allow for
% SLang/Jed completions at said prompt.
define slang_mini_completion()
{
  variable fun;
  variable words = get_blocal_var ("Words"); % completion target words from calling buffer
  variable f = get_blocal_var ("F"); % associated fields to completion target words
  variable buf = whatbuf();
  variable wordchars = get_blocal_var("Wordchars") + get_blocal_var("Extended_Wordchars");
  variable newl_delim = Newl_Delim;

  make_completions_hash(expand_filename("~/.tabcomplete_slang"));
  Wordchars = "-a-zA-Z0-9!#;@_$";
  Newl_Delim = "\\n";
  undefinekey(Completion_Key, "Mini_Map");
  definekey("tabcomplete", Completion_Key, "Mini_Map");

#ifexists mini_isearch
  definekey ("mini_isearch", "^r","Mini_Map");
#endif

  try
  {
    fun = read_mini("S-Lang>", "", "");
    eval(fun);
  }
  finally
  {
    Words = words; % reset completion target words to those of calling buffer
    F = f; % ditto with their associated fields
    Wordchars = wordchars;
    Newl_Delim = newl_delim;

    % make sure that alt-x completions work again.
    undefinekey(Completion_Key, "Mini_Map");
    definekey("mini_complete", Completion_Key, "Mini_Map");
  }
}

% '"' inserts "", '(' inserts (), '[' inserts [] and places the
% editing point between the pair of characters.
define compl_delim_pair(delim)
{
  ifnot (any(what_char() == [']',')',',',';']) || eolp())
    return insert(delim);

  switch (delim)
  { case "\"": insert("\"\""); }
  { case "(": insert("\(\)"); }
  { case "[": insert("[]"); }

  go_left_1();
}

private variable Completions_Files = String_Type[0];

define init_tabcomplete ()
{
  variable locale = get_locale ();

  ifnot (_NARGS)
  {
    % the default completions file
    Completions_File = expand_filename (sprintf ("~/.tabcomplete_%s", detect_mode));

    ifnot (1 == file_status (Completions_File))
    {
      if (strlen (locale))
      {
        Completions_File = expand_filename (sprintf ("~/.tabcomplete_%s", locale));

        ifnot (1 == file_status (Completions_File))
          Completions_File = expand_filename (sprintf ("~/.tabcomplete_%s", locale[[0:1]]));
      }
    }
  }
  else
    Completions_File = ();

  ifnot (1 == file_status (Completions_File))
    throw OpenError, "could not open $Completions_File"$;

  ifnot (blocal_var_exists("Completions_File"))
    define_blocal_var ("Completions_File", Completions_File);

  ifnot (blocal_var_exists("Wordchars"))
    define_blocal_var ("Wordchars", Wordchars);

  ifnot (blocal_var_exists("Extended_Wordchars"))
    define_blocal_var ("Extended_Wordchars", Extended_Wordchars);

  ifnot (blocal_var_exists("Use_Completion_Menu"))
    define_blocal_var ("Use_Completion_Menu", Use_Completion_Menu);

  define_word (get_blocal_var ("Extended_Wordchars") + get_blocal_var ("Wordchars"));

% show help or mini help from function in hyperhelp from jedmodes
#ifexists help->get_mini_help
  {
    mini_hlpfun = &help->get_mini_help;
    hlpfun = &describe_function;
  }
% jed's native help interface
#else
  hlpfun = &help_for_function;
#endif

  % In the same jed session, don't hash again if no change in
  % completions file when opening a new buffer.
  ifnot (any (Completions_File == Completions_Files))
    make_completions_hash (Completions_File);

  ifnot (blocal_var_exists("Words"))
    define_blocal_var ("Words", Words);

  ifnot (blocal_var_exists("F"))
    define_blocal_var ("F", F);

  Completions_Files = [Completions_Files, Completions_File];

  local_unsetkey(Completion_Key);
  local_setkey("tabcomplete", Completion_Key);
  local_unsetkey_reserved("c");
  local_unsetkey_reserved("w");
  local_setkey_reserved("select_completions_file", "c");
  local_setkey_reserved("append_word_to_completions_file", "w");

  if ("slang" == detect_mode() || "c" == detect_mode())
  {
    local_unsetkey(Key_Shift_Tab);
    local_setkey("move_down_and_indent", Key_Shift_Tab);
  }

  if (Tabcomplete_Use_Help)
  {
    local_unsetkey(Key_F1);
    local_unsetkey(Key_F2);
    local_setkey("show_hlp_for_word_at_point", Key_F1);
    local_setkey("compl_apropos", Key_F2);
  }

  if (Tabcomplete_Compl_Delims)
  {
    local_unsetkey("(");
    local_setkey("compl_delim_pair(\"\(\")", "(");
    local_unsetkey("[");
    local_setkey("compl_delim_pair(\"[\")", "[");
    local_unsetkey("\"");
    local_setkey("compl_delim_pair(\"\\\"\")", "\"");
  }
  
  if (SLang_Completion_In_Minibuffer)
  {
    local_unsetkey(get_evaluate_cmd_key());
    local_setkey("slang_mini_completion", get_evaluate_cmd_key());
  }

  Extended_Wordchars += "@"; % so aliases always work
}
%}}}
