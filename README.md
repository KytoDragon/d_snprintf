This is a port of Holger Weiß' implementation of snprintf (available at http://www.jhweiss.de/software/snprintf.html).
This version has no dependencies on other external libraries or the C standard library.
It does use D's TypeInfo inorder to access varargs in a typesafe and convenient manner. All Code is nothrow and @nogc.

This library defines snprintf and vsnprintf as well as a few templates that allow you to easely define a version of (v)asprinf, (v)fprintf and (v)printf that use a specific function to allocate memory or write to a file.
An example using C standard library functions (see d_snprintf/test.d):

```D
import d_snprintf;
import core.stdc.stdio : FILE, stdout, fwrite;
import core.stdc.stdlib : malloc;

void write_file(void* p_file, ubyte[] data) {
    fwrite(data.ptr, 1, data.length, cast(FILE*)p_file);
}

void* alloc_func(size_t size) { // wrapper with D calling convention
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
```

You can define the version-flag "SNPRINTF_TEST" to test this version of snprintf against the C version of your system.
