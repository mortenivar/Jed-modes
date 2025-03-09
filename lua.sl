% lua.sl, a Jed major mode to facilitate the editing of lua code
% Author: Morten Bo Johansen, mortenbo at hotmail dot com
% License: GPLv3
% Version 0.2.4.1 (2025/03/07)
require("pcre");
require("keydefs");
autoload("add_keywords", "syntax");

% The default number of spaces per indentation level
custom_variable ("Lua_Indent_Default", 3);

% Typing <enter> after a conditional or looping keyword will expand to
% the full syntax of the keyword.
custom_variable ("Lua_Expand_Kw_Syntax", 1);

% The options to the luacheck command. "--no-color" should never be
% removed, otherwise there will be ansi color codes in the output.
custom_variable ("Luacheck_Cmd_Opts", "--no-color --no-global --no-unused --codes");

private variable Mode = "Lua";
private variable Syntax_Table = Mode;
private variable Lua_Kw_Expand_Hash = Assoc_Type[String_Type, ""];

% These are all highlighted
private variable Lua_Reserved_Keywords =
  ["and","break","do","else","elseif","end","false","for","function","if","in",
   "local","nil","not","or","repeat","return","then","true","until","while"];

% For highlighting. Many function names are strung together from a
% library name and an associated function name, such as in
% "string.reverse", but as you cannot use dots in keywords used with
% the add_keywords() function, they are split up here. DFA syntax is
% not well suited for this mode. This may give an occasional unwanted
% highlighting.
private variable Lua_Funcs =
  ["assert","collectgarbage","dofile","error","getmetatable","ipairs","load",
    "loadfile","next","pairs","pcall","print","rawequal","rawget","rawlen","rawset",
    "select","setmetatable","tonumber","tostring","type","_VERSION","warn","xpcall",
    "close","create","isyieldable","resume","running","status","wrap","coroutine",
    "yield","require","config","cpath","loaded","loadlib","path","preload",
    "searchers","package","searchpath","byte","char","dump","find","format",
    "gmatch","gsub","len","lower","match","pack","packsize","rep","reverse","sub",
    "unpack","string","upper","char","charpattern","codes","codepoint","len",
    "utf8","offset","concat","insert","move","pack","remove","sort","table",
    "unpack","abs","acos","asin","atan","ceil","cos","deg","exp","floor","fmod",
    "huge","log","max","maxinteger","min","mininteger","modf","pi","rad","random",
    "randomseed","sin","sqrt","tan","tointeger","type","math","ult","close",
    "flush","input","lines","open","output","popen","read","tmpfile","type",
    "io","write","close","flush","lines","read","seek","file","setvbuf","write",
    "clock","date","difftime","execute","exit","getenv","remove","rename",
    "setlocale","time","os","tmpname","gethook","getinfo","getlocal","getmetatable",
    "getregistry","getupvalue","getuservalue","sethook","setlocal","setmetatable",
    "setupvalue","setuservalue","traceback","upvalueid","debug","upvaluejoin"];

% Keywords that begin a block or sub-block
private variable Lua_Block_Beg_Kws =
  ["function","if","else","elseif","for","do","while","repeat","{","}{","\\("];

% Keywords that end a block or sub-block
private variable Lua_Block_End_Kws = ["end","until","}","\\)","}{"];

% The PCRE regular expression that vets a string for keywords that
% should or should not affect indentation. It is meant to do the
% following:
%
% - Match and capture keywords: 'function', 'if', 'else', 'elseif',
%   'while', 'for', 'do', 'end', 'repeat', 'until', as whole
%   words as well as delimiters '}', '{', ')', '(' 
%
% - If keywords, 'if', 'for', 'while', 'do' are followed by zero or more
%   characters and then followed by the 'end' keyword on the same line,
%   all matched as whole words, return NULL.
%
% - If keywords, 'elseif', 'function' or 'end', is present in a line
%   with other keywords, always give priority to capturing those
%   keywords with 'elseif' given the highest priority.
%   
% - If the resulting capture is enveloped in single or double quotes,
%   return NULL.
variable Pat = "(?<![\"'])^\\h*\\b(elseif)\\b|(^.*?\\b(function|if|for|while|" +
               "do)\\b.*\\bend\\b(*SKIP)(*F))|^(?:.*\\b(end|function)\\b|" +
               ".*?\\b(if|else|elseif|for|while|repeat|until)\\b|" +
               "^\\h*\\b(do)\\b|(?:.*?([}{\)\(])))(?![\"'])";

% Associative array to insert and expand syntaxes for its keys
Lua_Kw_Expand_Hash["if"] = " @ then\n \nend";
Lua_Kw_Expand_Hash["elseif"] = " @ then\n ";
Lua_Kw_Expand_Hash["for"] = " @ in do\n \nend";
Lua_Kw_Expand_Hash["while"] = " @ do\n \nend";
Lua_Kw_Expand_Hash["repeat"] = " @ \n \nuntil";
Lua_Kw_Expand_Hash["function"] = " @ \n \nend";

% Add keywords to a syntax table for highlighting
private define add_kws_to_table(kws, tbl, n)
{
  variable kws_i, i;

  _for i (1, 48, 1) % 48 is the keyword length limit.
  {
    kws_i = kws[where(strlen(kws) == i)];
    kws_i = kws_i[array_sort (kws_i)];
    kws_i = strtrim(kws_i);
    kws_i = strjoin(kws_i, "");

    ifnot (strlen (kws_i)) continue;

    () = add_keywords(Syntax_Table, kws_i, i, n);
  }
}

% Block strings - "[[ ... ]]" not supported.
private define lua_setup_syntax()
{
  variable bg;

  (, bg) = get_color("normal"); % get the current background color
  set_color("keyword", "red", bg);
  set_color("operator", "yellow", bg);
  create_syntax_table(Syntax_Table);
  define_syntax ("--", "", '%', Syntax_Table); % comments
  define_syntax ("--[[", "]]", '%', Syntax_Table); % block comments
  define_syntax ("{(", "})", '(', Syntax_Table);
  define_syntax ("([{", ")]}", '(', Syntax_Table);
  define_syntax('"', '"', Syntax_Table); % strings
  define_syntax('`', '"', Syntax_Table); % strings
  define_syntax('\'', '\'', Syntax_Table);
  define_syntax('\\', '\\', Syntax_Table);
  define_syntax("0-9a-zA-Z_", 'w', Syntax_Table); % words
  define_syntax ("-+0-9.eE", '0', Syntax_Table); % Numbers
  define_syntax(",;:.", ',', Syntax_Table);
  define_syntax("-+/&%*=<>|!~^", '+', Syntax_Table);
  set_syntax_flags (Syntax_Table, 0); % case sensitive keywords
  use_syntax_table(Syntax_Table);
}

private define lua_line_as_str()
{
  push_spot_bol(); push_mark_eol(); bufsubstr(); pop_spot();
}

% Checks if a pcre style regex pattern matches in the current line.
private define lua_re_match_line(re)
{
  pcre_exec(pcre_compile(re), lua_line_as_str());
}

% A regular expression version of ffind(). It checks if the match
% being in a string or comment and if so, then tries to see if there
% are subsequent matches on the line that might not be.
private define lua_re_ffind(re)
{
  variable pos = 0, p = pcre_compile(re);

  while (pcre_exec(p, lua_line_as_str(), pos))
  {
    pos = pcre_nth_match(p, 0)[0];
    goto_column(pos + 1);
    pos += 1;
    if (0 == parse_to_point()) break;
  }
}

% If number of left and right delimiters in a line is uneven, return
% the unbalanced delimiter.
private define lua_get_unbalanced_delim(ldelim, rdelim)
{
  variable ldelim_n = 0, rdelim_n = 0, line = lua_line_as_str();
  line = str_uncomment_string(line,"\"", "\"");
  line = str_uncomment_string(line,"\'", "\'");
  ldelim_n = count_char_occurrences(line, ldelim);
  rdelim_n = count_char_occurrences(line, rdelim);

  if (ldelim_n > rdelim_n)
    return char(ldelim);
  if (rdelim_n > ldelim_n)
    return char(rdelim);

  return NULL;
}

% Find the line of a matching beginning delimiter.
private define lua_get_indent_matching_delim(delim, matching_delim)
{
  variable cnt = 0;

  do
  {
    if (string_match(lua_line_as_str(), char(delim), 1))
      if (char(delim) == lua_get_unbalanced_delim(delim, matching_delim)) cnt++;
    if (string_match(lua_line_as_str(), char(matching_delim), 1))
      if (char(matching_delim) ==
          lua_get_unbalanced_delim(delim, matching_delim)) cnt--;

    if (cnt == 0) break;
  }
  while (up(1));
}

% Capture a Lua keyword or a delimiter in a line
private define lua_get_kw()
{
  variable kws, kw = NULL, ldelim_n, rdelim_n;
  variable line = lua_line_as_str();

  % remove a trailing comment part in a line
  if (lua_re_match_line("^.+\\h*--"))
    line = pcre_matches("(^.*)\\h*--.*?$", line)[-1];

  kws = pcre_matches(Pat, line);
  kws = kws[[1:]];
  kws = kws[wherenot(_isnull(kws))];

  ifnot (length(kws)) return NULL;

  kw = kws[-1];

  if (any(kw == ["(",")"]))
    kw = lua_get_unbalanced_delim('(',')');

  if (any(kw == ["{","}"]))
  {
    kw = lua_get_unbalanced_delim('{','}');

    if (lua_re_match_line("^\\h*},\\h*{\\h*$"))
      kw = "}{";
  }

  push_spot();

  if (any(kw == ["{","}",")","("]))
  {
    % This captures the outermost delimiter of matches like ")}" or
    % "})" as this is the one that should be used for finding the line
    % with the matching delimiter and therefore the correct
    % indentation. It should have been done in the keyword pattern
    % regexp, but I couldn't make it fit in ...
    if (lua_re_match_line("[}\)][}\)]\\h*$"))
      kw = pcre_matches("[)}]([)}])", lua_line_as_str())[-1];

    kw = str_quote_string(kw, "()", '\\');
    lua_re_ffind(kw);
  }
  else
    lua_re_ffind("\\b$kw\\b"$);

  if (0 != parse_to_point())
    kw = NULL;

  pop_spot();

  if (kw != NULL)
    kw = strtrim(kw);

  return kw;
}

% Find the keyword that matches the level of an 'end' keyword.
define lua_find_end_matching_level()
{
  variable kw, end_cnt = 0;

  do
  {
    bol();
    kw = lua_get_kw();
    if (kw == "end") end_cnt++;
    if (any(kw == ["if","for","while","function"])) end_cnt--;
    if (end_cnt == 0) break;
  }
  while (up(1));
}

% Return the keyword in the current line plus the keyword and its
% column in a preceding line.
private define lua_find_kw_prev_kw_and_col()
{
  variable this_kw = NULL, prev_kw = NULL, prev_kw_col = 0;

  push_spot();
  this_kw = lua_get_kw();

  try
  {
    if (this_kw == "end")
    {
      lua_find_end_matching_level();
      prev_kw = lua_get_kw();
    }
    else if (this_kw == "}")
    {
      prev_kw = "{";
      lua_get_indent_matching_delim('{', '}');
    }
    else if (this_kw == "\\)")
    {
      prev_kw = "\\(";
      lua_get_indent_matching_delim('(', ')');
    }
    else if (this_kw == "until")
    {
      while (up(1))
      {
        bol();
        prev_kw = lua_get_kw();
        % supports nested repeat ... until
        if ((prev_kw == "until") || (prev_kw == "repeat")) break;
      }
    }
    else
    {
      while (up(1))
      {
        bol();
        prev_kw = lua_get_kw();
        if (prev_kw != NULL) return;
      }
    }
  }
  finally
  {
    bol_skip_white();
    prev_kw_col = _get_point();
    pop_spot();
    return this_kw, prev_kw, prev_kw_col;
  }
}

% Return the point in the line to indent to
private define lua_get_indentation()
{
  variable this_kw = NULL, prev_kw = NULL, prev_kw_col = 0;

  (this_kw, prev_kw, prev_kw_col) = lua_find_kw_prev_kw_and_col();

  if (this_kw == "}{") this_kw = "}";
  if (prev_kw == "}{") prev_kw = "{";

  if (prev_kw == NULL) return 0;

  if (any(this_kw == ["}","\\)"]))
    return prev_kw_col;

  if (this_kw == "end" && any(prev_kw == Lua_Block_Beg_Kws))
    return prev_kw_col;

  if (any(this_kw == ["else","elseif"]) && not any(prev_kw == ["if","elseif"]))
    return prev_kw_col - Lua_Indent_Default;

  if (any(this_kw == ["end","until"]) && any(prev_kw == ["end","until","{","}"]))
    return prev_kw_col - Lua_Indent_Default;

  if (any(this_kw == ["else","elseif","until"]))
    return prev_kw_col;

  if (any(prev_kw == Lua_Block_End_Kws))
    return prev_kw_col;

  if (any(prev_kw == Lua_Block_Beg_Kws))
    return prev_kw_col + Lua_Indent_Default;

  return NULL;
}

private define lua_indent_line()
{
  variable indentation = lua_get_indentation();

  if (indentation == NULL) return skip_white();

  bol(); trim(); insert_spaces(indentation);
}

private define _lua_newline_and_indent()
{
  bskip_white();
  push_spot(); lua_indent_line(); pop_spot();
  insert("\n");
  lua_indent_line();
}

define lua_indent_region_or_line()
{
  variable reg_endline, i = 1;

  ifnot (is_visible_mark())
    return lua_indent_line();

  check_region(0);
  reg_endline = what_line();
  pop_mark_1();

  do
  {
    flush (sprintf ("indenting buffer ... (%d%%)", (i*100)/reg_endline));
    if (eolp() and bolp()) continue;
    lua_indent_line();
    i++;
  }
  while (down(1) and what_line != reg_endline);
  clear_message();
}

% Insert and expand a code block
private define lua_insert_and_expand_syntax()
{
  variable kw = lua_get_kw();

  if ((kw == NULL) ||
      (0 == assoc_key_exists(Lua_Kw_Expand_Hash, kw) ||
      (0 == blooking_at(kw))))
    return _lua_newline_and_indent();

  push_visible_mark();
  insert (Lua_Kw_Expand_Hash[kw]);
  if (eobp()) insert("\n");
  go_right_1();
  exchange_point_and_mark();
  lua_indent_region_or_line();
  clear_message();
  () = re_bsearch("@");
  () = replace_match("", 1);
}

define lua_newline_and_indent()
{
  if (Lua_Expand_Kw_Syntax)
    return lua_insert_and_expand_syntax();

  _lua_newline_and_indent();
}

% Show output from execution of lua code in a marked region or entire
% buffer. Does not work with xjed.
define lua_exec_region_or_buffer()
{
  if (is_defined("x_server_vendor"))
    throw RunTimeError, "only works in a terminal, sorry";

  variable pager = search_path_for_file(getenv("PATH"), "most");
  variable tmpfile = make_tmp_file("/tmp/lua_exec");
  variable err_file = make_tmp_file("/tmp/lua_exec_err");
  variable lua = search_path_for_file(getenv("PATH"), "lua");

  if (lua == NULL)
    throw RunTimeError, "lua not found";

  if (pager == NULL)
  {
    pager = search_path_for_file(getenv("PATH"), "less");
    pager = "$pager -c"$;
  }
  if (pager == NULL)
    pager = search_path_for_file(getenv("PATH"), "more");

  if (-1 == access("/tmp", W_OK))
    throw RunTimeError, "you don't have write access to /tmp";

  if (markp())
    () = write_region_to_file(tmpfile);
  else
  {
    push_spot_bob(); push_mark_eob();
    () = write_region_to_file(tmpfile);
    pop_spot();
  }

  try
  {
    if (0 != run_program("clear && $lua -i $tmpfile 2>$err_file"$))
    {
      if (0 != run_program("$pager $err_file"$))
        throw RunTimeError, "execution failed";
    }
  }
  finally
  {
    () = remove(tmpfile);
    () = remove(err_file);
  }
}

private variable Luacheck_Lines = Int_Type[0];
private variable Luacheck_Linenos = Int_Type[0];
private variable Luacheck_Err_Cols = Int_Type[0];
private variable Luacheck_Error_Color = color_number("preprocess");

% Reset the luacheck error index and remove line coloring.
private define lua_luacheck_reset()
{
  push_spot_bob();

  do
    if (get_line_color == Luacheck_Error_Color)
      set_line_color(0);
  while (down(1));

  pop_spot();
  Luacheck_Lines = Int_Type[0];
  Luacheck_Linenos = Int_Type[0];
  Luacheck_Err_Cols = Int_Type[0];
  call("redraw");
}

private define lua_switch_buffer_hook (old_buffer)
{
  variable mode;
  (mode,) = what_mode();

  if (mode == "Lua")
    lua_luacheck_reset();
}
add_to_hook ("_jed_switch_active_buffer_hooks", &lua_switch_buffer_hook);

% Check the current buffer for errors/warnings using the luacheck program
define lua_luacheck_buffer()
{
  variable luacheck = search_path_for_file(getenv("PATH"), "luacheck");
  variable line, col, lineno, lineno_col, fp, cmd;
  variable tmpfile = make_tmp_file("/tmp/luacheck_tmpfile");

  if (luacheck == NULL)
    throw RunTimeError, "luacheck program not found";

  lua_luacheck_reset();
  push_spot_bob(); push_mark_eob();
  () = write_string_to_file(bufsubstr(), tmpfile);
  pop_spot();
  cmd = "$luacheck $Luacheck_Cmd_Opts $tmpfile"$;
  flush("Indexing luacheck errors/warnings ...");
  fp = popen (cmd, "r");
  Luacheck_Lines = fgetslines(fp);
  () = pclose (fp);
  () = delete_file(tmpfile);
  Luacheck_Lines = Luacheck_Lines[where(array_map(Int_Type, &string_match,
                                                  Luacheck_Lines,
                                                  "\\d+:\\d+", 1))];
  ifnot (length(Luacheck_Lines))
    return flush("luacheck reported no errors or warnings");

  push_spot();

  foreach line (Luacheck_Lines)
  {
    lineno_col = pcre_matches(":(\\d+):(\\d+)", line);
    lineno = integer(lineno_col[1]);
    col = integer(lineno_col[2]);
    goto_line(lineno);
    set_line_color(Luacheck_Error_Color);
    Luacheck_Linenos = [Luacheck_Linenos, lineno];
    Luacheck_Err_Cols = [Luacheck_Err_Cols, col];
  }

  pop_spot();
  call("redraw");
  vmessage("found %d lines with issues", length(Luacheck_Lines));
}

% Go to next or previous line with errors relative to the editing
% point identified by luacheck and show the error message from
% luacheck in the message area.
define lua_goto_next_or_prev_luacheck_entry(dir)
{
  variable i, err_col, err_lineno, err_msg, this_line = what_line();

  try
  {
    if (dir < 0) % find index position of previous error line
      i = where(this_line > Luacheck_Linenos)[-1];
    else
      i = where(this_line < Luacheck_Linenos)[0];

    err_lineno = Luacheck_Linenos[i];
    err_col = Luacheck_Err_Cols[i];
    goto_line(err_lineno);
    goto_column(err_col);
    err_msg = Luacheck_Lines[i];
    err_msg = pcre_matches("^.*?:(.*)", err_msg)[1]; % omit file name
    call("redraw");
    flush(err_msg);
  }
  catch IndexError: flush("no luacheck errors/warnings beyond this line");
}

% Move up and down between keyword levels.
private define lua_goto_level(dir)
{
  variable kw, col = 1;
  variable kws_beg = Lua_Block_Beg_Kws;
  variable kws_end = [Lua_Block_End_Kws, ["else","elseif"]];
  variable move = &down;

  kw = lua_get_kw();

  if (dir < 0)
  {
    ifnot (any(kw == kws_end))
      verror("not in a line with any of keywords, \"%s\"", strjoin(kws_end, ", "));

    move = &up;
    kws_end = kws_beg;
  }
  else ifnot (any(kw == kws_beg))
    verror("not in a line with any of keywords, \"%s\"", strjoin(kws_beg, ", "));

  bol_skip_white();
  col = what_column();

  while (@move(1))
  {
    if (lua_re_match_line("^\\h*$")) continue;
    kw = lua_get_kw();
    if (any(kw == kws_end))
    {
      bol_skip_white();
      if (col == what_column()) break;
    }
  }
}

define lua_goto_top_of_level()
{
  lua_goto_level(-1);
}

define lua_goto_end_of_level()
{
  lua_goto_level(1);
}

define lua_electric_right_brace()
{
  if (NULL == lua_get_unbalanced_delim('{','}'))
  {
    if (lua_re_match_line("^\\h*$"))
      insert("}");
    else
      insert("\n}");
  }

  lua_indent_line();
  eol();
}

ifnot (keymap_p (Mode)) make_keymap(Mode);
undefinekey_reserved ("x", Mode);
definekey_reserved ("lua_exec_region_or_buffer", "x", Mode);
undefinekey_reserved ("C", Mode);
definekey_reserved ("lua_luacheck_buffer", "C", Mode);
undefinekey("}", Mode);
definekey("lua_electric_right_brace", "}", Mode);
undefinekey (Key_Shift_Up, Mode);
undefinekey (Key_Shift_Down, Mode);
definekey ("lua_goto_next_or_prev_luacheck_entry\(-1\)", Key_Shift_Up, Mode);
definekey ("lua_goto_next_or_prev_luacheck_entry\(1\)", Key_Shift_Down, Mode);

private define lua_menu(menu)
{
  menu_append_item (menu, "Check Buffer With Luacheck", "lua_luacheck_buffer");
  menu_append_item (menu, "Go to Next Luacheck Error Line", "lua_goto_next_or_prev_luacheck_entry\(1\)");
  menu_append_item (menu, "Go to Previous Luacheck Error Line", "lua_goto_next_or_prev_luacheck_entry\(-1\)");
  menu_append_item (menu, "Execute Code in Region or Buffer", "lua_exec_region_or_buffer");
}

define lua_mode()
{
  lua_setup_syntax();
  add_kws_to_table(Lua_Reserved_Keywords, Syntax_Table, 0);
  add_kws_to_table(Lua_Funcs, Mode, 1);
  use_syntax_table(Mode);
  set_comment_info(Mode, "-- ", "", 0);
  set_mode(Mode, 4);
  mode_set_mode_info (Mode, "init_mode_menu", &lua_menu);
  use_keymap (Mode);
  set_buffer_hook("newline_indent_hook", "lua_newline_and_indent");
  set_buffer_hook("indent_hook", "lua_indent_region_or_line");
  set_buffer_hook("backward_paragraph_hook", &lua_goto_top_of_level);
  set_buffer_hook("forward_paragraph_hook", &lua_goto_end_of_level);
  run_mode_hooks("lua_mode_hook");
}
