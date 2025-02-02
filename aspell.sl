% -*- mode: slang; mode: fold -*-
%
%{{{ Description, licence, version
%% aspell.sl, an extension minor mode for the jed editor to spellcheck
%% a buffer as you type along. It borrows some ideas from flyspell.sl
%% from jedmodes.
%%
%% Consult the supplied README.aspell.txt file for installation and
%% usage hints.
%%
%% Author: Morten Bo Johansen <mortenbo at hotmail dot com>
%% Licence: GPL, version 2 or later.
%%
%% Version: 0.9.1, 2025-02-02
%%
%}}}
%{{{ Requires
require("keydefs");
require("process");
require("pcre");
%}}}
%{{{ Custom variables
% A default for the spelling dictionary to use
custom_variable ("Aspell_Dict", "");

% What characters not normally part of a word, e.g. underscore,
% apostrophe, might be included.
custom_variable ("Aspell_Extended_Wordchars", "");

% Select a spelling dictionary upon startup
custom_variable ("Aspell_Ask_Dictionary", 0);

% The color for misspelled words
custom_variable ("Aspell_Typo_Color", "red");

% Whether or not to have misspelled words highlighted as you type.
% 0 = disable flyspelling
custom_variable ("Aspell_Flyspell", 1);

% Use replacement word list or not. 0 = disable
custom_variable ("Aspell_Use_Replacement_Wordlist", 1);

% Use tab completion (with tabcomplete.sl)
% 0 = disable
custom_variable ("Aspell_Use_Tabcompletion", 0);

% Accept compound words as correctly spelled or not.
% 0 = do not accept compound words
% Whether or not this has any effect relies on the
% "run-together" option in the aspell language data file, <lang>.dat,
% typically residing in /usr/lib/aspell-<version>/<lang>.dat
% For e.g. the Danish language, this option is set to "true" and
% therefore words that are strung together from two or more
% individually correctly spelled words are accepted as correctly
% spelled. For most languages, it won't have any effect.
custom_variable ("Aspell_Accept_Compound_Words", 0);

% The algorithm for Aspell's suggestions for correcting a misspelled
% word. Possible values are: "ultra", "fast", "normal", "slow",
% "bad-spellers" Take a look at http://aspell.net/test/cur to see how
% each mode performs in a test. But results will probably vary with
% the language, anyway. So it may be a good idea to try with different
% values
custom_variable ("Aspell_Suggestion_Mode", "fast");

% Whether or not to spell check the buffer immediately after loading it
% 0 = disable
custom_variable ("Aspell_Spellcheck_Buffer_On_Startup", 1);

% Show the menu with Aspell's suggestions for correcting a misspelled
% word when going to the next or previous misspelled word.
% 0 = disable
custom_variable ("Aspell_Show_Suggestions_Goto_Misspelled", 0);

%}}}
%{{{ Autoloads
autoload ("add_keywords", "syntax");
autoload ("remove_keywords", "syntax");
#ifnexists init_tabcomplete
if (strlen (expand_jedlib_file ("tabcomplete.sl")))
  autoload ("init_tabcomplete", "tabcomplete");
#endif
%}}}
%{{{ Prototypes
define aspell_select_dictionary ();
define add_word_to_personal_wordlist ();
define aspell_toggle_flyspell();
public define aspell_buffer();
%}}}
%{{{ Private variables
private variable
 Aspell_Pid = -1,
 Word = "",
 Mode_Init = 1, % indicates if minor mode is loaded 
 Aspell_Typo_Table = "",
 Aspell_Mode = "",
 Aspell_Run_Together_Switch = "-B",
 Aspell_Replacement_Wordlist = "";
%}}}
%{{{ Private functions
% Return the word under or before the cursor. An adapted version for this use
private define _aspell_get_word (delete)
{
  variable wchars = "\w"R + Aspell_Extended_Wordchars;

  push_spot ();
  bskip_chars (wchars); push_mark (); skip_chars (wchars);

  if (delete)
    bufsubstr_delete ();
  else
    strtrim (bufsubstr ());

  pop_spot ();
}

private define aspell_get_word ()
{
  return _aspell_get_word (0);
}

private define aspell_delete_word ()
{
  return _aspell_get_word (1);
}

% Returns the key sequence from the getkey() function as a string.
private define get_keysequence ()
{
  variable s = char (getkey());
  while (input_pending (1))
    s += char (getkey());
  return s;
}

% Return the words in the current buffer as an array
private define buf_as_words_array ()
{
  push_spot_bob (); push_mark_eob ();
  strtrim (strtok (bufsubstr (), "^\\w"));
  pop_spot ();
}

% Use the new_process() function for some IO instead of popen().
private define aspell_popen(cmd)
{
  variable obj, w, lines = [""], err, msg = "";

  obj = new_process(cmd ;; __qualifiers); % pass all qualifiers
  w = obj.wait(); % get some feedback from the process, including exit status

  try
  {
    lines = fgetslines(obj.fp1; trim=3); % collect the output in an array of lines
    () = fclose (obj.fp1);

    if (w.exit_status != 0) % process failed
    {
      () = fgets(&err, obj.fp2); % get first line of error message

      if (length(err)) % prioritize showing aspell's own error message
        throw RunTimeError, sprintf("%s failed", strtrim(strjoin(err, "")));
      else
        throw RunTimeError, sprintf("%s failed", strjoin(cmd, " "));
    }
  }
  catch InvalidParmError;
  finally: return lines;
}

% Return the installed aspell dictionaries
private define get_aspell_dicts ()
{
  variable dicts = aspell_popen(["aspell", "dump", "dicts"]; write={1,2});
  dicts = dicts[array_sort (strlen (dicts))];

  ifnot (length (dicts))
    throw RunTimeError, "no aspell dictionaries found";

  return strjoin (dicts, ",");
}

% Find the default spelling dictionary to use from some locale
% environment variables. For every language of installed aspell
% dictionaries, there is always one whose name consists only of the
% two-letter ISO-639-1 language code.
private define aspell_set_dictionary_from_env ()
{
  if (strlen (Aspell_Dict)) return;

  variable locale_values = array_map (String_Type,
                                      &getenv, ["LC_MESSAGES","LANG","LC_ALL"]);

  locale_values = locale_values[where (strlen (locale_values) >= 2)]; % filter out "C"

  ifnot (length(locale_values))
    throw RunTimeError, "could not set an aspell dictionary from the environment";

  foreach (locale_values)
  {
    variable locale_value = ();

    if (is_list_element (get_aspell_dicts, locale_value[[0:4]], ',')) % e.g. "de_AT"
      Aspell_Dict = locale_value[[0:4]];
    else
      Aspell_Dict = locale_value[[0:1]]; % e.g. "en"
  }
}

private define aspell_get_dict()
{
  ifnot (strlen(Aspell_Dict))
    aspell_set_dictionary_from_env(); % "Aspell_Dict" is set here

  variable dict = Aspell_Dict;

  if (blocal_var_exists("aspell_dict"))
    dict = get_blocal_var("aspell_dict");

  return dict;
}

% The syntax table for misspelled words
private define aspell_setup_syntax (tbl)
{
  variable bg;

  if (tbl != what_syntax_table())
    create_syntax_table(tbl);

  Aspell_Typo_Table = tbl;

  if (blocal_var_exists("typo_table"))
    set_blocal_var(Aspell_Typo_Table, "typo_table");

  (, bg) = get_color ("normal"); % get the current background color
  set_color ("keyword", Aspell_Typo_Color, bg);
  define_syntax ("${Aspell_Extended_Wordchars}a-zA-Z0-9"$, 'w', Aspell_Typo_Table);
  use_syntax_table (Aspell_Typo_Table);
}

% Give some information about some states of the mode in the status line
private define aspell_set_status_line ()
{
  variable status_str = "", dict = aspell_get_dict();

  if (blocal_var_exists("aspell_flyspell"))
    Aspell_Flyspell = get_blocal_var("aspell_flyspell");
  
  if (Aspell_Flyspell == 1 && Aspell_Use_Tabcompletion == 1)
    status_str = "%m aspell[$dict|fly|tabcomplete]"$;
  if (Aspell_Flyspell == 1 && Aspell_Use_Tabcompletion == 0)
    status_str = "%m aspell[$dict|fly]"$;
  if (Aspell_Flyspell == 0 && Aspell_Use_Tabcompletion == 1)
    status_str = "%m aspell[$dict|tabcomplete]"$;
  if (Aspell_Flyspell == 0 && Aspell_Use_Tabcompletion == 0)
    status_str = "%m aspell[$dict]"$;

  set_status_line (strreplace (Status_Line_String, "%m", status_str), 0);
}

% Set the aspell checking mode for various types of files.
private define aspell_set_filter_mode ()
{
  variable M = Assoc_Type[String_Type, ""];
  variable mode = strlow (what_mode (), pop ());

  M["groff"] = "-n", M["nroff"] = "-n", M["html"] = "-H",
  M["latex"] = "-t", M["mailedit"] = "-e", M["email"] = "-e",

  Aspell_Mode = M[mode];
}

% The parsing of the aspell check word output
private define aspell_highlight_misspelled (Aspell_Pid, str)
{
  ifnot (strlen(strtrim(Word))) return;

  % '*' is for a correctly spelled word found in the wordlist
  % '-' is for a word recognized as a compound word where its
  % individual parts are correctly spelled.
  if (Aspell_Accept_Compound_Words)
  {
    ifnot ((strtrim (str) == "*") || (strtrim (str) == "-"))
      add_keyword (Aspell_Typo_Table, Word);
  }
  else
  {
    ifnot (strtrim (str) == "*")
      add_keyword (Aspell_Typo_Table, Word);
  }

  Word = "";
}

private variable Prev_Word = "";

% Spell check the word behind the cursor with aspell. Space or return
% keys trigger the function.
private define aspell_check_word ()
{
  variable checked_words = Assoc_Type[String_Type, ""];

  if (blocal_var_exists("checked_words"))
    checked_words = get_blocal_var("checked_words");

  Word = strtrim(aspell_get_word ());
  
  ifnot (strlen (Word)) return;

  if (Word == Prev_Word) flush ("double word");

  Prev_Word = Word;

  % don't check already checked words
  if (assoc_key_exists (checked_words, Word))
    return;
  else
    checked_words[Word] = "";

  send_process (Aspell_Pid, "${Word}\n"$);
  get_process_input(5);
}

% The hook that triggers the spell checking of a word
private define before_key_hook (fun)
{
  % Checking of word is triggered by <return> or <space> keys
  if (is_substr (" \r", LASTKEY))
    aspell_check_word ();
}

private define aspell_signal_handler(pid, flags, status)
{
  variable msg;

  msg = aprocess_stringify_status (pid, flags, status);

  if (is_substr(msg, "exit")) % aspell process failed
  {
    if (blocal_var_exists("aspell_flyspell"))
    {
      set_blocal_var(0, "aspell_flyspell");
      Aspell_Flyspell = get_blocal_var("aspell_flyspell");
    }
    remove_from_hook ("_jed_before_key_hooks", &before_key_hook);
    throw RunTimeError, "could not start flyspell process, flyspelling disabled";
  }
}

% The initialization of the aspell flyspelling process. It is
% restarted if it is already running. If it were better to use the
% new_process() function in lieu of open_process() and you know how
% to do it, please drop me line.
private define aspell_start_flyspell_process ()
{
  variable buf = whatbuf (), spellbuf = " *aspell*";

  Aspell_Dict = aspell_get_dict();
  setbuf (spellbuf);

  ifnot (Aspell_Pid == -1)
    kill_process (Aspell_Pid);

  if (strlen (Aspell_Mode))
    Aspell_Pid = open_process ("aspell", Aspell_Mode,
                               Aspell_Run_Together_Switch,
                               "-d", Aspell_Dict, "-a", 5);
  else
    Aspell_Pid = open_process ("aspell", Aspell_Run_Together_Switch,
                               "-d", Aspell_Dict, "-a", 4);

  set_process (Aspell_Pid, "signal", &aspell_signal_handler);
  set_process (Aspell_Pid, "output", &aspell_highlight_misspelled);
  process_query_at_exit (Aspell_Pid, 0);
  setbuf (buf);
  aspell_set_status_line ();
  add_to_hook ("_jed_before_key_hooks", &before_key_hook);
}

private define aspell_switch_buffer_hook(oldbuf)
{
  Aspell_Typo_Table = whatbuf();
  aspell_setup_syntax(Aspell_Typo_Table);

  if (blocal_var_exists("aspell_flyspell"))
  {
    if (1 == get_blocal_var("aspell_flyspell"))
      aspell_start_flyspell_process();
  }
  else
    remove_from_hook("_jed_before_key_hooks", &before_key_hook);
}

% Pick an entry from a menu of at most 10 entries in the message area
% and return it.
private define aspell_select_from_mini (items_arr)
{
  variable items_arr_n, len, i, ch, word;

  items_arr = strtrim (items_arr);
  len = length (items_arr);
  items_arr_n = String_Type[len];

  _for i (0, len-1, 1)
    items_arr_n[i] = strcat (string (i), "|",  items_arr[i]);

  if (length (items_arr_n) > 10)
    items_arr_n = items_arr_n[[0:9]];

  flush ("c|ancel, a|dd, e|dit, " + strjoin (items_arr_n, ", "));
  ch = get_keysequence ();

  if (ch == "a")
    add_word_to_personal_wordlist ();

  else if (ch == "e")
    return read_mini ("", "", aspell_get_word ());
  else
  {
    ifnot (isdigit(ch))
      return "";

    i = integer (ch);
    return items_arr[i];
  }
}

% Return the word list used for completion with tabcomplete
private define aspell_set_tabcompletion_wordlist ()
{
  variable dict = aspell_get_dict();
  return expand_filename ("~/.tabcomplete_$dict"$);
}

% Load the tabcompletion extension with a word list that corresponds
% to the language of the aspell dictionary being used.
private define load_tabcompletion ()
{
  variable fun = __get_reference ("init_tabcomplete");

  if (fun != NULL)
    (@fun (aspell_set_tabcompletion_wordlist));
}

% An aspell menu addition to the "System" menu pop up.
private define aspell_popup_menu ()
{
  menu_append_popup ("Global.S&ystem", "&Aspell");
  $1 = "Global.S&ystem.&Aspell";
  menu_append_item ($1, "&Add Word to Personal Wordlist", "add_word_to_personal_wordlist");
  menu_append_item ($1, "Spellcheck &Buffer", "aspell_buffer");
  menu_append_item ($1, "Spellcheck R&egion", "aspell_flyspell_region");
  menu_append_item ($1, "Select Aspell &Dictionary", "aspell_select_dictionary");
  menu_append_item ($1, "&Change Aspell's Suggestion Mode", "aspell_set_suggestion_mode");
  menu_append_item ($1, "&Suggest Correction", "aspell_suggest_correction");
  menu_append_item ($1, "&Toggle Spell Checking on the Fly", "aspell_toggle_flyspell");
  menu_append_item ($1, "&Remove Misspelled Highlighting", "aspell_remove_word_highligtning()");
  menu_append_item ($1, "&Go to Next Misspelled", "aspell_goto_misspelled(1)");
  menu_append_item ($1, "&Go to Previous Misspelled", "aspell_goto_misspelled(-1)");
}
append_to_hook ("load_popup_hooks", &aspell_popup_menu);
%}}}
%{{{ User functions
%% A Function to auto correct oops-like typos, like typing "teh" instead of "the".
private define aspell_auto_replace_word ();
private define aspell_auto_replace_word (fun)
{
  ifnot (is_substr (" \r", LASTKEY)) return;

  variable repl_word = "", word = "";
  variable dict = aspell_get_dict();

  Aspell_Replacement_Wordlist = expand_filename ("~/.aspell_repl.$dict"$);

  if (0 == file_status (Aspell_Replacement_Wordlist))
    return remove_from_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

  word = aspell_get_word ();
  ifnot (strlen (word)) return;

  ifnot (search_file(Aspell_Replacement_Wordlist, "^$word *:"$, 1)) return;
  repl_word = ();
  repl_word = strtrim(strchop(repl_word, ':', 0))[1];
  () = aspell_delete_word ();
  insert (repl_word);
  flush ("\"$word\" auto corrected to \"$repl_word\""$);
}

% Adds the word before or under the editing point to the user's personal
% aspell dictionary. Remove the coloring of the word on the same token.
define add_word_to_personal_wordlist ()
{
  variable word = aspell_get_word ();
  variable dict = aspell_get_dict();
  
  () = system ("echo \"*${word}\n#\" | aspell -a -d $dict >/dev/null"$);
  () = remove_keywords (Aspell_Typo_Table, word, strbytelen (word), 0);
  call ("redraw");
  flush ("\"$word\" added to personal wordlist, .aspell.${dict}.pws"$);
}

% Remove the color highlighting of a word marked as misspelled.
define aspell_remove_word_highligtning()
{
  variable word = aspell_get_word ();
  () = remove_keywords (Aspell_Typo_Table, word, strbytelen (word), 0);
  call("redraw");
}

% Set the mode for Aspell's suggestions for correcting a misspelled word
define aspell_set_suggestion_mode()
{
  ungetkey('\t');
  Aspell_Suggestion_Mode = read_with_completion ("ultra,fast,normal,slow, bad-spellers",
                                                 "Choose suggestion mode:",
                                                 Aspell_Suggestion_Mode, "", 's');
}

% Use aspell's suggestions to replace a misspelling.
define aspell_suggest_correction ()
{
  variable dict, ch, word, out = "", suggs, i = 0, sugg;
  variable wordfile = "/tmp/aspell_sugg_word";

  dict = aspell_get_dict();
  word = strtrim (aspell_get_word ());
  ifnot (strlen (word)) return;
  () = write_string_to_file(word, wordfile);
  out = aspell_popen(["aspell", "--sug-mode=$Aspell_Suggestion_Mode"$,
                     Aspell_Run_Together_Switch, "-d", dict, "-a"]; write={1,2},
                     stdin=wordfile);

  out = strtrim(strjoin(out));
  () = remove(wordfile);

  try
  {
    if ((out[[-1]] == "*") || (out[[-1]] == "-"))
      return flush ("correct");
  }
  catch IndexError;

  out = strchop (out, ':', 0);

  if (length (out) > 1)
    suggs = strchop (out[1], ',', 0);
  else
    return flush ("no suggestion");

  suggs = strtrim (suggs);
  sugg = aspell_select_from_mini (suggs);

  if (strlen (sugg))
  {
    () = aspell_delete_word ();
    insert (sugg);
    clear_message ();

    variable entry = strcat(word, ":", sugg);

    % Adds the pair of words, one a typo, and the other, the correction to
    % the replacement word list.
    if (get_y_or_n(sprintf("Add the entry \"%s\" to %s", entry,
                           path_basename(Aspell_Replacement_Wordlist))))
    {
      () = system("echo $entry >> $Aspell_Replacement_Wordlist"$);
      flush("$entry added to $Aspell_Replacement_Wordlist"$);
    }
  }
  else clear_message();
}

% Initialize the spell process with another aspell dictionary
define aspell_select_dictionary ()
{
  variable aspell_dicts = get_aspell_dicts ();
  variable cur_dict = aspell_get_dict();
  variable bg, new_dict;

  ungetkey('\t');
  Aspell_Dict = read_with_completion (aspell_dicts, "[Aspell] Select language:",
                                      Aspell_Dict, "", 's');

  ifnot (is_list_element (get_aspell_dicts, Aspell_Dict, ','))
    throw RunTimeError, "dictionary, \"$Aspell_Dict\" not installed"$;

  if (blocal_var_exists("aspell_dict"))
    set_blocal_var(Aspell_Dict, "aspell_dict");

  if (blocal_var_exists("aspell_flyspell"))
  {
    if (1 == get_blocal_var("aspell_flyspell"))
      aspell_start_flyspell_process ();
  }

  % load the corresponding completion file
  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();

  Aspell_Replacement_Wordlist = expand_filename ("~/.aspell_repl.$Aspell_Dict"$);
  aspell_set_status_line();
  aspell_buffer ();
}

% Toggle flyspelling on or off
define aspell_toggle_flyspell ()
{
  ifnot (blocal_var_exists("aspell_flyspell"))
    return flush("flyspelling not enabled for this buffer");

  Aspell_Flyspell = not get_blocal_var("aspell_flyspell");
  set_blocal_var(Aspell_Flyspell, "aspell_flyspell");
  Aspell_Flyspell = get_blocal_var("aspell_flyspell");
  
  if (0 == get_blocal_var("aspell_flyspell"))
  {
    kill_process (Aspell_Pid);
    Aspell_Pid = -1;
    remove_from_hook ("_jed_before_key_hooks", &before_key_hook);
    create_syntax_table("");
    use_syntax_table("");
  }
  else
  {
    aspell_start_flyspell_process ();
    use_syntax_table(Aspell_Typo_Table);
  }

  vmessage ("spell checking on the fly set to %d", get_blocal_var("aspell_flyspell"));
  aspell_set_status_line ();
}

% Spell check a marked region.
define aspell_flyspell_region()
{
  variable flyspell_state, words_n, i = 0;
  
  if (blocal_var_exists("aspell_flyspell"))
    flyspell_state = get_blocal_var("aspell_flyspell");

  if (flyspell_state == 0)
    aspell_toggle_flyspell();

  ifnot (markp())
    return flush("no region defined");

  create_syntax_table(Aspell_Typo_Table);
  aspell_setup_syntax(Aspell_Typo_Table);

  % empty the cached database of formerly checked words
  if (blocal_var_exists("checked_words"))
    set_blocal_var(Assoc_Type[String_Type], "checked_words");

  exchange_point_and_mark();
  check_region(1); % push spot
  narrow_to_region();
  words_n = length(buf_as_words_array());
  bob();

  do
  {
    skip_word();
    aspell_check_word();
    flush (sprintf ("spell checking ... (%d%%)", (i*100)/words_n));
    i++;
  }
  while (not (eobp()));

  widen_region();
  pop_spot();
  flush("done");
  
  if (get_blocal_var("aspell_flyspell") != flyspell_state)
    aspell_toggle_flyspell();
}

% Spellcheck the whole buffer, without having to save the file
% associated with it first. This is rather efficient: First it
% produces a list of misspelled words with the "aspell list" command,
% then groups those words together by size and feeds them to
% add_keywords() size by size. This function may be used without
% loading the entire minor mode.
public define aspell_buffer ()
{
  if (NULL == search_path_for_file (getenv ("PATH"), "aspell"))
    return flush ("aspell is not installed or not in $PATH");

  if (eobp() && bobp()) return;

  variable
    tmpfile = make_tmp_file ("aspell_buffer"),
    typo_table = whatbuf(),
    dict = aspell_get_dict(),
    aspell_dicts = get_aspell_dicts (),
    misspelled_words_n = String_Type[0],
    misspelled_words = String_Type[0],
    typos_arr,
    cmd = "",
    fp,
    i = 0;

  % if minor mode is not loaded and this function is used on its own,
  % then ask user for a dictionary the first time.
  ifnot (blocal_var_exists("aspell_dict")) % mode is not loaded
  {
    create_blocal_var("aspell_dict");
    create_blocal_var("misspelled_words");
    dict = read_with_completion (aspell_dicts, "language?", dict, "", 's');
    set_blocal_var(dict, "aspell_dict");
    Mode_Init = 0;
  }

  Aspell_Dict = get_blocal_var("aspell_dict");
  flush(sprintf ("spell checking %s ...", whatbuf()));
  create_syntax_table(typo_table); % emties the existing one
  aspell_setup_syntax(typo_table);
  aspell_set_filter_mode();
  push_spot_bob(); push_mark_eob();
  () = write_string_to_file (bufsubstr(), tmpfile);
  pop_spot();
  % cmd = "aspell list $Aspell_Mode $Aspell_Run_Together_Switch -d $dict <$tmpfile"$,
  % fp = popen (cmd, "r");
  % typos_arr = strtrim (fgetslines (fp));
  typos_arr = aspell_popen(["aspell", "list", Aspell_Mode,
                            Aspell_Run_Together_Switch, "-d", Aspell_Dict];
                            write={1,2}, stdin=tmpfile);
  () = delete_file (tmpfile);
  set_blocal_var(typos_arr, "misspelled_words");
  misspelled_words = get_blocal_var("misspelled_words");

  ifnot (length(misspelled_words))
    return flush("no spelling errors found");

  _for i (2, 48, 1) % 48 is the keyword length limit.
  {
    misspelled_words_n = misspelled_words[where (strbytelen (misspelled_words) == i)];
    misspelled_words_n = misspelled_words_n[array_sort (misspelled_words_n)];
    misspelled_words_n = strjoin (misspelled_words_n, "");

    ifnot (strlen (misspelled_words_n)) continue;
    () = add_keywords (typo_table, misspelled_words_n, i, 0);
  }

  if (Mode_Init == 1) % only set the status line if mode is loaded
    aspell_set_status_line();

  call ("redraw");
}

% Go to the next misspelled word. This only works after having spell
% checked the whole buffer with aspell_buffer(). It doesn't work with
% aspell_flyspell_region()
define aspell_goto_misspelled(dir)
{
  ifnot (length(get_blocal_var("misspelled_words")))
    return flush("you must spell check the buffer first");

  variable misspelled_words = String_Type[0];

  if (blocal_var_exists("misspelled_words"))
    misspelled_words = get_blocal_var("misspelled_words");

  try
  {
    if (dir < 0)
    {
      while (not (bobp()))
      {
        bskip_word();
        skip_non_word_chars();
        if (any(aspell_get_word == misspelled_words)) return;
      }
    }
    else
    {
      do
      {
        skip_word();
        skip_non_word_chars();
        if (any(aspell_get_word == misspelled_words)) return;
      }
      while (not (eobp()));
    }
  }
  finally:
  {
    if (Aspell_Show_Suggestions_Goto_Misspelled)
      aspell_suggest_correction();
  }
}

%}}}
%{{{ Keymap

private variable Mode = "aspell";

% The keymap for the mode
ifnot (keymap_p (Mode))
  copy_keymap (Mode, what_keymap());

definekey("aspell_goto_misspelled(1)", Key_Shift_Down, Mode);
definekey("aspell_goto_misspelled(-1)", Key_Shift_Up, Mode);
definekey_reserved("add_word_to_personal_wordlist", "a", Mode);
definekey_reserved("aspell_buffer", "b", Mode);
definekey_reserved("aspell_select_dictionary", "d", Mode);
definekey_reserved("aspell_suggest_correction", "s", Mode);
definekey_reserved("aspell_toggle_flyspell", "t", Mode);
definekey_reserved("aspell_set_suggestion_mode", "S", Mode);
definekey_reserved("aspell_remove_word_highligtning()", "R", Mode);
definekey_reserved("aspell_flyspell_region()", "r", Mode);
%}}}
%{{{ Minor mode initialization

define init_aspell ()
{
  if (NULL == search_path_for_file (getenv ("PATH"), "aspell"))
    return flush ("aspell is not installed or not in $PATH, spell checking disabled.");

  aspell_set_dictionary_from_env ();
  Aspell_Replacement_Wordlist = expand_filename("~/.aspell_repl.$Aspell_Dict"$);

  ifnot (blocal_var_exists("aspell_dict"))
    define_blocal_var("aspell_dict", Aspell_Dict);

  ifnot (blocal_var_exists("misspelled_words"))
  {
    create_blocal_var("misspelled_words");
    set_blocal_var(String_Type[0], "misspelled_words");
  }

  ifnot (blocal_var_exists("checked_words"))
  {
    create_blocal_var("checked_words");
    set_blocal_var(Assoc_Type[String_Type], "checked_words");
  }

  ifnot (blocal_var_exists("aspell_flyspell"))
  {
    create_blocal_var("aspell_flyspell");
    set_blocal_var(Aspell_Flyspell, "aspell_flyspell");
  }

  if (Aspell_Accept_Compound_Words)
    Aspell_Run_Together_Switch = "-C"; % run together
  else
    Aspell_Run_Together_Switch = "-B";

  aspell_set_filter_mode ();
  use_keymap(Mode);
  aspell_setup_syntax ("");
  aspell_set_status_line ();
  define_blocal_var("aspell_initialized", 1);

  if (get_blocal_var("aspell_flyspell"))
    aspell_start_flyspell_process ();

  if ((1 == Aspell_Ask_Dictionary) || (0 == strlen (get_blocal_var("aspell_dict"))))
  {
    Aspell_Ask_Dictionary = 0;
    return aspell_select_dictionary ();
  }

  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();

  if (Aspell_Spellcheck_Buffer_On_Startup)
    aspell_buffer ();

  if (Aspell_Use_Replacement_Wordlist)
    append_to_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

  if (1 == get_blocal_var("aspell_flyspell"))
    add_to_hook("_jed_switch_active_buffer_hooks", &aspell_switch_buffer_hook);

  Mode_Init = 1;
}
%}}}
