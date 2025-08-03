% -*- mode: slang; mode: fold -*-

%{{{ Description, licence, version
%% spell.sl, an extension minor mode for the jed editor to spellcheck
%% a buffer as you type along and/or all at once.
%%
%% Consult the supplied README.spell.txt file for installation and
%% usage hints.
%%
%% Author: Morten Bo Johansen <mortenbo at hotmail dot com>
%% Licence: GPL, version 2 or later.
%%
%% Version: 0.9.4.1, 2025-08-03
%%
%}}}
%{{{ Requires
require("keydefs");
require("process");
require("pcre");
%}}}
%{{{ Custom variables

% A default for the spelling dictionary to use.
custom_variable("Spell_Dict", NULL);

% The base name (without full path) of a personal dictionary.
custom_variable("Spell_Personal_Dict", NULL);

% A user defined spell checking command
custom_variable("Spell_User_Cmd", NULL);

% Spell check as you type or not.
custom_variable("Spell_Flyspell", 1);

% What characters not normally part of a word, e.g. underscore,
% hyphen or apostrophe, might be included.
custom_variable("Spell_Extended_Wordchars", "");

% Select a spelling dictionary upon startup
custom_variable ("Spell_Ask_Dictionary", 0);

% The color for misspelled words
custom_variable("Spell_Misspelled_Color", "red");

% Use replacement word list to auto-correct misspellings or not. 0 = disable
custom_variable ("Spell_Use_Replacement_Wordlist", 1);

% Use word completion with the <tab> key (with tabcomplete.sl)
% 0 = disable
custom_variable ("Spell_Use_Tabcompletion", 0);

% Whether or not to spell check the buffer immediately after loading it.
% 0 = disable
custom_variable("Spell_Check_Buffer_On_Startup", 1);

% Do not check words of a length below or equal to this threshold
custom_variable("Spell_Minimum_Wordsize", 1);

% Do not check words that consist only of consonants
custom_variable("Spell_Ignore_Words_Without_Vowels", 0);

%}}}
%{{{ Autoloads
autoload("add_keywords", "syntax");
autoload("remove_keywords", "syntax");
autoload("fold_open_buffer", "folding");
autoload("get_comment_info", "comments");
#ifnexists init_tabcomplete
if (strlen (expand_jedlib_file ("tabcomplete.sl")))
  autoload ("init_tabcomplete", "tabcomplete");
#endif
%}}}
%{{{ Prototypes
define spell_add_word_to_personal_dict();
define spell_select_dictionary();
%}}}
%{{{ Private variables
private variable
  Spell_Pid = -1,
  Spell_Prg = "enchant-2",
  Word = "",
  Spell_Cmd = "",
  Spell_Replacement_Wordlist, 
  Spell_Misspelled_Table = "";
%}}}
%{{{ Private functions

% Use the new_process() function for some IO instead of popen(). If the
% process fails, the function returns NULL and prints the first line of the
% error message (if any) from the process in the echo area. Otherwise it
% returns the output from the process as an array of lines.
private define spell_popen(cmd)
{
  variable obj, w, lines = [""], err = "";

  obj = new_process(cmd ;; __qualifiers); % pass all qualifiers

  if (typeof(get_struct_field(obj, "fp1")) == File_Type)
  {
    lines = fgetslines(obj.fp1; trim=3);
    () = fclose(obj.fp1);
  }

  w = obj.wait(); % get some feedback from the process, including exit status

  if (w.exit_status != 0) % process failed
  {
    if (typeof(get_struct_field(obj, "fp2")) == File_Type)
    {
      () = fgets(&err, obj.fp2); % get first line of error message
    }

    if (length(err)) % prioritize showing the process' own error message
      vmessage("\"%s\" failed", strtrim(strjoin(err, "")));
    else
      vmessage("\"%s\" failed", strjoin(cmd, " "));

    return NULL;
  }

  return lines;
}

% Use a PCRE style regexp to replace a pattern in a string.
private define spell_pcre_replace(str, pat, rep)
{
  pat = pcre_compile(pat);
  
  if (pcre_exec(pat, str))
  {
    variable match = pcre_nth_substr(pat, str, 0);

    if (match != NULL)
      str = strreplace(str, match, rep);
  }

  return str;
}

% Return the word under or before the cursor.
private define _spell_get_word(delete)
{
  variable wchars = "\a"R + Spell_Extended_Wordchars;

  push_spot();
  bskip_chars(wchars); push_mark(); skip_chars(wchars);

  if (delete)
    bufsubstr_delete();
  else
    strtrim(bufsubstr());

  pop_spot();
}

private define spell_get_word()
{
  return _spell_get_word(0);
}

private define spell_delete_word()
{
  return _spell_get_word(1);
}

% Returns the key sequence from the getkey() function as a string.
private define spell_get_keysequence()
{
  variable s = char(getkey());
  while (input_pending(1))
    s += char(getkey());
  return s;
}

% The syntax table for misspelled words
private define spell_setup_syntax(tbl)
{
  if (tbl != what_syntax_table())
    create_syntax_table(tbl);

  Spell_Misspelled_Table = tbl;
  set_color("keyword", Spell_Misspelled_Color, "default");
  define_syntax("${Spell_Extended_Wordchars}a-zA-Z0-9"$, 'w', Spell_Misspelled_Table);
  use_syntax_table(Spell_Misspelled_Table);
}

% Pick an entry from a menu of at most 10 entries in the message area
% and return it.
private define spell_select_from_mini(items_arr)
{
  variable items_arr_n, len, i, ch, word;

  items_arr = strtrim(items_arr);
  len = length(items_arr);
  items_arr_n = String_Type[len];

  _for i (0, len-1, 1)
    items_arr_n[i] = strcat(string(i), "|",  items_arr[i]);

  if (length(items_arr_n) > 10)
    items_arr_n = items_arr_n[[0:9]];

  flush("c|ancel, a|dd, e|dit, " + strjoin(items_arr_n, " "));
  ch = spell_get_keysequence();

  if (ch == "a")
    spell_add_word_to_personal_dict();
  else if (ch == "e")
    return read_mini("", "", spell_get_word());
  else
  {
    ifnot (isdigit(ch))
    {
      clear_message();
    }
    else
    {
      i = integer(ch);
      return items_arr[i];
    }
  }

  return "";
}

private variable Suggestions = NULL; % value comes from check of word

private define spell_repl_with_sugg()
{
  variable sugg, suggs, signed;

  if (Suggestions == NULL || 0 == strlen(Suggestions)) return;

  signed = Suggestions[[0:0]]; % unrecognized words signed with '#' or '&'

  if (signed == "#")
    return flush("no suggestion");

  if (signed == "&")
    Suggestions = strtok(Suggestions, ":")[1]; 
    
  suggs = strtok(Suggestions);
  sugg = spell_select_from_mini(suggs);

  if (strlen(sugg))
  {
    () = spell_delete_word();
    insert(sugg);
    clear_message();
  }
}

% Return the available dictionaries as a comma separated string
private define spell_get_dicts()
{
  variable dicts;

  dicts = spell_popen(["enchant-lsmod-2", "-list-dicts"]; write={1,2});

  if (dicts == NULL) return;

  dicts = dicts[array_sort(strlen(dicts))];
  dicts = array_map(String_Type, &str_uncomment_string, dicts, "(", ")");
  dicts = strtrim(dicts);

  return strjoin(dicts, ",");
}

private define spell_str_has_vowels(str)
{
  variable vowels = "aeiouyøæåüïëäÿöáóéàèôîâûùœãąăěíőůúűýēėīųũúиоуыэюяαεηιοωυ";

  if (NULL != pcre_matches("[$vowels]"$, str; options=PCRE_CASELESS))
    return 1;

  return 0;
}

% Find the default spelling dictionary to use from some locale
% environment variables.
private define spell_set_dictionary_from_env()
{
  variable locale_values = array_map(String_Type,
                                     &getenv, ["LC_MESSAGES","LANG","LC_ALL"]);

  locale_values = locale_values[where(strlen(locale_values) >= 5)];

  ifnot (length(locale_values))
    throw RunTimeError, "could not set spelling dictionary from the environment";

  Spell_Dict = locale_values[0][[0:4]]; % e.g. de_AT

  if (blocal_var_exists("spell_dict"))
    set_blocal_var(Spell_Dict, "spell_dict");
}

private define spell_get_dict()
{
  if (Spell_Dict != NULL) return;

  if (Spell_User_Cmd != NULL)
    Spell_Dict = pcre_matches("-d\\h+([a-z]+)", Spell_User_Cmd)[-1];

  if (Spell_Dict == NULL)
    spell_set_dictionary_from_env();

  if (blocal_var_exists("spell_dict"))
    set_blocal_var(Spell_Dict, "spell_dict");
}

% Update the spell checking command with another dictionary.
% Give some information about some states of the mode in the status line
private define spell_set_status_line()
{
  variable backend, tabcomplete = "", fly = "";

  if (blocal_var_exists("spell_dict"))
    Spell_Dict = get_blocal_var("spell_dict");
    
  if (blocal_var_exists("spell_flyspell"))
  {
    if (1 == get_blocal_var("spell_flyspell"))
      fly = "|fly";
  }

  if (Spell_Use_Tabcompletion)
    tabcomplete = "|tabcomplete";

  if (Spell_User_Cmd != NULL)
    backend = "($Spell_Dict) "$ + pcre_matches("^([a-z]+)", Spell_User_Cmd)[-1];
  else
    backend = spell_popen(["enchant-lsmod-2", "-lang",
			   Spell_Dict]; write={1,2})[0];

  set_status_line(strreplace(Status_Line_String,
			     "%m", "%m " + backend + fly + tabcomplete), 0);
}

private define spell_set_cmd(dict)
{
  if (Spell_User_Cmd != NULL)
    Spell_Cmd = Spell_User_Cmd;

  Spell_Cmd = spell_pcre_replace(Spell_Cmd, "-d\\h+[-a-zA-Z0-9_,]+", "-d $dict"$);
}

private variable Is_Mispelled = 0;

% The parsing of the spell check word output
private define spell_highlight_misspelled(Spell_Pid, str)
{
  ifnot (strlen(strtrim(Word))) return;

  Suggestions = "";
  str = strtrim(str);
  
  % '*' is for a correctly spelled word found in the word list
  % '-' is for a word recognized as a compound word where its
  %     individual parts are spelled correctly.
  % '+' is for the root stem of a word
  ifnot ((str == "*") || ((str == "-")) || ((str == "+")))
  {
    add_keyword(Spell_Misspelled_Table, Word);
    Suggestions = str_delete_chars(str, ",");
    Is_Mispelled = 1;
  }
  else Is_Mispelled = 0;

  Word = "";
}

private variable Prev_Word = "";

% Spell check the word behind the cursor. Space or return keys trigger the
% function.
private define spell_check_word()
{
  Word = strtrim(spell_get_word());

  if (strlen(Word) <= Spell_Minimum_Wordsize) return;

  if (Spell_Ignore_Words_Without_Vowels)
    ifnot (spell_str_has_vowels(Word)) return;
  
  if (Word == Prev_Word)
    flush("double word");
  
  Prev_Word = Word;

  variable checked_words = get_blocal_var("checked_words");

  % don't check already checked words that are not misspelled
  ifnot (Is_Mispelled)
    if (assoc_key_exists(checked_words, Word)) return;

  checked_words[Word] = "";
  set_blocal_var(checked_words, "checked_words");
  
  send_process(Spell_Pid, "${Word}\n"$);
  get_process_input(3);
}

% The hook that triggers the spell checking of a word
private define spell_before_key_hook(fun)
{
  % Checking of word is triggered by <return> or <space> keys
  if (is_substr(" \r", LASTKEY))
    spell_check_word();
}

private define spell_signal_handler(pid, flags, status)
{
  variable msg;

  msg = aprocess_stringify_status(pid, flags, status);

  if (is_substr(msg, "exit")) % spell process failed
  {
    if (blocal_var_exists("spell_flyspell"))
    {
      set_blocal_var(0, "spell_flyspell");
      Spell_Flyspell = get_blocal_var("spell_flyspell");
    }
    remove_from_hook("_jed_before_key_hooks", &spell_before_key_hook);
    flush("could not start flyspell process, flyspelling disabled");
  }
}

private define spell_start_flyspell_process()
{
  variable cmd, buf = whatbuf(), spellbuf = " *spell", args;

  if (Spell_Pid != -1)
    kill_process(Spell_Pid);

  if (blocal_var_exists("spell_dict"))
    Spell_Dict = get_blocal_var("spell_dict");

  spell_set_cmd(Spell_Dict); % Spell_Cmd is set here
  args = strtok(Spell_Cmd);
  setbuf(spellbuf);
  
  foreach (args);
  length(args) - 1;
  Spell_Pid = open_process();

  set_process(Spell_Pid, "signal", &spell_signal_handler);
  set_process(Spell_Pid, "output", &spell_highlight_misspelled);
  
  % The flyspell check of the very first misspelled word will be sluggish,
  % because the spell checker has to initialize its interface of suggestions.
  % If one then keeps typing before it has properly finished, the subsequent
  % word may be seen as misspelled even if it isn't. So sending a
  % misspelled/unrecognized word to the flyspell process right after it
  % starts hopefully solves that little problem.
  send_process(Spell_Pid, "abcdef\n");
  process_query_at_exit(Spell_Pid, 0);
  setbuf(buf);
  spell_set_status_line();
  add_to_hook("_jed_before_key_hooks", &spell_before_key_hook);
}

private define spell_switch_buffer_hook(oldbuf)
{
  ifnot (blocal_var_exists("spell_dict")) return;

  Spell_Misspelled_Table = whatbuf();
  spell_setup_syntax(Spell_Misspelled_Table);

  % restart the flyspell process when switching buffer
  if (blocal_var_exists("spell_flyspell"))
  {
    if (1 == get_blocal_var("spell_flyspell"))
      spell_start_flyspell_process();
  }
  else
    remove_from_hook("_jed_before_key_hooks", &spell_before_key_hook);
}

private variable Cmt_Prefix_Beg = "", Cmt_Prefix_End = "";

% Isolate comments and strings. parse_to_point return values: -2 = cmts, -1 = strs
private define spell_get_strs_and_cmts()
{
  variable str, words, strs = String_Type[0];

  if (NULL == get_comment_info(get_mode_name))
    Cmt_Prefix_Beg = "#";
  else
  {
    Cmt_Prefix_Beg = strtrim(get_comment_info(get_mode_name).cbeg);
    Cmt_Prefix_End = strtrim(get_comment_info(get_mode_name).cend);
  }

  fold_open_buffer();
  push_spot_bob();

  do
  {
    if (parse_to_point() == -2) % cmts
    {
      push_mark();

      if (blooking_at("//")) % e.g. c++ or rust
        eol();
      else
      {
        if (strlen(Cmt_Prefix_End))
        {
          () = fsearch(Cmt_Prefix_End);
        }
        else eol();
      }
      
      strs = [strs, bufsubstr()];
      skip_chars(Cmt_Prefix_End);
    }
    if (parse_to_point() == -1) % strings
    {
      push_mark();

      while (parse_to_point() == -1)
        go_right_1();

      go_left_1();
      str = bufsubstr();
      strs = [strs, str];
    }
  }
  while (right(1));

  pop_spot();
  str = strjoin(strs, "\n");
  words = strtok(str);
  words = words[wherenot(array_map(Int_Type, &string_match, words, "\\<[A-Z0-9_*]+\\>", 1))];
  words = words[wherenot(array_map(Int_Type, &string_match, words, "0x.*", 1))];
  words = words[wherenot(array_map(Int_Type, &string_match, words, "\\.", 1))];
  str = strjoin(words, " ");

  return str;
}

private define spell_get_enchant_conf_dir()
{
  variable enchant_conf_dir = getenv("ENCHANT_CONFIG_DIR");
  variable xdg_config_home = getenv("XDG_CONFIG_HOME");

  if (NULL != enchant_conf_dir)
    return enchant_conf_dir;

  if (NULL != xdg_config_home)
    enchant_conf_dir = "${xdg_config_home}/enchant"$;
  else
    enchant_conf_dir = expand_filename("~/.config/enchant");

  if (2 != file_status(enchant_conf_dir))
    () = spell_popen(["mkdir", "-p", enchant_conf_dir]; write={1,2});

  return enchant_conf_dir;
}

% Return the word list used for completion with tabcomplete
private define spell_set_tabcompletion_wordlist ()
{
  spell_get_dict(); % Spell_Dict is derived from here
  return expand_filename ("~/.tabcomplete_$Spell_Dict"$);
}

% Load the tabcompletion extension with a word list that corresponds
% to the language of the aspell dictionary being used.
private define load_tabcompletion ()
{
  try
  {
    variable fun = __get_reference ("init_tabcomplete");

    if (fun != NULL)
      (@fun (spell_set_tabcompletion_wordlist));
  }
  catch OpenError:
  {
    flush("could not load .tabcomplete_$Spell_Dict"$);
    sleep(1);
  }
}

%% A Function to auto correct misspellings.
private define spell_auto_replace_word ();
private define spell_auto_replace_word (fun)
{
  ifnot (is_substr(" \r", LASTKEY)) return;

  variable repl_word = "", word = "";

  spell_get_dict();
  Spell_Replacement_Wordlist = expand_filename ("~/.spell_repl.$Spell_Dict"$);

  if (0 == file_status (Spell_Replacement_Wordlist))
    return remove_from_hook ("_jed_before_key_hooks", &spell_auto_replace_word);

  word = spell_get_word ();

  ifnot (strlen (word)) return;
  ifnot (search_file(Spell_Replacement_Wordlist, "^$word *:"$, 1)) return;

  repl_word = ();
  repl_word = strtrim(strchop(repl_word, ':', 0))[1];
  () = spell_delete_word ();
  insert (repl_word);
  flush ("\"$word\" auto corrected to \"$repl_word\""$);
}

% Check if the chosen dictionary is usable.
private define spell_check_dict(dict)
{
  if (NULL == spell_popen([Spell_Prg, "-d", dict, "-a"];
                          stdin="/dev/null", write={1,2}))
  {
    spell_select_dictionary();
  }
}
%}}}
%{{{ User functions

define spell_suggest_correction()
{
  spell_check_word(); % gets the suggestions
  spell_repl_with_sugg(); % menu w/suggestions
}

% Adds the word before or under the editing point to the user's personal
% spelling dictionary. Remove the coloring of the word on the same token.
define spell_add_word_to_personal_dict()
{
  variable pers_words, dict, pers_word_list, misspelled_words;
  variable enchant_conf_dir = spell_get_enchant_conf_dir();
  variable word = spell_get_word();

  ifnot (strlen(word)) return;

  if (blocal_var_exists("spell_dict"))
    dict = get_blocal_var("spell_dict");
  
  if (blocal_var_exists("personal_dict"))
  {
    pers_word_list = get_blocal_var("personal_dict");

    if (NULL != pers_word_list)
    {
      if (Spell_Prg == "aspell")
	Spell_Personal_Dict = expand_filename("~/.aspell.${dict}.pws"$);
      else
	Spell_Personal_Dict = "${enchant_conf_dir}/$pers_word_list"$;
    }
  }
    
  % If word is added to the personal wordlist, it means that it should not
  % be seen as misspelled anymore and therefore it should also be removed from
  % the array of misspelled words.
  if (blocal_var_exists("misspelled_words"))
  {
    misspelled_words = get_blocal_var("misspelled_words");
    misspelled_words = misspelled_words[wherenot(misspelled_words == word)];
    set_blocal_var(misspelled_words, "misspelled_words");
  }

  pers_words = spell_popen(["cat", Spell_Personal_Dict]; write={1,2});

  if (any(word == pers_words))
    return flush("$word already present in $Spell_Personal_Dict"$);

  % aspell's personal dictionaries are incompatible with enchant's/hunspell's
  if (Spell_Prg == "aspell")
    () = system("echo '*${word}\n#' | aspell -d $dict -a >/dev/null"$);
  else
    () = system("echo $word >> $Spell_Personal_Dict 2>/dev/null"$);

  () = remove_keywords(Spell_Misspelled_Table, word, strbytelen(word), 0);
  call("redraw");
  flush("\"$word\" added to personal wordlist, $Spell_Personal_Dict"$);
}

% Remove the color highlighting of a word marked as misspelled.
define spell_remove_word_highligtning()
{
  variable word = spell_get_word();
  () = remove_keywords(Spell_Misspelled_Table, word, strbytelen(word), 0);
  call("redraw");
}

% Initialize the spell process with another spelling dictionary
define spell_select_dictionary()
{
  variable dicts = spell_get_dicts(), dict, spell_dicts;
  
  if (blocal_var_exists("spell_dict"))
    Spell_Dict = get_blocal_var("spell_dict");

  ungetkey('\t');
  Spell_Dict = read_with_completion(dicts, "[Spell] Select dictionary:",
                                    Spell_Dict, "", 's');

  spell_dicts = strtok(Spell_Dict, ","); % multiple dictionaries may be specified
    
  foreach dict (spell_dicts)
  {
    ifnot (is_list_element(dicts, strtrim(dict), ','))
      throw RunTimeError, "you set Spell_Dict to \"$Spell_Dict\" but dictionary,"$ +
                          "\"$dict\", is not installed"$;
  }

  if (blocal_var_exists("spell_dict"))
    set_blocal_var(Spell_Dict, "spell_dict");

  Spell_Personal_Dict = "${Spell_Dict}.dic"$;

  if (blocal_var_exists("personal_dict"))
    set_blocal_var(Spell_Personal_Dict, "personal_dict");

  spell_set_cmd(Spell_Dict); % Spell_Cmd is set here

  if (blocal_var_exists("spell_flyspell"))
  {
    if (1 == get_blocal_var("spell_flyspell"))
      spell_start_flyspell_process();
  }

  % load the corresponding completion file
  if (Spell_Use_Tabcompletion)
  {
    ifnot (is_substr(Spell_Dict, ",")) % do not load w/multiple dictionaries
      load_tabcompletion ();
  }

  Spell_Replacement_Wordlist = expand_filename ("~/.spell_repl.$Spell_Dict"$);
  spell_set_status_line();
  spell_buffer();
}

% Spellcheck the whole buffer, without having to save the file associated
% with it first. This function may be used without loading the entire minor
% mode.
public define spell_buffer()
{
  if (NULL == search_path_for_file(getenv("PATH"), Spell_Prg))
    return flush("enchant is not installed or not in $PATH");

  if (eobp() && bobp()) return;

  variable
    enchant_conf_dir = spell_get_enchant_conf_dir(),
    tmpfile = make_tmp_file("spell_buffer"),
    tmpfile1 = make_tmp_file("spell_buffer1"),
    pers_dict_word_arr,
    misspelled_words,
    misspelling,
    list = "-l",
    pers_dict,
    mode_flags,
    dict,
    cmd,
    i = 0;

  % if minor mode is not loaded and this function is used on its own,
  % then ask user for a dictionary.
  ifnot (blocal_var_exists("spell_dict")) % minor mode is not loaded
  {
    if (NULL == search_path_for_file(getenv("PATH"), "enchant-2"))
      return flush("Could not find enchant-2, can't spell check.");

    dict = read_with_completion (spell_get_dicts, "dictionary?", "", "", 's');
    Spell_Misspelled_Table = whatbuf();
    Spell_Cmd = "enchant-2 -d $dict -a"$;
  }
  else
    dict = get_blocal_var("spell_dict");
 
  (, mode_flags) = what_mode();

  if (mode_flags > 1) % programming language modes -> only check comments/strings
  {
    () = write_string_to_file(spell_get_strs_and_cmts(), tmpfile);
    no_mode();
  }
  else
  {
    push_spot_bob(); push_mark_eob();
    () = write_string_to_file(bufsubstr(), tmpfile);
    pop_spot();
  }

  if (Spell_Personal_Dict == NULL)
    Spell_Personal_Dict = "${dict}.dic";

  flush(sprintf("spell checking %s ...", whatbuf()));

  create_syntax_table(Spell_Misspelled_Table); % empties the existing one
  spell_setup_syntax(Spell_Misspelled_Table);

  if (Spell_Prg == "aspell")
    pers_dict = expand_filename("~/.aspell.${dict}.pws"$);
  else
    pers_dict = "${enchant_conf_dir}/$Spell_Personal_Dict"$;

  % hunspell/enchant use "-l", aspell uses "list" to produce a list of
  % misspelled words.
  if (Spell_Prg == "aspell")
    list = "list";

  cmd = spell_pcre_replace(Spell_Cmd, "$Spell_Prg"$, "$Spell_Prg $list"$);
  cmd = strtok(cmd);
  misspelled_words = spell_popen(cmd; write={1,2}, stdin=tmpfile, stdout=tmpfile1);
  misspelled_words = spell_popen(["sort", "-u"]; write={1,2}, stdin=tmpfile1);

  () = remove(tmpfile);
  () = remove(tmpfile1);
  
  if (misspelled_words == NULL) return;

  ifnot (length(misspelled_words))
    return flush("no spelling errors found");

  misspelled_words = misspelled_words[where(array_map(Int_Type, &strlen,
                                            misspelled_words) >
                                            Spell_Minimum_Wordsize)];

  if (Spell_Ignore_Words_Without_Vowels)
    misspelled_words = misspelled_words[where(array_map(Int_Type,
                                              &spell_str_has_vowels(),
                                              misspelled_words))];

  if (blocal_var_exists("misspelled_words"))
    set_blocal_var(misspelled_words, "misspelled_words");

  % Return the words in the personal dictionary as an array.
  pers_dict_word_arr = spell_popen(["cat", pers_dict]; write={1,2});

  % This modifies the spell checker's own mechanism for looking up words in
  % the personal dictionary. Especially, some hunspell dictionaries strangely
  % include the period, '.', as a valid word character even at the end of a
  % word, so in those cases a misspelled word with an affixed period such as
  % a word at the end of a sentence will be seen by hunspell as "<word>.", so
  % you must actually add both the word with and without the period to the
  % personal wordlist if you don't want the word to be seen as misspelled
  % by hunspell anymore. This little hack solves that.
  _for i (0, length(misspelled_words)-1, 1)
  {
    misspelling = misspelled_words[i];

    if (strbytelen(misspelling) > 48) continue; % maximum keyword length

    ifnot (any(misspelling == pers_dict_word_arr))
      add_keyword (Spell_Misspelled_Table, misspelling);
  }

  call("redraw");
}

% Go to the next misspelled word. This only works after having spell
% checked the whole buffer with spell_buffer().
define spell_goto_misspelled(dir)
{
  variable misspelled_words;
  
  if (blocal_var_exists("misspelled_words"))
  {
    misspelled_words = get_blocal_var("misspelled_words");
    
    ifnot (length(misspelled_words))
      return flush("you must spell check the buffer first");
  }
  
  if (dir < 0)
  {
    while (not (bobp()))
    {
      bskip_word();
      skip_non_word_chars();
      if (any(spell_get_word == misspelled_words)) return;
    }
  }
  else
  {
    do
    {
      skip_word();
      skip_non_word_chars();
      if (any(spell_get_word == misspelled_words)) return;
    }
    while (not (eobp()));
  }
}
%}}}
%{{{ Keymap
private variable Mode = "spell";

% The keymap for the mode
ifnot (keymap_p(Mode))
  copy_keymap(Mode, what_keymap());

definekey("spell_goto_misspelled(1)", Key_Shift_Down, Mode);
definekey("spell_goto_misspelled(-1)", Key_Shift_Up, Mode);
definekey_reserved("spell_add_word_to_personal_dict", "a", Mode);
definekey_reserved("spell_buffer", "b", Mode);
definekey_reserved("spell_select_dictionary", "d", Mode);
definekey_reserved("spell_suggest_correction", "s", Mode);
definekey_reserved("spell_remove_word_highligtning()", "R", Mode);
%}}}
%{{{ Menu
% A menu addition to the "System" menu pop up.
private define spell_popup_menu()
{
  menu_append_popup("Global.S&ystem", "&Spell");
  $1 = "Global.S&ystem.&Spell";
  menu_append_item($1, "&Add Word to Personal Dictionary", "spell_add_word_to_personal_dict");
  menu_append_item($1, "Spellcheck &Buffer", "spell_buffer");
  menu_append_item($1, "Select Spell &Dictionary", "spell_select_dictionary");
  menu_append_item($1, "&Suggest Correction", "spell_suggest_correction");
  menu_append_item($1, "&Remove Misspelled Highlighting", "spell_remove_word_highligtning()");
  menu_append_item($1, "Go to &Next Misspelled", "spell_goto_misspelled(1)");
  menu_append_item($1, "Go to &Previous Misspelled", "spell_goto_misspelled(-1)");
}
append_to_hook ("load_popup_hooks", &spell_popup_menu);
%}}}
%{{{ Minor mode initialization
define spell_init()
{
  ifnot (blocal_var_exists("checked_words"))
    define_blocal_var("checked_words", Assoc_Type[String_Type, ""]);

  ifnot (blocal_var_exists("misspelled_words"))
    define_blocal_var("misspelled_words", String_Type[0]);

  ifnot (blocal_var_exists("spell_flyspell"))
    define_blocal_var("spell_flyspell", Spell_Flyspell);

  spell_get_dict(); % Spell_Dict is set here

  % With multiple dictionaries specified, whitespace is not accepted
  Spell_Dict = str_delete_chars(Spell_Dict, "\\s");

  ifnot (blocal_var_exists("spell_dict"))
    define_blocal_var("spell_dict", Spell_Dict);

  if (Spell_Personal_Dict == NULL)
    Spell_Personal_Dict = "${Spell_Dict}.dic"$;

  ifnot (blocal_var_exists("personal_dict"))
    define_blocal_var("personal_dict", Spell_Personal_Dict);

  if (Spell_User_Cmd == NULL)
    Spell_Cmd = "enchant-2 -d $Spell_Dict -a"$;
  else
    Spell_Cmd = Spell_User_Cmd;
  
  Spell_Misspelled_Table = whatbuf();
  spell_setup_syntax(Spell_Misspelled_Table);
  spell_check_dict(Spell_Dict);
  use_keymap(Mode);
  spell_set_status_line();
  Spell_Prg = strtok(Spell_Cmd)[0];
  
  if (NULL == search_path_for_file(getenv("PATH"), Spell_Prg))
    return flush("Could not find \"$Spell_Prg\", spell checking disabled."$);

  if (1 == Spell_Ask_Dictionary)
  {
    Spell_Ask_Dictionary = 0;
    return spell_select_dictionary ();
  }

  if (Spell_Check_Buffer_On_Startup)
    spell_buffer();

  if (Spell_Use_Tabcompletion)
  {
    ifnot (is_substr(Spell_Dict, ",")) % don't load with multiple dictionaries
      load_tabcompletion ();
  }

  if (Spell_Use_Replacement_Wordlist)
    append_to_hook ("_jed_before_key_hooks", &spell_auto_replace_word);

  if (1 == get_blocal_var("spell_flyspell"))
  {
    spell_start_flyspell_process();
    add_to_hook("_jed_switch_active_buffer_hooks", &spell_switch_buffer_hook);
  }
}
%}}}
