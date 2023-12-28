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
%% Version: 0.8.2
%%
%}}}

require("keydefs");

%{{{ Custom variables
% A default for the spelling dictionary to use
custom_variable ("Aspell_Dict", "");

% What characters not normally part of a word, e.g. underscore,
% apostrohpe, might be included.
custom_variable ("Aspell_Extended_Wordchars", "");

% Select a spelling dictionary upon startup
custom_variable ("Aspell_Ask_Dictionary", 0);

% The color for misspelled words
custom_variable ("Aspell_Typo_Color", "red");

% Whether or not to have misspelled words highlighted as you type.
% 0 = disable flyspelling
custom_variable ("Aspell_Flyspell", 1);

% Use replacement wordlist or not. 0 = disable
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

% The algorithm for Aspell's suggestions for correcting a missepelled
% word. Possible values are: "ultra", "fast", "normal", "slow", "bad-spellers"
% Take a look at http://aspell.net/test/cur to see each mode performs in
% a test. But results will probably vary with the language, anyway. So
% it may be a good idea to try with different values
custom_variable ("Aspell_Suggestion_Mode", "fast");

% Whether or not to spell check the buffer immediately after loading it
% 0 = disable
custom_variable ("Aspell_Spellcheck_Buffer_On_Startup", 1);

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

private define aspell_get_word ()
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
% enviroment variables. For every language of installed aspell
% dictionaries, there is always one whose name consists only of the
% two-letter ISO-639-1 language code.
private define aspell_set_dictionary_from_env ()
{
  if (strlen (Aspell_Dict)) return;

  variable locale_values = array_map (String_Type, &getenv, ["LC_MESSAGES","LANG","LC_ALL"]);

  locale_values = locale_values[where (strlen (locale_values) >= 2)]; % filter out "C"

  ifnot (length(locale_values))
    throw RunTimeError, "could not set an aspell dictionary from the enviroment";

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
  return expand_filename ("~/.tabcomplete_$Aspell_Dict"$);
}

% Is the chosen Aspell dictionary installed?
private define aspell_verify_dict ()
{
  ifnot (strlen (Aspell_Dict))
    return aspell_select_dictionary ();

  ifnot (is_list_element (get_aspell_dicts, Aspell_Dict, ','))
    throw RunTimeError, "aspell dictionary \"$Aspell_Dict\" not found"$;
}

% The parsing of the aspell check word output
private define aspell_highlight_misspelled (Aspell_Pid, str)
{
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

variable Checked_Words = Assoc_Type[String_Type, ""];

% Spell check the word behind the cursor with aspell. Space or return
% keys trigger the function.
private define aspell_check_word ()
{
  variable word_prev = Word;

  Word = strtrim(aspell_get_word ());

  ifnot (strlen (Word)) return;

  if ((looking_at(" ") || eolp()))
    if (Word == word_prev) flush ("double word");

  if (assoc_key_exists (Checked_Words, Word)) % don't check already checked words
    return;
  else
    Checked_Words[Word] = "";

  send_process (Aspell_Pid, "${Word}\n"$);
  get_process_input(5);
}

% The hook that triggers the spell checking of a word
private define before_key_hook (fun)
{
  % Checking of word is triggered by <return> or <space> keys, or if
  % typing right before or inside a word.
  if (is_substr (" \r", LASTKEY))
    aspell_check_word ();
}

% The syntax table for misspelled words
private define aspell_setup_syntax ()
{
  variable bg;

  (, bg) = get_color ("normal"); % get the current background color
  set_color ("keyword", Aspell_Typo_Color, bg);
  Aspell_Typo_Table = "Aspell";
  create_syntax_table (Aspell_Typo_Table);
  define_syntax ("a-zA-Z" + Aspell_Extended_Wordchars, 'w', Aspell_Typo_Table);
  use_syntax_table (Aspell_Typo_Table);
}

% Give some information about some states of the mode in the status line
private define aspell_set_status_line ()
{
  if (Aspell_Flyspell && Aspell_Use_Tabcompletion)
    set_status_line (strreplace (Status_Line_String, "%m", "%m aspell[$Aspell_Dict|fly|tabcomplete]"$), 0);
  else if (0 == Aspell_Flyspell && Aspell_Use_Tabcompletion)
    set_status_line (strreplace (Status_Line_String, "%m", "%m aspell[$Aspell_Dict|tabcomplete]"$), 0);
  else if (Aspell_Flyspell && 0 == Aspell_Use_Tabcompletion)
    set_status_line (strreplace (Status_Line_String, "%m", "%m aspell[$Aspell_Dict|fly]"$), 0);
  else
    set_status_line (strreplace (Status_Line_String, "%m", "%m aspell[$Aspell_Dict]"$), 0);
}

% The initialization of the aspell flyspelling process
private define aspell_start_flyspell_process ()
{
  ifnot ((1 == Aspell_Flyspell) || (strlen (Aspell_Dict))) return;

  variable buf = whatbuf (), spellbuf = " *aspell*";

  setbuf (spellbuf);

  ifnot (Aspell_Pid == NULL)
    kill_process (Aspell_Pid);

  if (strlen (Aspell_Mode))
    Aspell_Pid = open_process ("aspell", Aspell_Mode, Aspell_Run_Together_Switch, "-d", Aspell_Dict, "-a", "-c", 6);
  else
    Aspell_Pid = open_process ("aspell", Aspell_Run_Together_Switch, "-d", Aspell_Dict, "-a", "-c", 5);

  set_process (Aspell_Pid, "output", &aspell_highlight_misspelled);
  % Occasionally the first word in the buffer may be highlighted as
  % misspelled even if it isn't. Sending a word to the process right after
  % starting it seems to help
  send_process (Aspell_Pid, "${Word}\n"$);
  get_process_input(5);
  process_query_at_exit (Aspell_Pid, 0);
  bury_buffer (spellbuf);
  setbuf (buf);
  aspell_set_status_line ();
  aspell_setup_syntax ();
  add_to_hook ("_jed_before_key_hooks", &before_key_hook);
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
    {
      clear_message ();
      return "";
    }

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
  menu_append_item ($1, "&Remove Misspelled Highligting", "aspell_remove_word_highligtning()");
  menu_append_item ($1, "&Go to Next Misspelled", "aspell_goto_next_misspelled()");
}
append_to_hook ("load_popup_hooks", &aspell_popup_menu);
%}}}
%{{{ User functions
%% A Function to autocorrect oops-like typos, like typing "teh" instead of "the".
private define aspell_auto_replace_word ();
private define aspell_auto_replace_word (fun)
{
  ifnot (is_substr (" \r", LASTKEY)) return;

  variable repl_word = "", word = "";

  Aspell_Replacement_Wordlist = expand_filename ("~/.aspell_repl.$Aspell_Dict"$);

  if (0 == file_status (Aspell_Replacement_Wordlist))
    return remove_from_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

  word = aspell_get_word ();
  ifnot (strlen (word)) return;

  ifnot (search_file(Aspell_Replacement_Wordlist, "^$word *:"$, 1)) return;
  repl_word = ();
  repl_word = strtrim(strchop(repl_word, ':', 0))[1];
  () = aspell_delete_word ();
  insert (repl_word);
  flush ("\"$word\" autocorrected to \"$repl_word\""$);
}

if (Aspell_Use_Replacement_Wordlist)
 append_to_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

% Adds the word before or under the editing point to the user's personal
% aspell dictionary. Remove the coloring of the word on the same token.
define add_word_to_personal_wordlist ()
{
  variable word = aspell_get_word ();

  () = system ("echo \"*${word}\n#\" | aspell -a -d $Aspell_Dict >/dev/null"$);
  () = remove_keywords (Aspell_Typo_Table, word, strbytelen (word), 0);
  call ("redraw");
  flush ("\"$word\" added to personal wordlist"$);
}

% Remove the color highlighting of a word marked as misspelled.
define aspell_remove_word_highligtning()
{
  variable word = aspell_get_word ();
  () = remove_keywords (Aspell_Typo_Table, word, strbytelen (word), 0);
  call("redraw");
}

% Set the mode for Aspell's suggetions for correcting a missepelled word
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
  variable cmd = "aspell --sug-mode=$Aspell_Suggestion_Mode $Aspell_Run_Together_Switch "$ +
                 "-d $Aspell_Dict -a -c 2>/dev/null"$;

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
    if (get_y_or_n(sprintf("Add the entry \"%s\" to %s", entry, path_basename(Aspell_Replacement_Wordlist))))
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

  Aspell_Dict = read_with_completion (aspell_dicts, "[Aspell] Select language (<TAB> lists):", Aspell_Dict, "", 's');
  aspell_verify_dict ();
  aspell_start_flyspell_process ();
  Aspell_Replacement_Wordlist = expand_filename ("~/.aspell_repl.$Aspell_Dict"$);
  aspell_buffer ();

  % load the corresponding completion file
  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();
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

  % empty the cached database of formerly checked words
  Checked_Words = Assoc_Type[String_Type, ""];
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

variable Misspelled_Words = String_Type[0];

% Spellcheck the whole buffer. This is rather efficient: First it
% produces a list of misspelled words with the "aspell list" command,
% then groups those words together by size and feeds them to
% add_keywords() size by size. This function may be used without loading
% the entire minor mode.
public define aspell_buffer ()
{
  variable
    tmpfile = make_tmp_file ("aspell_buffer"),
    cmd = "aspell list $Aspell_Mode $Aspell_Run_Together_Switch -d $Aspell_Dict <$tmpfile"$,
    misspelled_words_n = String_Type[0],
    misspelled_words = String_Type[0],
    out = "",
    fp,
    i = 0;

  flush("spell checking buffer ...");
  aspell_setup_syntax(); % empties existing syntax table and sets up syntax highlighting
  out = strjoin (buf_as_words_array (), "\n");
  () = write_string_to_file (out, tmpfile);
  fp = popen (cmd, "r");
  Misspelled_Words = strtrim (fgetslines (fp));
  () = fclose (fp);

  _for i (2, 48, 1) % 48 is the keyword length limit.
  {
    misspelled_words_n = Misspelled_Words[where (strbytelen (Misspelled_Words) == i)];
    misspelled_words_n = misspelled_words_n[array_sort (misspelled_words_n)];
    misspelled_words_n = strjoin (misspelled_words_n, "");

    ifnot (strlen (misspelled_words_n)) continue;
    () = add_keywords (Aspell_Typo_Table, misspelled_words_n, i, 0);
  }

  () = delete_file (tmpfile);
  call ("redraw");
}

% Go to the next misspelled word. This only works after having spell
% checked the whole buffer with aspell_buffer(). It doesn't work with
% aspell_flyspell_region()
define aspell_goto_next_misspelled()
{
  ifnot (length(Misspelled_Words))
    return flush("you must spell check the buffer first");

  while (not (eobp()))
  {
    skip_word();
    if (any(aspell_get_word == Misspelled_Words)) return;
  }
}

%}}}
%{{{ Keymap
$1 = "aspell";

% The keymap for the mode
ifnot (keymap_p ($1)) make_keymap($1);
definekey("aspell_goto_next_misspelled", Key_Shift_Tab, $1);
definekey_reserved("add_word_to_personal_wordlist", "a", $1);
definekey_reserved("aspell_buffer", "b", $1);
definekey_reserved("aspell_select_dictionary", "d", $1);
definekey_reserved("aspell_suggest_correction", "s", $1);
definekey_reserved("aspell_toggle_flyspell", "t", $1);
definekey_reserved("aspell_set_suggestion_mode", "S", $1);
definekey_reserved("aspell_remove_word_highligtning()", "R", $1);
definekey_reserved("aspell_flyspell_region()", "r", $1);
%}}}
%{{{ Minor mode initialization
define init_aspell ()
{
  aspell_set_dictionary_from_env ();
  aspell_verify_dict ();
  aspell_set_filter_mode ();
  use_keymap($1);
  aspell_setup_syntax ();
  aspell_set_status_line ();
  add_completion ("aspell_buffer");

  if (NULL == search_path_for_file (getenv ("PATH"), "aspell"))
    return flush ("aspell is not installed or not in $PATH, spell checking disabled.");

  if (Aspell_Accept_Compound_Words)
    Aspell_Run_Together_Switch = "-C";
  else
    Aspell_Run_Together_Switch = "-B";

  aspell_start_flyspell_process ();

  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();

  if ((1 == Aspell_Ask_Dictionary) || (0 == strlen (Aspell_Dict)))
  {
    Aspell_Ask_Dictionary = 0;
    return aspell_select_dictionary ();
  }

  if (Aspell_Spellcheck_Buffer_On_Startup)
    aspell_buffer ();
}
%}}}
