module va_toolbox.hexdumps;

import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.format;
import std.math;
import std.range;
import std.stdio;
import std.string;

/**
 * Converts the given array of `ubyte` to a hex dump string.
 * After 16 bytes of hexadecimal numbers, the same bytes are shown as characters,
 * or '.' if not printable. Similar to the `hexdump` CLI command.
 *
 * Params:
 *     data = The array of `ubyte` to be dumped as hex.
 *     offset = Instead of 0 use some other start value for the dump
 *     prefix = Prefix to output
 *
 * Returns:
 *     A string representing the hex dump of the input data.
 *
 * Example:
 *     ubyte[] exampleData = cast(ubyte[])"This is an example of a hex dump function in D.\n";
 *     string dump = toPrettyHexDump(exampleData);
 *     writeln(dump);
 */
string toPrettyHexDump(T)(const T[] edata, size_t offset = 0, string prefix = "") {
    auto result = appender!string();

    const ubyte[] data = cast(ubyte[]) edata;
    enum chunksize = 16;
    foreach (idxLine; iota(0, data.length, chunksize)) {
        result.put(format("%s%08x: ", prefix, offset + idxLine));
        // Hexadecimal representation
        foreach (idxCol; 0 .. chunksize) {
            if (idxLine + idxCol < data.length) {
                result.put(format("%02x ", data[idxLine + idxCol]));
            } else {
                result.put("   ");
            }
        }

        // ASCII representation
        result.put(" '");
        foreach (idxCol; 0 .. chunksize) {
            if (idxLine + idxCol < data.length) {
                char c = cast(char) data[idxLine + idxCol];
                if (isPrintable(c)) {
                    result.put(c);
                } else {
                    result.put('.');
                }
            }
        }
        result.put("'\n");
    }
    return result.data;
}

@("toPrettyHexDump()")
 /// Unittests to verify the `toPrettyHexDump` function.
unittest {
    ubyte[] testData1 = cast(ubyte[])("Hello, World!" ~ "Hello, World!");
    string expectedOutput1 =
        "00000000: 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 21 48 65 6c  'Hello, World!Hel'\n" ~
        "00000010: 6c 6f 2c 20 57 6f 72 6c 64 21                    'lo, World!'\n";

    string result1 = toPrettyHexDump(testData1);
    assert(result1 == expectedOutput1, format("Expected:\n%s\nGot:\n%s", expectedOutput1, result1));

    ubyte[] testData2 = cast(ubyte[]) "This is an example of a hex dump function in D.\n";
    string result2 = toPrettyHexDump(testData2);

    // Check that the output starts correctly.
    string expectedStart =
        "00000000: 54 68 69 73 20 69 73 20 61 6e 20 65 78 61 6d 70  'This is an examp'\n" ~
        "00000010: 6c 65 20 6f 66 20 61 20 68 65 78 20 64 75 6d 70  'le of a hex dump'\n" ~
        "00000020: 20 66 75 6e 63 74 69 6f 6e 20 69 6e 20 44 2e 0a  ' function in D..'\n";
    assert(result2.startsWith(expectedStart), format("Expected start:\n%s\nGot:\n%s", expectedStart, result2));
}

/++ Print the difference between two array
 +
 + Params:
 +   ra = dynamic Array A
 +   rb = dynamic Array B
 + Returns:
 +/
string toDiffDump(T)(const void[] ra, const void[] rb, string adesc = "<:", string bdesc = ">:") {
    enum chunksize = 16;
    auto r_combined = lockstep( (cast(ubyte[])ra).chunks(chunksize), (cast(ubyte[])rb).chunks(chunksize));

    auto result = appender!string;
    size_t nextPrintIdx = 0;
    size_t idx = 0;
    foreach (a, b; r_combined) {
        if (a != b) {
            if (nextPrintIdx != idx)
                result.put("...\n");
            nextPrintIdx = idx + chunksize;
            result.put(toPrettyHexDump(a, idx, adesc));
            result.put(toPrettyHexDump(b, idx, bdesc));
        }
        idx += chunksize;
    }
    return result.data;
}

@("toDiffDump()")
unittest {
    ubyte[] a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    ubyte[] b = [1, 2, 3, 4, 5, 6, 7, 15, 9, 10, 11, 12];
    auto result1 = toDiffDump!(ubyte[])(a, b, "A:", "B:");
    const string expect1 = "A:00000000: 01 02 03 04 05 06 07 08 09 0a 0b 0c              '............'\n" ~
        "B:00000000: 01 02 03 04 05 06 07 0f 09 0a 0b 0c              '............'\n";
    assert(result1 == expect1);

    ubyte[1024] aa = 0, bb = 0;
    aa[aa.length / 2] = 0x55;
    bb[bb.length / 4] = 0xAA;
    auto result2 = toDiffDump!(ubyte[])(aa, bb);
    const string expect2 =
        "...\n" ~
        "<:00000100: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  '................'\n" ~
        ">:00000100: aa 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  '................'\n" ~
        "...\n" ~
        "<:00000200: 55 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  'U...............'\n" ~
        ">:00000200: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  '................'\n";
    assert(result2 == expect2);

    auto result3 = toDiffDump!(ubyte[])(aa, aa);
    const string expect3 =
        "";
    // writeln(result3);
    assert(result3 == expect3, "We expect an empty string here.");
}

/**
 * Compares two arrays of raw byte data and produces a detailed comparison report.
 *
 * The function generates a hex dump for each byte array, followed by a diff of the two arrays,
 * highlighting the differences. This is useful for debugging and verifying binary data, such as
 * audio files, image files, or any other binary data format.
 *
 * Params:
 *   va = The first byte array to compare.
 *   vb = The second byte array to compare.
 *   namea = A label for the first byte array (default: "DATA A:").
 *   nameb = A label for the second byte array (default: "DATA B:").
 *   header = A custom header for the comparison output (default: "START OF DIFF").
 *
 * Returns:
 *   A string containing the detailed comparison report, including the hex dumps and the diff.
 */
string toRawDataDiff(const void[] va, const void[] vb, string namea = "DATA A:\n", string nameb = "DATA B:\n", string header = "START OF DIFF\n") {

    const ubyte[] a  = cast(ubyte[])va;
    const ubyte[] b  = cast(ubyte[])vb;

    Appender!string output;

    output.put(header);
    output.put(namea);
    output.put(toPrettyHexDump(a));
    output.put(nameb);
    output.put(toPrettyHexDump(b));
    auto diffText = toDiffDump!(ubyte[])(a, b);
    if (!diffText.empty) {
        output.put("DIFF:\n");
        output.put(toDiffDump!(ubyte[])(a, b));
    }
    output.put("END OF DIFF\n");

    return output.data;
}

unittest {
    import std.array : array;
    import std.conv : to;

    // Test case: Comparing two identical byte arrays
    ubyte[] dataA = [0x01, 0x02, 0x03, 0x04];
    ubyte[] dataB = [0x01, 0x02, 0x03, 0x04];
    string result = toRawDataDiff(dataA, dataB);

    assert(result.length > 0, "Result should not be empty.");
    assert(result.canFind("START OF DIFF"), "Header should be present.");
    assert(result.canFind("END OF DIFF"), "Footer should be present.");
    assert(!result.canFind("DIFF:"), "There should be no differences in identical data.");

    // Test case: Comparing two different byte arrays
    ubyte[] dataC = [0x01, 0x02, 0x03, 0x05];
    result = toRawDataDiff(dataA, dataC);

    assert(result.canFind("DIFF:"), "Differences should be reported.");
    assert(result.canFind("04") && result.canFind("05"), "The differing bytes should be shown.");
}
