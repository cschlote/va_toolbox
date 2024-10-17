/** Simple class to write BMP (RIFF) files. Only a subset is supported.
 * Loading of BMP files might be added later.
 *
 * Authors: Carsten Schlote
 * Copyright: Carsten Schlote, 2024
 * License: GPL-3.0-only
 */
module va_toolbox.bmp_image;

import std.array;
import std.bitmanip;
import std.conv;
import std.file;
import std.math;
import std.outbuffer;
import std.stdint;
import std.stdio;

import va_toolbox.rgbpixel;
import va_toolbox.hexdumps;

/++ A simple hacked BMP image class. Image can be drawn to, and saved as a .bmp file  +/
class SimpleBMPImage {
    /** Create a RGB image (3 byte per pixel, no alpha)
     *
     * Params:
     *   w = number of pixels width
     *   h = number of pixel height
     */
    this(int w, int h) {
        pixels.length = w * h * 3;
        pixels[] = RGBPixel(0, 0, 0);
        width = w;
        height = h;
    }
    /** Create a RGB image (3 byte per pixel, no alpha)
     *
     * Params:
     *   w = number of pixels width
     *   h = number of pixel height
     *   pxdata = xy map of bool
     */
    this(int w, int h, const bool[] pxdata) {
        import std.algorithm : map;

        pixels = map!(a => a ? RGBPixel(255, 255, 255) : RGBPixel(0, 0, 0))(pxdata).array;
        width = w;
        height = h;
    }

    /** Import a iteration map using uint[]. Scale colores over range 0..max
     *
     * Params:
     *   w = number of pixels width
     *   h = number of pixel height
     *   iterMap = map with iterations.
     */
    this(int w, int h, const uint[] iterMap) {
        import std.algorithm : map, fold, max;

        uint maxIter = fold!max(iterMap);
        if (maxIter != 0)
            pixels = map!(a => mapIterToColor(a, maxIter))(iterMap).array;
        else {
            pixels.length = w * h * 3;
            pixels[] = RGBPixel(0, 0, 0);
        }
        width = w;
        height = h;
    }

    /** Import a iteration map using float[]. Scales 2 color rangeses over range -max..0..max
     *
     * Params:
     *   w = number of pixels width
     *   h = number of pixel height
     *   signedMap = map with iterations.
     */
    this(int w, int h, const float[] signedMap) {
        import std.algorithm : map, fold, max, min, mean;

        real maxPosVal = fold!max(signedMap);
        real maxNegVal = abs(fold!min(signedMap));
        real meanVal = mean(signedMap);

        RGBPixel mapFloat2RGB(float p) pure @safe nothrow {
            real scaleB = 0.0, scaleG = 0.0, scaleR = 0.0;
            if (p < 0) { // Negative values -> Blue shade
                scaleR = (-p) / maxNegVal;
            } else { // Positive values -> Green shade
                scaleG = p / maxPosVal;
            }
            auto meanDistants = abs(abs(meanVal) - abs(p));
            scaleB = 1.0 - meanDistants.min(1.0);

            return (RGBPixel(60, 60, 80) * scaleB)
                + (RGBPixel(10, 255, 10) * scaleG)
                + (RGBPixel(255, 10, 10) * scaleR);
        }

        pixels = map!mapFloat2RGB(signedMap).array;
        width = w;
        height = h;
    }

    /** Save Data as BMP
     *
     * Params:
     *   filename = Name of file to save to.
     */
    void saveBMP(string filename) {
        // Write 2 bytes, Little-Endian
        void out2(ref File f, int x) {
            f.rawWrite((cast(ushort*)(&x))[0 .. 1]);
        }
        // Write 4 bytes, LSB first, Little-Endian
        void out4(ref File f, uint x) {
            f.rawWrite((cast(uint*)(&x))[0 .. 1]);
        }

        File f = File(filename, "wb");
        f.rawWrite(['B', 'M']);
        auto sz = RGBPixel.sizeof * height * width;
        out4(f, cast(uint)(54 + sz)); // file size
        out4(f, 0); // reserved
        out4(f, 54); // offset to start of image (no palette)
        out4(f, 40); // info header size
        out4(f, width); // image size in pixels
        out4(f, height);
        out2(f, 1); // image planes
        out2(f, 24); // output bits per pixel
        out4(f, 0); // no compression
        out4(f, width * height * 3); // image size in bytes
        out4(f, 3000); // x pixels per meter
        out4(f, 3000); // y pixels per meter
        out4(f, 0); // colors
        out4(f, 0); // important colors
        f.rawWrite(pixels);
    }

    /** Encode Data as BMP image and return data */
    ubyte[] encodeAsBMPData() {
        // Write 2 bytes, Little-Endian
        void out2(ref OutBuffer b, ushort x) {
            b.write(x.nativeToLittleEndian);
        }
        // Write 4 bytes, LSB first, Little-Endian
        void out4(ref OutBuffer b, uint x) {
            b.write(x.nativeToLittleEndian);
        }

        auto bmpData = new OutBuffer();
        bmpData.write(['B', 'M']);
        auto sz = RGBPixel.sizeof * height * width;
        out4(bmpData, cast(uint)(54 + sz)); // file size
        out4(bmpData, 0); // reserved
        out4(bmpData, 54); // offset to start of image (no palette)
        out4(bmpData, 40); // info header size
        out4(bmpData, width); // image size in pixels
        out4(bmpData, height);
        out2(bmpData, 1); // image planes
        out2(bmpData, 24); // output bits per pixel
        out4(bmpData, 0); // no compression
        out4(bmpData, width * height * 3); // image size in bytes
        out4(bmpData, 3000); // x pixels per meter
        out4(bmpData, 3000); // y pixels per meter
        out4(bmpData, 0); // colors
        out4(bmpData, 0); // important colors

        bmpData.write(this.toBinary);

        return bmpData.toBytes(); //.data.to[0..bmpData.offset];
    }

    /** Return the pixelarray as ubyte array.
     *
     * Returns: An inout(ubyte[]) array of the pixeldata.
     */
    inout(ubyte[]) toBinary() const pure nothrow inout {
        ubyte[] a = cast(ubyte[]) pixels;
        auto sz = RGBPixel.sizeof * height * width;
        return a[0 .. sz];
    }

    /** Add colors (-255 to 255) to pixel at x,y (origin at lower left)
     *
     * Params:
     *   x = The X coordinate of the pixel (origin at lower left).
     *   y = The Y coordinate of the pixel (origin at lower left).
     *   red = The intensity of the red color component (0 to 255).
     *   green = The intensity of the green color component (0 to 255).
     *   blue = The intensity of the blue color component (0 to 255).
     */
    void modifyPixel(int x, int y, int red, int green, int blue) pure @nogc
    in {
        assert(x >= 0, "X must be >= 0");
        assert(x < width, "X must be < width");
        assert(y >= 0, "Y must be >= 0");
        assert(y < height, "Y must be < height");
    }
    do {
        const int idx = y * width + x;
        pixels[idx].blue = clipVal(pixels[idx].blue);
        pixels[idx].green = clipVal(pixels[idx].green);
        pixels[idx].red = clipVal(pixels[idx].red);
    }

    /**
     * Gets the color of the pixel at the specified position.
     *
     * The pixel is identified by its `x` and `y` coordinates, with the origin
     * (0, 0) located at the lower-left corner of the grid. The function returns
     * the RGB values as an `RGBPixel` struct.
     *
     * Params:
     *   x = The X coordinate of the pixel (origin at lower left).
     *   y = The Y coordinate of the pixel (origin at lower left).
     *
     * Returns:
     *   An `RGBPixel` struct containing the red, green, and blue color components.
     */
    RGBPixel getPixel(int x, int y) const {
        const int idx = (y * width + x) * 3;
        return pixels[idx];
    }

    /** Sets the color of a pixel at a specified position in a 2D grid.
     *
     * The pixel is identified by its `x` and `y` coordinates, with the origin
     * (0,0) located at the lower-left corner of the grid. The color of the pixel
     * is defined by the red, green, and blue components, each ranging from 0 to 255.
     *
     * Params:
     *   x = The X coordinate of the pixel (origin at lower left).
     *   y = The Y coordinate of the pixel (origin at lower left).
     *   red = The intensity of the red color component (0 to 255).
     *   green = The intensity of the green color component (0 to 255).
     *   blue = The intensity of the blue color component (0 to 255).
     */
    void setPixel(int x, int y, int red, int green, int blue) pure @nogc
    in {
        assert(x >= 0, "X must be >= 0");
        assert(x < width, "X must be < width");
        assert(y >= 0, "Y must be >= 0");
        assert(y < height, "Y must be < height");
    }
    do {
        const int idx = (y * width + x) * 3;
        pixels[idx].blue = clipVal(blue);
        pixels[idx].green = clipVal(green);
        pixels[idx].red = clipVal(red);
    }

    /// dito
    void setPixel(int x, int y, RGBPixel px) pure @nogc
    in {
        assert(x >= 0, "X must be >= 0");
        assert(x < width, "X must be < width");
        assert(y >= 0, "Y must be >= 0");
        assert(y < height, "Y must be < height");
    }
    do {
        const int idx = (y * width + x) * 3;
        pixels[idx] = px;
    }

private:
    ubyte clipVal(int c) pure @nogc nothrow {
        return cast(ubyte)(c > 255 ? 255 : c < 0 ? 0 : c);
    }

    RGBPixel[] pixels; /// width * height * blue-green-red (3 bytes)
    int width, height; /// Image size in pixels
}

///
@("class SimpleBMPImage")
unittest {
    {
        auto imgObj = new SimpleBMPImage(2, 2);
        auto bmpData = imgObj.encodeAsBMPData();
        // writeln(bmpData);
        static ubyte[] expectBmpData = [
            66, 77, 66, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 2, 0, 0, 0,
            2, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 12, 0, 0, 0, 184, 11, 0, 0, 184,
            11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ];
        if (bmpData != expectBmpData) {

            write(toRawDataDiff(bmpData, expectBmpData));
        }
        assert(bmpData == expectBmpData, "Should be reference data.");

        imgObj.modifyPixel(0, 0, 64, 64, 64);
        imgObj.modifyPixel(0, 0, -64, -64, -64);
        auto bmpData2 = imgObj.encodeAsBMPData();
        assert(bmpData2[] == expectBmpData, "Should be reference data.");

        auto px = imgObj.getPixel(1, 1);
        imgObj.setPixel(1, 1, 200, 150, 100);
        imgObj.setPixel(1, 1, px);
        bmpData2 = imgObj.encodeAsBMPData();
        assert(bmpData2[] == expectBmpData, "Should be reference data.");
    }
    {
        auto imgObj = new SimpleBMPImage(2, 2, new uint[4]);
        auto bmpData = imgObj.encodeAsBMPData();
        // writeln(bmpData);
        static ubyte[] expectBmpData = [
            66, 77, 66, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 2, 0, 0, 0,
            2, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 12, 0, 0, 0, 184, 11, 0, 0, 184,
            11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ];
        if (bmpData != expectBmpData) {

            write(toRawDataDiff(bmpData, expectBmpData));
        }
        assert(bmpData == expectBmpData, "Should be reference data.");
    }
    {
        const bool[] boolPmp = [true, false, false, true];
        auto imgObj = new SimpleBMPImage(2, 2, boolPmp);
        auto bmpData = imgObj.encodeAsBMPData();
        // writeln(bmpData);
        static ubyte[] expectBmpData = [
            66, 77, 66, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 2, 0, 0, 0,
            2, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 12, 0, 0, 0, 184, 11, 0, 0, 184,
            11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 0, 0, 0, 0, 0, 0, 255,
            255, 255
        ];
        assert(bmpData[] == expectBmpData, "Should be reference data.");
    }
    {
        const uint[] uintPmp = [10, 20, 30, 40];
        auto imgObj = new SimpleBMPImage(2, 2, uintPmp);
        auto bmpData = imgObj.encodeAsBMPData();
        // writeln(bmpData);
        static ubyte[] expectBmpData = [
            66, 77, 66, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 2, 0, 0, 0,
            2, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 12, 0, 0, 0, 184, 11, 0, 0, 184,
            11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 143, 239, 135, 237, 164, 38, 199, 51,
            4, 25, 25, 25
        ];
        assert(bmpData[] == expectBmpData, "Should be reference data.");
        imgObj.saveBMP("tests/tmp/u8pcm-2x2.bmp");

    }
    {
        const float[] uintPmp = [10, 20, 30, 40];
        auto imgObj = new SimpleBMPImage(2, 2, uintPmp);
        auto bmpData = imgObj.encodeAsBMPData();
        // writeln(bmpData);
        static ubyte[] expectBmpData = [
            66, 77, 66, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 2, 0, 0, 0,
            2, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 12, 0, 0, 0, 184, 11, 0, 0, 184,
            11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 63, 2, 5, 127, 5, 7, 191, 7, 10,
            255, 10
        ];
        assert(bmpData[] == expectBmpData, "Should be reference data.");
        imgObj.saveBMP("tests/tmp/float-2x2.bmp");
    }
}
