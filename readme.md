# Engine Starter

My collection of examples demonstrating fundamental game engine building blocks. Adding more examples to collection as I learn.

Based on [Odin SDL3 Template](https://github.com/epsilonbsp/odin_sdl3_template) - check that repo if you need help setting up Odin or SDL3.

## Setup

Build SDL:

```
./build.bat build-sdl
```

## Usage

Run the current example:

```
./build.bat run
```

To switch examples, edit [source/main.odin](source/main.odin) and change the import to point to a different example package:

```odin
// Change import to run different examples
import example "01_io/01_window"
```

## References

```
OpenGL Tutorials:
    https://learnopengl.com/
    https://www.opengl-tutorial.org/
    https://webgl2fundamentals.org/

Assets:
    https://ambientcg.com/
    https://freestylized.com/
    https://polyhaven.com/

Tools:
    https://github.com/BoundingBoxSoftware/Materialize
```
