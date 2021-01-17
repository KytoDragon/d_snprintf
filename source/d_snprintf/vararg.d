module d_snprintf.vararg;

@nogc:
nothrow:

version (D_TypeInfo) {
    alias Type = TypeInfo;
} else {
    // Without TypeInfo we use an opaque hash to identify types.
    alias Type = size_t;
}

struct va_list {
    void*[] values;
    Type[] types;
    size_t current;

    @nogc:
    nothrow:

    int opApply(int delegate(va_elem) nothrow @nogc dg) {
        int result = 0;

        for (size_t i = current; i < values.length; i++) {
            result = dg(va_elem(values[i], types[i]));
            if (result) {
                break;
            }
        }
        return result;
    }
}

struct va_elem {
    void* value;
    Type type;
}

mixin template va_start(a...) {
    ubyte[a.length * (size_t.sizeof) * 2] va_args_buffer;
    va_list va_args = get_varargs(a, va_args_buffer[]);
}
pragma(inline, true) void va_end(va_list) {}

pragma(inline, true) void va_copy(ref va_list copy, ref va_list args) {
    copy = args;
}

va_list get_varargs(A...)(ref A a, ubyte[] buffer) {
    va_list result;
    result.values = (cast(void**)buffer.ptr)[0..a.length];
    result.types = (cast(Type*)buffer.ptr)[a.length..a.length * 2];
    static foreach (i, t; a) {
        result.values[i] = cast(void*)&t;
        result.types[i] = va_get_type!(typeof(t));
    }
    return result;
}

static if (size_t.sizeof == 8) {
    private enum TYPE_MASK      = 0x0FFFFFFFFFFFFFFF;
    private enum TYPE_POINTER   = 0x1000000000000000;
    private enum TYPE_ARRAY     = 0x2000000000000000;
    private enum TYPE_ENUM      = 0x4000000000000000;
    private enum TYPE_CLASS     = 0x8000000000000000;
} else {
    private enum TYPE_MASK      = 0x0FFFFFFF;
    private enum TYPE_POINTER   = 0x10000000;
    private enum TYPE_ARRAY     = 0x20000000;
    private enum TYPE_ENUM      = 0x40000000;
    private enum TYPE_CLASS     = 0x80000000;
}

Type va_get_type(T)() {
    version(D_TypeInfo) {
        return strip_type_info(typeid(T));
    } else {
        import std.traits : Unqual, isPointer, OriginalType;
        size_t result = 0;
        alias stripped_T = Unqual!T;
        static if (isPointer!(stripped_T)) {
            alias actual_T = PointerTarget!stripped_T;
            result |= TYPE_POINTER;
        } else static if (is(stripped_T : E[], E)) {
            alias actual_T = E;
            result |= TYPE_ARRAY;
        } else static if (is(stripped_T == enum)) {
            alias actual_T = OriginalType!stripped_T;
            result |= TYPE_ENUM;
        } else static if (is(stripped_T == class)) {
            alias actual_T = stripped_T;
            result |= TYPE_CLASS;
        } else {
            alias actual_T = stripped_T;
        }

        // We just have to hope this is unique.
        result |= get_type_hash!(Unqual!actual_T) & TYPE_MASK;
        return result;
    }
}

private template get_type_hash(T) {
    // Removes const, immutabe, shared and inout
    enum get_type_hash = fnv_1a_hash(T.mangleof);
}

private size_t fnv_1a_hash(string s) {
    static if (size_t.sizeof == 8) {
        enum fnv_prime = 0x100000001b3;
        enum fnv_offset_basis = 0xcbf29ce484222000;
    } else {
        enum fnv_prime = 0x1000193;
        enum fnv_offset_basis = 0x811c9dc5;
    }
    size_t hash = fnv_offset_basis;
    foreach (char value; s) {
            hash = hash ^ value;
            hash = hash * fnv_prime;
    }
    return hash;
}

pragma(inline, true) T va_arg(T)(ref va_list list) {
    return *(cast(T*)list.values[list.current++]);
}

pragma(inline, true) T va_peek(T)(ref va_list list) {
    return *(cast(T*)list.values[list.current]);
}

pragma(inline, true) va_elem va_get_elem(ref va_list list) {
    return va_elem(list.values[list.current], list.types[list.current]);
}

pragma(inline, true) va_elem va_get_elem(ref va_list list, int i) {
    return va_elem(list.values[list.current + i], list.types[list.current + i]);
}

pragma(inline, true) T va_value(T)(va_elem elem) {
    return *(cast(T*)elem.value);
}

pragma(inline, true) size_t va_size(va_list list) {
    return list.types.length - list.current;
}

pragma(inline, true) Type va_get_type(va_list list) {
    return list.types[list.current];
}

pragma(inline, true) bool va_is_enum(Type type) {
    version(D_TypeInfo) {
        return (cast(TypeInfo_Enum)type) !is null;
    } else {
        return (type & TYPE_ENUM) != 0;
    }
}

pragma(inline, true) bool va_is_pointer(Type type) {
    version(D_TypeInfo) {
        return (cast(TypeInfo_Pointer)type) !is null;
    } else {
        return (type & TYPE_POINTER) != 0;
    }
}

pragma(inline, true) bool va_is_class(Type type) {
    version(D_TypeInfo) {
        return (cast(TypeInfo_Class)type) !is null;
    } else {
        return (type & TYPE_CLASS) != 0;
    }
}

pragma(inline, true) bool va_is_array(Type type) {
    version(D_TypeInfo) {
        return (cast(TypeInfo_Array)type) !is null;
    } else {
        return (type & TYPE_ARRAY) != 0;
    }
}

pragma(inline, true) Type va_remove_enum(Type type) {
    if (va_is_enum(type)) {
        version(D_TypeInfo) {
            return strip_type_info((cast(TypeInfo_Enum)type).base);
        } else {
            return type & TYPE_MASK;
        }
    }
    return type;
}

pragma(inline, true) Type va_get_array_elem(Type type) {
    assert(va_is_array(type));
    version(D_TypeInfo) {
        return type = strip_type_info((cast(TypeInfo_Array)type).value);
    } else {
        return type & TYPE_MASK;
    }
}

version (D_TypeInfo) {
    // Removes const, immutabe, shared and inout
    TypeInfo strip_type_info(TypeInfo type) {

        while ((cast(TypeInfo_Const)type) !is null) {
            type = (cast(TypeInfo_Const)type).base;
        }
        return type;
    }
}

void* get_any_pointer(ref va_list list) {
    Type type = va_get_type(list);
    if (va_is_pointer(type)) {
        void* result = va_arg!(void*)(list);
        return result;
    } else if (va_is_array(type)) {
        void[] result = va_arg!(void[])(list);
        return result.ptr;
    } else if (type is va_get_type!(size_t)) {
        size_t result = va_arg!(size_t)(list);
        return cast(void*)result;
    } else if (va_is_class(type)) {
        Object result = va_arg!(Object)(list);
        return cast(void*)result;
    } else {
        assert(false, "Tried to read a pointer from varargs but found a different type.");
    }
}

long get_any_int(ref va_list list) {
    Type type = va_get_type(list);
    type = va_remove_enum(type);
    if (va_get_type!(byte) is type) {
        return va_arg!byte(list);
    } else if (va_get_type!(ubyte) is type) {
        return va_arg!ubyte(list);
    } else if (va_get_type!(short) is type) {
        return va_arg!short(list);
    } else if (va_get_type!(ushort) is type) {
        return va_arg!ushort(list);
    } else if (va_get_type!(int) is type) {
        return va_arg!int(list);
    } else if (va_get_type!(uint) is type) {
        return va_arg!uint(list);
    } else if (va_get_type!(long) is type) {
        return va_arg!long(list);
    } else if (va_get_type!(ulong) is type) {
        return va_arg!ulong(list);
    } else if (va_get_type!(bool) is type) {
        return va_arg!bool(list) ? 1 : 0;
    } else {
        assert(false, "Tried to read a integer from varargs but found a different type.");
    }
}

real get_any_float(ref va_list list) {
    Type type = va_get_type(list);
    type = va_remove_enum(type);
    if (va_get_type!(float) is type) {
        return va_arg!float(list);
    } else if (va_get_type!(double) is type) {
        return va_arg!double(list);
    } else if (va_get_type!(real) is type) {
        return va_arg!real(list);
    } else {
        assert(false, "Tried to read a floating point number from varargs but found a different type.");
    }
}

// Look for string, char[] or (u)byte[]
bool has_string_like_value(ref va_list list) {
    Type type = va_get_type(list);
    if (va_get_type!(string) is type) {
        return true;
    } else if (va_is_array(type)) {
        type = va_get_array_elem(type);
        if (va_get_type!(char) is type || va_get_type!(byte) is type || va_get_type!(ubyte) is type) {
            return true;
        }
    }
    return false;
}