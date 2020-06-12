module d_snprintf.vararg;

import core.stdc.stdarg : org_va_list = va_list, org_va_arg = va_arg;

@nogc:
nothrow:

struct va_list {
    org_va_list values;
    TypeInfo[] types;
    size_t current;
}

mixin template va_start() {
    va_list va_args = get_varargs(_argptr, _arguments);
}
pragma(inline, true) void va_end(va_list) {}

pragma(inline, true) void va_copy(ref va_list copy, ref va_list args) {
    copy = args;
}

va_list get_varargs(org_va_list list, TypeInfo[] types) {
    va_list result;
    result.values = list;
    result.types = types;
    // Ideally we would strip the all types of attributes here, but "types" is in read-only memory.
    // We could alloca a copy of it, but it is not worth it right now.
    // (We could also alloca a list of pointers to each element in "values" in order to be able to backwards)
    return result;
}

pragma(inline, true) T va_arg(T)(ref va_list list) {
    list.current++;
    return org_va_arg!T(list.values);
}

pragma(inline, true) size_t va_size(va_list list) {
    return list.types.length - list.current;
}

pragma(inline, true) TypeInfo get_type(va_list list) {
    return strip_type_info(list.types[list.current]);
}

// Removes const, immutabe, shared and inout
TypeInfo strip_type_info(TypeInfo type) {

    while ((cast(TypeInfo_Const)type) !is null) {
        type = (cast(TypeInfo_Const)type).base;
    }
    return type;
}

void* get_any_pointer(ref va_list list) {
    TypeInfo type = get_type(list);
    if ((cast(TypeInfo_Pointer)type) !is null) {
        void* result = va_arg!(void*)(list);
        return result;
    } else if ((cast(TypeInfo_Array)type) !is null) {
        void[] result = va_arg!(void[])(list);
        return result.ptr;
    } else if (type is typeid(size_t)) {
        size_t result = va_arg!(size_t)(list);
        return cast(void*)result;
    } else if ((cast(TypeInfo_Class)type) !is null) {
        Object result = va_arg!(Object)(list);
        return cast(void*)result;
    } else {
        assert(false, "Tried to read a pointer from varargs but found a different type.");
    }
}

long get_any_int(ref va_list list) {
    TypeInfo type = get_type(list);
    if ((cast(TypeInfo_Enum)type) !is null) {
        type = strip_type_info((cast(TypeInfo_Enum)type).base);
    }
    if (typeid(byte) is type) {
        return va_arg!byte(list);
    } else if (typeid(ubyte) is type) {
        return va_arg!ubyte(list);
    } else if (typeid(short) is type) {
        return va_arg!short(list);
    } else if (typeid(ushort) is type) {
        return va_arg!ushort(list);
    } else if (typeid(int) is type) {
        return va_arg!int(list);
    } else if (typeid(uint) is type) {
        return va_arg!uint(list);
    } else if (typeid(long) is type) {
        return va_arg!long(list);
    } else if (typeid(ulong) is type) {
        return va_arg!ulong(list);
    } else if (typeid(bool) is type) {
        return va_arg!bool(list) ? 1 : 0;
    } else {
        assert(false, "Tried to read a integer from varargs but found a different type.");
    }
}

real get_any_float(ref va_list list) {
    TypeInfo type = get_type(list);
    if ((cast(TypeInfo_Enum)type) !is null) {
        type = strip_type_info((cast(TypeInfo_Enum)type).base);
    }
    if (typeid(float) is type) {
        return va_arg!float(list);
    } else if (typeid(double) is type) {
        return va_arg!double(list);
    } else if (typeid(real) is type) {
        return va_arg!real(list);
    } else {
        assert(false, "Tried to read a floating point number from varargs but found a different type.");
    }
}

// Look for string, char[] or (u)byte[]
bool has_string_like_value(ref va_list list) {
    TypeInfo type = get_type(list);
    if (typeid(string) is type) {
        return true;
    } else if ((cast(TypeInfo_Array)type) !is null) {
        type = strip_type_info((cast(TypeInfo_Array)type).value);
        if (typeid(char) is type || typeid(byte) is type || typeid(ubyte) is type) {
            return true;
        }
    }
    return false;
}