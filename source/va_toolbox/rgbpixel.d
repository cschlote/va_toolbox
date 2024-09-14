/** This module defines a 3 byte GBR pixel.
 *
 * Authors: Carsten Schlote
 * Copyright: Carsten Schlote, 2024
 * License: GPL-3.0-only
 */
module va_toolbox.rgbpixel;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.math;
import std.range;
import std.stdio;

/// All code is using RGB pixel, provide some struct for it
align(1) struct RGBPixel {
    // ubyte red, green, blue;
    ubyte blue, green, red;

    this(ubyte r, ubyte g, ubyte b) pure @safe nothrow {
        red = r;
        green = g;
        blue = b;
    }

    string toString() const {
        return format("RGBPixel(%3d, %3d, %3d)", red, green, blue);
    }

    /// Addition of two RGBPixels
    RGBPixel opBinary(string op : "+")(RGBPixel other) const pure @safe {
        return RGBPixel(
            saturateAdd(this.red, other.red),
            saturateAdd(this.green, other.green),
            saturateAdd(this.blue, other.blue)
        );
    }

    /// Subtraction of two RGBPixels
    RGBPixel opBinary(string op : "-")(RGBPixel other) const pure @safe {
        return RGBPixel(
            saturateSub(this.red, other.red),
            saturateSub(this.green, other.green),
            saturateSub(this.blue, other.blue)
        );
    }

    /// Multiplication by a scalar
    RGBPixel opBinary(string op : "*")(float scalar) const pure @safe {
        return RGBPixel(
            cast(ubyte)(this.red * scalar).min(255),
            cast(ubyte)(this.green * scalar).min(255),
            cast(ubyte)(this.blue * scalar).min(255)
        );
    }

    /// Division by a scalar
    RGBPixel opBinary(string op : "/")(float scalar) const pure @safe {
        return RGBPixel(
            cast(ubyte)(this.red / scalar).min(255),
            cast(ubyte)(this.green / scalar).min(255),
            cast(ubyte)(this.blue / scalar).min(255)
        );
    }

    /// Addition with assignment
    RGBPixel opOpAssign(string op : "+")(RGBPixel other) pure @safe {
        this.red = saturateAdd(this.red, other.red);
        this.green = saturateAdd(this.green, other.green);
        this.blue = saturateAdd(this.blue, other.blue);
        return this;
    }

    /// Subtraction with assignment
    RGBPixel opOpAssign(string op : "-")(RGBPixel other) pure @safe {
        this.red = saturateSub(this.red, other.red);
        this.green = saturateSub(this.green, other.green);
        this.blue = saturateSub(this.blue, other.blue);
        return this;
    }

    /// Scalar multiplication with assignment
    RGBPixel opOpAssign(string op : "*")(float scalar) pure @safe {
        this.red = cast(ubyte)(this.red * scalar).min(255);
        this.green = cast(ubyte)(this.green * scalar).min(255);
        this.blue = cast(ubyte)(this.blue * scalar).min(255);
        return this;
    }

    /// Scalar division with assignment
    RGBPixel opOpAssign(string op : "/")(float scalar) pure @safe {
        this.red = cast(ubyte)(this.red / scalar).min(255);
        this.green = cast(ubyte)(this.green / scalar).min(255);
        this.blue = cast(ubyte)(this.blue / scalar).min(255);
        return this;
    }

    /// Negation (inverts the colors)
    RGBPixel opUnary(string op : "-")() const pure @safe {
        return RGBPixel(255 - this.red, 255 - this.green, 255 - this.blue);
    }

    // Method to blend two RGBPixel values
    RGBPixel blend(RGBPixel other) const pure @safe nothrow {
        ubyte newRed = (cast(uint) red + other.red) / 2;
        ubyte newGreen = (cast(uint) green + other.green) / 2;
        ubyte newBlue = (cast(uint) blue + other.blue) / 2;
        return RGBPixel(newRed, newGreen, newBlue);
    }

    // Method to blend multiple RGBPixel values
    RGBPixel blend(RGBPixel[] others) const pure @safe nothrow {
        uint sumRed = red;
        uint sumGreen = green;
        uint sumBlue = blue;

        foreach (pixel; others) {
            sumRed += pixel.red;
            sumGreen += pixel.green;
            sumBlue += pixel.blue;
        }

        auto count = 1 + others.length;
        ubyte newRed = cast(ubyte)((sumRed / count).min(255));
        ubyte newGreen = cast(ubyte)((sumGreen / count).min(255));
        ubyte newBlue = cast(ubyte)((sumBlue / count).min(255));

        return RGBPixel(newRed, newGreen, newBlue);
    }

    // Weighted blend method
    RGBPixel weightedBlend(RGBPixel other, float weight) const pure @safe nothrow {
        float w1 = 1.0f - weight;
        float w2 = weight;
        ubyte newRed = cast(ubyte)((w1 * red + w2 * other.red).min(255));
        ubyte newGreen = cast(ubyte)((w1 * green + w2 * other.green).min(255));
        ubyte newBlue = cast(ubyte)((w1 * blue + w2 * other.blue).min(255));
        return RGBPixel(newRed, newGreen, newBlue);
    }

private:
    /// Helper function for saturated addition
    static ubyte saturateAdd(ubyte a, ubyte b) pure @safe nothrow {
        return cast(ubyte)(min(a + b, 255));
    }

    /// Helper function for saturated subtraction
    static ubyte saturateSub(ubyte a, ubyte b) pure @safe nothrow {
        return cast(ubyte)(max(a - b, 0));
    }
}

@("struct RGBPixel: special alignments")
unittest {
    assert(RGBPixel.sizeof == 3, "Expected 3 byte pixels.");

    RGBPixel[4] staticRGBPackedPmp = [
        RGBPixel(1, 2, 3), RGBPixel(1, 2, 3), RGBPixel(1, 2, 3), RGBPixel(1, 2, 3)
    ];
    assert(staticRGBPackedPmp.length == 4, "Expected 4 entries");
    assert(staticRGBPackedPmp.sizeof == 12, "Expected 4 entries a 3 byte == 12");

    RGBPixel[] dynRGBPackedPmp = [
        RGBPixel(1, 2, 3), RGBPixel(1, 2, 3), RGBPixel(1, 2, 3), RGBPixel(1, 2, 3)
    ];
    assert(dynRGBPackedPmp.length == 4, "Expected 4 entries");
    // assert(dynRGBPackedPmp.sizeof == 12, "Expected 4 entries a 3 byte == 12");

    // writeln(rgbPackedPmp, " ", rgbPackedPmp.length);

    void* addrH = cast(void*)&staticRGBPackedPmp[2];
    void* addrL = cast(void*)&staticRGBPackedPmp[0];
    auto diff = addrH - addrL;
    assert(diff == 6, text("Expected 6, got ", diff));
}

@("struct RGBPixel: operator overloads")
unittest {
    // Test addition
    auto pixel1 = RGBPixel(100, 150, 200);
    auto pixel2 = RGBPixel(100, 150, 100);
    auto resultAdd = pixel1 + pixel2;
    assert(resultAdd == RGBPixel(200, 255, 255), "Addition failed with saturation.");

    // Test subtraction
    auto pixel3 = RGBPixel(50, 100, 150);
    auto pixel4 = RGBPixel(100, 100, 100);
    auto resultSub = pixel3 - pixel4;
    assert(resultSub == RGBPixel(0, 0, 50), "Subtraction failed with saturation.");

    // Test scalar multiplication
    auto pixel5 = RGBPixel(50, 100, 200);
    auto resultMul = pixel5 * 2.0f;
    assert(resultMul == RGBPixel(100, 200, 255), "Multiplication failed with saturation.");

    // Test scalar division
    auto pixel6 = RGBPixel(100, 200, 255);
    auto resultDiv = pixel6 / 2.0f;
    assert(resultDiv == RGBPixel(50, 100, 127), "Division failed.");

    // Test addition with assignment
    auto pixel7 = RGBPixel(150, 150, 150);
    pixel7 += RGBPixel(100, 100, 100);
    assert(pixel7 == RGBPixel(250, 250, 250), "Addition with assignment failed with saturation.");

    // Test subtraction with assignment
    auto pixel8 = RGBPixel(200, 200, 200);
    pixel8 -= RGBPixel(100, 150, 250);
    assert(pixel8 == RGBPixel(100, 50, 0), "Subtraction with assignment failed with saturation.");

    // Test scalar multiplication with assignment
    auto pixel9 = RGBPixel(100, 100, 100);
    pixel9 *= 3.0f;
    assert(pixel9 == RGBPixel(255, 255, 255), "Scalar multiplication with assignment failed with saturation.");

    // Test scalar division with assignment
    auto pixel10 = RGBPixel(100, 100, 100);
    pixel10 /= 2.0f;
    assert(pixel10 == RGBPixel(50, 50, 50), "Scalar division with assignment failed.");

    // Test negation
    auto pixel11 = RGBPixel(50, 100, 150);
    auto resultNeg = -pixel11;
    assert(resultNeg == RGBPixel(205, 155, 105), "Negation failed.");

    // Check saturation on addition
    auto pixel12 = RGBPixel(255, 255, 255);
    auto resultAddSaturation = pixel12 + RGBPixel(10, 10, 10);
    assert(resultAddSaturation == RGBPixel(255, 255, 255), "Saturation failed on addition.");

    // Check saturation on subtraction
    auto pixel13 = RGBPixel(0, 0, 0);
    auto resultSubSaturation = pixel13 - RGBPixel(10, 10, 10);
    assert(resultSubSaturation == RGBPixel(0, 0, 0), "Saturation failed on subtraction.");

    // Check extreme values for multiplication
    auto pixel14 = RGBPixel(128, 128, 128);
    auto resultMulExtreme = pixel14 * 10.0f;
    assert(resultMulExtreme == RGBPixel(255, 255, 255), "Saturation failed on extreme multiplication.");

    // Check extreme values for division
    auto pixel15 = RGBPixel(128, 128, 128);
    auto resultDivExtreme = pixel15 / 0.1f;
    assert(resultDivExtreme == RGBPixel(255, 255, 255), "Saturation failed on extreme division.");

    // Test simple blend
    auto pixel16 = RGBPixel(100, 150, 200);
    auto pixel17 = RGBPixel(200, 50, 100);
    auto resultBlend = pixel16.blend(pixel17);
    assert(resultBlend == RGBPixel(150, 100, 150), "Simple blend failed.");

    // Test blend with multiple pixels
    auto pixel18 = RGBPixel(100, 150, 200);
    auto resultMultiBlend = pixel18.blend([
        RGBPixel(200, 50, 100), RGBPixel(150, 100, 50)
    ]);
    assert(resultMultiBlend == RGBPixel(150, 100, 116), "Multi-pixel blend failed.");

    // Test weighted blend
    auto pixel19 = RGBPixel(50, 100, 150);
    auto pixel20 = RGBPixel(200, 50, 100);
    auto resultWeightedBlend = pixel19.weightedBlend(pixel20, 0.25f);
    assert(resultWeightedBlend == RGBPixel(87, 87, 137), "Weighted blend failed.");

    // Test weighted blend with edge cases
    auto pixel21 = RGBPixel(255, 255, 255);
    auto pixel22 = RGBPixel(0, 0, 0);
    auto resultWeightedBlendEdge = pixel21.weightedBlend(pixel22, 0.75f);
    assert(resultWeightedBlendEdge == RGBPixel(63, 63, 63), "Weighted blend with edge case failed.");

}

/++ Map iter/maxIter to a RGBPixel
 +
 + Params:
 +   iter = actual iterations
 +   maxIter = maximum/cutoff iteration
 + Returns:
 +   RGBPixel
 +/
RGBPixel mapIterToColor(string MODE = "CM2")(uint iter, uint maxIter) pure @safe nothrow
in (iter <= maxIter)
in (maxIter != 0) {

    if (iter & 1)
        iter = maxIter - iter;

    real pgl = (0.0 + iter) / maxIter;

    ubyte r = 0, g = 0, b = 0;
    void mkVals(real scaleR, real scaleG, real scaleB) {
        r = cast(ubyte)(25.0 + (scaleR * pgl));
        g = cast(ubyte)(25.0 + (scaleG * pgl));
        b = cast(ubyte)(25.0 + (scaleB * pgl));
    }

    static if (MODE == "SW") {
        mkVals(230, 230, 230);
    } else static if (MODE == "CM1") {
        if (pgl >= 0.70) {
            mkVals(230, 115, 80);
        } else if (pgl >= 0.50) {
            mkVals(155, 230, 115);
        } else if (pgl >= 0.30) {
            mkVals(120, 160, 160);
        } else {
            mkVals(230, 230, 230);
        }
    } else static if (MODE == "CM2") {
        if (iter == maxIter) {
            mkVals(0, 0, 0); // Black for points in the set
        } else {
            real gamma = pow(iter / cast(real) maxIter, 0.5); // Use a non-linear scaling (gamma correction)
            // Use a smoother gradient transition between colors
            b = cast(ubyte)(9 * (1 - gamma) * pow(gamma, 3) * 255);
            g = cast(ubyte)(15 * pow((1 - gamma), 2) * pow(gamma, 2) * 255);
            r = cast(ubyte)(8.5 * pow((1 - gamma), 3) * gamma * 255);
        }
    } else
        static assert(false, "Unknown mapping.");

    auto pixel = RGBPixel(r, g, b);

    return pixel;
}

@("mapIterToColor()")
unittest {
    RGBPixel[11] expectSW = [
        RGBPixel(25, 25, 25),
        RGBPixel(234, 234, 234),
        RGBPixel(66, 66, 66),
        RGBPixel(192, 192, 192),
        RGBPixel(108, 108, 108),
        RGBPixel(150, 150, 150),
        RGBPixel(150, 150, 150),
        RGBPixel(108, 108, 108),
        RGBPixel(192, 192, 192),
        RGBPixel(66, 66, 66),
        RGBPixel(234, 234, 234)
    ];
    foreach (int k; 0 .. 11) {
        auto a = mapIterToColor!"SW"(k, 11);
        // writefln("%2d: %s", k, a);
        assert(expectSW[k] == a, "Color mismatch.");
    }

    // Why are the tables different?
    RGBPixel[11] expectCM1_DMD = [
        RGBPixel(25, 25, 25),
        RGBPixel(232, 128, 97),
        RGBPixel(71, 71, 71),
        RGBPixel(186, 105, 81), // DMD
        RGBPixel(73, 89, 89),
        RGBPixel(102, 140, 82),
        RGBPixel(118, 163, 94), // DMD
        RGBPixel(61, 73, 73), // DMD
        RGBPixel(209, 117, 89),
        RGBPixel(48, 48, 48),
        RGBPixel(255, 140, 105)
    ];
    RGBPixel[11] expectCM1 = [
        RGBPixel(25, 25, 25),
        RGBPixel(232, 128, 97),
        RGBPixel(71, 71, 71),
        RGBPixel(133, 185, 105), // LDC2, GDC
        RGBPixel(73, 89, 89),
        RGBPixel(102, 140, 82),
        RGBPixel(117, 162, 93), // LDC2, GDC
        RGBPixel(93, 93, 93), // LDC2, GDC
        RGBPixel(209, 117, 89),
        RGBPixel(48, 48, 48),
        RGBPixel(255, 140, 105)
    ];
    version (DigitalMars) {
        writeln("CAUTION: DMD has different table!");
    }
    foreach (int k; 0 .. expectCM1.length) {
        auto a = mapIterToColor!"CM1"(k, 10);
        version (DigitalMars) {
            // writefln(" %s,", a);
            // writefln("%2d: %s", k, a);
            if (a != expectCM1[k])
                writefln("%2d: test:%10s expectLDC: %10s", k, a, expectCM1[k]);
            assert(expectCM1_DMD[k] == a, "Color mismatch on DMD table.");
        } else {
            assert(expectCM1[k] == a, "Color mismatch.");
        }
    }

    RGBPixel[11] expectCM2 = [
        RGBPixel(0, 0, 0),
        RGBPixel(0, 9, 100),
        RGBPixel(163, 233, 113),
        RGBPixel(7, 71, 219),
        RGBPixel(68, 206, 213),
        RGBPixel(38, 164, 237),
        RGBPixel(19, 116, 240),
        RGBPixel(109, 234, 170),
        RGBPixel(2, 34, 173),
        RGBPixel(219, 178, 49),
        RGBPixel(25, 25, 25)
    ];

    foreach (int k; 0 .. expectCM2.length) {
        auto a = mapIterToColor!"CM2"(k, 10);
        // writeln(format("%2d: %s", k, a));
        assert(expectCM2[k] == a, "Color mismatch.");
    }
}
