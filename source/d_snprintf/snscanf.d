module d_snprintf.snscanf;

/*
* Copyright (c) 2023 KytoDragon.
*
* A version of sscanf based on d_snprintf.
* Use however you like, as long as this and the previous notices remain intact.
*/

/*
 * ToDo
 *
 * - Add wide character support?
 * - Add support for character ranges ([ab], [^cd])
 */

import d_snprintf.vararg;

alias snscanf = rpl_snscanf;
alias vsnscanf = rpl_vsnscanf;

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

/*
* Buffer size to hold the octal string representation of UINT128_MAX without
* nul-termination ("3777777777777777777777777777777777777777777").
*/
enum MAX_CONVERT_LENGTH      = 43;

/* Format read states. */
enum SCAN_S {
    DEFAULT         = 0,
    FLAGS           = 1,
    WIDTH           = 2,
    MOD             = 5,
    CONV            = 6,
}

/* Format flags. */
enum SCAN_F {
    NO_DATA         = 0,
    UNSIGNED        = 1,
}

/* Conversion flags. */
enum SCAN_C {
    CHAR            = 1,
    SHORT           = 2,
    LONG            = 3,
    LLONG           = 4,
    LDOUBLE         = 5,
    SIZE            = 6,
    PTRDIFF         = 7,
    INTMAX          = 8,
}

pragma(inline, true) T MAX(T)(T x, T y) { return ((x >= y) ? x : y); }
pragma(inline, true) T MIN(T)(T x, T y) { return ((x <= y) ? x : y); }
pragma(inline, true) char CHARTOINT(char ch) { return cast(char)(ch - '0'); }
pragma(inline, true) bool ISDIGIT(char ch) { return ('0' <= ch && ch <= '9'); }
pragma(inline, true) bool ISNAN(real x) { return (x != x); }
pragma(inline, true) bool ISINF(real x) { return (x != 0.0 && x + x == x); }
pragma(inline, true) bool ISSPACE(char ch) { return (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\v' || ch == '\f' || ch == '\r'); }

int rpl_vsnscanf(string str, string format, va_list args) {
    size_t index = 0;
    bool fail = false;
    int base = 0;
    int cflags = 0;
    int flags = 0;
    int width = 0;
    int state = SCAN_S.DEFAULT;
    size_t format_index = 0;
    int num_parsed = 0;
    
    pragma(inline, true) char INCHAR() {
        char c = '\0';
        if (index < str.length)
            c = str[index];
        index++;
        return c;
    }
    
    pragma(inline, true) char PEEKCHAR() {
        if (index + 1 < str.length)
            return str[index + 1];
        return '\0';
    }

    // We're forgiving and allow a null pointer even if a size larger than zero was specified.
    if (str is null && str.length != 0)
        str = str[0..0];

    big_loop:
    while (format_index < format.length) {
        char ch = format[format_index++];
        final switch (state) {
            case SCAN_S.DEFAULT:
                if (ch == '%')
                    state = SCAN_S.FLAGS;
                else if (ISSPACE(ch)) {
                    while (ISSPACE(PEEKCHAR())) {
                        index++;
                    }
                } else {
                    char match = INCHAR();
                    if (match != ch) {
                        // In the case of an input failure before any data could be successfully interpreted, EOF (-1) is returned.
                        if (num_parsed == 0 && index > str.length) {
                            return -1;
                        } else {
                            return num_parsed;
                        }
                    }
                }
                break;
            case SCAN_S.FLAGS:
                switch (ch) {
                    case '*':
                        flags |= SCAN_F.NO_DATA;
                        break;
                    default:
                        state = SCAN_S.WIDTH;
                        format_index--;
                        break;
                }
                break;
            case SCAN_S.WIDTH:
                if (ISDIGIT(ch)) {
                    ch = CHARTOINT(ch);
                    if (width > (INT_MAX - ch) / 10) {
                        fail = true;
                        break big_loop;
                    }
                    width = 10 * width + ch;
                } else {
                    format_index--;
                    state = SCAN_S.MOD;
                }
                break;
            case SCAN_S.MOD:
                switch (ch) {
                    case 'h':
                        if (format_index < format.length && format[format_index] == 'h') {
                            /* It's a char. */
                            format_index++;
                            cflags = SCAN_C.CHAR;
                        } else
                            cflags = SCAN_C.SHORT;
                        break;
                    case 'l':
                        if (format_index < format.length && format[format_index] == 'l') {
                            /* It's a long long. */
                            format_index++;
                            cflags = SCAN_C.LLONG;
                        } else
                            cflags = SCAN_C.LONG;
                        break;
                    case 'L':
                        cflags = SCAN_C.LDOUBLE;
                        break;
                    case 'j':
                        cflags = SCAN_C.INTMAX;
                        break;
                    case 't':
                        cflags = SCAN_C.PTRDIFF;
                        break;
                    case 'z':
                        cflags = SCAN_C.SIZE;
                        break;
                    default:
                        format_index--;
                        break;
                }
                state = SCAN_S.CONV;
                break;
            case SCAN_S.CONV:
                // All the conversion specifiers except %c, %[…] (scan sets) and %n skip leading white space automatically
                if (ch != 'c' && ch != '[' && ch != 'n') {
                    while (ISSPACE(PEEKCHAR())) {
                        index++;
                    }
                }
                // Except for n, at least one character shall be consumed by any specifier. Otherwise the match fails, and the scan ends there.
                if (ch != 'n' && index >= str.length) {
                    // In the case of an input failure before any data could be successfully interpreted, EOF (-1) is returned.
                    if (num_parsed == 0) {
                        return -1;
                    } else {
                        return num_parsed;
                    }
                }
                switch (ch) {
                    case 'x':
                    case 'X':
                        base = 16;
                        /* FALLTHROUGH */
                        goto case 'o';
                    case 'o':
                        if (base == 0)
                            base = 8;
                        /* FALLTHROUGH */
                        goto case 'u';
                    case 'i':
                    case 'u':
                        if (base == 0)
                            base = 10;
                        /* FALLTHROUGH */
                        goto case 'd';
                    case 'd':
                        if (ch != 'd' && ch != 'i') {
                            flags |= SCAN_F.UNSIGNED;
                        }
                        // Determine base via the given prefix
                        if (base == 0) {
                            bool sign;
                            if (PEEKCHAR() == '-' || PEEKCHAR() == '+') {
                                sign = true;
                                index++;
                            }
                            base = 10;
                            if (PEEKCHAR() == '0') {
                                index++;
                                if (PEEKCHAR() == 'x' || PEEKCHAR() == 'X') {
                                    base = 16;
                                } else {
                                    base = 8;
                                }
                                index--;
                            }
                            if (sign) {
                                index--;
                            }
                        }

                        size_t max_length = MIN(str.length, index + width);
                        intmax_t value = prsint(str[0..max_length], &index, base, &fail);
                        if (fail)
                            break big_loop;
                        if (~flags & SCAN_F.NO_DATA)
                            store_any_int(value, args);
                        num_parsed++;
                        break;
                    case 'A':
                    case 'E':
                    case 'F':
                    case 'G':
                    case 'a':
                    case 'e':
                    case 'f':
                    case 'g':
                        real fvalue = prsflt(str, &index, flags, &fail);
                        if (fail)
                            break big_loop;
                        if (~flags & SCAN_F.NO_DATA)
                            store_any_float(fvalue, args);
                        num_parsed++;
                        break;
                    case 'c':
                        if (width == 0)
                            width = 1;
                        if (width == 1) {
                            char value = INCHAR();
                            if (~flags & SCAN_F.NO_DATA) {
                                if (va_get_type(args) is va_get_type!(char*)) {
                                    char* result = va_arg!(char*)(args);
                                    *result = value;
                                } else {
                                    store_any_string(cast(string)(&value)[0..1], args);
                                }
                            }
                            num_parsed++;
                        } else {
                            if (index + width > str.length) {
                                // In the case of an input failure before any data could be successfully interpreted, EOF (-1) is returned.
                                if (num_parsed == 0) {
                                    return -1;
                                } else {
                                    return num_parsed;
                                }
                            }
                            string value = str[index..index+width];
                            index += width;
                            if (~flags & SCAN_F.NO_DATA)
                                store_any_string(value, args);
                            num_parsed++;
                        }
                        break;
                    case 's':
                        size_t start = index;
                        while (index < str.length && !ISSPACE(PEEKCHAR())) {
                            index++;
                        }

                        string value = str[start..index];
                        if (~flags & SCAN_F.NO_DATA)
                            store_any_string(value, args);
                        num_parsed++;
                        break;
                    case 'p':
                        // Use hexadecimal format for pointers
                        size_t max_length = MIN(str.length, index + width);
                        intmax_t value = prsint(str[0..max_length], &index, 16, &fail);
                        if (fail)
                            break big_loop;
                        if (~flags & SCAN_F.NO_DATA)
                            store_any_pointer(cast(void*)value, args);
                        num_parsed++;
                        break;
                    case 'n':
                        if (~flags & SCAN_F.NO_DATA)
                            store_any_int(num_parsed, args);
                        num_parsed++;
                        break;
                    case '[':
                        // TODO not yet supported
                        break;
                    case '%':    /* Parse a "%" character verbatim. */
                        if (ch != INCHAR()) {
                            return num_parsed;
                        }
                        break;
                    default:    /* Skip other characters. */
                        break;
                }
                state = SCAN_S.DEFAULT;
                base = cflags = flags = width = 0;
                break;
        }
    }

    if (fail) {
        return -1;
    }
    return num_parsed;
}

intmax_t prsint(string str, size_t *index, int base, bool* fail) {
    
    pragma(inline, true) char INCHAR() {
        char c = '\0';
        if (*index < str.length)
            c = str[*index];
        *index += 1;
        return c;
    }

    pragma(inline, true) char PEEKCHAR() {
        if (*index + 1 < str.length)
            return str[*index + 1];
        return '\0';
    }

    bool minus;
    if (PEEKCHAR() == '-') {
        minus = true;
        *index += 1;
    } else if (PEEKCHAR() == '+') {
        *index += 1;
    }

    if (base == 16) {
        if (*index + 2 <= str.length && str[*index] == '0' && (str[*index+1] == 'x' || str[*index+1] == 'X')) {
            *index += 2;
        }
    } else if (base == 8) {
        if (*index + 1 <= str.length && str[*index] == '0') {
            *index += 1;
        }
    }

    string integer = getIntegerString(str, index, base);
    
    // No digits found
    if (integer.length) {
        *fail = true;
        return 0;
    }

    uintmax_t uvalue = parseInteger(integer);
    intmax_t result;
    if (minus) {
        if (uvalue == UINTMAX_MAX) {
            *fail = true;
            return 0;
        }
        result = -uvalue;
    } else {
        result = uvalue;
    }
    return result;
}

real prsflt(string str, size_t *index, real fvalue, bool *fail) {
    
    pragma(inline, true) char INCHAR() {
        char c = '\0';
        if (*index < str.length)
            c = str[*index];
        *index += 1;
        return c;
    }

    pragma(inline, true) char PEEKCHAR() {
        if (*index + 1 < str.length)
            return str[*index + 1];
        return '\0';
    }

    bool minus;
    if (PEEKCHAR() == '-') {
        minus = true;
        *index += 1;
    } else if (PEEKCHAR() == '+') {
        *index += 1;
    }

    if (str.length - *index >= 3) {
        string start = str[*index..*index+3];
        if (start == "NAN" || start == "nan") {
            return float.nan;
        } else  if (start == "INF" || start == "inf") {
            if (minus) {
                return -float.infinity;
            } else {
                return float.infinity;
            }
        }
    }

    int base = 10;
    // TODO Hex floats?
    
    string i_part = getIntegerString(str, index, base);
    string f_part;
    if (PEEKCHAR() == '.') {
        f_part = getIntegerString(str, index, base);
    }

    // No digits found
    if (i_part.length == 0 && f_part.length == 0) {
        *fail = true;
        return 0;
    }
    
    int exp = 0;
    if (PEEKCHAR() == 'e' || PEEKCHAR() == 'E') {
        
        bool e_minus;
        if (PEEKCHAR() == '-') {
            e_minus = true;
            *index += 1;
        } else if (PEEKCHAR() == '+') {
            *index += 1;
        }
        
        string e_part = getIntegerString(str, index, base);

        // No digits found
        if (e_part.length == 0) {
            *fail = true;
            return 0;
        }
        
        uintmax_t exp_ = parseInteger(e_part);
        // TODO overflow?
        exp = cast(int)exp_;
        if (e_minus) {
            exp = -exp;
        }
    }

    real result = 0;
    foreach (char c ; i_part) {
        result = 10 * result + (c - '0');
    }
    real fract_pow = 1;
    foreach (char c ; f_part) {
        fract_pow /= 10;
        result = result + fract_pow * (c - '0');
    }
    if (exp != 0) {
        result *= mypow10(exp);
    }
    if (minus) {
        result = -result;
    }
    return result;
}

string getIntegerString(string str, size_t* index, int base) {
    
    size_t start = *index;
    while (*index < str.length) {
        char c = str[*index];
        if ((c >= '0' && c <= '7')
            || (base >= 10 && c >= '8' && c <= '9')
            || (base == 16 && c >= 'a' && c <= 'a')
            || (base == 16 && c >= 'A' && c <= 'F')) {
            *index += 1;
        } else {
            break;
        }
    }
    return str[start..*index];
}

uintmax_t parseInteger(string str) {
    
    uintmax_t uvalue;
    foreach (char c; str) {
        int value;
        if (c >= '0' && c <= '9') {
            value = c - '0';
        } else if (c >= 'a' && c <= 'a') {
            value = c - 'a';
        } else if (c >= 'A' && c <= 'F') {
            value = c - 'A';
        }

        uvalue = uvalue * 10 + value;
    }
    return uvalue;
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

void store_any_int(intmax_t value, ref va_list list) {

    Type type = va_get_type(list);
    type = va_get_enum_base_type(type);
    if (va_get_type!(byte*) is type) {
        *va_arg!(byte*)(list) = cast(byte)value;
    } else if (va_get_type!(ubyte*) is type) {
        *va_arg!(ubyte*)(list) = cast(ubyte)value;
    } else if (va_get_type!(short*) is type) {
        *va_arg!(short*)(list) = cast(short)value;
    } else if (va_get_type!(ushort*) is type) {
        *va_arg!(ushort*)(list) = cast(ushort)value;
    } else if (va_get_type!(int*) is type) {
        *va_arg!(int*)(list) = cast(int)value;
    } else if (va_get_type!(uint*) is type) {
        *va_arg!(uint*)(list) = cast(uint)value;
    } else if (va_get_type!(long*) is type) {
        *va_arg!(long*)(list) = cast(long)value;
    } else if (va_get_type!(ulong*) is type) {
        *va_arg!(ulong*)(list) = cast(ulong)value;
    } else if (va_get_type!(bool*) is type) {
        *va_arg!(bool*)(list) = cast(bool)value;
    } else {
        assert(false, "Tried to store an integer to varargs but found a different type.");
    }
}

void store_any_float(real value, ref va_list list) {
    Type type = va_get_type(list);
    type = va_get_enum_base_type(type);
    if (va_get_type!(float*) is type) {
        *va_arg!(float*)(list) = cast(float)value;
    } else if (va_get_type!(double*) is type) {
        *va_arg!(double*)(list) = cast(double)value;
    } else if (va_get_type!(real*) is type) {
        *va_arg!(real*)(list) = cast(real)value;
    } else {
        assert(false, "Tried to store a floating point number to varargs but found a different type.");
    }
}

void store_any_pointer(void* value, ref va_list list) {
    Type type = va_get_type(list);
    if (va_is_pointer(type)) {
        void** result = va_arg!(void**)(list);
        *result = value;
    } else if (type is va_get_type!(size_t*)) {
        size_t* result = va_arg!(size_t*)(list);
        *result = cast(size_t)value;
    } else if (va_is_class(type)) {
        Object* result = va_arg!(Object*)(list);
        *result = cast(Object)value;
    } else {
        assert(false, "Tried to store a pointer to varargs but found a different type.");
    }
}

void store_any_string(string value, ref va_list list) {
    Type type = va_get_type(list);
    if (va_get_type!(string*) is type) { // string* -> store string
        string* result = va_arg!(string*)(list);
        *result = value;
        return;
    } else if (va_is_array(type)) { // char[], ubyte[] or byte[] -> copy string to output, zero-terminate if output has room
        type = va_get_array_elem_type(type);
        if (va_get_type!(char) is type || va_get_type!(byte) is type || va_get_type!(ubyte) is type) {
            char[] result = va_arg!(char[])(list);
            result[0..value.length] = value[];
            if (value.length < result.length) {
                result[value.length] = '\0';
            }
            return;
        }
    } else if (va_is_pointer(type)) { // char*, ubyte* or byte* -> copy string to output, zero-terminate
        type = va_get_pointer_target_type(type);
        if (va_get_type!(char) is type || va_get_type!(byte) is type || va_get_type!(ubyte) is type) {
            char[] result = va_arg!(char[])(list);
            result[0..value.length] = value[];
            result[value.length] = '\0';
            return;
        } else if (va_is_array(type)) { // char[]*, ubyte[]* or byte[]* -> store string
            type = va_get_array_elem_type(type);
            if (va_get_type!(char) is type || va_get_type!(byte) is type || va_get_type!(ubyte) is type) {
                string* result = va_arg!(string*)(list);
                *result = value;
                return;
            }
        }
    }
    assert(false, "Tried to store a string to varargs but found a different type.");
}

public:

int rpl_snscanf(A...)(string input, string format, A a) {
    mixin va_start!a;

    int count = rpl_vsnscantf(input, format, va_args);
    return count;
}
