%% groff_mode.sl - a Jed editing mode for nroff/troff/groff files
%%
%% Copyright: Morten Bo Johansen <mortenbo at hotmail dot com>
%% License: http://www.fsf.org/copyleft/gpl.html

require("keydefs");
require("pcre");

% The user defined output device when converting the document.
% Defaults to "pdf". If Groff_Output_Device is "ps", the postscript
% will still be converted to pdf-format with ps2pdf(1). The other
% options are "ascii", "latin1", "utf8", "html", "xhtml".
custom_variable("Groff_Output_Device", "pdf");

% The viewer for pdf output. If it isn't installed, other viewers will
% be tried. Defaults to zathura.
custom_variable("Groff_Pdf_Viewer", "zathura");

% The paper format. See groff_tmac(5) under "papersize"
custom_variable("Groff_Paper_Format", "A4");

% The encoding
custom_variable("Groff_Encoding", "utf-8");

% The user defined groff command to convert the groff source file. The
% standard is to use the mode's own detection mechanism based on the
% contents of the document to set the macro package and preprocessor
% options to groff and to convert to the pdf-format. If this variable
% is set, then it will override the detection mechanism.
custom_variable("Groff_Cmd", "");

% Use tab completion (with tabcomplete.sl)
% 1 = enable, 0 = disable
custom_variable("Groff_Use_Tabcompletion", 0);

private variable
  Groff_Data_Dir = "",
  Version = "0.5.0",
  Mode = "groff",
  Home = getenv("HOME"),
  Must_Exist_Tmac = "groff/current/tmac/s.tmac",
  Groff_Fonts_User_Dir = getenv("GROFF_FONT_PATH"),
  Groff_Paper_Orientation = "",
  Xdg_Data_Home = getenv("XDG_DATA_HOME");

% Where are the groff data files installed.
if (1 == file_status("$Xdg_Data_Home/$Must_Exist_Tmac"$))
  Groff_Data_Dir = "$Xdg_Data_Home/groff"$;
else if (1 == file_status("$Home/.local/share/$Must_Exist_Tmac"$))
  Groff_Data_Dir = "$Home/.local/share/groff"$;
else if (1 == file_status("/usr/local/share/$Must_Exist_Tmac"$))
  Groff_Data_Dir = "/usr/local/share/groff"$;
else if (1 == file_status("/usr/share/$Must_Exist_Tmac"$))
  Groff_Data_Dir = "/usr/share/groff"$;
else
  throw RunTimeError, "no groff installation found";

% Set the GROFF_FONT_PATH environment variable if it is unset.
if (Groff_Fonts_User_Dir == NULL || Groff_Fonts_User_Dir == "")
{
  if (Xdg_Data_Home != NULL)
    Groff_Fonts_User_Dir = "$Xdg_Data_Home/groff/site-font"$;
  else
    Groff_Fonts_User_Dir = "$Home/.local/share/groff/site-font"$;

  putenv("GROFF_FONT_PATH=$Groff_Fonts_User_Dir"$);
}

% Run a shell command and show a possible error message in a window
private define groff_run_system_cmd(cmd)
{
  variable err_msg_file = "/tmp/system_err_msg";
  variable wname = "***system error message***";

  if (bufferp(wname))
    delbuf(wname);

  ifnot (0 == system("$cmd 2>$err_msg_file"$))
  {
    pop2buf(wname);
    () = insert_file(err_msg_file);
    bob();
    set_buffer_modified_flag(0);
    most_mode();
    () = delete_file(err_msg_file);
    throw RunTimeError, "an error occurred";
  }
}

% Determine if we are between a pair of macros., e.g. .PS/.PE
private define groff_is_between_macros(beg_macro, end_macro)
{
  variable my_line = what_line();

  push_spot_bol();

  try
  {
    if ((re_bsearch("^\\<\\$beg_macro\\>"$)) && (re_fsearch("^\\<\\$end_macro\\>"$)))
    {
      if (my_line >= what_line()) return 0;
      else return 1;
    }

    return 0;
  }
  finally pop_spot();
}

private define groff_mark_word()
{
  while (not (re_looking_at("[ \t]")) && not (bolp()))
  {
    ifnot (left(1))
      break;
  }

  if (re_looking_at("^\\. *\\<[a-zA-Z0-9]+\\>")) % groff request or macro
    return;

  skip_non_word_chars();
  push_visible_mark();
  skip_word_chars();
}

% Look for a program in $PATH from a list of programs delimited by a
% space and return the first one found
private define groff_find_prgs_use_first(prgs)
{
  variable
    prgs_arr = strtok(prgs),
    path = getenv("PATH");

  prgs_arr = prgs_arr[wherenot(_isnull(array_map(String_Type,
                                                 &search_path_for_file,
                                                 path, prgs_arr)))];
  ifnot (length(prgs_arr))
    throw RunTimeError, "Error: You must install one of $prgs"$;
  else
    return prgs_arr[0];
}

% Return the first line of a file
private define groff_get_1st_line(file)
{
  variable fp, line = "";

  fp = fopen(file, "r");

  if (fp == NULL) return "";

  () = fgets(&line, fp);
  () = fclose(fp);
  return line;
}

% Sort a string array, weeding out duplicates
private define groff_sort_str_arr_unique(a)
{
  variable A = Assoc_Type[String_Type], i = "";

  foreach i (a)
    A[i] = i;

  a = assoc_get_keys(A);
  return a[array_sort(a)];
}

% Return names of installed Groff fonts as a comma separated string.
private define groff_get_font_names()
{
  variable
    fontdir = "",
    first_lines = [""],
    fontdirs = [""],
    fontfiles = [""];

  fontdirs = ["$Groff_Data_Dir/site-font/devpdf"$,
              "$Groff_Data_Dir/current/font/devpdf"$,
              "$Groff_Fonts_User_Dir/devpdf"$];

  % include only existing directories in the array
  fontdirs = fontdirs[where(array_map(Int_Type, &file_status, fontdirs) == 2)];

  ifnot (length(fontdirs))
    throw RunTimeError, "none of the designated font directories exist";

  % Return the full paths of all the groff font files as an array.
  foreach fontdir(fontdirs)
    fontfiles = [fontfiles, array_map(String_Type, &dircat, fontdir, listdir(fontdir))];;

  % Return the first line in every font file and put them all in an array.
  first_lines = array_map(String_Type, &groff_get_1st_line, fontfiles);

  % only Groff font files
  fontfiles = fontfiles[where(array_map(Int_Type, &string_match, first_lines,
                                                  "GNU afmtodit", 1))];

  % Back to the basic font file names
  fontfiles = array_map(String_Type, &path_basename, fontfiles);

  ifnot (length(fontfiles))
    throw RunTimeError, "no Groff font description files found";

  fontfiles = groff_sort_str_arr_unique(fontfiles);
  return strjoin(fontfiles, ",");
}

% Parse the font file name for a font family and a font style.
private define groff_get_font_family_and_style(font)
{
  variable re, fontfile, family, style, matches;

  re = "(.*?)(bolditalic|boldoblique|italic|oblique|regular|bold)|(.*)";
  fontfile = str_delete_chars(path_basename(font), "-_ ");
  fontfile = path_sans_extname(fontfile);
  matches = pcre_matches(re, fontfile; options=PCRE_CASELESS);
  matches = matches[wherenot(_isnull(matches))];
  family = matches[1];
  style = strlow(matches[-1]);

  if (style == "oblique") style = "italic";
  if (style == "boldoblique") style = "bolditalic";

  ifnot (any(style == ["regular","bold","italic","bolditalic"]))
    style = "regular";

  return family, style;
}

private variable Macro_Cnt = 0;
private variable Macro_Cnts = Assoc_Type[Int_Type];

% This counts the total number of a single groff macro in a document
private define groff_count_macro(macro)
{
  CASE_SEARCH = 1;

  bob();

  while (re_fsearch("^\\<\\$macro\\>"$))
  {
    go_right_1();
    Macro_Cnt++;
  }

  CASE_SEARCH = CASE_SEARCH_DEFAULT;
  return Macro_Cnt;
}

% This counts all of the macros present in a document belonging to 
% the six main macro packages. The macro package that has the highest
% count of its macros in the document "wins" and so it will be used as
% an argument to groff when converting the document. This may be an
% overkill, but since there are macros that are common to more than
% one package, at least this should hopefully ensure a rather robust
% detection. This function in combination with the
% infer_preproc_options() function aims to do what the grog(1) program
% does.
private define groff_infer_macro_package()
{
  variable me_macros, ms_macros, mom_macros, mm_macros, man_macros, mdoc_macros;
  variable max_cnt = 0, mp = "";

  % The .HX and .LI macros are not me, ms or mom macros, but they are
  % included in these three arrays as "dummy" macros because they are
  % shared between the www and mm macro packages which means that if a
  % document using any of the me, ms or mom macro packages also
  % included the www.tmac and used e.g. a lot of .LI macros, it could
  % fool the function to see the document as an mm document.
  me_macros =
    [
     ".$0",".$1",".$2",".$3",".$4",".$5",".$6",".$C",".$c",".$d",".$f",".$H",
     ".$h",".$i",".$l",".$m",".$p",".$s",".1c",".2c",".ar",".(b",".)b",".b",
     ".ba",".bc",".bi",".bl",".bm",".bs",".bt",".bu",".bx",".(c",".)c",".+c",
     ".cp",".ef",".eh",".ep",".fo",".he",".hl",".hm",".hx",".HX",".i",".ii",
     ".ip",".ix",".(l",".)l",".ld",".LI",".lp",".lq",".m1",".m2",".m3",
     ".m4",".mo",".n1",".n2",".no",".np",".of",".oh",".pa",".pd",".pf",".pp",
     ".(q",".)q",".q",".qi",".qp",".qs",".r",".re",".rj",".ro",".rq",".sf",
     ".sh",".si",".sk",".sm",".sx",".sz",".td",".tf",".tp",".tv",".u",".uh",
     ".wa",".wc",".(b",".)b",".(c",".)c",".(d",".)d",".(f",".)f",".(l",".)l",
     ".(q",".)q",".(z",".)z",".(x",".)x",".xl",".xp",".xs",".xu",".y2",".y4",
     ".yr",".(z",".)z",".zs"
    ];

  ms_macros =
    [
     ".RP",".TL",".AU",".AB",".AI",".AU",".DA",".ND",".AB",".AE",".LP",".PP",
     ".IP",".QP",".QS",".QE",".QE",".XP",".NH",".NH",".SH",".B",".R",".I",".LI",
     ".BI",".CW",".BX",".UL",".LG",".SM",".NL",".RS",".RE",".KS",".KF",".KE",
     ".B1",".B2",".B1",".B2",".DS",".LD",".DS",".ID",".DS",".BD",".DS",".CD",
     ".DS",".RD",".DE",".FS",".FE",".OH",".OF",".EH",".EF",".P1",".TA",".1C",
     ".2C",".MC",".XS",".XA",".XE",".XE",".PX",".TC",".XH",".XN",".XH",".HX",
     ".XN-REPLACEMENT",".XH-REPLACEMENT",".XH-INIT",".XN-INIT",".XH-UPDATE-TOC"
    ];

  mom_macros =
    [
     ".ADD_SPACE",".ALD",".ALIAS",".AUTHOR",".AUTOLABEL",".AUTOLEAD",".B_MARGIN",
     ".BIBLIOGRAPHY",".BLOCKQUOTE",".BR",".CAPS",".CAPTION",".CENTER",".CODE",
     ".COLLATE",".CONDENSE",".COPYRIGHT",".COVER",".DRV",".DRH",".EL",
     ".EPIGRAPH",".EW",".EXTEND",".FALLBACK_FONT",".FAM",".FAMILY",".FINIS",
     ".FLOAT",".FOOTERS",".FOOTNOTE",".FT",".HEADING",".HI",".HY",".HY_SET",
     ".HX",".IB",".IBX",".IL",".ILX",".IQ",".IR",".IR",".IRX",".ITEM",
     ".JUSTIFY",".KERN",".LABEL",".LEFT",".LI",".LINEBREAK",".LIST",".LL",
     ".L_MARGIN",".LS",".MCO",".MCR",".MCX",".NEWPAGE",".NO_SHIM",".PAD",
     ".PAGE",".PAGELENGTH",".PAGEWIDTH",".PAPER",".PAPER",".PDF_LINK",".PP",
     ".PRINTSTYLE",".PSPIC",".PT_SIZE",".QUAD",".QUOTE",".REF",".RIGHT",".RLD",
     ".R_MARGIN",".RW",".SETBOLDER",".SETSLANT",".SPACE",".SPREAD",".SS",".ST",
     ".STYLE",".TB",".TI",".TI",".T_MARGIN",".TITLE",".TN",".TO",".TOC",".TQ",
     ".TRAP",".TYPESET",".TYPEWRITE",".UNDERLINE",".WS"
    ];

  mm_macros =
    [
     ".)E",".1C",".2C",".AE",".AF",".AL",".APP",".APPSK",".AS",".AST",".AT",
     ".AU",".AV",".AVL",".B",".B1",".B2",".BE",".BI",".BL",".BR",".BS",".BVL",
     ".COVER",".COVEND",".DE",".DF",".DL",".DS",".EC",".EF",".EH",".EN",".EOP",
     ".EPIC",".EX",".FC",".FD",".FE",".FG",".FS",".GETHN",".GETPN",
     ".GETR",".GETST",".H",".HX",".HY",".HZ",".HC",".HM",".HU",".I",".IA",
     ".IB",".IE",".IND",".INDP",".INITI",".INITR",".IR",".ISODATE",".LB",
     ".LC",".LE",".LI",".LO",".LT",".BL",".SB",".FB",".SP",".MC",".ML",".MT",
     ".MOVE",".MULB",".MULN",".MULE",".NCOL",".ND",".NE",".nP",".NS",".OF",
     ".OH",".OP",".P",".PF",".PGFORM",".PGNH",".PH",".PIC",".R",".RB",".RD",
     ".RF",".RI",".RL",".RP",".RS",".S",".SA",".SETR",".SG",".SK",".SM",".SP",
     ".TAB",".TB",".TC",".TL",".TM",".TP",".VERBON",".VERBOFF",".VL",".VM",
     ".WA",".WC",".WE",".WF"
    ];

  man_macros =
    [
     ".B",".BI",".BR",".EE",".EX",".I",".IB",".IP",".IR",".LP",".ME",".MR",
     ".MT",".P",".PP",".RB",".RE",".RI",".RS",".SB",".SH",".SM",".SS",".SY",
     ".TH",".TP",".TQ",".UE",".UR",".YS",".AT",".DT",".HP",".OP",".PD",".UC"
    ];

  mdoc_macros =
    [
     ".Ac",".Ad",".An",".Ao",".Ap",".Aq",".Ar",".At",".Bc",".Bd",".Bf",".Bk",
     ".Bl",".Bo",".Bq",".Brc",".Bro",".Brq",".Bsx",".Bt",".Bx",".Cd",".Cm",
     ".Db",".Dc",".Dd",".Dl",".Do",".Dq",".Dt",".Dv",".Dx",".Ec",".Ed",".Ek",
     ".El",".Em",".En",".Eo",".Eq",".Er",".Es",".Ev",".Ex",".Fa",".Fc",".Fl",
     ".Fn",".Fo",".Fr",".Ft",".Fx",".Hf",".Ic",".In",".It",".Lb",".Li",".Lk",
     ".Me",".Ms",".Mt",".Nd",".Nm",".No",".Ns",".Nx",".Oc",".Oo",".Op",".Os",
     ".Ot",".Ox",".Pa",".Pc",".Pf",".Po",".Pp",".Pq",".Qc",".Ql",".Qo",".Qq",
     ".Re",".Rs",".Rv",".Sc",".Sh",".Sm",".So",".Sq",".St",".Sx",".Sy",".Tn",
     ".Ud",".Ux",".Va",".Vt",".Xc",".Xo",".Xr",".Xx"
    ];

  % The groff_count_macro() function is run once for each macro belonging to
  % a macro package to create a total count for each macro package. It stores
  % that count in the variable Macro_Cnt which is then associated with the
  % groff option for the macro package.
  () = array_map(Int_Type, &groff_count_macro, me_macros);
  Macro_Cnts["-me"] = Macro_Cnt;
  Macro_Cnt = 0;

  () = array_map(Int_Type, &groff_count_macro, ms_macros);
  Macro_Cnts["-ms"] = Macro_Cnt;
  Macro_Cnt = 0;

  () = array_map(Int_Type, &groff_count_macro, mom_macros);
  Macro_Cnts["-mom"] = Macro_Cnt;
  Macro_Cnt = 0;

  () = array_map(Int_Type, &groff_count_macro, mm_macros);
  Macro_Cnts["-mm"] = Macro_Cnt;
  Macro_Cnt = 0;

  () = array_map(Int_Type, &groff_count_macro, man_macros);
  Macro_Cnts["-man"] = Macro_Cnt;
  Macro_Cnt = 0;

  () = array_map(Int_Type, &groff_count_macro, mdoc_macros);
  Macro_Cnts["-mdoc"] = Macro_Cnt;
  Macro_Cnt = 0;

  max_cnt = max(assoc_get_values(Macro_Cnts));

  if (max_cnt == 0) return ""; % pure nroff/troff, apparently.

  % the macro package that has the highest number of its macros in the document
  mp = assoc_get_keys(Macro_Cnts)[wherefirst(assoc_get_values(Macro_Cnts) == max_cnt)];
  return mp;
}

% Detect what preprocessor options may be needed for the document.
private define groff_infer_preproc_options()
{
  variable preproc, preprocs = Assoc_Type[String_Type];
  variable opts = String_Type[0];

  % associate the preprocessor options to groff with the defining macros
  preprocs[".cstart"] = "-j"; % chem
  preprocs[".\\["] = "-R";    % refer
  preprocs[".TS"] = "-t";     % tbl
  preprocs[".EQ"] = "-e";     % eqn
  preprocs[".GS"] = "-g";     % grn
  preprocs[".G1"] = "-G";     % grap
  preprocs[".PS"] = "-p";     % pic
  preprocs[".BOXSTART"] = "-msboxes"; % sboxes - a macro package, actually

  % Detect and accumulate all possibly needed preprocessors in a string.
  foreach preproc (assoc_get_keys(preprocs))
  {
    if (groff_count_macro(preproc))
      opts = [opts, preprocs[preproc]];

    Macro_Cnt = 0;
  }

  return strjoin(opts, " ");
}

% Return the values of some other groff options.
define groff_get_other_options()
{
  variable opts = "-T$Groff_Output_Device -k -K $Groff_Encoding "$;

  if (any(Groff_Output_Device == ["ps","pdf"]))
  {
    if (Groff_Paper_Orientation == "l")
      opts += "-d paper=${Groff_Paper_Format}l -P-p$Groff_Paper_Format -P-l"$;
    else
      opts += "-dpaper=${Groff_Paper_Format} -P-p$Groff_Paper_Format"$;
  }
  else if (any(Groff_Output_Device == ["html", "xhtml"])) opts += " -P-D/tmp";
  return opts;
}

% The variable that holds the process id for the pdf viewer.
private variable Pdfviewer_Pid;

private define groff_show_pdfviewer_error(pid, error)
{
  return flush(strtrim(error));
}

private define groff_pdfviewer_signal_handler(pid, flags, status)
{
  variable msg = aprocess_stringify_status(pid, flags, status);
  flush(msg);

  ifnot (flags == 1) % if proces is no longer running
    __uninitialize(&Pdfviewer_Pid);
}

% Insert a font name from a list of installed groff fonts
define groff_insert_font_name()
{
  ungetkey('\t');
  insert(read_with_completion(groff_get_font_names(), "Font:", "", "", 's'));
}

%% Convert a truetype or open type font to a groff font and make
%% it available to groff. It uses the environment variable
%% GROFF_FONT_PATH as the installation target.
define groff_install_font()
{
  ifnot (2 == file_status(Groff_Fonts_User_Dir))
  {
    if (1 == get_y_or_n("the directory \"$Groff_Fonts_User_Dir\" does not exist, create it?"$))
      groff_run_system_cmd("mkdir -p $Groff_Fonts_User_Dir"$);
    else
      throw RunTimeError, "aborting font installation!";
  }

  % The user defined font path should include only one directory. If
  % it contains more, then use the first one in the list.
  if (length(strchop(Groff_Fonts_User_Dir, path_get_delimiter(), 0)) > 1)
  {
    Groff_Fonts_User_Dir = strchop(Groff_Fonts_User_Dir, path_get_delimiter(), 0)[0];
    flush("using $Groff_Fonts_User_Dir for font installation"$);
    sleep(1);
  }

  if (-1 == access(Groff_Fonts_User_Dir, W_OK))
    throw RunTimeError, "you don't have write access to $Groff_Fonts_User_Dir"$;

  variable font = "";

  ifnot (_NARGS)
    font = read_with_completion("Path to font file (*.otf, *.ttf):", "", "", 'f');
  else
    font = ();

  ifnot (1 == file_status(font))
    throw RunTimeError, "$font does not exist or is not file"$;

  variable
    pwd = getcwd(),
    path = getenv("PATH"),
    convertdir_files = [""],
    groff_font = "",
    fam_name = "",
    style = "",
    style_abbr = "",
    afm_file = "",
    t42_file = "",
    pfa_file = "",
    devps_dl_str = "",
    devpdf_dl_str = "",
    textmap = "",
    font_enc = "$Groff_Data_Dir/current/font/devps/text.enc"$,
    devps_dir = dircat(Groff_Fonts_User_Dir, "devps"),
    devpdf_dir = dircat(Groff_Fonts_User_Dir, "devpdf"),
    devps_dl_file = dircat(devps_dir, "download"),
    devpdf_dl_file = dircat(devpdf_dir, "download"),
    convert_dir = make_tmp_file("/tmp/fontinstall"),
    pe_file = dircat(convert_dir, "convert.pe"),
    pe_str = "Open ($1);\nGenerate($fontname + \".pfa\");\nGenerate(\$fontname + \".t42\");",
    Styles = Assoc_Type[String_Type, ""];

    % Map the style names from the font files to corresponding abbreviations.
    Styles["bolditalic"] = "BI",
    Styles["regular"] = "R",
    Styles["italic"] = "I",
    Styles["bold"] = "B";

  try
  {
    if (NULL == search_path_for_file(path, "fontforge"))
      throw OpenError, "fontforge is not installed"$;

    % "textmap" was renamed from "textmap" to "text.map" in 2022. In
    % case an older groff version is used, also check for the old
    % filename.
    textmap = dircat(Groff_Data_Dir, "current/font/devpdf/map/text.map");

    ifnot (1 == file_status(textmap))
      textmap = dircat(Groff_Data_Dir, "current/font/devpdf/map/textmap");

    ifnot (1 == file_status(textmap))
      throw OpenError, "text.map file not found";

    if (-1 == mkdir(convert_dir, 0755))
      throw WriteError, "could not create $convert_dir"$;

    if (-1 == write_string_to_file(pe_str, pe_file))
      throw WriteError, "could not write to $pe_file"$;

    if (-1 == chdir(convert_dir))
      throw RunTimeError, "could not change to $convert_dir"$;

    (fam_name, style) = groff_get_font_family_and_style(font);
    fam_name = path_basename(fam_name);
    style_abbr = Styles[style];
    groff_run_system_cmd("fontforge -script $pe_file \"$font\""$);
    convertdir_files = listdir(convert_dir);
    afm_file = convertdir_files[wherefirst(array_map (String_Type,
                                                      &path_extname,
                                                      convertdir_files) == ".afm")];

    t42_file = convertdir_files[wherefirst(array_map (String_Type,
                                                      &path_extname,
                                                      convertdir_files) == ".t42")];

    pfa_file = convertdir_files[wherefirst(array_map (String_Type,
                                                      &path_extname,
                                                      convertdir_files) == ".pfa")];

    devps_dl_str = strcat(path_sans_extname(t42_file), "\t",
                          path_basename(t42_file));

    % The "download" file in the devpdf directory must have a leading
    % tab character before each entry to satisfy gropdf
    devpdf_dl_str = strcat("\t", path_sans_extname(pfa_file), "\t",
                           path_basename(pfa_file));

    ifnot (1 == file_status(afm_file))
      throw OpenError, "$afm_file not found"$;

    groff_font = fam_name + style_abbr;
    groff_font = strreplace(groff_font, " ", "-");

    if (is_list_element(groff_get_font_names, groff_font, ','))
      ifnot (get_y_or_n("$groff_font already appears to be installed, overwrite"$))
        throw AnyError;

    groff_run_system_cmd("afmtodit -e $font_enc $afm_file $textmap $groff_font"$);
    groff_run_system_cmd("mkdir -p $devps_dir"$);
    groff_run_system_cmd("mkdir -p $devpdf_dir"$);
    groff_run_system_cmd("chmod 0644 $groff_font $t42_file"$);
    groff_run_system_cmd("cp $groff_font $t42_file $devps_dir"$);
    groff_run_system_cmd("cp  $pfa_file $devpdf_dir"$);
    groff_run_system_cmd("ln -s -f $devps_dir/$groff_font $devpdf_dir"$);
    groff_run_system_cmd("echo '$devps_dl_str' >> $devps_dl_file"$);
    groff_run_system_cmd("echo '$devpdf_dl_str' >> $devpdf_dl_file"$);
    groff_run_system_cmd("sort -u $devps_dl_file | tee $devps_dl_file >/dev/null 2>&1"$);
    groff_run_system_cmd("chmod 0755 $devpdf_dl_file $devps_dl_file"$);

    if (1 == file_status(devps_dl_file))
      groff_run_system_cmd("cp $devps_dl_file ${devps_dl_file}.bak"$);
    if (1 == file_status(devpdf_dl_file))
      groff_run_system_cmd("cp $devpdf_dl_file ${devpdf_dl_file}.bak"$);
  }
  finally
  {
    () = chdir(pwd);
    groff_run_system_cmd("rm -rf $convert_dir"$);
  }

  flush("$groff_font installed in $Groff_Fonts_User_Dir"$);
}

% Convert and install all truetype and opentype fonts in a directory
define groff_install_fonts_in_dir()
{
  variable
    dir = read_with_completion("Full path of font directory:", "", "/", 'f'),
    fbuf = "***Fonts to be installed***",
    fonts = listdir(dir),
    font = "",
    fonts_cs = "",
    answer = "",
    expr = "",
    ttf = fonts[where(array_map(String_Type, &path_extname, fonts) == ".ttf")],
    otf = fonts[where(array_map(String_Type, &path_extname, fonts) == ".otf")];

  fonts = [otf, ttf];

  ifnot (length(fonts))
    throw RunTimeError, "no *.ttf or *.otf fonts found in $dir"$;

  fonts_cs = strjoin(fonts, ",");
  answer =
    read_with_completion(fonts_cs,
                         "Install (a)ll fonts or fonts that match an " +
                         "(e)xpression or (c)ancel [a/e/c]:", "", "", 's');
  switch (answer)
  { case "e":
    {
      update_sans_update_hook(1);
      expr = read_mini("(Regular) expression:", "", "");
      fonts = fonts[where(array_map(Int_Type, &string_match, fonts, "\\C$expr"$, 1))];

      ifnot (length(fonts))
        throw RunTimeError, "no *.ttf or *.otf fonts match \"$expr\""$;

      pop2buf(fbuf);
      insert(strjoin(fonts, "\n"));
      set_buffer_modified_flag(0);
      bob();

      try
      {
        ifnot (get_y_or_n(sprintf("Install these %d fonts", length(fonts))))
          return flush("aborting");
      }
      finally
      {
        delbuf(fbuf);
        otherwindow();
        onewindow();
      }
    }
  }
  { case "a": vmessage("installing %d fonts in $dir ..."$,
                       length(fonts)); sleep(2); }

  { return flush("aborting"); }

  foreach font(fonts)
  {
    font = dircat(dir, font);
    try
    {
      groff_install_font(font);
      () = append_string_to_file("[SUCCESS]: " + "$font\n"$, "/tmp/ifonts");
    }
    catch AnyError:
      () = append_string_to_file("[FAILED]: " + "$font\n"$, "/tmp/ifonts");
  }

  variable fbname = "*** FONTS INSTALLATION RESULTS ***";

  if (bufferp(fbname))
    delbuf(fbname);

  pop2buf(fbname);
  () = insert_file("/tmp/ifonts");
  set_buffer_modified_flag(0);
  most_mode();
  bob();
  flush("type 'q' to close this window");
  () = delete_file("/tmp/ifonts");
}

% If output device is "ps" or "pdf", preview buffer in a pdf-viewer.
% Display in pdf-viewer is updated with changes in buffer upon
% pressing a key, with no need to save the file associated with the
% buffer in between or restarting the pdf-viewer. If output device is
% "utf8", "latin1" or "ascii", viewing is in a pager program such as
% less(1), if output device is "html" or "xhtml", viewing is in a text
% based browser such as lynx(1).
define groff_preview_buffer()
{
  if (Groff_Output_Device == "ps")
    if (NULL == search_path_for_file(getenv("PATH"), "ps2pdf"))
      throw RunTimeError, "output device \"ps\" needs the program \"ps2pdf\"";

  push_spot();

  variable
    xpdfserver = "xpdfserver",
    path = getenv("PATH"),
    pwd = getenv("PWD"),
    pager = "",
    browser = "",
    macro_package = groff_infer_macro_package(),
    preproc_opts = groff_infer_preproc_options(),
    other_opts = groff_get_other_options(),
    output_file = "/tmp/groff_mode_out",
    tmpfile = "/tmp/groff_mode_tmpfile",
    cmd = "",
    dir = "";

  (,dir,,) = getbuf_info(whatbuf());
  () = chdir(dir);

  mark_buffer();
  () = write_string_to_file(bufsubstr(), tmpfile);
  pop_spot();

  % If mandoc is installed use that for converting manual page
  % documents, otherwise use -man or -mdoc whichever applies
  if ((macro_package == "-man" || macro_package == "-mdoc") &&
      (NULL != search_path_for_file(getenv("PATH"), "mandoc")))
  {
    macro_package = "(mandoc)"; % just for the status line
    cmd = "mandoc -K $Groff_Encoding -T $Groff_Output_Device $tmpfile"$;
  }
  else
    cmd = "groff $macro_package $preproc_opts $other_opts $tmpfile 2>/dev/null"$;

  switch (Groff_Output_Device)
  { case "ps" or case "pdf": output_file += ".pdf"; }
  { case "html" or case "xhtml": output_file += ".html"; }
  
  if (strlen(Groff_Cmd)) cmd = "$Groff_Cmd $tmpfile 2>/dev/null"$;

  if (Groff_Output_Device == "ps")
    cmd += "| ps2pdf - >$output_file"$;
  else
    cmd += ">$output_file"$;

  groff_run_system_cmd(cmd);
  () = chdir(pwd);

  pager = groff_find_prgs_use_first("less most more");

  if (pager == "less") pager = "less -frs";
  else pager = "$pager -s"$;
  
  if (any(Groff_Output_Device == ["ascii","latin1","utf8"]))
    return run_program("$pager $output_file"$);

  browser = groff_find_prgs_use_first("lynx elinks w3m links");

  if (any(Groff_Output_Device == ["html","xhtml"]))
    return run_program("$browser $output_file"$);

  if (NULL == search_path_for_file(path, Groff_Pdf_Viewer))
    Groff_Pdf_Viewer = groff_find_prgs_use_first("mupdf evince qpdfview " +
                                                 "okular apvlv atril gv xpdf");
  ifnot (__is_initialized(&Pdfviewer_Pid))
  {
    switch (Groff_Pdf_Viewer)
    { case "gv":
      Pdfviewer_Pid = open_process("gv", "--nocenter", "--watch",
                                    output_file, 3); }
    { case "xpdf":
      Pdfviewer_Pid = open_process("xpdf", "-remote", xpdfserver,
                                    output_file, 3); }
    { case "qpdfview":
      Pdfviewer_Pid = open_process("qpdfview", "--unique", output_file, 2); }

    { Pdfviewer_Pid = open_process(Groff_Pdf_Viewer, output_file, 1); };

    set_process(Pdfviewer_Pid, "output", &groff_show_pdfviewer_error);
    set_process(Pdfviewer_Pid, "signal", &groff_pdfviewer_signal_handler);
    process_query_at_exit(Pdfviewer_Pid, 0);
  }
  % this is to address some quirks that some pdf viewers have in
  % updating the display
  else
  {
    if (Groff_Pdf_Viewer == "mupdf") % mupdf wants a SIGHUP
      signal_process(Pdfviewer_Pid, 1);
    if (Groff_Pdf_Viewer == "xpdf")
      groff_run_system_cmd("xpdf -remote $xpdfserver -reload"$);
    if (Groff_Pdf_Viewer == "qpdfview")
      groff_run_system_cmd("qpdfview --unique $output_file"$);
  }

  variable status_str = strcompress("$preproc_opts $macro_package"$, " ");
  % update the status line with the inferred macro package and
  % preprocessor options
  set_status_line("%b | %m $status_str (%a%n%o)  %p   %t"$, 0);
}

% Show the inferred groff command to convert the current document in
% the message area or return it.
define groff_return_or_show_cmd(show)
{
  variable cmd = sprintf("groff %s %s %s", groff_infer_preproc_options(),
                                           groff_infer_macro_package(),
                                           groff_get_other_options());
  cmd = strcompress(cmd, " ");

  if (show) return flush(cmd);
  return cmd;
}

% Draw various objects, lines, circles, arcs, etc., using basic troff
define groff_draw()
{
  variable length, height, width, diam, coords;

  flush("Draw: (h)line, (v)line, (c)ircle, s(o)lid circle, (e)llipse, " +
        "(a)rc, (p)olygon, (s)pline");

  ifnot (input_pending (50))
    return flush("");

  switch (getkey())
  { case 'h': length = read_mini("Line length in cm?", "", ""); insert("\\l'${length}c'"$); }
  { case 'v': height = read_mini("Line height in cm?", "", ""); insert("\\L'${height}c'"$); }
  { case 'c': diam = read_mini("Circle diameter in cm?", "", ""); insert("\\D'c ${diam}c'"$); }
  { case 'o': diam = read_mini("Circle diameter in cm?", "", ""); insert("\\D'C ${diam}c'"$); }
  { case 'e': width = read_mini("Ellipse: width in cm?", "", "");
              height = read_mini("Ellipse: height in cm?", "", "");
              insert ("\\D'e ${width}c ${height}c'"$); }
  { case 'p': coords = read_mini("Polygon coordinates (space delim.)?", "", "");
              insert("\\D'p $coords'"$); }
  { case 'a': coords = read_mini ("Arc coordinates (space delim.)?", "", "");
              insert("\\D'a $coords'"$); }
  { case 's': coords = read_mini ("Spline coordinates (space delim.)?", "", "");
              insert("\\D'~ $coords'"$); }
  { flush(""); }
}

% Return the defined groff color names as a comma separated string
define groff_get_color_names(ins)
{
  variable matches, line, color, colorname, colornames = {};

  % make room for a 1000 color names. Currently there are about 550 defined names
  () = search_file("$Groff_Data_Dir/current/tmac/ps.tmac"$, "\.defcolor", 1000);
  matches = __pop_list(_stkdepth());

  foreach line (matches)
  {
    colorname = pcre_matches("^\.defcolor\\h+(.*?)\\h+rgb", line);
    list_append(colornames, colorname[-1]);
  }

  ungetkey('\t');

  ifnot (length(colornames))
    return "red,green,blue,yellow,magenta,cyan,white,black";

  colornames = list_to_array(colornames);
  colornames = strjoin(colornames, ",");

  if (ins)
  {
    color = read_with_completion(colornames, "Color:", "", "", 's');
    insert(color);
  }
  else return colornames;
}

% Give word or marked text some attribute or remove it.
define groff_toggle_inline_markup()
{
  variable str = "", sz = "", font_name = "";

  define_word("-A-Za-zÀ-ÿ0-9\[\]\\");

  ifnot (markp()) groff_mark_word();

  () = dupmark();
  str = bufsubstr();

  ifnot (strlen(str))
    throw UsageError, "you must mark some word(s)";

  if (string_match(str, "\\\\", 1))
    return insert(str_uncomment_string(bufsubstr_delete(), "\\[", "]\\"));

  flush("Text Attributes: (f)ont face, (b)old, (i)talic, (s)ize:, (c)olor, (q)uote");

  ifnot (input_pending (50))
  {
    flush("");
    return pop_mark_1;
  }

  switch (getkey())
  { case 'f':
    {
      ungetkey('\t');
      font_name = read_with_completion(groff_get_font_names(), "Font:", "H", "", 's');
      str = strcat("\\f[$font_name]"$, str, "\\f[]");
    }
  }
  { case 'b': str = strcat("\\f[B]", str, "\\f[]"); }
  { case 'i': str = strcat("\\f[I]", str, "\\f[]"); }
  { case 's':
    {
      sz = read_mini("Font Size?", "", "");
      str = strcat("\\s[$sz]"$, str, "\\s[0]");
    }
  }
  { case 'c':
    {
      variable color = read_with_completion(groff_get_color_names(0),
                                            "Color:", "", "", 's');

      str = strcat("\\m[$color]"$, str, "\\m[]");
    }
  }
  { case 'q': str = strcat("\\[lq]", str, "\\[rq]"); }

  flush("");
  () = bufsubstr_delete();
  insert(str);
}

% scale unit from inch to cm in gpic
define groff_gpic_scale_to_cm()
{
  if (groff_is_between_macros(".PS", ".PE"))
    insert("scale = 2.54");
  else
    insert(".PS\nscale = 2.54\n.PE");
}

%% Draw some figures with gpic. The "fill" modifier is not included.
%% The same effect can be obtained with e.g shaded "grey".
define groff_draw_gpic(obj)
{
  variable dir = "", linetype = "", length = "", width = "", height = "";
  variable rad = "", thn, msg = "", strs = "", str = "", i = 1, nlines = 0;
  variable color = "", shaded_color = "", pic_str = "", pos = "";

  thn = read_mini("Line thickness for object", "0", "");
  color = read_with_completion(groff_get_color_names(0),
                               "line/outline color:", "black", "", 's');

  linetype = read_mini("(s)olid, d(a)shed, d(o)tted?:", "s", "");

  switch (linetype)
  { case "a": linetype = "dashed"; }
  { case "o": linetype = "dotted"; }
  { case "s": linetype = "solid"; }
  { linetype = "solid"; }

  switch (obj)
  { case "line" or case "arrow": length = read_mini("$obj length:"$, "", ""); }
  { case "box":
    width = read_mini("$obj width:"$, "2", "");
    height = read_mini("$obj height:"$, "1", "");
    rad = read_mini("$obj fillet radius:"$, "0", "");
    pic_str = "$obj width $width height $height rad $rad"$;
  }
  { case "ellipse":
    width = read_mini("$obj width:"$, "2", "");
    height = read_mini("$obj height:"$, "1", "");
    pic_str = "$obj width $width height $height"$;
  }
  { case "circle":
    rad = read_mini("Circle radius?:", "1", "");
    pic_str = "$obj rad $rad"$;
  }
  { case "arc":
    rad = read_mini("Arc radius?:", "1", "");

    if (get_y_or_n("Clockwise")) dir = "cw";
    pic_str = "$obj outline \"$color\" $linetype thickness $thn $dir rad $rad"$;
  }

  if (obj == "box" or obj == "circle" or obj == "ellipse")
  {
    shaded_color = read_with_completion(groff_get_color_names(0),
                                        "shaded color:", "white", "", 's');

    nlines = read_mini("Number of text lines:", "1", "");

    loop (integer(nlines))
    {
      msg = sprintf("Text line %d:", i);
      str = read_mini(msg, "", "");
      strs += "\"$str\" "$;
      i++;
    }

    pic_str = "$pic_str thickness $thn $linetype shaded \"$shaded_color\" "$ +
              "outline \"$color\" $strs"$;
  }

  if (obj == "arrow" or obj == "line")
  {
    dir = read_mini("(u)p, (d)own, (l)eft, (r)ight, up/l(e)ft, up/r(i)ght," +
                    "down/le(f)t, down/ri(g)ht?:", "right", "");
    switch (dir)
    { case "d": dir = "down"; }
    { case "e": dir = "up left"; }
    { case "f": dir = "down left"; }
    { case "g": dir = "down right"; }
    { case "i": dir = "up right"; }
    { case "l": dir = "left"; }
    { case "r": dir = "right"; }
    { case "u": dir = "up"; }
    { dir = "right"; }

    if (any(dir == ["left","right","up right","up left","down left","down right"]))
    {
      if (get_y_or_n("Add a line of text below or above $obj"$))
      {
        str = read_mini("Enter text:"$, "", "");
        pos = read_mini("Specify \"above\" or \"below\":"$, "above", "");

        if (pos == "above")
          str = "\"$str\" \"\""$;
        else
          str = "\"\" " + "\"$str\" below"$;
      }
    }

    pic_str = "$obj $length $linetype thickness $thn outline " +
              "\"$color\" $dir $str aligned"$;
  }

  pic_str = strcompress(pic_str, " ");

  if (groff_is_between_macros(".PS", ".PE"))
    insert(pic_str);
  else
    insert(strcat(".PS\n", pic_str, "\n.PE\n"));
}

% A one line menu with gpic items in the message area
define groff_gpic_mini_menu()
{
  variable n, dir;

  flush("Gpic: (a)rrow, (l)ine, a(r)c, (b)ox, (c)ircle, (e)llipse, (m)ove, (u)nit/cm");

  % keep the menu visible for 4 seconds
  ifnot (input_pending(50)) return flush("");

  switch (getkey())
  { case 'a': groff_draw_gpic("arrow"); }
  { case 'l': groff_draw_gpic("line"); }
  { case 'b': groff_draw_gpic("box"); }
  { case 'r': groff_draw_gpic("arc"); }
  { case 'c': groff_draw_gpic("circle"); }
  { case 'e': groff_draw_gpic("ellipse"); }
  { case 'u': groff_gpic_scale_to_cm(); }
  { case 'm':
    {
      n = read_mini("move, number of units?", "0.5", "");
      flush("move direction? ((u)p, (d)own, (l)eft, (r)ight, l(a)st)");

      switch (getkey())
      { case 'u': dir = "up"; }
      { case 'd': dir = "down"; }
      { case 'l': dir = "left"; }
      { case 'r': dir = "right"; }
      { case 'a':
        {
          flush("move to last? (a)rrow, (l)ine, a(r)c, (b)ox, (c)ircle, (e)llipse");

          switch (getkey())
          { case 'a': dir = "to last arrow"; }
          { case 'l': dir = "to last line"; }
          { case 'b': dir = "to last box"; }
          { case 'r': dir = "to last arc"; }
          { case 'c': dir = "to last circle"; }
          { case 'e': dir = "to last ellipse"; }

          return insert("move $dir .s"$);
        }
      }

      insert("move $dir $n"$);
    }
  }
  { return flush(""); }
}

% Edit and set the groff command used to convert the document
define groff_edit_cmd()
{
  ifnot (strlen(Groff_Cmd))
    Groff_Cmd = groff_return_or_show_cmd(0);

  Groff_Cmd = read_mini("Edit Groff Cmd:", "", Groff_Cmd);
}

% Skip forwards to regular text parts of the document.
define groff_goto_text_forwards()
{
  while (not (re_looking_at("^[.\"\\\\]") || eobp())) go_down_1();
  while (re_looking_at("^[.\"\\\\]")) go_down_1();
}

% Skip backwards to regular text parts of the document.
define groff_goto_text_backwards()
{
  bol();
  while (not (re_looking_at("^[.\"\\\\]") || bobp())) call("previous_line_cmd");
  while (re_looking_at("^[.\"\\\\]")) call("previous_line_cmd");
  while (not (re_looking_at("^[.\"\\\\]") || bobp())) call("previous_line_cmd");
  go_down_1();
}

% Set groff options on the fly for output device, paper format,
% input encoding, paper format or paper orientation.
define groff_set_other_options()
{
  variable devs = "ps,pdf,ascii,utf8,latin1,html,xhtml";

  variable encs = "big5,cp1047,euc-jp,euc-kr,gb2312,iso-8859-1,iso-8859-2," +
                  "iso-8859-5,iso-8859-7,iso-8859-9,iso-8859-13,iso-8859-15," +
                  "koi8-r,us-ascii,utf-8,utf-16,utf-16be,utf-16le,ascii," +
                  "chinese-big5,chinese-euc,chinese-iso-8bit,cn-big5," +
                  "cn-gb,cn-gb-2312,cp878,csascii,csisolatin1," +
                  "cyrillic-iso-8bit,cyrillic-koi8,euc-china,euc-cn," +
                  "euc-japan,euc-japan-1990,euc-korea,greek-iso-8bit," +
                  "iso-10646/utf8,iso-10646/utf-8,iso-latin-1,iso-latin-2," +
                  "iso-latin-5,iso-latin-7,iso-latin-9,japanese-euc," +
                  "japanese-iso-8bit,jis8,koi8,korean-euc,korean-iso-8bit," +
                  "latin-0,latin1,latin-1,latin-2,latin-5,latin-7," +
                  "latin-9,mule-utf-8,mule-utf-16,mule-utf-16be," +
                  "mule-utf-16-be,mule-utf-16be-with-signature,mule-utf-16le," +
                  "mule-utf-16-le,mule-utf-16le-with-signature,utf8,utf-16-be," +
                  "utf-16-be-with-signature,utf-16be-with-signature,utf-16-le," +
                  "utf-16-le-with-signature,utf-16le-with-signature";

  variable pfms = "A0,A1,A2,A3,A4,A5,A6,B0,B1,B2,B3,B4,B5,B6,C0,C1,C2,C3,C4,C5,C6," +
                  "D0,D1,D2,D3,D4,D5,D6,letter,legal,tabloid,ledger,statement," +
                  "executive,com10,monarch,DL";

  flush("Options Menu: output (d)evice, (e)ncoding, paper (f)ormat, " +
        "(t)oggle portrait/landscape");

  ifnot (input_pending(50)) return flush("");

  switch (getkey())
  { case 'd': ungetkey('\t');
              Groff_Output_Device =
              read_with_completion(devs, "Set Output Device:", "", "", 's');

              if (__is_initialized(&Pdfviewer_Pid))
                kill_process (Pdfviewer_Pid); }

  { case 'e': ungetkey('\t');
              Groff_Encoding =
              read_with_completion(encs, "Set Input Encoding:", "", "", 's'); }

  { case 'f': ungetkey('\t');
              Groff_Paper_Format =
              read_with_completion(pfms, "Set Paper Format:", "", "", 's'); }

  { case 't': if (Groff_Paper_Orientation == "")
              {
                Groff_Paper_Orientation = "l";
                flush("paper orientation set to landscape");
              }
              else if (Groff_Paper_Orientation == "l")
              {
                Groff_Paper_Orientation = "";
                flush("paper orientation set to portrait");
              }
  }
  { return flush(""); }
}

% Return the completion file that matches the macro package used. This
% is detected first from the contents of the document and if this is
% not possible, then from the extension of the document. If nothing
% sensible is returned, then a completion file for troff requests is
% returned.
private define groff_set_tabcompletion_file()
{
  variable completion_file = "";
  variable mp = groff_infer_macro_package();

  ifnot (mp == "")
    mp = strtrim_beg(mp, "-");
  else
    mp = strtrim_beg(path_extname(whatbuf()), ".");

  completion_file = expand_filename("~/.tabcomplete_$mp"$);

  if (1 == file_status(completion_file))
    return completion_file;
  else
    return expand_filename("~/.tabcomplete_troff");
}

% Load the tabcompletion extension with a completion file
% that matches the macro package in use.
define groff_load_tabcompletion()
{
  variable fun = __get_reference("init_tabcomplete");

  if (fun != NULL)
    (@fun(groff_set_tabcompletion_file));
}

% This is designed to give DFA highlighting in the help window if
% the tabcomplete.sl extension is enabled.
private define groff_switch_buffer_hook(oldbuf)
{
  if (is_substr(whatbuf(), "Help for") || is_substr(whatbuf(), "Apropos"))
  {
    use_syntax_table(Mode);
    use_dfa_syntax(1);
  }
}

% Check the current document for errors. It works on the contents of
% the current buffer, not the file associated with the buffer-
define groff_check_document()
{
  variable tmpfile = "/tmp/groff_check_document";
  variable mp = groff_infer_macro_package();

  push_spot(); mark_buffer();
  () = write_string_to_file(bufsubstr(), tmpfile);
  pop_spot();
  () = run_program("nroff -ww -z $mp $tmpfile 2>&1 >/dev/null | less"$);
}

% Search the groff's info page for a subnode on the macro in the
% current line
define groff_help_for_macro()
{
  variable kw = "";

  push_spot_bol();
  if (looking_at(".")) go_right_1();
  push_mark();
  skip_word_chars();
  kw = bufsubstr();
  pop_spot();

  ifnot (strlen(kw))
    kw = read_mini ("Search for?", "", "");

  ifnot (0 == run_program("info --index-search=$kw groff"$))
    flush("info found no node, \"$kw\""$);
}

define insert_tab()
{
  insert("\t");
}

%{{{ DFA syntax

% The syntax highlighting scheme for the mode.
#ifdef HAS_DFA_SYNTAX
create_syntax_table(Mode);
static define setup_dfa_callback(Mode)
{
  dfa_define_highlight_rule("^\\.[ ]*[a-zA-Z0-9_\\$\\(\\)\\-]+", "keyword", Mode); % macros
  dfa_define_highlight_rule("^\\.\\.", "keyword", Mode); % macro definition end
  dfa_define_highlight_rule("^\\.?\\\\[\"#].*", "comment", Mode); % comments
  dfa_define_highlight_rule("\\\\\".*", "comment", Mode); % comments
  dfa_define_highlight_rule("\"([^\"\\\\]|\\\\.)*\"", "string", Mode); % strings
  dfa_define_highlight_rule("\\\\[a-zA-Z]\\[[a-zA-Z]\\]", "keyword1", Mode); % text attribute
  dfa_define_highlight_rule("\\\\[a-zA-Z]\\[\\]", "keyword1", Mode); % text attribute
  dfa_define_highlight_rule("\\\\\\*\\(?", "keyword1", Mode); % string interpolation
  dfa_define_highlight_rule("\\\\\\(em", "keyword1", Mode); % em-dash
  dfa_define_highlight_rule("\\\\\\[..\\]", "keyword1", Mode); % some characters
  dfa_define_highlight_rule("\\\\\\*\\[.*\\]", "keyword1", Mode); % some strings
  dfa_define_highlight_rule("\\\\n\\[.*\\]", "keyword1", Mode); % registers
  dfa_define_highlight_rule("\\\\[\\-'0\\^\!%\\\\abcCdDefghHklmLnNoprsStuvwxXzZ" +
                            "\\|\{\}\\(&]", "keyword1", Mode);

  dfa_build_highlight_table(Mode);
  enable_dfa_syntax_for_mode(Mode);
}
dfa_set_init_callback(&setup_dfa_callback, Mode);
#endif

%}}}
%{{{ Mode keymap

ifnot (keymap_p(Mode)) make_keymap(Mode);
definekey("insert_tab", Key_Shift_Tab, Mode);
definekey("groff_help_for_macro", Key_F1, Mode);
definekey("groff_preview_buffer", Key_F9, Mode);
definekey_reserved("groff_check_document", "C", Mode);
definekey_reserved("groff_return_or_show_cmd(1)", "g", Mode);
definekey_reserved("groff_draw", "d", Mode);
definekey_reserved("groff_gpic_mini_menu", "p", Mode);
definekey_reserved("groff_toggle_inline_markup", "i", Mode);
definekey_reserved("groff_insert_font_name", "n", Mode);
definekey_reserved("groff_install_font", "f", Mode);
definekey_reserved("groff_install_fonts_in_dir", "F", Mode);
definekey_reserved("groff_set_other_options", "O", Mode);
definekey_reserved("groff_edit_cmd", "e", Mode);

%}}}

private define groff_menu(menu)
{
  menu_append_item(menu, "Preview Current Buffer", "groff_preview_buffer");
  menu_append_item(menu, "Help for macro", "groff_help_for_macro");
  menu_append_item(menu, "Insert Font Name", "groff_insert_font_name");
  menu_append_item(menu, "Install Groff Font", "groff_install_font");
  menu_append_item(menu, "Install Groff Fonts in Directory",  "groff_install_fonts_in_dir");
  menu_append_item(menu, "Toggle Text Attribute", "groff_toggle_inline_markup");
  menu_append_item(menu, "Show Groff Command", "groff_return_or_show_cmd(1)");
  menu_append_item(menu, "Edit Groff Cmd", "groff_edit_cmd");
  menu_append_item(menu, "Set Some Groff Options", "groff_set_other_options");
  menu_append_item(menu, "Draw Some Items w/Gpic", "groff_gpic_mini_menu");
  menu_append_item(menu, "Draw Some Items w/Troff", "groff_draw");
  menu_append_item(menu, "Check document for errors", "groff_check_document");
  menu_append_item(menu, "Insert Tab", "insert_tab");
}

public define groff_mode()
{
  set_mode(Mode, 4);
  set_buffer_hook("forward_paragraph_hook", "groff_goto_text_forwards");
  set_buffer_hook("backward_paragraph_hook", "groff_goto_text_backwards");
  use_syntax_table(Mode);
  use_dfa_syntax (1);
  mode_set_mode_info(Mode, "init_mode_menu", &groff_menu);
  mode_set_mode_info(Mode, "fold_info", "\\\"{{{\r\\\"}}}\r\r");
  set_comment_info(Mode, "\.\\\" ", "", 0x04);
  set_status_line("%b (%m) %a%n%o  %p   %t", 0);
  use_keymap(Mode);
  run_mode_hooks("groff_mode_hook");

  % Enable the tabcompletion extension if wanted.
  if (Groff_Use_Tabcompletion)
  {
#ifnexists init_tabcomplete
    if (strlen(expand_jedlib_file("tabcomplete.sl")))
      autoload("init_tabcomplete", "tabcomplete");
#endif

    groff_load_tabcompletion();
    add_to_hook ("_jed_switch_active_buffer_hooks", &groff_switch_buffer_hook);
  }
}
