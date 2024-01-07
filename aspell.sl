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
%% Version: 0.8.5
%%
%}}}
%{{{ Requires
require("keydefs");
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
% word. Possible values are: "ultra", "fast", "normal", "slow", "bad-spellers"
% Take a look at http://aspell.net/test/cur to see each mode performs in
% a test. But results will probably vary with the language, anyway. So
% it may be a good idea to try with different values
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
%}}}
%{{{ Private variables
private variable
 Aspell_Pid = NULL,
 Word = "",
 Aspell_Typo_Table = "",
 Aspell_Mode = "",
 Aspell_Lang = "",
 Aspell_Run_Together_Switch,
 Aspell_Replacement_Wordlist = "";

%}}}
%{{{ Private functions
% Return the word under or before the cursor. An adapted version for this use
private define _aspell_get_word (delete)
{
  variable wchars = "\a"R + Aspell_Extended_Wordchars;

  push_spot ();
  bskip_chars (wchars); push_mark (); skip_chars (wchars);

  if (delete)
    bufsubstr_delete ();
  else
    strtrim (bufsubstr ());

  pop_spot ();
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
  strtrim (strtok (bufsubstr (), "^\\a"));
  pop_spot ();
}

define aspell_get_word ()
{
  return _aspell_get_word (0);
}

private define aspell_delete_word ()
{
  return _aspell_get_word (1);
}

% Return the installed aspell dictionaries
private define get_aspell_dicts ()
{
  variable dicts, fp;
  fp = popen("aspell dump dicts", "r");
  dicts = strtrim(fgetslines(fp));
  () = fclose(fp);
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

  Aspell_Replacement_Wordlist = expand_filename("~/.aspell_repl.$Aspell_Dict"$);
}

% Return the word list used for completion with tabcomplete
private define aspell_set_tabcompletion_wordlist ()
{
  variable dict = get_blocal_var("aspell_dict");
  return expand_filename ("~/.tabcomplete_$dict"$);
}

% Is the chosen Aspell dictionary installed?
private define aspell_verify_dict ()
{
  variable dict = get_blocal_var("aspell_dict");

  ifnot (strlen (dict))
    return aspell_select_dictionary ();

  ifnot (is_list_element (get_aspell_dicts, dict, ','))
    throw RunTimeError, "aspell dictionary \"$dict\" not found"$;
}

% The syntax table for misspelled words
private define aspell_setup_syntax (tbl)
{
  variable bg;

  if (tbl != what_syntax_table())
    create_syntax_table(tbl);

  Aspell_Typo_Table = tbl;
  (, bg) = get_color ("normal"); % get the current background color
  set_color ("keyword", Aspell_Typo_Color, bg);
  define_syntax ("a-zA-Z" + Aspell_Extended_Wordchars, 'w', Aspell_Typo_Table);
  use_syntax_table (Aspell_Typo_Table);
}

% Give some information about some states of the mode in the status line
private define aspell_set_status_line ()
{
  variable dict = get_blocal_var("aspell_dict");

  if (Aspell_Flyspell && Aspell_Use_Tabcompletion)
    set_status_line (strreplace (Status_Line_String, "%m",
                                 "%m aspell[$dict|fly|tabcomplete]"$), 0);
  else if (0 == Aspell_Flyspell && Aspell_Use_Tabcompletion)
    set_status_line (strreplace (Status_Line_String, "%m",
                                 "%m aspell[$dict|tabcomplete]"$), 0);
  else if (Aspell_Flyspell && 0 == Aspell_Use_Tabcompletion)
    set_status_line (strreplace (Status_Line_String, "%m",
                                 "%m aspell[$dict|fly]"$), 0);
  else
    set_status_line (strreplace (Status_Line_String, "%m",
                                 "%m aspell[$dict]"$), 0);
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

% Spell check the word behind the cursor with aspell. Space or return
% keys trigger the function.
private define aspell_check_word ()
{
  variable word_prev = Word;
  variable checked_words = get_blocal_var("checked_words");
  variable misspelled_words = get_blocal_var("misspelled_words");
  
  Word = strtrim(aspell_get_word ());

  ifnot (strlen (Word)) return;

  if (any(Word == misspelled_words)) return;

  if ((looking_at(" ") || eolp()))
    if (Word == word_prev) flush ("double word");

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

% The initialization of the aspell flyspelling process. It is
% restarted if it is already running.
private define aspell_start_flyspell_process ()
{
  variable dict = get_blocal_var("aspell_dict");
  variable buf = whatbuf (), spellbuf = " *aspell*";

  ifnot (strlen (dict)) return;

  setbuf (spellbuf);

  ifnot (Aspell_Pid == NULL)
    kill_process (Aspell_Pid);

  if (strlen (Aspell_Mode))
    Aspell_Pid = open_process ("aspell", Aspell_Mode,
                               Aspell_Run_Together_Switch,
                               "-d", dict, "-a", "-c", 6);
  else
    Aspell_Pid = open_process ("aspell", Aspell_Run_Together_Switch,
                               "-d", dict, "-a", "-c", 5);

  set_process (Aspell_Pid, "output", &aspell_highlight_misspelled);
  process_query_at_exit (Aspell_Pid, 0);
  bury_buffer (spellbuf);
  setbuf (buf);
  aspell_set_status_line ();
  add_to_hook ("_jed_before_key_hooks", &before_key_hook);
}

define aspell_switch_buffer_hook(oldbuf)
{
  ifnot (blocal_var_exists("aspell_dict")) return;
  
  Aspell_Typo_Table = whatbuf();
  aspell_setup_syntax(Aspell_Typo_Table);
  aspell_start_flyspell_process();
}
if (Aspell_Flyspell)
  add_to_hook("_jed_switch_active_buffer_hooks", &aspell_switch_buffer_hook);

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
  variable dict = get_blocal_var("aspell_dict");

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

if (Aspell_Use_Replacement_Wordlist)
 append_to_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

% Adds the word before or under the editing point to the user's personal
% aspell dictionary. Remove the coloring of the word on the same token.
define add_word_to_personal_wordlist ()
{
  variable word = aspell_get_word ();
  variable dict = get_blocal_var("aspell_dict");
  
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
  Aspell_Suggestion_Mode = read_with_completion ("ultra,fast,normal,slow,bad-spellers",
                                                 "Choose suggestion mode:",
                                                 Aspell_Suggestion_Mode, "", 's');
}

% Use aspell's suggestions to replace a misspelling.
define aspell_suggest_correction ()
{
  variable fp, ch, word = "", out = "", suggs, i = 0, sugg;
  variable dict = get_blocal_var("aspell_dict");
  variable cmd = "aspell --sug-mode=$Aspell_Suggestion_Mode $Aspell_Run_Together_Switch "$ +
                 "-d $dict -a -c 2>/dev/null"$;

  word = strtrim (aspell_get_word ());

  ifnot (strlen (word)) return;

  fp = popen ("echo $word | $cmd"$, "r");
  out = strtrim(strjoin(fgetslines(fp)));
  () = fclose(fp);

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
  variable cur_dict = get_blocal_var("aspell_dict");
  variable bg, new_dict;

  ungetkey('\t');
  new_dict = read_with_completion (aspell_dicts, "[Aspell] Select language:",
                                      cur_dict, "", 's');
  aspell_verify_dict ();
  set_blocal_var(new_dict, "aspell_dict");

  if (Aspell_Flyspell)
    aspell_start_flyspell_process ();

  % load the corresponding completion file
  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();

  Aspell_Replacement_Wordlist = expand_filename ("~/.aspell_repl.$new_dict"$);
  aspell_set_status_line();
  aspell_buffer ();

}

% Toggle flyspelling on or off
define aspell_toggle_flyspell ()
{
  Aspell_Flyspell = not (Aspell_Flyspell);

  ifnot (Aspell_Flyspell)
  {
    kill_process (Aspell_Pid);
    Aspell_Pid = NULL;
    remove_from_hook ("_jed_before_key_hooks", &before_key_hook);
  }
  else
    aspell_start_flyspell_process ();

  flush ("spell checking on the fly set to $Aspell_Flyspell"$);
  aspell_set_status_line ();
}

% Spell check a marked region.
define aspell_flyspell_region()
{
  variable flyspell_state = Aspell_Flyspell;
  variable words_n, i = 0;
  
  if (flyspell_state == 0)
    aspell_toggle_flyspell();

  ifnot (markp())
    return flush("no region defined");

  create_syntax_table(Aspell_Typo_Table);
  aspell_setup_syntax(Aspell_Typo_Table);
  % empty the cached database of formerly checked words
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
  
  if (Aspell_Flyspell != flyspell_state)
    aspell_toggle_flyspell();
}

% Spellcheck the whole buffer. This is rather efficient: First it
% produces a list of misspelled words with the "aspell list" command,
% then groups those words together by size and feeds them to
% add_keywords() size by size. This function may be used without loading
% the entire minor mode.
public define aspell_buffer ()
{
  if (eobp() && bobp()) return;
  variable
    tmpfile = make_tmp_file ("aspell_buffer"),
    typo_table = whatbuf(),
    dict = get_blocal_var("aspell_dict"),
    cmd = "aspell list $Aspell_Mode $Aspell_Run_Together_Switch -d $dict <$tmpfile"$,
    misspelled_words_n = String_Type[0],
    misspelled_words = String_Type[0],
    words_arr,
    out = "",
    fp,
    i = 0;

  flush("spell checking buffer ...");
  create_syntax_table(typo_table); % emties the existing one
  aspell_setup_syntax(typo_table);
  out = strjoin (buf_as_words_array (), "\n");
  () = write_string_to_file (out, tmpfile);
  fp = popen (cmd, "r");
  words_arr = strtrim (fgetslines (fp));
  () = delete_file (tmpfile);
  set_blocal_var(words_arr, "misspelled_words");
  misspelled_words = get_blocal_var("misspelled_words");
  () = fclose (fp);

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

  call ("redraw");
}

% Go to the next misspelled word. This only works after having spell
% checked the whole buffer with aspell_buffer(). It doesn't work with
% aspell_flyspell_region()
define aspell_goto_misspelled(dir)
{
  ifnot (length(get_blocal_var("misspelled_words")))
    return flush("you must spell check the buffer first");

  if (Aspell_Show_Suggestions_Goto_Misspelled)
    aspell_suggest_correction();

  variable misspelled_words = get_blocal_var("misspelled_words");

  if (dir < 0)
  {
    while (not (bobp()))
    {
      bskip_word();
      if (any(aspell_get_word == misspelled_words)) return;
    }
  }
  else
  {
    while (not (eobp()))
    {
      skip_word();
      skip_non_word_chars();
      if (any(aspell_get_word == misspelled_words)) return;
    }
  }
}

%}}}
%{{{ Keymap

private variable Mode = "aspell";

% The keymap for the mode
ifnot (keymap_p (Mode)) make_keymap(Mode);
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

  if (Aspell_Accept_Compound_Words)
    Aspell_Run_Together_Switch = "-C";
  else
    Aspell_Run_Together_Switch = "-B";

  define_word("\a"R + Aspell_Extended_Wordchars);
  aspell_verify_dict ();
  aspell_set_filter_mode ();
  use_keymap(Mode);
  Aspell_Typo_Table = "";
  create_syntax_table(Aspell_Typo_Table);
  aspell_setup_syntax (Aspell_Typo_Table);
  aspell_set_status_line ();

  if (Aspell_Flyspell)
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
}
%}}}
