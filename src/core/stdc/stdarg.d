/**
 * D header file for C99.
 *
 * $(C_HEADER_DESCRIPTION pubs.opengroup.org/onlinepubs/009695399/basedefs/_stdarg.h.html, _stdarg.h)
 *
 * Copyright: Copyright Digital Mars 2000 - 2020.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Walter Bright, Hauke Duden
 * Standards: ISO/IEC 9899:1999 (E)
 * Source: $(DRUNTIMESRC core/stdc/_stdarg.d)
 */

module core.stdc.stdarg;

@system:
//@nogc:    // Not yet, need to make TypeInfo's member functions @nogc first
nothrow:

version (X86_64)
{
    version (Windows) { /* different ABI */ }
    else version = SysV_x64;
}

version (SysV_x64)
{
    static import core.internal.vararg.sysv_x64;

    version (DigitalMars)
    {
        align(16) struct __va_argsave_t
        {
            size_t[6] regs;   // RDI,RSI,RDX,RCX,R8,R9
            real[8] fpregs;   // XMM0..XMM7
            __va_list va;
        }
    }
}

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

version (Darwin) { /* simpler varargs implementation */ }
else
{
    version (ARM)
        version = AAPCS32;
}

version (MIPS32) version = MIPS_Any;
version (MIPS64) version = MIPS_Any;
version (PPC)    version = PPC_Any;
version (PPC64)  version = PPC_Any;


T alignUp(size_t alignment = size_t.sizeof, T)(T base) pure
{
    enum mask = alignment - 1;
    static assert(alignment > 0 && (alignment & mask) == 0, "alignment must be a power of 2");
    auto b = cast(size_t) base;
    b = (b + mask) & ~mask;
    return cast(T) b;
}

unittest
{
    assert(1.alignUp == size_t.sizeof);
    assert(31.alignUp!16 == 32);
    assert(32.alignUp!16 == 32);
    assert(33.alignUp!16 == 48);
    assert((-9).alignUp!8 == -8);
}


/**
 * The argument pointer type.
 */
version (SysV_x64)
{
    alias va_list = core.internal.vararg.sysv_x64.va_list;
    public import core.internal.vararg.sysv_x64 : __va_list, __va_list_tag;
}
else version (AAPCS32)
{
    alias va_list = __va_list;

    // need std::__va_list for C++ mangling compatibility (AAPCS32 section 8.1.4)
    extern (C++, std) struct __va_list
    {
        void* __ap;
    }
}
else
{
    alias va_list = char*;
}


/**
 * Initialize ap.
 * parmn should be the last named parameter;
 * for DMD and non-Windows x86_64 targets, it should be __va_argsave.
 */
version (X86)
{
    void va_start(T)(out va_list ap, ref T parmn)
    {
        ap = cast(va_list) ((cast(void*) &parmn) + T.sizeof.alignUp);
    }
}
else
{
    void va_start(T)(out va_list ap, ref T parmn); // Compiler intrinsic
}


/**
 * Retrieve and return the next value that is of type T.
 */
T va_arg(T)(ref va_list ap)
{
    version (X86)
    {
        T arg = *cast(T*) ap;
        ap += T.sizeof.alignUp;
        return arg;
    }
    else version (Win64)
    {
        static if (T.sizeof > size_t.sizeof)
            T arg = **cast(T**) ap;
        else
            T arg = *cast(T*) ap;
        ap += size_t.sizeof;
        return arg;
    }
    else
    {
        T a;
        va_arg(ap, a);
        return a;
    }
}


/**
 * Retrieve and store in parmn the next value that is of type T.
 */
void va_arg(T)(ref va_list ap, ref T parmn)
{
    version (X86)
    {
        parmn = *cast(T*) ap;
        ap += T.sizeof.alignUp;
    }
    else version (Win64)
    {
        static if (T.sizeof > size_t.sizeof)
            parmn = **cast(T**) ap;
        else
            parmn = *cast(T*) ap;
        ap += size_t.sizeof;
    }
    else version (SysV_x64)
    {
        core.internal.vararg.sysv_x64.va_arg!T(ap, parmn);
    }
    else version (ARM)
    {
        version (AAPCS32)
        {
            // AAPCS32 section 6.5 B.5: type with alignment >= 8 is 8-byte
            // aligned instead of normal 4-byte alignment (APCS doesn't do
            // this).
            if (T.alignof >= 8)
                ap.__ap = ap.__ap.alignUp!8;
            auto p = ap.__ap;
            ap.__ap += T.sizeof.alignUp;
        }
        else
        {
            auto p = ap;
            ap += T.sizeof.alignUp;
        }
        parmn = *cast(T*) p;
    }
    else version (PPC_Any)
    {
        /*
         * The rules are described in the 64bit PowerPC ELF ABI Supplement 1.9,
         * available here:
         * http://refspecs.linuxfoundation.org/ELF/ppc64/PPC-elf64abi-1.9.html#PARAM-PASS
         */

        // Chapter 3.1.4 and 3.2.3: alignment may require the va_list pointer to first
        // be aligned before accessing a value
        if (T.alignof >= 8)
            ap = ap.alignUp!8;
        auto p = ap;
        version (BigEndian)
            static if (T.sizeof < size_t.sizeof)
                p += size_t.sizeof - T.sizeof;
        parmn = *cast(T*) p;
        ap += T.sizeof.alignUp;
    }
    else version (MIPS_Any)
    {
        auto p = ap;
        version (BigEndian)
            static if (T.sizeof < size_t.sizeof)
                p += size_t.sizeof - T.sizeof;
        parmn = *cast(T*) p;
        ap += T.sizeof.alignUp;
    }
    else
        static assert(0, "Unsupported platform");
}


/**
 * Retrieve and store through parmn the next value that is of TypeInfo ti.
 * Used when the static type is not known.
 */
void va_arg()(ref va_list ap, TypeInfo ti, void* parmn)
{
    version (X86)
    {
        // Wait until everyone updates to get TypeInfo.talign
        //auto talign = ti.talign;
        //auto p = cast(void*)(cast(size_t)ap + talign - 1) & ~(talign - 1);
        auto p = ap;
        auto tsize = ti.tsize;
        ap = cast(va_list) (p + tsize.alignUp);
        parmn[0..tsize] = p[0..tsize];
    }
    else version (Win64)
    {
        // Wait until everyone updates to get TypeInfo.talign
        //auto talign = ti.talign;
        //auto p = cast(void*)(cast(size_t)ap + talign - 1) & ~(talign - 1);
        auto p = ap;
        auto tsize = ti.tsize;
        ap = cast(va_list) (p + size_t.sizeof);
        void* q = (tsize > size_t.sizeof) ? *cast(void**) p : p;
        parmn[0..tsize] = q[0..tsize];
    }
    else version (SysV_x64)
    {
        core.internal.vararg.sysv_x64.va_arg(ap, ti, parmn);
    }
    else version (ARM)
    {
        const tsize = ti.tsize;
        version (AAPCS32)
        {
            if (ti.talign >= 8)
                ap.__ap = ap.__ap.alignUp!8;
            auto p = ap.__ap;
            ap.__ap += tsize.alignUp;
        }
        else
        {
            auto p = cast(void*) ap;
            ap += tsize.alignUp;
        }
        parmn[0..tsize] = p[0..tsize];
    }
    else version (PPC_Any)
    {
        if (ti.talign >= 8)
            ap = ap.alignUp!8;
        auto p = cast(void*) ap;
        const tsize = ti.tsize;
        version (BigEndian)
            if (tsize < size_t.sizeof)
                p += size_t.sizeof - tsize;
        ap += tsize.alignUp;
        parmn[0..tsize] = p[0..tsize];
    }
    else version (MIPS_Any)
    {
        auto p = cast(void*) ap;
        const tsize = ti.tsize;
        version (BigEndian)
            if (tsize < size_t.sizeof)
                p += size_t.sizeof - tsize;
        ap += tsize.alignUp;
        parmn[0..tsize] = p[0..tsize];
    }
    else
        static assert(0, "Unsupported platform");
}


/**
 * End use of ap.
 */
void va_end(va_list ap)
{
}


// va_copy
version (SysV_x64)
{
    import core.stdc.stdlib : alloca;

    ///
    void va_copy(out va_list dest, va_list src, void* storage = alloca(__va_list_tag.sizeof))
    {
        // Instead of copying the pointers, and aliasing the source va_list,
        // the default argument alloca will allocate storage in the caller's
        // stack frame.  This is still not correct (it should be allocated in
        // the place where the va_list variable is declared) but most of the
        // time the caller's stack frame _is_ the place where the va_list is
        // allocated, so in most cases this will now work.
        dest = cast(va_list) storage;
        *dest = *src;
    }
}
else
{
    ///
    void va_copy(out va_list dest, va_list src)
    {
        dest = src;
    }
}
