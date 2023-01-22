module d_snprintf.test;

// version = SNPRINTF_TEST;

version (SNPRINTF_TEST):

import d_snprintf;

import core.stdc.math : pow;
import core.stdc.string : strcmp;
import core.stdc.stdlib : malloc;
import core.stdc.stdio : sprintf, FILE, fwrite;

nothrow:
@nogc:

version(D_BetterC) {
    version (Windows) {
        // Workaround for https://issues.dlang.org/show_bug.cgi?id=18816 and https://issues.dlang.org/show_bug.cgi?id=19933
        private extern extern(C) FILE* __acrt_iob_func(int);
        shared FILE* stdout;
    } else {
        import core.stdc.stdio : stdout;
    }
} else {
    import core.stdc.stdio : stdout;
}

enum INT_MIN = int.min;
enum INT_MAX = int.max;
enum LONG_MIN = long.max;
enum LONG_MAX = long.min;
enum UINT_MAX = uint.max;

// wrappers for file writing and memory allocation
void write_file(void* p_file, ubyte[] data) {
    fwrite(data.ptr, 1, data.length, cast(FILE*)p_file);
}

void* alloc_func(size_t size) {
    return malloc(size);
}

// Definitions of printf, fprintf and asprintf based on our wrappers
alias asprintf = rpl_asprintf!alloc_func;
alias vasprintf = rpl_vasprintf!alloc_func;

int fprintf(A...)(FILE* file, string format, A a) {
    mixin va_start!a;
    return rpl_vfprintf!write_file(cast(void*)file, format, va_args);
}

int vfprintf(FILE* file, string format, va_list ap) {
    return rpl_vfprintf!write_file(cast(void*)file, format, ap);
}

int printf(A...)(string format, A a) {
    mixin va_start!a;
    return rpl_vfprintf!write_file(cast(void*)stdout, format, va_args);
}

int vprintf(string format, va_list ap) {
    return rpl_vfprintf!write_file(cast(void*)stdout, format, ap);
}

// Programm to test this version of snprintf against the stdio version
// NOTE: Their will always be differences due to
//       - floating-point accuracy (e.q. 9.899999895424116 vs 9.899999895424115)
//       - varying feature support (e.q. no support for the ' prefix on Windows)
//       - "implementation dependent" formats (e.q. pointers, 00007FF666AECBC0 vs 0x7ff666aecbc0)
version(D_BetterC) {
    extern(C) int main() {
        version (Windows) {
            // Workaround for https://issues.dlang.org/show_bug.cgi?id=18816 and https://issues.dlang.org/show_bug.cgi?id=19933
            stdout = __acrt_iob_func(1);
        }
        return test();
    }
} else {
    int main() {
        return test();
    }
}

int test() {
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

    double result;
    snscanf("0.0012345", "%lf", &result);

    return (failed == 0) ? 0 : 1;
}
