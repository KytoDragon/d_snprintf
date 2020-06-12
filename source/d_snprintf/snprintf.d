module d_snprintf.snprintf;

/* $Id: snprintf.c,v 1.9 2008/01/20 14:02:00 holger Exp $ */

/*
* Copyright (c) 1995 Patrick Powell.
*
* This code is based on code written by Patrick Powell <papowell@astart.com>.
* It may be used for any purpose as long as this notice remains intact on all
* source code distributions.
*/

/*
* Copyright (c) 2008 Holger Weiss.
*
* This version of the code is maintained by Holger Weiss <holger@jhweiss.de>.
* My changes to the code may freely be used, modified and/or redistributed for
* any purpose.  It would be nice if additions and fixes to this file (including
* trivial code cleanups) would be sent back in order to let me include them in
* the version available at <http://www.jhweiss.de/software/snprintf.html>.
* However, this is not a requirement for using or redistributing (possibly
* modified) versions of this file, nor is leaving this notice intact mandatory.
*/

/*
* Copyright (c) 2018 KytoDragon.
*
* This version of the code is a port to the D programming language.
* Use however you like, as long as this and the previous notices remain intact.
*/

/*
 * History
 *
 * 2008-01-20 Holger Weiss <holger@jhweiss.de> for C99-snprintf 1.1:
 *
 *  Fixed the detection of infinite floating point values on IRIX (and
 *  possibly other systems) and applied another few minor cleanups.
 *
 * 2008-01-06 Holger Weiss <holger@jhweiss.de> for C99-snprintf 1.0:
 *
 *  Added a lot of new features, fixed many bugs, and incorporated various
 *  improvements done by Andrew Tridgell <tridge@samba.org>, Russ Allbery
 *  <rra@stanford.edu>, Hrvoje Niksic <hniksic@xemacs.org>, Damien Miller
 *  <djm@mindrot.org>, and others for the Samba, INN, Wget, and OpenSSH
 *  projects.  The additions include: support the "e", "E", "g", "G", and
 *  "F" conversion specifiers (and use conversion style "f" or "F" for the
 *  still unsupported "a" and "A" specifiers); support the "hh", "ll", "j",
 *  "t", and "z" length modifiers; support the "#" flag and the (non-C99)
 *  "'" flag; use localeconv(3) (if available) to get both the current
 *  locale's decimal point character and the separator between groups of
 *  digits; fix the handling of various corner cases of field width and
 *  precision specifications; fix various floating point conversion bugs;
 *  handle infinite and NaN floating point values; don't attempt to write to
 *  the output buffer (which may be NULL) if a size of zero was specified;
 *  check for integer overflow of the field width, precision, and return
 *  values and during the floating point conversion; use the OUTCHAR() macro
 *  instead of a function for better performance; provide asprintf(3) and
 *  vasprintf(3) functions; add new test cases.  The replacement functions
 *  have been renamed to use an "rpl_" prefix, the function calls in the
 *  main project (and in this file) must be redefined accordingly for each
 *  replacement function which is needed (by using Autoconf or other means).
 *  Various other minor improvements have been applied and the coding style
 *  was cleaned up for consistency.
 *
 * 2007-07-23 Holger Weiss <holger@jhweiss.de> for Mutt 1.5.13:
 *
 *  C99 compliant snprintf(3) and vsnprintf(3) functions return the number
 *  of characters that would have been written to a sufficiently sized
 *  buffer (excluding the '\0').  The original code simply returned the
 *  length of the resulting output string, so that's been fixed.
 *
 * 1998-03-05 Michael Elkins <me@mutt.org> for Mutt 0.90.8:
 *
 *  The original code assumed that both snprintf(3) and vsnprintf(3) were
 *  missing.  Some systems only have snprintf(3) but not vsnprintf(3), so
 *  the code is now broken down under HAVE_SNPRINTF and HAVE_VSNPRINTF.
 *
 * 1998-01-27 Thomas Roessler <roessler@does-not-exist.org> for Mutt 0.89i:
 *
 *  The PGP code was using unsigned hexadecimal formats.  Unfortunately,
 *  unsigned formats simply didn't work.
 *
 * 1997-10-22 Brandon Long <blong@fiction.net> for Mutt 0.87.1:
 *
 *  Ok, added some minimal floating point support, which means this probably
 *  requires libm on most operating systems.  Don't yet support the exponent
 *  (e,E) and sigfig (g,G).  Also, fmtint() was pretty badly broken, it just
 *  wasn't being exercised in ways which showed it, so that's been fixed.
 *  Also, formatted the code to Mutt conventions, and removed dead code left
 *  over from the original.  Also, there is now a builtin-test, run with:
 *  gcc -DTEST_SNPRINTF -o snprintf snprintf.c -lm && ./snprintf
 *
 * 2996-09-15 Brandon Long <blong@fiction.net> for Mutt 0.43:
 *
 *  This was ugly.  It is still ugly.  I opted out of floating point
 *  numbers, but the formatter understands just about everything from the
 *  normal C string format, at least as far as I can tell from the Solaris
 *  2.5 printf(3S) man page.
 */

/*
 * ToDo
 *
 * - Add wide character support.
 * - Add support for "%a" and "%A" conversions.
 * - Create test routines which predefine the expected results.  Our test cases
 *   usually expose bugs in system implementations rather than in ours :-)
 */

//version = SNPRINTF_TEST;

import d_snprintf.vararg;
public import d_snprintf.vararg : va_list, va_start, va_copy, va_end;

version (SNPRINTF_TEST) {
    import core.stdc.math : pow;
    import core.stdc.string : strcmp;
    import core.stdc.stdlib : malloc;
    import core.stdc.stdio : sprintf, FILE, stdout, fwrite;
}

alias snprintf = rpl_snprintf;
alias vsnprintf = rpl_vsnprintf!dummy_file_func;

alias snprintf_file_func = void function(void* file, ubyte[] data) nothrow @nogc;
alias snprintf_alloc_func = void* function(size_t ) nothrow @nogc;

private:
nothrow:
@nogc:

/* Support for uintmax_t.  We also need UINTMAX_MAX. */
alias uintmax_t = ulong;
/* Support for intmax_t. */
alias intmax_t = long;
/* Support for uintptr_t. */
alias uintptr_t = size_t;
/*
 * We need an unsigned integer type corresponding to ptrdiff_t (cf. C99:
 * 7.19.6.1, 7).  However, we'll simply use PTRDIFF_T and convert it to an
 * unsigned type if necessary.  This should work just fine in practice.
 */
alias uptrdiff_t = size_t;
/*
 * We need a signed integer type corresponding to size_t (cf. C99: 7.19.6.1, 7).
 * However, we'll simply use size_t and convert it to a signed type if
 * necessary.  This should work just fine in practice.
 */
alias ssize_t = ptrdiff_t;

enum UINTMAX_MAX = ulong.max;
enum INT_MAX = int.max;
enum INT_MIN = int.min;
enum UINT_MAX = uint.max;
enum LONG_MAX = long.min;
enum LONG_MIN = long.max;

/*
* Buffer size to hold the octal string representation of UINT128_MAX without
* nul-termination ("3777777777777777777777777777777777777777777").
*/
enum MAX_CONVERT_LENGTH      = 43;

/* Format read states. */
enum PRINT_S {
    DEFAULT         = 0,
    FLAGS           = 1,
    WIDTH           = 2,
    DOT             = 3,
    PRECISION       = 4,
    MOD             = 5,
    CONV            = 6,
}

/* Format flags. */
enum PRINT_F {
    MINUS           = (1 << 0),
    PLUS            = (1 << 1),
    SPACE           = (1 << 2),
    NUM             = (1 << 3),
    ZERO            = (1 << 4),
    QUOTE           = (1 << 5),
    UP              = (1 << 6),
    UNSIGNED        = (1 << 7),
    TYPE_G          = (1 << 8),
    TYPE_E          = (1 << 9),
}

/* Conversion flags. */
enum PRINT_C {
    CHAR            = 1,
    SHORT           = 2,
    LONG            = 3,
    LLONG           = 4,
    LDOUBLE         = 5,
    SIZE            = 6,
    PTRDIFF         = 7,
    INTMAX          = 8,
}

// We can't pass null as a template parameter of type function, so we use this as a comparison
void dummy_file_func(void* file, ubyte[] data) {}

pragma(inline, true) T MAX(T)(T x, T y) { return ((x >= y) ? x : y); }
pragma(inline, true) char CHARTOINT(char ch) { return cast(char)(ch - '0'); }
pragma(inline, true) bool ISDIGIT(char ch) { return ('0' <= ch && ch <= '9'); }
pragma(inline, true) bool ISNAN(real x) { return (x != x); }
pragma(inline, true) bool ISINF(real x) { return (x != 0.0 && x + x == x); }

int rpl_vsnprintf(alias file_func)(char[] str, string format, va_list args, void* file = null) {
    size_t len = 0;
    int overflow = 0;
    int base = 0;
    int cflags = 0;
    int flags = 0;
    int width = 0;
    int precision = -1;
    int state = PRINT_S.DEFAULT;
    size_t format_index = 0;
    size_t file_len = 0;
    
    pragma(inline, true) void OUTCHAR(char ch) {
        if (len < str.length)
            str[len] = ch;
        len++;
        static if (&file_func != &dummy_file_func) {
            if (file != null && len == str.length) {
                file_func(file, cast(ubyte[])str);
                file_len += len;
                len = 0;
            }
        }
    }

    /*
    * C99 says: "If `n' is zero, nothing is written, and `s' may be a null
    * pointer." (7.19.6.5, 2)  We're forgiving and allow a null pointer
    * even if a size larger than zero was specified.  At least NetBSD's
    * snprintf(3) does the same, as well as other versions of this file.
    * (Though some of these versions will write to a non-null buffer even
    * if a size of zero was specified, which violates the standard.)
    */
    if (str is null && str.length != 0)
        str = str[0..0];

    big_loop:
    while (format_index < format.length) {
        char ch = format[format_index++];
        final switch (state) {
            case PRINT_S.DEFAULT:
                if (ch == '%')
                    state = PRINT_S.FLAGS;
                else
                    OUTCHAR(ch);
                break;
            case PRINT_S.FLAGS:
                switch (ch) {
                    case '-':
                        flags |= PRINT_F.MINUS;
                        break;
                    case '+':
                        flags |= PRINT_F.PLUS;
                        break;
                    case ' ':
                        flags |= PRINT_F.SPACE;
                        break;
                    case '#':
                        flags |= PRINT_F.NUM;
                        break;
                    case '0':
                        flags |= PRINT_F.ZERO;
                        break;
                    case '\'':    /* SUSv2 flag (not in C99). */
                        flags |= PRINT_F.QUOTE;
                        break;
                    default:
                        state = PRINT_S.WIDTH;
                        format_index--;
                        break;
                }
                break;
            case PRINT_S.WIDTH:
                if (ISDIGIT(ch)) {
                    ch = CHARTOINT(ch);
                    if (width > (INT_MAX - ch) / 10) {
                        overflow = 1;
                        break big_loop;
                    }
                    width = 10 * width + ch;
                } else if (ch == '*') {
                    /*
                    * C99 says: "A negative field width argument is
                    * taken as a `-' flag followed by a positive
                    * field width." (7.19.6.1, 5)
                    */
                    width = cast(int)get_any_int(args);
                    if (width < 0) {
                        flags |= PRINT_F.MINUS;
                        width = -width;
                    }
                    state = PRINT_S.DOT;
                } else {
                    format_index--;
                    state = PRINT_S.DOT;
                }
                break;
            case PRINT_S.DOT:
                if (ch == '.') {
                    state = PRINT_S.PRECISION;
                } else {
                    format_index--;
                    state = PRINT_S.MOD;
                }
                break;
            case PRINT_S.PRECISION:
                if (precision == -1)
                    precision = 0;
                
                if (ISDIGIT(ch)) {
                    ch = CHARTOINT(ch);
                    if (precision > (INT_MAX - ch) / 10) {
                        overflow = 1;
                        break big_loop;
                    }
                    precision = 10 * precision + ch;
                } else if (ch == '*') {
                    /*
                    * C99 says: "A negative precision argument is
                    * taken as if the precision were omitted."
                    * (7.19.6.1, 5)
                    */
                    precision = cast(int)get_any_int(args);
                    if (precision < 0)
                        precision = -1;
                    state = PRINT_S.MOD;
                } else {
                    format_index--;
                    state = PRINT_S.MOD;
                }
                break;
            case PRINT_S.MOD:
                switch (ch) {
                    case 'h':
                        if (format_index < format.length && format[format_index] == 'h') {
                            /* It's a char. */
                            format_index++;
                            cflags = PRINT_C.CHAR;
                        } else
                            cflags = PRINT_C.SHORT;
                        break;
                    case 'l':
                        if (format_index < format.length && format[format_index] == 'l') {
                            /* It's a long long. */
                            format_index++;
                            cflags = PRINT_C.LLONG;
                        } else
                            cflags = PRINT_C.LONG;
                        break;
                    case 'L':
                        cflags = PRINT_C.LDOUBLE;
                        break;
                    case 'j':
                        cflags = PRINT_C.INTMAX;
                        break;
                    case 't':
                        cflags = PRINT_C.PTRDIFF;
                        break;
                    case 'z':
                        cflags = PRINT_C.SIZE;
                        break;
                    default:
                        format_index--;
                        break;
                }
                state = PRINT_S.CONV;
                break;
            case PRINT_S.CONV:
                switch (ch) {
                    case 'd':
                        /* FALLTHROUGH */
                    case 'i':
                        intmax_t value;
                        switch (cflags) {
                            case PRINT_C.CHAR:
                                value = cast(char)get_any_int(args);
                                break;
                            case PRINT_C.SHORT:
                                value = cast(short)get_any_int(args);
                                break;
                            case PRINT_C.LONG:
                                value = cast(int)get_any_int(args);
                                break;
                            case PRINT_C.LLONG:
                            case PRINT_C.INTMAX:
                                value = cast(long)get_any_int(args);
                                break;
                            case PRINT_C.SIZE:
                            case PRINT_C.PTRDIFF:
                                value = cast(ptrdiff_t)get_any_int(args);
                                break;
                            default:
                                value = get_any_int(args);
                                break;
                        }
                        fmtint!file_func(str, &len, value, 10, width,
                            precision, flags, file, &file_len);
                        break;
                    case 'X':
                        flags |= PRINT_F.UP;
                        /* FALLTHROUGH */
                        goto case 'x';
                    case 'x':
                        base = 16;
                        /* FALLTHROUGH */
                        goto case 'o';
                    case 'o':
                        if (base == 0)
                            base = 8;
                        /* FALLTHROUGH */
                        goto case 'u';
                    case 'u':
                        if (base == 0)
                            base = 10;
                        uintmax_t value;
                        flags |= PRINT_F.UNSIGNED;
                        switch (cflags) {
                            case PRINT_C.CHAR:
                                value = cast(ubyte)get_any_int(args);
                                break;
                            case PRINT_C.SHORT:
                                value = cast(ushort)get_any_int(args);
                                break;
                            case PRINT_C.LONG:
                                value = cast(uint)get_any_int(args);
                                break;
                            case PRINT_C.LLONG:
                            case PRINT_C.INTMAX:
                                value = cast(ulong)get_any_int(args);
                                break;
                            case PRINT_C.SIZE:
                            case PRINT_C.PTRDIFF:
                                value = cast(size_t)get_any_int(args);
                                break;
                            default:
                                value = cast(uint)get_any_int(args);
                                break;
                        }
                        fmtint!file_func(str, &len, value, base, width,
                            precision, flags, file, &file_len);
                        break;
                    case 'A':
                        /* Not yet supported, we'll use "%F". */
                        /* FALLTHROUGH */
                        goto case 'F';
                    case 'F':
                        flags |= PRINT_F.UP;
                        /* FALLTHROUGH */
                        goto case 'a';
                    case 'a':
                        /* Not yet supported, we'll use "%f". */
                        /* FALLTHROUGH */
                        goto case 'f';
                    case 'f':
                        real fvalue;
                        if (cflags == PRINT_C.LDOUBLE)
                            fvalue = cast(real)get_any_float(args);
                            // Unlike C, D does not upconvert floats to double. You need to use %lf to print doubles.
                        else if (cflags == PRINT_C.LONG)
                            fvalue = cast(double)get_any_float(args);
                        else
                            fvalue = cast(float)get_any_float(args);
                        fmtflt!file_func(str, &len, fvalue, width,
                            precision, flags, &overflow, file, &file_len);
                        if (overflow)
                            break big_loop;
                        break;
                    case 'E':
                        flags |= PRINT_F.UP;
                        /* FALLTHROUGH */
                        goto case 'e';
                    case 'e':
                        real fvalue;
                        flags |= PRINT_F.TYPE_E;
                        if (cflags == PRINT_C.LDOUBLE)
                            fvalue = cast(real)get_any_float(args);
                        else if (cflags == PRINT_C.LONG)
                            fvalue = cast(double)get_any_float(args);
                        else
                            fvalue = cast(float)get_any_float(args);
                        fmtflt!file_func(str, &len, fvalue, width,
                            precision, flags, &overflow, file, &file_len);
                        if (overflow)
                            break big_loop;
                        break;
                    case 'G':
                        flags |= PRINT_F.UP;
                        /* FALLTHROUGH */
                        goto case 'g';
                    case 'g':
                        real fvalue;
                        flags |= PRINT_F.TYPE_G;
                        if (cflags == PRINT_C.LDOUBLE)
                            fvalue = cast(real)get_any_float(args);
                        else if (cflags == PRINT_C.LONG)
                            fvalue = cast(double)get_any_float(args);
                        else
                            fvalue = cast(float)get_any_float(args);
                        /*
                        * If the precision is zero, it is treated as
                        * one (cf. C99: 7.19.6.1, 8).
                        */
                        if (precision == 0)
                            precision = 1;
                        fmtflt!file_func(str, &len, fvalue, width,
                            precision, flags, &overflow, file, &file_len);
                        if (overflow)
                            break big_loop;
                        break;
                    case 'c':
                        char cvalue;
                        if (get_type(args) is typeid(char)) {
                            cvalue = va_arg!(char)(args);
                        } else {
                            cvalue = cast(char)get_any_int(args);
                        }
                        OUTCHAR(cvalue);
                        break;
                    case 's':
                        if (has_string_like_value(args)) {
                            string strvalue = va_arg!(string)(args);
                            if (precision == -1 || precision > strvalue.length) {
                                precision = cast(int)strvalue.length;
                            }
                            fmtstr!file_func(str, &len, strvalue.ptr, width,
                                precision, flags, file, &file_len);
                        } else {
                            const(char)* strvalue = cast(const(char)*)get_any_pointer(args);
                            fmtstr!file_func(str, &len, strvalue, width,
                                precision, flags, file, &file_len);
                        }
                        break;
                    case 'p':
                        /*
                        * C99 says: "The value of the pointer is
                        * converted to a sequence of printing
                        * characters, in an implementation-defined
                        * manner." (C99: 7.19.6.1, 8)
                        */
                        void *strvalue = get_any_pointer(args);
                        if (strvalue == null)
                            /*
                            * We use the glibc format.  BSD prints
                            * "0x0", SysV "0".
                            */
                            fmtstr!file_func(str, &len, "(nil)", width, -1, flags, file, &file_len);
                        else {
                            /*
                            * We use the BSD/glibc format.  SysV
                            * omits the "0x" prefix (which we emit
                            * using the PRINT_F.NUM flag).
                            */
                            flags |= PRINT_F.NUM;
                            flags |= PRINT_F.UNSIGNED;
                            fmtint!file_func(str, &len,
                                cast(uintptr_t)strvalue, 16, width,
                                precision, flags, file, &file_len);
                        }
                        break;
                    case 'n':
                        switch (cflags) {
                            case PRINT_C.CHAR:
                                char* charptr = cast(char*)get_any_pointer(args);
                                *charptr = cast(char)(len + file_len);
                                break;
                            case PRINT_C.SHORT:
                                short* shortptr = cast(short *)get_any_pointer(args);
                                *shortptr = cast(short)(len + file_len);
                                break;
                            case PRINT_C.LONG:
                                int* longptr = cast(int *)get_any_pointer(args);
                                *longptr = cast(int)(len + file_len);
                                break;
                            case PRINT_C.LLONG:
                                long* llongptr = cast(long *)get_any_pointer(args);
                                *llongptr = cast(long)(len + file_len);
                                break;
                            case PRINT_C.SIZE:
                                /*
                                * C99 says that with the "z" length
                                * modifier, "a following `n' conversion
                                * specifier applies to a pointer to a
                                * signed integer type corresponding to
                                * size_t argument." (7.19.6.1, 7)
                                */
                                ssize_t* sizeptr = cast(ssize_t *)get_any_pointer(args);
                                *sizeptr = cast(ssize_t)(len + file_len);
                                break;
                            case PRINT_C.INTMAX:
                                intmax_t* intmaxptr = cast(intmax_t *)get_any_pointer(args);
                                *intmaxptr = cast(intmax_t)(len + file_len);
                                break;
                            case PRINT_C.PTRDIFF:
                                ptrdiff_t* ptrdiffptr = cast(ptrdiff_t *)get_any_pointer(args);
                                *ptrdiffptr = cast(ptrdiff_t)(len + file_len);
                                break;
                            default:
                                int* intptr = cast(int *)get_any_pointer(args);
                                *intptr = cast(int)(len + file_len);
                                break;
                        }
                        break;
                    case '%':    /* Print a "%" character verbatim. */
                        OUTCHAR(ch);
                        break;
                    default:    /* Skip other characters. */
                        break;
                }
                state = PRINT_S.DEFAULT;
                base = cflags = flags = width = 0;
                precision = -1;
                break;
        }
    }


    static if (&file_func != &dummy_file_func) {
        if (file != null && len > 0) {
            write_file(file, cast(ubyte[])str[0..len]);
            file_len += len;
            len = file_len;
        }
    } else {
        if (len < str.length)
            str[len] = '\0';
        else if (str.length > 0)
            str[$ - 1] = '\0';
    }
        
    if (overflow || len >= INT_MAX) {
        //errno = overflow ? EOVERFLOW : ERANGE;
        return -1;
    }
    return cast(int)len;
}

void fmtstr(alias file_func)(char[] str, size_t *len, const(char)* value, int width, int precision, int flags, void* file, size_t* file_len) {
    bool noprecision = (precision == -1);

    pragma(inline, true) void OUTCHAR(char ch) {
        if (*len + 1 <= str.length)
            str[*len] = ch;
        (*len)++;
        static if (&file_func != &dummy_file_func) {
            if (file != null && *len == str.length) {
                file_func(file, cast(ubyte[])str);
                *file_len += *len;
                *len = 0;
            }
        }
    }

    if (value == null)    /* We're forgiving. */
        value = "(null)";

    /* If a precision was specified, don't read the string past it. */
    int strln;
    for (strln = 0; (noprecision || strln < precision) &&
        value[strln] != '\0'; strln++)
        continue;

    int padlen = width - strln;    /* Amount to pad. */
    if (padlen < 0)
        padlen = 0;
    if (flags & PRINT_F.MINUS)    /* Left justify. */
        padlen = -padlen;

    while (padlen > 0) {    /* Leading spaces. */
        OUTCHAR(' ');
        padlen--;
    }
    while ((noprecision || precision-- > 0) && *value != '\0') {
        OUTCHAR(*value);
        value++;
    }
    while (padlen < 0) {    /* Trailing spaces. */
        OUTCHAR(' ');
        padlen++;
    }
}

void fmtint(alias file_func)(char[] str, size_t *len, intmax_t value, int base, int width,
    int precision, int flags, void* file, size_t* file_len) {
    bool noprecision = (precision == -1);
    
    pragma(inline, true) void OUTCHAR(char ch) {
        if (*len + 1 <= str.length)
            str[*len] = ch;
        (*len)++;
        static if (&file_func != &dummy_file_func) {
            if (file != null && *len == str.length) {
                file_func(file, cast(ubyte[])str);
                *file_len += *len;
                *len = 0;
            }
        }
    }

    uintmax_t uvalue;
    char sign = 0;
    if (flags & PRINT_F.UNSIGNED)
        uvalue = value;
    else {
        uvalue = (value >= 0) ? value : -value;
        if (value < 0)
            sign = '-';
        else if (flags & PRINT_F.PLUS)    /* Do a sign. */
            sign = '+';
        else if (flags & PRINT_F.SPACE)
            sign = ' ';
    }

    char[MAX_CONVERT_LENGTH] iconvert;
    int pos = convert(uvalue, iconvert, base,
        flags & PRINT_F.UP);

    char hexprefix = 0;
    if (flags & PRINT_F.NUM && uvalue != 0) {
        /*
        * C99 says: "The result is converted to an `alternative form'.
        * For `o' conversion, it increases the precision, if and only
        * if necessary, to force the first digit of the result to be a
        * zero (if the value and precision are both 0, a single 0 is
        * printed).  For `x' (or `X') conversion, a nonzero result has
        * `0x' (or `0X') prefixed to it." (7.19.6.1, 6)
        */
        switch (base) {
            case 8:
                if (precision <= pos)
                    precision = pos + 1;
                break;
            case 16:
                hexprefix = (flags & PRINT_F.UP) ? 'X' : 'x';
                break;
            default:
                break;
        }
    }

    int separators = 0;
    if (flags & PRINT_F.QUOTE)    /* Get the number of group separators we'll print. */
        separators = getnumsep(pos);

    int zpadlen = precision - pos - separators;    /* Amount to zero pad. */
    int spadlen = width                         /* Minimum field width. */
        - separators                        /* Number of separators. */
        - MAX(precision, pos)               /* Number of integer digits. */
        - ((sign != 0) ? 1 : 0)             /* Will we print a sign? */
        - ((hexprefix != 0) ? 2 : 0);       /* Will we print a prefix? */

    if (zpadlen < 0)
        zpadlen = 0;
    if (spadlen < 0)
        spadlen = 0;

    /*
    * C99 says: "If the `0' and `-' flags both appear, the `0' flag is
    * ignored.  For `d', `i', `o', `u', `x', and `X' conversions, if a
    * precision is specified, the `0' flag is ignored." (7.19.6.1, 6)
    */
    if (flags & PRINT_F.MINUS)    /* Left justify. */
        spadlen = -spadlen;
    else if (flags & PRINT_F.ZERO && noprecision) {
        zpadlen += spadlen;
        spadlen = 0;
    }
    while (spadlen > 0) {    /* Leading spaces. */
        OUTCHAR(' ');
        spadlen--;
    }
    if (sign != 0)    /* Sign. */
        OUTCHAR(sign);
    if (hexprefix != 0) {    /* A "0x" or "0X" prefix. */
        OUTCHAR('0');
        OUTCHAR(hexprefix);
    }
    while (zpadlen > 0) {    /* Leading zeros. */
        OUTCHAR('0');
        zpadlen--;
    }
    while (pos > 0) {    /* The actual digits. */
        pos--;
        OUTCHAR(iconvert[pos]);
        if (separators > 0 && pos > 0 && pos % 3 == 0)
            OUTCHAR(',');
    }
    while (spadlen < 0) {    /* Trailing spaces. */
        OUTCHAR(' ');
        spadlen++;
    }
}

void fmtflt(alias file_func)(char[] str, size_t *len, real fvalue, int width,
    int precision, int flags, int *overflow, void* file, size_t* file_len) {
    
    pragma(inline, true) void OUTCHAR(char ch) {
        if (*len + 1 <= str.length)
            str[*len] = ch;
        (*len)++;
        static if (&file_func != &dummy_file_func) {
            if (file != null && *len == str.length) {
                file_func(file, cast(ubyte[])str);
                *file_len += *len;
                *len = 0;
            }
        }
    }

    /*
    * AIX' man page says the default is 0, but C99 and at least Solaris'
    * and NetBSD's man pages say the default is 6, and sprintf(3) on AIX
    * defaults to 6.
    */
    if (precision == -1)
        precision = 6;

    char sign = 0;
    if (fvalue < 0.0)
        sign = '-';
    else if (flags & PRINT_F.PLUS)    /* Do a sign. */
        sign = '+';
    else if (flags & PRINT_F.SPACE)
        sign = ' ';

    const(char)* infnan = null;
    if (ISNAN(fvalue))
        infnan = (flags & PRINT_F.UP) ? "NAN" : "nan";
    else if (ISINF(fvalue))
        infnan = (flags & PRINT_F.UP) ? "INF" : "inf";

    int ipos = 0;
    if (infnan != null) {
        char[MAX_CONVERT_LENGTH] iconvert;
        if (sign != 0)
            iconvert[ipos++] = sign;
        while (*infnan != '\0')
            iconvert[ipos++] = *infnan++;
        fmtstr!file_func(str, len, iconvert.ptr, width, ipos, flags, file, file_len);
        return;
    }


    /* "%e" (or "%E") or "%g" (or "%G") conversion. */
    int exponent = 0;
    bool omitzeros = false;
    bool estyle = (flags & PRINT_F.TYPE_E) != 0;
    if (flags & PRINT_F.TYPE_E || flags & PRINT_F.TYPE_G) {
        if (flags & PRINT_F.TYPE_G) {
            /*
            * For "%g" (and "%G") conversions, the precision
            * specifies the number of significant digits, which
            * includes the digits in the integer part.  The
            * conversion will or will not be using "e-style" (like
            * "%e" or "%E" conversions) depending on the precision
            * and on the exponent.  However, the exponent can be
            * affected by rounding the converted value, so we'll
            * leave this decision for later.  Until then, we'll
            * assume that we're going to do an "e-style" conversion
            * (in order to get the exponent calculated).  For
            * "e-style", the precision must be decremented by one.
            */
            precision--;
            /*
            * For "%g" (and "%G") conversions, trailing zeros are
            * removed from the fractional portion of the result
            * unless the "#" flag was specified.
            */
            if (!(flags & PRINT_F.NUM))
                omitzeros = true;
        }
        exponent = getexponent(fvalue);
        estyle = true;
    }

    again:
    /*
    * Sorry, we only support 9, 19, or 38 digits (that is, the number of
    * digits of the 32-bit, the 64-bit, or the 128-bit UINTMAX_MAX value
    * minus one) past the decimal point due to our conversion method.
    */
    switch (uintmax_t.sizeof) {
        case 16:
        if (precision > 38)
            precision = 38;
        break;
        case 8:
        if (precision > 19)
            precision = 19;
        break;
        default:
        if (precision > 9)
            precision = 9;
        break;
    }

    real ufvalue = (fvalue >= 0.0) ? fvalue : -fvalue;
    if (estyle)    /* We want exactly one integer digit. */
        ufvalue /= mypow10(exponent);

    uintmax_t intpart = _cast(ufvalue);
    if (intpart == UINTMAX_MAX) {
        *overflow = 1;
        return;
    }

    /*
    * Factor of ten with the number of digits needed for the fractional
    * part.  For example, if the precision is 3, the mask will be 1000.
    */
    uintmax_t mask = cast(uintmax_t)mypow10(precision);
    /*
    * We "cheat" by converting the fractional part to integer by
    * multiplying by a factor of ten.
    */
    uintmax_t fracpart = myround(mask * (ufvalue - intpart));
    if (fracpart >= mask) {
        /*
        * For example, ufvalue = 2.99962, intpart = 2, and mask = 1000
        * (because precision = 3).  Now, myround(1000 * 0.99962) will
        * return 1000.  So, the integer part must be incremented by one
        * and the fractional part must be set to zero.
        */
        intpart++;
        fracpart = 0;
        if (estyle && intpart == 10) {
            /*
            * The value was rounded up to ten, but we only want one
            * integer digit if using "e-style".  So, the integer
            * part must be set to one and the exponent must be
            * incremented by one.
            */
            intpart = 1;
            exponent++;
        }
    }

    /*
    * Now that we know the real exponent, we can check whether or not to
    * use "e-style" for "%g" (and "%G") conversions.  If we don't need
    * "e-style", the precision must be adjusted and the integer and
    * fractional parts must be recalculated from the original value.
    *
    * C99 says: "Let P equal the precision if nonzero, 6 if the precision
    * is omitted, or 1 if the precision is zero.  Then, if a conversion
    * with style `E' would have an exponent of X:
    *
    * - if P > X >= -4, the conversion is with style `f' (or `F') and
    *   precision P - (X + 1).
    *
    * - otherwise, the conversion is with style `e' (or `E') and precision
    *   P - 1." (7.19.6.1, 8)
    *
    * Note that we had decremented the precision by one.
    */
    if (flags & PRINT_F.TYPE_G && estyle &&
        precision + 1 > exponent && exponent >= -4) {
        precision -= exponent;
        estyle = false;
        goto again;
    }

    char[4] econvert;    /* "e-12" (without nul-termination). */
    int epos = 0;
    if (estyle) {
        char esign = 0;
        if (exponent < 0) {
            exponent = -exponent;
            esign = '-';
        } else
            esign = '+';

        /*
        * Convert the exponent.  The econvert.sizeof is 4.  So, the
        * econvert buffer can hold e.g. "e+99" and "e-99".  We don't
        * support an exponent which contains more than two digits.
        * Therefore, the following stores are safe.
        */
        epos = convert(exponent, econvert[0..2], 10, 0);
        /*
        * C99 says: "The exponent always contains at least two digits,
        * and only as many more digits as necessary to represent the
        * exponent." (7.19.6.1, 8)
        */
        if (epos == 1)
            econvert[epos++] = '0';
        econvert[epos++] = esign;
        econvert[epos++] = (flags & PRINT_F.UP) ? 'E' : 'e';
    }

    char[MAX_CONVERT_LENGTH] iconvert;
    char[MAX_CONVERT_LENGTH] fconvert;
    /* Convert the integer part and the fractional part. */
    ipos = convert(intpart, iconvert, 10, 0);
    int fpos = 0;
    if (fracpart != 0)    /* convert() would return 1 if fracpart == 0. */
        fpos = convert(fracpart, fconvert, 10, 0);

    int leadfraczeros = precision - fpos;

    int omitcount = 0;
    if (omitzeros) {
        if (fpos > 0)    /* Omit trailing fractional part zeros. */
            while (omitcount < fpos && fconvert[omitcount] == '0')
                omitcount++;
        else {    /* The fractional part is zero, omit it completely. */
            omitcount = precision;
            leadfraczeros = 0;
        }
        precision -= omitcount;
    }

    /*
    * Print a decimal point if either the fractional part is non-zero
    * and/or the "#" flag was specified.
    */
    bool emitpoint = false;
    if (precision > 0 || flags & PRINT_F.NUM)
        emitpoint = true;
    int separators = 0;
    if (flags & PRINT_F.QUOTE)    /* Get the number of group separators we'll print. */
        separators = getnumsep(ipos);

    int padlen = width                  /* Minimum field width. */
        - ipos                      /* Number of integer digits. */
        - epos                      /* Number of exponent characters. */
        - precision                 /* Number of fractional digits. */
        - separators                /* Number of group separators. */
        - (emitpoint ? 1 : 0)       /* Will we print a decimal point? */
        - ((sign != 0) ? 1 : 0);    /* Will we print a sign character? */

    if (padlen < 0)
        padlen = 0;

    /*
    * C99 says: "If the `0' and `-' flags both appear, the `0' flag is
    * ignored." (7.19.6.1, 6)
    */
    if (flags & PRINT_F.MINUS)    /* Left justifty. */
        padlen = -padlen;
    else if (flags & PRINT_F.ZERO && padlen > 0) {
        if (sign != 0) {    /* Sign. */
            OUTCHAR(sign);
            sign = 0;
        }
        while (padlen > 0) {    /* Leading zeros. */
            OUTCHAR('0');
            padlen--;
        }
    }
    while (padlen > 0) {    /* Leading spaces. */
        OUTCHAR(' ');
        padlen--;
    }
    if (sign != 0)    /* Sign. */
        OUTCHAR(sign);
    while (ipos > 0) {    /* Integer part. */
        ipos--;
        OUTCHAR(iconvert[ipos]);
        if (separators > 0 && ipos > 0 && ipos % 3 == 0)
            OUTCHAR(',');
    }
    if (emitpoint) {    /* Decimal point. */
        OUTCHAR('.');
    }
    while (leadfraczeros > 0) {    /* Leading fractional part zeros. */
        OUTCHAR('0');
        leadfraczeros--;
    }
    while (fpos > omitcount) {    /* The remaining fractional part. */
        fpos--;
        OUTCHAR(fconvert[fpos]);
    }
    while (epos > 0) {    /* Exponent. */
        epos--;
        OUTCHAR(econvert[epos]);
    }
    while (padlen < 0) {    /* Trailing spaces. */
        OUTCHAR(' ');
        padlen++;
    }
}

int getnumsep(inout int digits) {
    inout const shared int separators = (digits - ((digits % 3 == 0) ? 1 : 0)) / 3;
    return separators;
}

int getexponent(real value) {
    real tmp = (value >= 0.0) ? value : -value;
    int exponent = 0;

    /*
    * We check for 99 > exponent > -99 in order to work around possible
    * endless loops which could happen (at least) in the second loop (at
    * least) if we're called with an infinite value.  However, we checked
    * for infinity before calling this function using our ISINF() macro, so
    * this might be somewhat paranoid.
    */
    while (tmp < 1.0 && tmp > 0.0 && --exponent > -99)
        tmp *= 10;
    while (tmp >= 10.0 && ++exponent < 99)
        tmp /= 10;

    return exponent;
}

int convert(uintmax_t value, char[] buf, int base, int caps) {
    const(char)* digits = caps ? "0123456789ABCDEF" : "0123456789abcdef";
    size_t pos = 0;

    /* We return an unterminated buffer with the digits in reverse order. */
    do {
        buf[pos++] = digits[cast(size_t)(value % base)];
        value /= base;
    } while (value != 0 && pos < buf.length);

    return cast(int)pos;
}

uintmax_t _cast(real value) {
    uintmax_t result;

    /*
    * We check for ">=" and not for ">" because if UINTMAX_MAX cannot be
    * represented exactly as an LDOUBLE value (but is less than LDBL_MAX),
    * it may be increased to the nearest higher representable value for the
    * comparison (cf. C99: 6.3.1.4, 2).  It might then equal the LDOUBLE
    * value although converting the latter to UINTMAX_MAX would overflow.
    */
    if (value >= UINTMAX_MAX)
        return UINTMAX_MAX;

    result = cast(uintmax_t)value;
    /*
    * At least on NetBSD/sparc64 3.0.2 and 4.99.30, casting long double to
    * an integer type converts e.g. 1.9 to 2 instead of 1 (which violates
    * the standard).  Sigh.
    */
    return (result <= value) ? result : result - 1;
}

uintmax_t myround(real value) {
    uintmax_t intpart = _cast(value);

    return ((value -= intpart) < 0.5) ? intpart : intpart + 1;
}

real mypow10(int exponent) {
    real result = 1;

    while (exponent > 0) {
        result *= 10;
        exponent--;
    }
    while (exponent < 0) {
        result /= 10;
        exponent++;
    }
    return result;
}

public:

int rpl_snprintf(char[] str, string format, ...) {
    mixin va_start;

    int len = rpl_vsnprintf!dummy_file_func(str, format, va_args);
    return len;
}

int rpl_fprintf(alias file_func)(void* file, string format, ...) {
    mixin va_start;

    int len = rpl_vfprintf!file_func(file, format, va_args);
    return len;
}

int rpl_vfprintf(alias file_func)(void* file, string format, va_list ap) {
    if (file == null) {
        int len = rpl_vsnprintf!dummy_file_func(null, format, ap);
        return len;
    } else {
        char[1024] str = 0;
        int len = rpl_vsnprintf!file_func(str, format, ap, file);
        return len;
    }
}

int rpl_asprintf(alias alloc_func)(char[]* ret, string format, ...) {
    mixin va_start;

    int len = rpl_vasprintf!alloc_func(ret, format, va_args);
    return len;
}

int rpl_vasprintf(alias alloc_func)(char[]* ret, string format, va_list ap) {
    va_list aq;
    size_t size;
    va_copy(aq, ap);

    int len = rpl_vsnprintf!dummy_file_func(null, format, aq);
    if (len < 0 || (*ret = (cast(char*)alloc_func(size = len + 1))[0..size]) is null)
        return -1;
    return rpl_vsnprintf!dummy_file_func(*ret, format, ap);
}

version(SNPRINTF_TEST) {

void write_file(void* p_file, ubyte[] data) {
    fwrite(data.ptr, 1, data.length, cast(FILE*)p_file);
}

// wrapper with D calling convention
void* alloc_func(size_t size) {
    return malloc(size);
}

alias asprintf = rpl_asprintf!alloc_func;
alias vasprintf = rpl_vasprintf!alloc_func;

int fprintf(FILE* file, string format, ...) {
    mixin va_start;
    return rpl_vfprintf!write_file(cast(void*)file, format, va_args);
}

int vfprintf(FILE* file, string format, va_list ap) {
    return rpl_vfprintf!write_file(cast(void*)file, format, ap);
}

int printf(string format, ...) {
    mixin va_start;
    return rpl_vfprintf!write_file(cast(void*)stdout, format, va_args);
}

int vprintf(string format, va_list ap) {
    return rpl_vfprintf!write_file(cast(void*)stdout, format, ap);
}

int main() {
    __gshared const string[] float_fmt = [
        /* "%E" and "%e" formats. */
        "%.16e",
        "%22.16e",
        "%022.16e",
        "%-22.16e",
        "%#+'022.16e",
        "foo|%#+0123.9E|bar",
        "%-123.9e",
        "%123.9e",
        "%+23.9e",
        "%+05.8e",
        "%-05.8e",
        "%05.8e",
        "%+5.8e",
        "%-5.8e",
        "% 5.8e",
        "%5.8e",
        "%+4.9e",
        "%+#010.0e",
        "%#10.1e",
        "%10.5e",
        "% 10.5e",
        "%5.0e",
        "%5.e",
        "%#5.0e",
        "%#5.e",
        "%3.2e",
        "%3.1e",
        "%-1.5e",
        "%1.5e",
        "%01.3e",
        "%1.e",
        "%.1e",
        "%#.0e",
        "%+.0e",
        "% .0e",
        "%.0e",
        "%#.e",
        "%+.e",
        "% .e",
        "%.e",
        "%4e",
        "%e",
        "%E",
        /* "%F" and "%f" formats. */
        "% '022f",
        "%+'022f",
        "%-'22f",
        "%'22f",
        "%.16f",
        "%22.16f",
        "%022.16f",
        "%-22.16f",
        "%#+'022.16f",
        "foo|%#+0123.9F|bar",
        "%-123.9f",
        "%123.9f",
        "%+23.9f",
        "%+#010.0f",
        "%#10.1f",
        "%10.5f",
        "% 10.5f",
        "%+05.8f",
        "%-05.8f",
        "%05.8f",
        "%+5.8f",
        "%-5.8f",
        "% 5.8f",
        "%5.8f",
        "%5.0f",
        "%5.f",
        "%#5.0f",
        "%#5.f",
        "%+4.9f",
        "%3.2f",
        "%3.1f",
        "%-1.5f",
        "%1.5f",
        "%01.3f",
        "%1.f",
        "%.1f",
        "%#.0f",
        "%+.0f",
        "% .0f",
        "%.0f",
        "%#.f",
        "%+.f",
        "% .f",
        "%.f",
        "%4f",
        "%f",
        "%F",
        /* "%G" and "%g" formats. */
        "% '022g",
        "%+'022g",
        "%-'22g",
        "%'22g",
        "%.16g",
        "%22.16g",
        "%022.16g",
        "%-22.16g",
        "%#+'022.16g",
        "foo|%#+0123.9G|bar",
        "%-123.9g",
        "%123.9g",
        "%+23.9g",
        "%+05.8g",
        "%-05.8g",
        "%05.8g",
        "%+5.8g",
        "%-5.8g",
        "% 5.8g",
        "%5.8g",
        "%+4.9g",
        "%+#010.0g",
        "%#10.1g",
        "%10.5g",
        "% 10.5g",
        "%5.0g",
        "%5.g",
        "%#5.0g",
        "%#5.g",
        "%3.2g",
        "%3.1g",
        "%-1.5g",
        "%1.5g",
        "%01.3g",
        "%1.g",
        "%.1g",
        "%#.0g",
        "%+.0g",
        "% .0g",
        "%.0g",
        "%#.g",
        "%+.g",
        "% .g",
        "%.g",
        "%4g",
        "%g",
        "%G",
    ];
    __gshared const float[] float_val = [
        -4.136,
        -134.52,
        -5.04030201,
        -3410.01234,
        -999999.999999,
        -913450.29876,
        -913450.2,
        -91345.2,
        -9134.2,
        -913.2,
        -91.2,
        -9.2,
        -9.9,
        4.136,
        134.52,
        5.04030201,
        3410.01234,
        999999.999999,
        913450.29876,
        913450.2,
        91345.2,
        9134.2,
        913.2,
        91.2,
        9.2,
        9.9,
        9.96,
        9.996,
        9.9996,
        9.99996,
        9.999996,
        9.9999996,
        9.99999996,
        0.99999996,
        0.99999999,
        0.09999999,
        0.00999999,
        0.00099999,
        0.00009999,
        0.00000999,
        0.00000099,
        0.00000009,
        0.00000001,
        0.0000001,
        0.000001,
        0.00001,
        0.0001,
        0.001,
        0.01,
        0.1,
        1.0,
        1.5,
        -1.5,
        -1.0,
        -0.1,
        float.infinity,
        -float.infinity,
        float.nan,
        0
    ];
    __gshared const string[] long_fmt = [
        "foo|%0123ld|bar",
        "% '0123ld",
        "%+'0123ld",
        "%-'123ld",
        "%'123ld",
        "%123.9ld",
        "% 123.9ld",
        "%+123.9ld",
        "%-123.9ld",
        "%0123ld",
        "% 0123ld",
        "%+0123ld",
        "%-0123ld",
        "%10.5ld",
        "% 10.5ld",
        "%+10.5ld",
        "%-10.5ld",
        "%010ld",
        "% 010ld",
        "%+010ld",
        "%-010ld",
        "%4.2ld",
        "% 4.2ld",
        "%+4.2ld",
        "%-4.2ld",
        "%04ld",
        "% 04ld",
        "%+04ld",
        "%-04ld",
        "%5.5ld",
        "%+22.33ld",
        "%01.3ld",
        "%1.5ld",
        "%-1.5ld",
        "%44ld",
        "%4ld",
        "%4.0ld",
        "%4.ld",
        "%.44ld",
        "%.4ld",
        "%.0ld",
        "%.ld",
        "%ld",
    ];
    __gshared const int[] long_val = [
        INT_MAX,
        INT_MIN,
        - 91340,
        91340,
        341,
        134,
        131,
        -1,
        1,
        0
    ];
    __gshared const string[] ulong_fmt = [
        /* "%u" formats. */
        "foo|%0123lu|bar",
        "% '0123lu",
        "%+'0123lu",
        "%-'123lu",
        "%'123lu",
        "%123.9lu",
        "% 123.9lu",
        "%+123.9lu",
        "%-123.9lu",
        "%0123lu",
        "% 0123lu",
        "%+0123lu",
        "%-0123lu",
        "%5.5lu",
        "%+22.33lu",
        "%01.3lu",
        "%1.5lu",
        "%-1.5lu",
        "%44lu",
        "%lu",
        /* "%o" formats. */
        "foo|%#0123lo|bar",
        "%#123.9lo",
        "%# 123.9lo",
        "%#+123.9lo",
        "%#-123.9lo",
        "%#0123lo",
        "%# 0123lo",
        "%#+0123lo",
        "%#-0123lo",
        "%#5.5lo",
        "%#+22.33lo",
        "%#01.3lo",
        "%#1.5lo",
        "%#-1.5lo",
        "%#44lo",
        "%#lo",
        "%123.9lo",
        "% 123.9lo",
        "%+123.9lo",
        "%-123.9lo",
        "%0123lo",
        "% 0123lo",
        "%+0123lo",
        "%-0123lo",
        "%5.5lo",
        "%+22.33lo",
        "%01.3lo",
        "%1.5lo",
        "%-1.5lo",
        "%44lo",
        "%lo",
        /* "%X" and "%x" formats. */
        "foo|%#0123lX|bar",
        "%#123.9lx",
        "%# 123.9lx",
        "%#+123.9lx",
        "%#-123.9lx",
        "%#0123lx",
        "%# 0123lx",
        "%#+0123lx",
        "%#-0123lx",
        "%#5.5lx",
        "%#+22.33lx",
        "%#01.3lx",
        "%#1.5lx",
        "%#-1.5lx",
        "%#44lx",
        "%#lx",
        "%#lX",
        "%123.9lx",
        "% 123.9lx",
        "%+123.9lx",
        "%-123.9lx",
        "%0123lx",
        "% 0123lx",
        "%+0123lx",
        "%-0123lx",
        "%5.5lx",
        "%+22.33lx",
        "%01.3lx",
        "%1.5lx",
        "%-1.5lx",
        "%44lx",
        "%lx",
        "%lX",
    ];
    __gshared const uint[] ulong_val = [
        UINT_MAX,
        91340,
        341,
        134,
        131,
        1,
        0
    ];
    __gshared const string[] llong_fmt = [
        "foo|%0123lld|bar",
        "%123.9lld",
        "% 123.9lld",
        "%+123.9lld",
        "%-123.9lld",
        "%0123lld",
        "% 0123lld",
        "%+0123lld",
        "%-0123lld",
        "%5.5lld",
        "%+22.33lld",
        "%01.3lld",
        "%1.5lld",
        "%-1.5lld",
        "%44lld",
        "%lld",
    ];
    __gshared const long[] llong_val = [
        LONG_MAX,
        LONG_MIN,
        - 91340,
        91340,
        341,
        134,
        131,
        -1,
        1,
        0
    ];
    __gshared const string[] string_fmt = [
        "foo|%10.10s|bar",
        "%-10.10s",
        "%10.10s",
        "%10.5s",
        "%5.10s",
        "%10.1s",
        "%1.10s",
        "%10.0s",
        "%0.10s",
        "%-42.5s",
        "%2.s",
        "%.10s",
        "%.1s",
        "%.0s",
        "%.s",
        "%4s",
        "%s",
    ];
    __gshared const string[] string_val = [
        "Hello",
        "Hello, world!",
        "Sound check: One, two, three.",
        "This string is a little longer than the other strings.",
        "1",
        "\0"[0..0], // D outputs null for empty strings, this is a workaround
        null
    ];
    __gshared const string[] pointer_fmt = [
        "foo|%p|bar",
        "%42p",
        "%p",
    ];
    __gshared const string[]*[] pointer_val = [
        &pointer_fmt,
        &string_fmt,
        &string_val,
        null
    ];
    char[1024] buf1;
    char[1024] buf2;
    double digits = 9.123456789012345678901234567890123456789;
    int failed = 0, num = 0;

    void TEST(T)(const string[] fmt, T[] val) {
        for (int i = 0; i < fmt.length; i++)
            for (int j = 0; j < val.length; j++) {
                static if (typeid(T) is typeid(const string)) {
                    int r1 = sprintf(buf1.ptr, fmt[i].ptr, val[j].ptr);
                } else {
                    int r1 = sprintf(buf1.ptr, fmt[i].ptr, val[j]);
                }
                int r2 = snprintf(buf2, fmt[i], val[j]);
                string a = r1 < 0 ? null : cast(string)buf1[0..r1];
                string b = r2 < 0 ? null : cast(string)buf2[0..r2];
                if (a != b || r1 != r2) {
                    printf("Results don't match, "
                        ~ "format string: %s\n"
                        ~ "\t sprintf(3): [%s] (%d)\n"
                        ~ "\tsnprintf(3): [%s] (%d)\n",
                        fmt[i], a, r1, b, r2);
                    failed++;
                }
                num++;
            }
    }

    printf("Testing our snprintf(3) against your system's sprintf(3).\n");
    TEST(float_fmt, float_val);
    TEST(long_fmt, long_val);
    TEST(ulong_fmt, ulong_val);
    TEST(llong_fmt, llong_val);
    TEST(string_fmt, string_val);
    TEST(pointer_fmt, pointer_val);
    printf("Result: %d out of %d tests failed.\n", failed, num);

    printf("Checking how many digits we support: ");
    for (int i = 0; i < 100; i++) {
        double value = pow(10.0, cast(double)i) * digits;
        sprintf(buf1.ptr, "%.1f\n", value);
        snprintf(buf2, "%.1f\n", value);
        if (strcmp(buf1.ptr, buf2.ptr) != 0) {
            printf("apparently %d.\n", i);
            break;
        }
    }
    return (failed == 0) ? 0 : 1;
}

}
