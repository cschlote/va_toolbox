/**
 * This modules provides code to declare enumeration with hashed values instead of usual
 * numeration starting from 0 to n .
 */
module va_toolbox.hashed_enum;

import std.range.primitives;
public import std.system : Endian;
import std.traits;

private string myToString(ulong n) pure @safe
{
    import core.internal.string : UnsignedStringBuf, unsignedToTempString;

    UnsignedStringBuf buf;
    auto s = unsignedToTempString(n, buf);
    // pure allows implicit cast to string
    return s ~ (n > uint.max ? "UL" : "U");
}

@("myToString()")
@safe pure unittest
{
    assert(myToString(5) == "5U");
    assert(myToString(uint.max) == "4294967295U");
    assert(myToString(uint.max + 1UL) == "4294967296UL");
}

/** Simple hash function for enumeration name
 */
static size_t toHash(string name) @nogc pure nothrow
{
    size_t hash = 3557;
    foreach (i; 0 .. name.length)
    {
        hash *= 3571;
        hash += (cast(byte*) name.ptr)[i];
    }
    return hash;
}

@("toHash()")
@nogc pure nothrow unittest
{
    assert(toHash("Alpha") == 17_959_635_420_765_137_357UL);
    assert(toHash("Beta") == 578_422_959_926_732_917UL);
    assert(toHash("Gamma") == 17_960_610_607_111_970_654UL);
}

/** Create the enumerations member list with hashed member name */
template createEnumLines(args...)
{
    //pragma(msg, "Build hased entry for " ~ args[0]);
    enum argHash = args[0].toHash;
    //pragma(msg, argHash);
    static if (args.length > 1)
        enum createEnumLines = args[0] ~ " = " ~ argHash.myToString ~ ", " ~ createEnumLines!(
                args[1 .. $]);
    else
        enum createEnumLines = args[0] ~ " = " ~ argHash.myToString;
}

/** Create the enumerations member list with hashed member name */
template createNames(int n)
{
    //pragma(msg, "Build hased entry for " ~ args[0]);
    //pragma(msg, argHash);

    static if (n > 1)
        enum createNames = "\"STRING" ~ n.myToString ~ "\", " ~ createNames!(n-1);
    else
        enum createNames = "\"STRING" ~ n.myToString ~ "\"";
}

/** Create a named enumeration with hash value for each enumeration member calculated from member name
*
* This mixin template creates an enumeration with a given name and a list of enum members. The hash value
* of the member name is assigned to the enumeration member.
*
* Params:
*   enumName - name of enumeration
*   args - List of enumeration members
*/
mixin template HashedEnum(string enumName, args...)
{
    // pragma(msg, "Build hased entry for " ~ args);
    enum enumLines = createEnumLines!(args);
    // pragma(msg, enumLines);
    mixin("enum " ~ enumName ~ " { " ~ createEnumLines!(args) ~ " }");
}

@("check created hashes")
unittest
{
    import std.stdio;
    import std.conv;

    mixin HashedEnum!("MyEnum", "Alpha", "Beta", "Gamma");

    // writeln("UNITTEST(", __FUNCTION__,"): Values of 'MyEnum' enumeration ");
    // writeln("Alpha = ", MyEnum.Alpha.to!size_t);
    // writeln("Beta = ", MyEnum.Beta.to!size_t);
    // writeln("Gamma = ", MyEnum.Gamma.to!size_t);
    assert(MyEnum.Alpha == 17_959_635_420_765_137_357UL);
    assert(MyEnum.Beta == 578_422_959_926_732_917UL);
    assert(MyEnum.Gamma == 17_960_610_607_111_970_654UL);
}

@("create manually") unittest
{
    import std.stdio;
    import std.conv;
    import std.traits;

    enum myEnumName = "StateEngine";
    mixin HashedEnum!(myEnumName, "State1", "State2", "State3", "LastState");

    // writeln("UNITTEST(", __FUNCTION__,"): Values of 'StateEngine' enumeration ");
    auto vals = [EnumMembers!StateEngine];
    foreach (val; vals)
    {
        auto hashValue = toHash(val.to!string);
        // writefln("%20s = %016x, %20s.tohash() = %16x", val, val.to!size_t, val, hashValue);
        assert(val == hashValue);
    }
}

@("create 499 enum members") unittest
{
    import std.stdio;
    import std.conv;
    import std.traits;

    enum myEnumName = "StringEnum";
    enum myEnumMembers = createNames!499;
    // pragma(msg, myEnumMembers);
    mixin( "mixin HashedEnum!(myEnumName," ~ myEnumMembers ~ ");" );

    // writeln("UNITTEST(", __FUNCTION__,"): Values of 'StringEnum' enumeration ");
    auto vals = [EnumMembers!StringEnum];
    foreach (val; vals)
    {
        auto hashValue = toHash(val.to!string);
        // writefln("%20s = %016x, %20s.tohash() = %16x", val, val.to!size_t, val, hashValue);
        assert(val == hashValue);
    }
}
