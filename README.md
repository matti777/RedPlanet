# Red Planet

A small demo application for Apple VisionOS that demostrates geometry generated in code as well as the use of custom materials using [ShaderGraphMaterial](TBD).

Developed in the spirit of the old PC demo "mars".

# Terrain generation

The terrain is generated using the classic [Diamond-Square](https://en.wikipedia.org/wiki/Diamond-square_algorithm) algorithm.

Gaussian blur (using two-pass application of 1D convolution kernels) is applied to the height map data to reduce spike artifacts.

# TerrainMaterial explained

TBA

For a nice Shader Graph primer, see [this WWDC video](https://developer.apple.com/videos/play/wwdc2023/10202/).

NOTE: there seems to be a weird issue with these shader materials created in a an USDx file; their textures *will not work* in your app unless you create a dummy object in the USDx file (in Reality Composer Pro) *and bind your material* to it! (Situation Xcode 15.3 Beta). You don't need to use the dummy object, it just needs to be there in the scene file and have your texture bound to it and then you can use your texture for whatever.

## Disabling default scene lighting

To disable the default scene lighting, an Image Based Lighting component is used. The terrain material handles its own lighting based on the light source position.

# License

This software is available under the [MIT License](LICENSE.md).

# Acknowledgements & attritions

Space skybox texture is a free download from [hdri-skies.com](https://hdri-skies.com/).

App icon by Toni Itkonen.

Textures are free downloads from [manytextures.com](https://www.manytextures.com/). Licensed under [Creative Commons Attribution 4.0 International License](http://creativecommons.org/licenses/by/4.0/).

With respect to the author's copyrights.
