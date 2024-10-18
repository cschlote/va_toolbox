# VA Toolbox

A collection of sources for debugging, data analysis.

Latest API documentation: http://dlang.pages.vahanus.net/va-toolbox/

## Background

Over the years you write a lot of code. And most amazingly, we write a lot of code over and over again.

On the next level you start to copy files around. This is dedious, error-prone.

So it is time to move all this little helpers to some common place, and publish them together as a dub
module. So instead of rewriting, copying and modifying your code, just add it as dependency.

### Audio

Some game here. I hacked some code related to audio, and check if the code can execute in CTFE mode.

## How to compile?

You can use:

```bash
dub build
dub test -- -v
```

Visual Studio Code (VSC) can be used, because it has a cool D plugin and supports source level debugging.

## Contents of this toolbox

[x] = well matured, good coverage
[+] = needs more examples
[ ] = open

- [x] Image: Simple code to write BMP files
- [+] Audio: Precompute audio waveforms or data during compilation to reduce runtime processing and ensure consistency.
- [+] Compile-Time Regular Expression Engine: Match patterns against strings at compile time, useful for validating or transforming strings.
- [+] Compile-Time Code Generation: Generate specialized functions or classes based on compile-time parameters, such as serialization code. -> Hashed Enums
- [ ] Compile-Time Parsing and Code Generation from Text Files: Parse custom configuration or markup languages at compile time to generate corresponding code or data structures.
