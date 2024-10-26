% lua.sl, a Jed major mode to facilitate the editing of lua code
% Author (this version): Morten Bo Johansen, mortenbo at hotmail dot com
% License: GPLv3
% Version = 0.1.1 (2024/10/26)

require("pcre");
autoload("add_keywords", "syntax");

% The default number of spaces per indentation level
custom_variable ("Lua_Indent_Default", 2);

% Typing <enter> after a conditional or looping keyword will expand to
% the full syntax of the keyword.
custom_variable ("Lua_Expand_Kw_Syntax", 1);

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
  ["function","if","else","elseif","for","while","do","repeat","{","}{"];

% Keywords that end a block or sub-block
private variable Lua_Block_End_Kws = ["end","else","elseif","until","}"];

% The regex pattern to detect keywords. It captures at most two
% keywords, one conditional/looping keyword and/or the 'end' keyword
% if present in the same line.
private variable Pat = "\\b(function|if|else|elseif|for|while|until|repeat|" +
                       "do|end)\\b.*?(\\b(end|return)\\b[ ,;()}]*)?$";

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

private define lua_setup_syntax()
{
  variable bg;

  (, bg) = get_color("normal"); % get the current background color
  set_color("keyword", "red", bg);
  set_color("operator", "yellow", bg);
  create_syntax_table(Syntax_Table);
  define_syntax ("--", "", '%', Syntax_Table); % comments
  define_syntax ("--[[", "]]", '%', Syntax_Table); % comments
  define_syntax ("[[", "]]", '%', Syntax_Table); % comment but should have been a string!
  define_syntax("([{", ")]}", '(', Syntax_Table);
  define_syntax('"', '"', Syntax_Table);
  define_syntax('`', '"', Syntax_Table);
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

% A regular expression version of ffind()
private define lua_re_ffind(re)
{
  variable p = pcre_compile(re);
  variable pos = 0;

  if (pcre_exec(p, lua_line_as_str()))
  {
    pos = pcre_nth_match(p, 0)[0];
    goto_column(pos + 1);
  }
}

% If number of left and right delimiters in a line is uneven, return
% the unbalanced delimiter.
define lua_get_unbalanced_delim(ldelim, rdelim)
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

% Return the keyword(s) in a line or if none, return NULL
private define lua_get_kw()
{
  variable kws, kw = NULL, ldelim_n, rdelim_n;
  variable line = lua_line_as_str();

  % remove a trailing comment part in a line
  if (lua_re_match_line("^.+-- "))
    line = pcre_matches("(^.*)\\h*--.*?$", line)[-1];

  kws = pcre_matches(Pat, line);
  kws = kws[[1:]];
  kws = kws[wherenot(_isnull(kws))];

  if (length (kws))
  {
    kw = kws[-1];

    if (length (kws) > 1)
    {
      % one-liners, function ... end
      if (any (kw == ["end","return"]) && any(kws[0] == ["if","for","while","function"]))
        kw = NULL;
    }
  }
  else
  {
    if (lua_re_match_line("{|}"))
    {
      kw = lua_get_unbalanced_delim('{','}');

      if (lua_re_match_line("^\\h*},\\h*{\\h*$"))
        kw = "}{";
    }
  }

  push_spot();

  if (any(kw == ["{","}"]))
  {
    eol();
    () = bfind(kw);
  }
  else
    lua_re_ffind("\\b$kw\\b"$);

  if (0 > parse_to_point())
    kw = NULL;

  pop_spot();

  return kw, kws;
}

% Return the column position of a matching delimiter
private define lua_find_col_matching_delim(delim)
{
  variable pos = 0;
  push_spot(); eol();
  () = bfind_char(delim);
  if (1 == find_matching_delimiter(delim))
  {
    bol_skip_white ();
    pos = _get_point();
  }
  pop_spot();
  return pos;
}

% Return the keyword in the current line plus the keyword and its
% column in a preceding line.
private define find_kw_prev_kw_and_col()
{
  variable this_kw = NULL, prev_kw = NULL, prev_kw_col = 0;
  push_spot();

  (this_kw,) = lua_get_kw();

  if (this_kw == "until")
  {
    while (up(1))
    {
      (prev_kw,) = lua_get_kw();
      % supports nested repeat ... until
      if ((prev_kw == "until") || (prev_kw == "repeat")) break;
    }
  }
  else
  {
    while (up(1))
    {
      (prev_kw,) = lua_get_kw();
      if (prev_kw != NULL) break;
    }
  }

  bol_skip_white();
  prev_kw_col = _get_point();
  pop_spot();
  return this_kw, prev_kw, prev_kw_col;
}

% Return the point in the line to indent to
private define lua_get_indentation()
{
  variable this_kw = NULL, prev_kw = NULL, prev_kw_col = 0;

  (this_kw, prev_kw, prev_kw_col) = find_kw_prev_kw_and_col();

  if (this_kw == "}{") this_kw = "}";
  if (prev_kw == "}{") prev_kw = "{";

  if (this_kw == "}")
    return lua_find_col_matching_delim('}');

  if (any(this_kw == ["else","elseif"]) && not any(prev_kw == ["if","elseif"]))
    return prev_kw_col - Lua_Indent_Default;

  if (any(this_kw == ["end","until"]) && any(prev_kw == ["end","until","{","}"]))
    return prev_kw_col - Lua_Indent_Default;

  if (any(this_kw == ["else","elseif","until","do"]))
    return prev_kw_col;

  if (this_kw == "end" && any(prev_kw == Lua_Block_Beg_Kws))
    return prev_kw_col;

  if (any(prev_kw == Lua_Block_Beg_Kws))
    return prev_kw_col + Lua_Indent_Default;

  if (any(prev_kw == Lua_Block_End_Kws))
    return prev_kw_col;

  return NULL;
}

private define lua_indent_line()
{
  variable indentation = lua_get_indentation();

  if (indentation == NULL) return skip_white();

  bol(); trim(); insert_spaces(indentation); eol();
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
  flush("indent region done");
}

% Insert and expand a code block
private define lua_insert_and_expand_syntax()
{
  variable kw = (lua_get_kw(), pop);

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
  variable tmpfile = "/tmp/lua_exec_region.lua";
  variable err_file = "/tmp/lua_exec_region.err";

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

  if (0 != run_program("clear && lua -i $tmpfile 2>$err_file"$))
  {
    if (0 != run_program("$pager $err_file"$))
      throw RunTimeError, "execution failed";
  }
}

% Move up and down between keyword levels.
private define lua_goto_level(dir)
{
  variable kw, col = 1;
  variable kws_beg = Lua_Block_Beg_Kws;
  variable kws_end = Lua_Block_End_Kws;
  variable move = &down;

  (kw,) = lua_get_kw();

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
    (kw,) = lua_get_kw();
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
  insert("}");

  if (lua_re_match_line("^\\h*}\\h*$"))
    lua_indent_line();
}

ifnot (keymap_p (Mode)) make_keymap(Mode);
undefinekey_reserved ("x", Mode);
definekey_reserved ("lua_exec_region_or_buffer", "x", Mode);
undefinekey("}", Mode);
definekey("lua_electric_right_brace", "}", Mode);

define lua_mode()
{
  lua_setup_syntax();
  add_kws_to_table(Lua_Reserved_Keywords, Syntax_Table, 0);
  add_kws_to_table(Lua_Funcs, Mode, 1);
  use_syntax_table(Mode);
  set_comment_info(Mode, "--", "", 0x01);
  set_mode(Mode, 4);
  use_keymap (Mode);
  set_buffer_hook("newline_indent_hook", "lua_newline_and_indent");
  set_buffer_hook("indent_hook", "lua_indent_region_or_line");
  set_buffer_hook("backward_paragraph_hook", &lua_goto_top_of_level);
  set_buffer_hook("forward_paragraph_hook", &lua_goto_end_of_level);
  run_mode_hooks("lua_mode_hook");
}
