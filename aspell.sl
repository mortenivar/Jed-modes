% -*- mode: slang; mode: fold -*-
%
% FIXME: sidste ord i buffer forbliver rødt ved skift af sprog, selvom
% det er korrekt stavet
%
%{{{ Description, licence, version
%% aspell.sl, an extension minor mode for the jed editor to spellcheck
%% a buffer as you type along. It borrows some ideas from flyspell.sl
%% from jedmodes.
%%
%% Consult the supplied README.aspell.txt file for installation and
%% usage hints.
%%
%% Author: Morten Bo Johansen <listmail@mbjnet.dk>
%% Licence: GPL, version 2 or later.
%%
%% Version: 0.7.2
%%
%}}}
%{{{ Custom variables
% A default for the spelling dictionary to use
custom_variable ("Aspell_Dict", "");

% What characters not normally part of a word, e.g. underscore,
% apostrohpe, should be included.
custom_variable ("Extended_Wordchars", "-'");

% Select a spelling dictionary upon startup
custom_variable ("Aspell_Ask_Dictionary", 0);

% The color for misspelled words
custom_variable ("Aspell_Typo_Color", "red");

% Whether or not to have misspelled words highlighted as you type.
custom_variable ("Aspell_Flyspell", 1);

% Use replacement wordlist or not
custom_variable ("Aspell_Use_Replacement_Wordlist", 0);

% Use tab completion (with tabcomplete.sl)
custom_variable ("Aspell_Use_Tabcompletion", 0);
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
 Aspell_Replacement_Wordlist = "";
%}}}
%{{{ Private functions
% Return the word under or before the cursor. An adapted version for this use
define _aspell_get_word (delete)
{
  variable wchars = "\a"R + Extended_Wordchars;
  variable punct = "!?.,:;'`\")]>";

  push_spot ();
  bskip_chars (punct); bskip_chars (wchars); push_mark (); skip_chars (wchars);

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

% Return the installed aspell dictionaries
private define get_aspell_dicts ()
{
  variable dicts = strtrim (strjoin (fgetslines (popen ("aspell dump dicts", "r"))));
  dicts = strchop (dicts, '\n', 0);
  dicts = dicts[array_sort (strlen (dicts))];

  ifnot (length (dicts))
    throw RunTimeError, "no aspell dictionaries found";

  return strjoin (dicts, ",");
}

% Find the default spelling dictionary to use from some locale
% enviroment variables. For every language of installed aspell
% dictionaries, there is always one whose name conists only of the
% two-letter ISO-639-1 language code.
private define aspell_set_dictionary_from_env ()
{
  if (strlen (Aspell_Dict)) return;

  variable locale_values = array_map (String_Type, &getenv, ["LANG","LC_MESSAGES","LC_ALL"]);

  locale_values = locale_values[where (strlen (locale_values) >= 2)]; % filter out "C"

  if (length (locale_values))
  {
    foreach (locale_values)
    {
      variable locale_value = ();

      try
      {
        if (is_list_element (get_aspell_dicts, locale_value[[0:4]], ','))
        {
          Aspell_Dict = locale_value[[0:4]];
          break;
        }
        else if (is_list_element (get_aspell_dicts, locale_value[[0:1]], ','))
        {
          Aspell_Dict = locale_value[[0:1]];
          break;
        }
      }
      catch IndexError:
      {
        Aspell_Dict = locale_value[[0:1]];
        break;
      }
    }
    Aspell_Lang = Aspell_Dict;
  }
}

private define aspell_set_tabcompletion_wordlist ()
{
  aspell_set_dictionary_from_env ();
  variable completion_file = expand_filename ("~/.tabcomplete_$Aspell_Lang"$);

  ifnot (1 == file_status (completion_file))
  {
    variable lang = Aspell_Lang[[0:1]];
    completion_file = expand_filename ("~/.tabcomplete_$lang"$);
  }

  return completion_file;
}

% Return the words in the current buffer as an array
private define buf_as_words_array ()
{
  push_spot_bob (); push_mark_eob ();
  strtrim (strtok (bufsubstr (), "^\\w" + Extended_Wordchars));
  pop_spot ();
}

% Is the chosen Aspell dictionary installed
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
  ifnot ((strtrim (str) == "*") || (strtrim (str) == "-"))
    add_keyword (Aspell_Typo_Table, Word);
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
define aspell_check_word ()
{
  variable word_prev = Word;

  Word = aspell_get_word ();

  ifnot (strlen (Word)) return;

  if (Word == word_prev)
    return flush ("double word");

  if (assoc_key_exists (Checked_Words, Word)) % don't check already checked words
    return;
  else
    Checked_Words[Word] = "";

  send_process (Aspell_Pid, "${Word}\n"$);
  get_process_input (5);
}

private define before_key_hook (fun)
{
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
  define_syntax ("-a-zA-Z" + Extended_Wordchars, 'w', Aspell_Typo_Table);
  use_syntax_table (Aspell_Typo_Table);
}

private define aspell_set_status_line ()
{
  if (Aspell_Flyspell)
    set_status_line (strreplace (Status_Line_String, "%m", "%m aspell[$Aspell_Dict|fly]"$), 0);
  else
    set_status_line (strreplace (Status_Line_String, "%m", "%m aspell[$Aspell_Dict]"$), 0);
}

% The initialization of the aspell flyspelling process
private define aspell_start_flyspell_process ()
{
  ifnot ((1 == Aspell_Flyspell) || (strlen (Aspell_Dict))) return;

  variable buf = whatbuf (), spellbuf = " *aspell*";

  % aspell_set_status_line ();
  setbuf (spellbuf);

  ifnot (Aspell_Pid == NULL)
    kill_process (Aspell_Pid);

  if (strlen (Aspell_Mode))
    Aspell_Pid = open_process ("aspell", Aspell_Mode, "-l", Aspell_Lang, "-d", Aspell_Dict, "-a", "-c", 7);
  else
    Aspell_Pid = open_process ("aspell", "-l", Aspell_Lang, "-d", Aspell_Dict, "-a", "-c", 6);

  if (-1 == Aspell_Pid)
  {
    Aspell_Pid = NULL;
    throw RunTimeError, "could not start aspell process";
  }

  set_process (Aspell_Pid, "output", &aspell_highlight_misspelled);
  process_query_at_exit (Aspell_Pid, 0);
  bury_buffer (spellbuf);
  setbuf (buf);
  aspell_setup_syntax ();
  aspell_set_status_line ();
  add_to_hook ("_jed_before_key_hooks", &before_key_hook);
}

% Pick an entry from a menu in the mini buffer and return it.
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
  ch = getkey ();

  if (ch == 'a')
  {
    add_word_to_personal_wordlist ();
  }
  else if (ch == 'e')
    return read_mini ("", "", aspell_get_word ());

  else ifnot (isdigit (ch))
    clear_message ();
  else
  {
    i = integer (char (ch));
    len = length (items_arr_n)-1;

    ifnot (any ([0:len] == i))
      throw UsageError, "type a digit between 0 and $len"$;
    else
      return items_arr[i];
  }

  return "";
}

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
  menu_append_item ($1, "Select Aspell &Dictionary", "aspell_select_dictionary");
  menu_append_item ($1, "&Suggest Correction", "aspell_suggest_correction");
  menu_append_item ($1, "&Toggle Spell Checking on the Fly", "toggle_aspell_flyspell");
}
append_to_hook ("load_popup_hooks", &aspell_popup_menu);
%}}}
%{{{ User functions
%% A Function to autocorrect oops-like typos, like typing "teh" instead of "the".
private define aspell_auto_replace_word ();
private define aspell_auto_replace_word (fun)
{
  ifnot (is_substr (" \r", LASTKEY)) return;

  variable repl_word = "", word = "", repl_buf = "", buf = whatbuf ();

  Aspell_Replacement_Wordlist = expand_filename ("~/.aspell_repl.$Aspell_Lang"$);
  repl_buf = " *$Aspell_Replacement_Wordlist*"$; % leading space trick hides the buffer

  if (0 == file_status (Aspell_Replacement_Wordlist))
    return remove_from_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

  word = aspell_get_word ();

  ifnot (strlen (word)) return;

  setbuf (repl_buf); % creates the buffer

  if (eobp () && bobp ())
  {
    () = insert_file (Aspell_Replacement_Wordlist);
    bob ();
  }

  if (bol_fsearch (word + ":"))
  {
    eol ();
    repl_word = aspell_get_word ();
    bob ();
    setbuf (buf);
    () = aspell_delete_word ();
    insert (repl_word);
    flush ("\"$word\" autocorrected to \"$repl_word\""$);
  }

  setbuf (buf);
}
if (Aspell_Use_Replacement_Wordlist)
 append_to_hook ("_jed_before_key_hooks", &aspell_auto_replace_word);

% Adds the word before or under the editing point to the user's personal aspell dictionary.
define add_word_to_personal_wordlist ()
{
  variable word = aspell_get_word ();

  () = system ("echo \"*${word}\n#\" | aspell -a -d $Aspell_Dict -l $Aspell_Lang >/dev/null"$);
  () = remove_keywords (Aspell_Typo_Table, word, strbytelen (word), 0);
  call ("redraw");
  flush ("\"$word\" added to personal wordlist"$);
}

% Use aspell's suggestions to replace a misspelling.
define aspell_suggest_correction ()
{
  variable ch, word = "", out = "", suggs, i = 0, sugg;
  variable cmd = "aspell --sug-mode=fast -B -l $Aspell_Lang -d $Aspell_Dict -a -c 2>/dev/null"$;
  % variable cmd = "aspell --sug-mode=ultra --run-together --run-together-limit=2 --run-together-min=3 -l $Aspell_Lang -d $Aspell_Dict -a -c 2>/dev/null"$;

  word = strtrim (aspell_get_word ());

  ifnot (strlen (word)) return;

  out = strtrim (strjoin (fgetslines (popen ("echo $word | $cmd"$, "r"))));

  try
  {
    if (out[[-1]] == "*")
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
  }
}

% Spellcheck the whole buffer. This is rather efficient: First it
% produces a list of misspelled words with the "aspell list" command,
% then groups those words together by size and feeds them to
% add_keywords() size by size. This function may be used without loading
% the entire minor mode.
public define aspell_buffer ()
{
  ifnot (strlen (Aspell_Dict))
  {
    aspell_set_dictionary_from_env ();
    aspell_select_dictionary ();
    aspell_set_filter_mode ();
  }

  variable
    tmpfile = make_tmp_file ("aspell_buffer"),
    cmd = "aspell list $Aspell_Mode -C -d $Aspell_Dict <$tmpfile"$,
    misspelled_words_n = String_Type[0],
    misspelled_words = String_Type[0],
    out = "",
    i = 0;

  out = strjoin (buf_as_words_array (), "\n");
  () = write_string_to_file (out, tmpfile);
  misspelled_words = strtrim (fgetslines (popen (cmd, "r")));

  _for i (2, 48, 1) % 48 is the keyword length limit.
  {
    misspelled_words_n = misspelled_words[where (strbytelen (misspelled_words) == i)];
    misspelled_words_n = misspelled_words_n[array_sort (misspelled_words_n)];
    misspelled_words_n = strjoin (misspelled_words_n, "");

    ifnot (strlen (misspelled_words_n)) continue;
    () = add_keywords (Aspell_Typo_Table, misspelled_words_n, i, 0);
  }

  () = delete_file (tmpfile);
  call ("redraw");
}

% Initialize the spell process with another aspell dictionary
define aspell_select_dictionary ()
{
  variable aspell_dicts = get_aspell_dicts ();

  Aspell_Dict = read_with_completion (aspell_dicts, "[Aspell] Select language (<TAB> lists):", Aspell_Dict, "", 's');
  aspell_verify_dict ();
  Aspell_Lang = Aspell_Dict;
  aspell_start_flyspell_process ();
  aspell_buffer ();

  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();
}

define toggle_aspell_flyspell ()
{
  Aspell_Flyspell = not (Aspell_Flyspell);

  ifnot (Aspell_Flyspell)
  {
    kill_process (Aspell_Pid);
    Aspell_Pid = NULL;
    create_syntax_table (Aspell_Typo_Table); % empties the syntax table
    call ("redraw");
    remove_from_hook ("_jed_before_key_hooks", &before_key_hook);
  }
  else
  {
    aspell_start_flyspell_process ();
    aspell_buffer ();
  }

  flush ("spell checking on the fly set to $Aspell_Flyspell"$);
  aspell_set_status_line ();
}

%}}}
%{{{ Minor mode initialization
define init_aspell ()
{
  if (NULL == search_path_for_file (getenv ("PATH"), "aspell"))
    return flush ("aspell is not installed or not in $PATH, spell checking disabled.");

  local_unsetkey_reserved ("a");
  local_setkey_reserved ("add_word_to_personal_wordlist", "a");
  local_unsetkey_reserved ("b");
  local_setkey_reserved ("aspell_buffer", "b");
  local_unsetkey_reserved ("d");
  local_setkey_reserved ("aspell_select_dictionary", "d");
  local_unsetkey_reserved ("s");
  local_setkey_reserved ("aspell_suggest_correction", "s");
  local_unsetkey_reserved ("t");
  local_setkey_reserved ("toggle_aspell_flyspell", "t");

  aspell_set_dictionary_from_env ();
  aspell_verify_dict ();
  aspell_set_filter_mode ();

  if ((1 == Aspell_Ask_Dictionary) || (0 == strlen (Aspell_Dict)))
  {
    Aspell_Ask_Dictionary = 0;
    return aspell_select_dictionary ();
  }

  if (Aspell_Use_Tabcompletion)
    load_tabcompletion ();

  if (NULL == Aspell_Pid)
    aspell_start_flyspell_process ();
  else
    use_syntax_table (Aspell_Typo_Table);

  aspell_buffer ();
}
%}}}
