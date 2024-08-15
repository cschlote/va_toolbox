/**
 * This module provides functionality to generate and write audio data in
 * the WAV file format. It supports various integer and floating-point types
 * by converting them to a suitable WAV format.
 *
 * The WAV format is a simple, uncompressed audio format used for storing
 * waveform data. This module allows for writing WAV files from raw audio data
 * arrays, supporting a range of data types including `ubyte`, `short`, `int`,
 * `float`, and `double`.
 */
module va_toolbox.wav_audio;

import std.algorithm;
import std.array;
import std.stdio;
import std.conv;
import std.range;
import std.exception;
import std.string;
import std.format;
import std.math;
import std.stdint;
import core.time;

import va_toolbox.hexdumps;


/**
 * Enums for WAV file format constants.
 */
enum WAVChunkIDs {
    RIFF = 0x46464952, // "RIFF" in little-endian
    WAVE = 0x45564157, // "WAVE" in little-endian
    FMT = 0x20746d66, // "fmt " in little-endian
    DATA = 0x61746164 // "data" in little-endian
}

enum AudioFormats {
    PCM = 0x0001, // Linear Pulse Code Modulation
    MS_ADPCM = 0x0002,
    IEEE_FLOAT = 0x0003,
    IBM_CVSD = 0x0005,
    ALAW = 0x0006,
    MULAW = 0x0007,
    OKI_ADPCM = 0x0010,
    DVI_IMA_ADPCM = 0x0011,
    MEDIASPACE_ADPCM = 0x0012,
    SIERRA_ADPCM = 0x0013,
    G723_ADPCM = 0x0014,
    DIGISTD = 0x0015,
    DIGIFIX = 0x0016,
    DIALOGIC_OKI_ADPCM = 0x0017,
    YAMAHA_ADPCM = 0x0020,
    SONARC = 0x0021,
    DSPGROUP_TRUESPEECH = 0x0022,
    ECHOSC1 = 0x0023,
    AUDIOFILE_AF36 = 0x0024,
    APTX = 0x0025,
    AUDIOFILE_AF10 = 0x0026,
    DOLBY_AC2 = 0x0030,
    GSM610 = 0x0031,
    ANTEX_ADPCME = 0x0033,
    CONTROL_RES_VQLPC1 = 0x0034,
    CONTROL_RES_VQLPC2 = 0x0035,
    DIGIADPCM = 0x0036,
    CONTROL_RES_CR10 = 0x0037,
    NMS_VBXADPCM = 0x0038,
    CS_IMAADPCM = 0x0039,
    G721_ADPCM = 0x0040,
    MPEG1_Layer_I_II = 0x0050,
    MPEG1_Layer_III = 0x0055,
    Xbox_ADPCM = 0x0069,
    CREATIVE_ADPCM = 0x0200,
    CREATIVE_FASTSPEECH8 = 0x0202,
    CREATIVE_FASTSPEECH10 = 0x0203,
    FM_TOWNS_SND = 0x0300,
    OLIGSM = 0x1000,
    OLIADPCM = 0x1001,
    OLICELP = 0x1002,
    OLISBC = 0x1003,
    OLIOPR = 0x1004
}

/**
 * Converts audio data of supported types to WAV file format as a `ubyte[]` buffer.
 *
 * This function constructs a WAV file header and appends audio data to create
 * a valid WAV file format byte array. It supports the following data types:
 * - `ubyte` (8-bit unsigned)
 * - `byte` (8-bit signed) -> mapped to unsigned 8 bit
 * - `short` (16-bit signed)
 * - `int` (32-bit signed)
 * - `float` (32-bit float)
 *
 * Params:
 *   T = The type of audio data (e.g., `ubyte`, `short`, `int`, `float`).
 *   audioData = The raw audio data to be written to the WAV file.
 *   sampleRate = The sampling rate of the audio data.
 *   numChannels = The number of audio channels (1 for mono, 2 for stereo).
 *   bitsPerSample = The number of bits per sample (e.g., 8, 16, 24, 32).
 *
 * Returns:
 *   A `ubyte[]` containing the WAV file formatted data.
 */
ubyte[] toWAVFile(T)(const T[] audioData, uint sampleRate, ushort numChannels)
    if (is(T == ubyte) || is(T == byte) || is(T == short) || is(T == int) || is(T == float)) {

    ushort bitsPerSample;
    ubyte[] pcmData;

    // Convert audio data to PCM format if necessary
    static if (is(T == ubyte)) {
        // Convert 8-bit audio data directly
        pcmData = cast(ubyte[]) audioData;
        bitsPerSample = 8;
    } else static if (is(T == byte)) {
        // Shift the signed variant up.
        pcmData = audioData.map!(a => cast(ubyte)(a + 128)).array;
        bitsPerSample = 8;
    } else static if (is(T == short)) {
        foreach (item; audioData) {
            auto bytes = cast(ubyte[])((&item)[0 .. 1]);
            pcmData ~= bytes;
        }
        bitsPerSample = 16;
    } else static if (is(T == int)) {
        foreach (item; audioData) {
            auto bytes = cast(ubyte[])((&item)[0 .. 1]);
            pcmData ~= bytes;
        }
        bitsPerSample = 32;
    } else static if (is(T == float)) {
        foreach (item; audioData) {
            auto bytes = cast(ubyte[])((&item)[0 .. 1]);
            pcmData ~= bytes;
        }
        bitsPerSample = 32;
    } else {
        static assert(0, "Unsupported source data type.");
    }
    enforce(bitsPerSample == 8 || bitsPerSample == 16 || bitsPerSample == 32,
        "Unsupported bitsPerSample value.");
    assert(pcmData.length, "No data to process.");

    import std.outbuffer : OutBuffer;

    auto buf = new OutBuffer();

    // https://de.wikipedia.org/wiki/RIFF_WAVE

    // Write the initial RIFF header (we'll correct the sizes later)
    buf.write("RIFF");
    size_t fileSizePos = buf.offset; // Remember position to overwrite later
    buf.write(uint(0)); // Placeholder for file size
    buf.write("WAVE");

    // Write the format chunk
    buf.write("fmt ");
    buf.write((16).to!uint); // Size of the format chunk (16 for PCM)
    buf.write((is(T == float) ? AudioFormats.IEEE_FLOAT : AudioFormats.PCM).to!ushort); // Audio format (1 for PCM)
    buf.write(numChannels);
    buf.write(sampleRate);
    buf.write((sampleRate * numChannels * bitsPerSample / 8).to!uint); // bytes per seconds
    buf.write((numChannels * (bitsPerSample + 7) / 8).to!ushort); // block align
    buf.write(bitsPerSample);

    // Write the 'fact' chunk only for non-PCM formats (i.e., 32-bit float)
    if (is(T == float)) {

        buf.write("fact");
        buf.write(uint(uint.sizeof)); // Size of the 'fact' chunk
        buf.write(audioData.length.to!uint); // Number of samples
    }
    // Write the 'fact' chunk only for non-PCM formats (i.e., 32-bit float)
    if (is(T == float)) {
        import std.datetime : Clock, SysTime, DateTime, UTC;

        // Get the current time in UTC
        SysTime currentTime = Clock.currTime(UTC());
        // Calculate the number of seconds since the Unix epoch
        uint secondsSinceEpoch = currentTime.toUnixTime().to!uint;

        // Write PEAK chunk (https://web.archive.org/web/20081201144551/http://music.calarts.edu/~tre/PeakChunk.html)
        buf.write("PEAK");
        buf.write(uint(8 + (numChannels * 8))); // Size of PEAK chunk (16 bytes total)

        buf.write(uint(1)); // version (4 bytes)
        buf.write(uint(secondsSinceEpoch)); // Placeholder for timestamp seconds since 1.1.1970 (4 bytes)

        foreach (chan; 0 .. numChannels) {
            float peakValue = 0.0f;
            uint peakPos = 0;
            foreach (idx, ref val; audioData) {
                if (abs(val) > peakValue) {
                    peakPos = idx.to!uint;
                    peakValue = abs(val);
                }
            }
            buf.write(peakValue); // Peak value (8 bytes)  value, position
            buf.write(peakPos);
        }
    }
    // Write the data chunk header
    buf.write("data");
    buf.write(pcmData.length.to!uint); // Placeholder for data size

    // Write the PCM data
    buf.write(pcmData);

    uint fileSize = cast(uint)(buf.offset - 8);
    buf.data[fileSizePos .. fileSizePos + uint.sizeof] = (
        cast(ubyte*)&fileSize)[0 .. uint
            .sizeof];

    return buf.toBytes();
}

/**
 * Writes an audio data array to a WAV file on disk.
 *
 * This function generates a WAV file format byte array using `toWAVFile()` and
 * writes it to a specified file path.
 *
 * Params:
 *   filePath = The path where the WAV file should be written.
 *   audioData = The raw audio data to be written.
 *   sampleRate = The sampling rate of the audio data.
 *   numChannels = The number of audio channels (1 for mono, 2 for stereo).
 *   bitsPerSample = The number of bits per sample (e.g., 8, 16, 24, 32).
 */
void writeWAVFile(T)(string filePath, const T[] audioData, uint sampleRate, ushort numChannels)
    if (is(T == ubyte) || is(T == byte) || is(T == short) || is(T == int) || is(T == float)) {
    auto wavData = toWAVFile(audioData, sampleRate, numChannels);
    File(filePath, "wb").rawWrite(wavData);
}

/**
 * Generates a sinusoidal waveform of a specified frequency and duration.
 *
 * This function creates an array of samples representing a sine wave with a given
 * frequency (`hertz`), duration (`dur`), and sample rate (`samplerate`). The type of
 * the samples is specified by the template parameter `T`. The function supports various
 * numeric types (`float`, `double`, `int`, etc.).
 *
 * The generated sine wave can be used as audio data for further processing or writing
 * to an audio file.
 *
 * Params:
 *   T = The data type of the samples (e.g., `float`, `double`, `int`).
 *   hertz = The frequency of the sine wave in Hertz (Hz).
 *   intensity = 0.0 - 1.0 to scale the sin.
 *   dur = The duration of the sine wave.
 *   samplerate = The number of samples per second (sampling rate).
 *
 * Returns:
 *   An array of type `T` containing the generated sine wave samples.
 *
 * Examples:
 * ---
 * auto wave = generateSinus!float(440.0, dur!"seconds"(2), 44_100);
 * ---
 */
private auto generateSinus(T)(float hertz, float intensity, Duration dur, int samplerate)
    if (is(T == byte) || is(T == short) || is(T == int) || is(T == long) || is(T == float) || is(
        T == double) || is(T == real)) {
    auto hnsecs = dur.total!"hnsecs";
    real fDur = (0.0 + hnsecs) / 10 ^^ 7; // Convert Duration to real [s] with hns prec
    real totalSamplesF = fDur * samplerate; // Caution: There might be precision issues here... so...
    auto totalSamples = (totalSamplesF.round).to!size_t; // Total number of samples at given rate, rounded
    auto data = new T[totalSamples]; // Get memory for it.

    auto samplesPerCycle = samplerate / hertz; // Number of samples per full cycle
    auto angleStep = (2.0 * PI) / samplesPerCycle; // Angle step per sample

    foreach (index, ref sample; data) {
        real rawval = (sin(angleStep * index)) * intensity;
        static if (is(T == float) || is(T == double) || is(T == real))
            sample = rawval.to!T; // Calculate the sine value and store it
        else
            sample = (rawval * T.max).round.to!T; // Calculate the sine value and store it
    }
    return data;
}

@("generateSinus()")
unittest {
    import std.math : abs;
    import std.datetime : seconds;

    enum testIntensity = 0.8;
    enum testFreq = 441.0; // This does evenly divide the samplerate, eases the test

    // Test 1: Check the generated sinus wave with float type
    auto samples = generateSinus!float(testFreq, testIntensity, 1.seconds, 44_100);

    // Verify the number of samples
    assert(samples.length == 44_100);

    // Verify the first sample (should be 0 since sin(0) = 0)
    assert(samples[0] == 0.0f);

    // Test 2: Check if the wave values are within expected range [-1.0, 1.0]
    foreach (sample; samples) {
        assert(abs(sample) <= 1.0f);
    }

    // Test 3: Verify that the generated wave is a valid sine wave by checking periodicity
    // The sine wave should repeat every period (44_100 / 440) samples
    int period = (44_100 / testFreq).round.to!int;
    auto diffVal = abs(samples[period] - samples[0]);
    assert(diffVal < 0.0001f);

    // Test 4: Check the generated sinus wave with int type (expects normalized samples)
    auto intSamples = generateSinus!int(testFreq, testIntensity, 1.seconds, 44_100);

    // Verify the number of samples
    assert(intSamples.length == 44_100);

    // Verify the first sample (should be 0)
    assert(intSamples[0] == 0);

    // Test 5: Check if the integer wave values are within expected range [-1, 1]
    foreach (sample; intSamples) {
        assert(abs(sample) <= int.max);
    }
}

/**
 * Unit tests for the WAV audio module.
 */
@("writeWAVFile()")
unittest {
    import std.array : array;
    import std.stdio : writefln;
    import std.file : remove;

    /// RIFF (little-endian) data, WAVE audio, IEEE Float, mono 44100 Hz
    enum string reffile_32f = "tests/wav_audio_ref_32f.wav";
    ///  RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 44100 Hz
    enum string reffile_s16pcm = "tests/wav_audio_ref_s16pcm.wav";
    ///  RIFF (little-endian) data, WAVE audio, Microsoft PCM, 32 bit, mono 44100 Hz
    enum string reffile_s32pcm = "tests/wav_audio_ref_s32pcm.wav";
    ///   RIFF (little-endian) data, WAVE audio, Microsoft PCM, 8 bit, mono 44100 Hz
    enum string reffile_u8pcm = "tests/wav_audio_ref_u8pcm.wav";

    enum string testfile_32f = "tests/tmp/wav_audio_32f.wav";
    enum string testfile_s16pcm = "tests/tmp/wav_audio_s16pcm.wav";
    enum string testfile_s32pcm = "tests/tmp/wav_audio_s32pcm.wav";
    enum string testfile_u8pcm = "tests/tmp/wav_audio_u8pcm.wav";

    enum testFreq = 441; // This does evenly divide the samplerate, eases the test
    enum sampleRate = 44_100;
    enum Duration cycleDur = dur!"hnsecs"(10 ^^ 7 / testFreq);

    // pragma(msg, cycleDur);
    // writeln(cycleDur);

    ubyte[] readFileAsUbyte(string filePath) {
        import std.file : read;

        return cast(ubyte[]) read(filePath);
    }

    void dumpDiff(ubyte[] testWAV, ubyte[] expectedWAV) {
        if (testWAV != expectedWAV) {
            write(toRawDataDiff(testWAV, expectedWAV, "TEST:\n", "EXPECT:\n"));
        }
    }

    // writeln("START OF byte DUMP:");
    {
        byte[] audioData = generateSinus!byte(testFreq.to!float, 1.0, cycleDur, sampleRate);
        assert(audioData.length == 100, "One cycle of 441Hz at 44100kHz is 100 bytes.");
        writeWAVFile(testfile_u8pcm, audioData, sampleRate, 1);
        ubyte[] testWAV = readFileAsUbyte(testfile_u8pcm);
        ubyte[] expectedWAV = readFileAsUbyte(reffile_u8pcm);
        dumpDiff(testWAV, expectedWAV);
        assert(testWAV == expectedWAV, "The written WAV file does not match the expected data.");
    }
    // writeln("START OF short DUMP:");
    {
        short[] audioData = generateSinus!short(testFreq.to!float, 1.0, cycleDur, sampleRate);
        assert(audioData.length == 100, "One cycle of 441Hz at 44100kHz is 100 bytes.");
        writeWAVFile(testfile_s16pcm, audioData, sampleRate, 1);
        ubyte[] testWAV = readFileAsUbyte(testfile_s16pcm);
        ubyte[] expectedWAV = readFileAsUbyte(reffile_s16pcm);
        dumpDiff(testWAV, expectedWAV);
        assert(testWAV == expectedWAV, "The written WAV file does not match the expected data.");
    }
    // writeln("START OF int DUMP:");
    {
        int[] audioData = generateSinus!int(testFreq.to!float, 1.0, cycleDur, sampleRate);
        assert(audioData.length == 100, "One cycle of 441Hz at 44100kHz is 100 bytes.");
        writeWAVFile(testfile_s32pcm, audioData, sampleRate, 1);
        ubyte[] testWAV = readFileAsUbyte(testfile_s32pcm);
        ubyte[] expectedWAV = readFileAsUbyte(reffile_s32pcm);
        dumpDiff(testWAV, expectedWAV);
        assert(testWAV == expectedWAV, "The written WAV file does not match the expected data.");
    }
    // writeln("START OF float DUMP:");
    {
        float[] audioData = generateSinus!float(testFreq.to!float, 1.0, cycleDur, sampleRate);
        assert(audioData.length == 100, "One cycle of 441Hz at 44100kHz is 100 bytes.");
        writeWAVFile(testfile_32f, audioData, sampleRate, 1);
        ubyte[] testWAV = readFileAsUbyte(testfile_32f);
        ubyte[] expectedWAV = readFileAsUbyte(reffile_32f);
        testWAV[0x3c .. 0x40] = 0; // This is seconds since epoche - it is dynamically updated by tools, so we set it to 0 for compare.
        expectedWAV[0x3c .. 0x40] = 0;
        dumpDiff(testWAV, expectedWAV);
        assert(testWAV == expectedWAV, "The written WAV file does not match the expected data.");
    }
}
