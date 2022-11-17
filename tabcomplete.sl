% -*- mode: slang; mode: fold; -*-
%{{{ Description, license, etc
% tabcomplete.sl -- a word or "snippet" completion function with an
% additional possible help, mini help and apropos interface.
%
% Version 0.8.4 2023/11/17
%
% Author : Morten Bo Johansen <mbj@mbjnet.dk>
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
custom_variable ("Show_Help_Upon_Completion", 1);

% The completion key. Default is TAB
custom_variable ("Completion_Key", "\t");

% What characters may constitute a word
% custom_variable ("Wordchars", "");
custom_variable ("Wordchars", "\a"R);

% What other characters may constitute a word?
custom_variable ("Extended_Wordchars", "._#<>");

% Insert completion word itself or not
custom_variable ("Insert_Completion_Word", 1);

% The delimiter for expanding newlines in aliases and syntaxes
custom_variable ("Newl_Delim", "\\n");

% The completion interface: 0 = at editing point or 1 = with menu
custom_variable ("Use_Completion_Menu", 0);

% Should there be a space between function name and opening paranthesis?
% E.g. strtok () vs. strtok(). Looping or conditional keywords will
% always have a space. The julia language will not accept spaces.
custom_variable ("Sep_Fun_Par_With_Space", 0);
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

% What mode are we in
private define detect_mode ()
{
  return (strlow (what_mode (), pop ()));
}

% Return the word under or before the cursor.
private define get_word ()
{
  variable wchars = "\a"R + Extended_Wordchars;

  if (blocal_var_exists("Wordchars") && blocal_var_exists("Extended_Wordchars"))
    wchars = get_blocal_var ("Extended_Wordchars") + get_blocal_var ("Wordchars");

	push_spot ();
	bskip_chars (wchars); push_mark (); skip_chars (wchars);
  strtrim (bufsubstr ());
  pop_spot ();
}

% Return a keypress as a string
define get_keystr (delay)
{
  variable s = char (getkey());

  while (input_pending (delay))
    s += char (getkey ());

  return s;
}

% Indent a marked region according to the mode rules
private define indent_region ()
{
  variable region_beg, region_end;

  check_region (1);
  region_end = what_line ();
  exchange_point_and_mark ();
  region_beg = what_line ();
  pop_mark_0;
  goto_line (region_beg);

  do
    call ("indent_line");
  while (down (1) && what_line <= region_end);

  pop_spot ();
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

% Detect a mismatch in number of left and right paranthesises
private define n_paranth_mismatch ()
{
  variable str = "", a, nleft, nright;

  push_spot(); str = line_as_string (); pop_spot();
  a = Char_Type [strlen (str)];
  init_char_array (a, str);
  nleft = length (where (a == '('));
  nright = length (where (a == ')'));

  if (nleft > nright)
    return nleft-nright;
  if (nright > nleft)
    return nleft-nright;
  return 0;
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

private define align_parens ()
{
  if (n_paranth_mismatch > 0)
  {
    loop (n_paranth_mismatch)
      return insert (")");
  }
  if (n_paranth_mismatch < 0)
  {
    loop (-n_paranth_mismatch)
    {
      go_left_1 ();
      del ();
    }
  }
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
  lines = lines[i];		       % don't include #INC lines

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

  foreach i (where (is_substr (lines, "::"), &j))
  {
    variable line_array = strtrim (strchop2 (lines[i], "::"));
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
  strchop (syntax, '\n', 0);
  syntax = strtrim ();
  syntax = strjoin (syntax, "\n");
  syntax = strreplace (syntax, Newl_Delim, "\n"); % expand newline delimiter in completions file
  kw = strtrim (kw);

  smart_set_mark_cmd ();

  if (kw[-1] == '@' or 0 == Insert_Completion_Word) % alias
  {
    bdelete_word ();
    insert (syntax);
  }
  else
  {
    if (any(Completed_Word == Loop_Cond_Kws) || Sep_Fun_Par_With_Space)
      insert (strcat (kw, " ",syntax));
    else
      insert (strcat (kw, syntax));
  }

  indent_region ();

  % position the cursor at the "@@" place holder"
  if (is_substr (syntax, "@@"))
  {
    () = re_bsearch ("@@");
    () = replace_match("", 1);
  }
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
    completion = "",
    keystr = "",
    syntax = "",
    stub = "",
    hlp = "",
    i = 0;

  if (blooking_at(")"))
    return align_parens();

  stub = strtrim (get_word ()); % "stub" is the word before the editing point to be completed

  if (1 == re_line_match ("^$", 1) ||
      0 == strlen (stub) ||
      markp() ||
      re_looking_at (sprintf ("[%s]", get_word_chars ())))
    return call("indent_line");

  % get all words where stub forms the beginning of the words
  completion_words = Words [where (0 == strnbytecmp (stub, Words, strbytelen (stub)))];

  % include stub as a completion target if it has a syntax attached,
  % so that syntax can be expanded with space or enter. Otherwise show
  % first completion right away. With a hash that contains both single
  % words as completion targets and completion targets with syntaxes
  % stub will always be a completion target.
  ifnot (length (F))
    completion_words = completion_words [wherenot (completion_words == stub)];

  completions = array_map (String_Type, &get_completion, completion_words, stub); % get all possible completions
  completions = completions[array_sort (strlen (completions))];

  % This pops up a buffer with a menu of all completions
	if (Use_Completion_Menu)
	{
		variable completed_words, I, menu, buf = whatbuf, mbuf = "***Completions***";

		stub = strtrim (get_word ());
		completed_words = array_map (String_Type, &strcat, stub, completions);
		I = array_map (String_Type, &string, [0:length (completed_words)-1]);
		menu = array_map (String_Type, &strcat, I, "|", completed_words);
		pop2buf (mbuf);
		insert (strjoin (menu, ",\n"));
		bob ();
		call ("format_paragraph");
		set_buffer_modified_flag (0);
    tabcomplete_fit_window();
		update_sans_update_hook (1);
		most_mode ();
		keystr = get_keystr (7);
		sw2buf (buf);

		if (any (keystr == I))
		{
			bdelete_word ();
			insert (completed_words[integer (keystr)]);
		}

		delbuf (mbuf);
		sw2buf (buf);
		return onewindow ();
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
					flush ("no more completions");
					i = 0; % restart cycle
				}
      }

      if (markp ())
        del_region ();

      keystr = get_keystr (0);

      % a little hack to prevent the byte strings emitted from hitting
      % some of the arrow keys from being inserted into the buffer
      if (any(keystr == ["OA","OB","OD"]))
        keystr = "";

      % right arrow key will now just insert the completion
      if (keystr == "OC")
        keystr = " ";

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
      { case " " || case "\r": break; } % space or enter inserts completion and break cycle
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
    if ("slang" == detect_mode () && re_line_match ("array_map", 0))
    {
      insert(completion);
      go_right_1();
    }
    else
      insert_and_expand_construct (completion, syntax);
  }
  else
  {
    if (keystr == "\r" or keystr == "	")
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
      flush (hlp);
  }
}

define move_down_2_and_indent ()
{
  () = down (2);
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

  if (assoc_key_exists (F, word))
  {
    if (length (F[word]) > 1)
      hlpmsg = F[word][1];
    else
      return flush ("no help for \"$word\""$);

    if (strlen (hlpmsg) >= window_info ('w'))
      {
        kill_buffers_by_expr ("*** Help for ");
        pop2buf ("*** Help for \"$word\" ***"$);
        insert (word + ": " + F[word][1]);
        bob ();
        call ("format_paragraph");
        tabcomplete_fit_window();
        set_buffer_modified_flag (0);
        most_mode ();
      }
    else
      flush (hlpmsg);
  }
}

% Return entries in the completion file that have a search string in
% keyword and/or help text.
define compl_apropos ()
{
  variable
    values = assoc_get_values (F),
    keys_l = {},
    values_l = {},
    matches = {},
    buffers = [""],
    hlp = "",
    i = 0,
    str = "";

  Completions_File = get_blocal_var ("Completions_File");

  ifnot (any (array_map (Int_Type, &length, values) > 1))
    throw RunTimeError, "$Completions_File contains no help or apropos messages"$;

  if ("slang" == detect_mode ())
    return apropos;
  else
    str = read_mini ("Apropos:", "", "");

  variable key, val;
  % list functions with search string first, then descriptions with search string
  foreach key, val (F)
  {
    try
    {
      hlp = val[1];
    }
    catch IndexError: hlp = "";

    if (string_match (key, "\\C$str"$, 1))
      list_append (keys_l, strcat (key, ": ", hlp));
    else if (string_match (hlp, "\\C$str"$, 1))
      list_append (values_l, strcat (key, ": ", hlp));
  }

  matches = list_concat (keys_l, values_l);

  ifnot (length (matches))
    return flush ("nothing relevant found for $str"$);

  matches = strjoin (list_to_array (matches), "\n");
  kill_buffers_by_expr ("*** Apropos");
  pop2buf ("*** Apropos \"$str\" ***"$);
  insert (matches);
  local_setkey ("show_hlp_for_word_at_point", Key_F1);
  set_buffer_modified_flag (0);
  most_mode ();
  bob ();
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
  {
    if (re_looking_at (sprintf ("[%s]", get_word_chars ())))
      word = get_word ();
    else
      word = get_word ();
  }

  ifnot (strlen (word))
    return;

  if (length (where (get_blocal_var ("Words") == strlow (word))))
    return flush (sprintf ("\"%s\" already exists in %s", word, get_blocal_var ("Completions_File")));

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

private variable Wordchars_Old = get_word_chars ();

% This ensures that characters that define a word is local to the
% buffer and that the arrays of words to complete from are also
% local to the buffer.
private define tabcomplete_switch_buffer_hook (old_buffer)
{
  if (blocal_var_exists ("Completions_File"))
    Completions_File = get_blocal_var ("Completions_File");

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

  define_blocal_var ("Completions_File", Completions_File);
  define_blocal_var ("Wordchars", Wordchars);
  define_blocal_var ("Extended_Wordchars", Extended_Wordchars);
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

  if (Tabcomplete_Use_Help)
  {
    local_setkey ("show_hlp_for_word_at_point", Key_F1);
    local_setkey ("compl_apropos", Key_F2);
  }
  local_setkey ("tabcomplete", Completion_Key);
  local_setkey ("move_down_2_and_indent", Key_Shift_Tab);
  local_setkey_reserved ("select_completions_file", "c");
  local_setkey_reserved ("append_word_to_completions_file", "w");
  define_blocal_var ("Words", Words);
  define_blocal_var ("F", F);
  Completions_Files = [Completions_Files, Completions_File];
}
%}}}
