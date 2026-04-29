package openfl.display;

import openfl.utils.ByteArray;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class DisplayObjectShader extends Shader
{
	@:glVertexHeader("
		attribute float openfl_Alpha;
		attribute vec4 openfl_ColorMultiplier;
		attribute vec4 openfl_ColorOffset;
		attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;

		varying float openfl_Alphav;
		varying vec4 openfl_ColorMultiplierv;
		varying vec4 openfl_ColorOffsetv;
		varying vec2 openfl_TextureCoordv;

		uniform mat4 openfl_Matrix;
		uniform bool openfl_HasColorTransform;
	")
	@:glVertexBody("
		openfl_Alphav = openfl_Alpha;
		openfl_TextureCoordv = openfl_TextureCoord;

		if (openfl_HasColorTransform) {

			openfl_ColorMultiplierv = openfl_ColorMultiplier;
			openfl_ColorOffsetv = openfl_ColorOffset / 255.0;

		}

		gl_Position = openfl_Matrix * openfl_Position;
	")
	@:glVertexSource("
		#pragma header

		void main(void) {

			#pragma body

		}
	")
	@:glFragmentHeader("
		varying float openfl_Alphav;
		varying vec4 openfl_ColorMultiplierv;
		varying vec4 openfl_ColorOffsetv;
		varying vec2 openfl_TextureCoordv;

		uniform mat4 openfl_Matrix;
		uniform bool openfl_HasColorTransform;
		uniform sampler2D openfl_Texture;

		vec4 openfl_baseColor()
		{
			return texture2D(openfl_Texture, openfl_TextureCoordv);
		}

		vec4 openfl_applyColorModifier(vec4 color)
		{
			if (color.a == 0.0) {

				return vec4 (0.0, 0.0, 0.0, 0.0);

			} else if (openfl_HasColorTransform) {

				color = vec4 (color.rgb / color.a, color.a);

				mat4 colorMultiplier = mat4 (0);
				colorMultiplier[0][0] = openfl_ColorMultiplierv.x;
				colorMultiplier[1][1] = openfl_ColorMultiplierv.y;
				colorMultiplier[2][2] = openfl_ColorMultiplierv.z;
				colorMultiplier[3][3] = 1.0;

				color = clamp (openfl_ColorOffsetv + (color * colorMultiplier), 0.0, 1.0);

				if (color.a > 0.0) {

					return vec4 (color.rgb * color.a * openfl_Alphav, color.a * openfl_Alphav);

				} else {

					return vec4 (0.0, 0.0, 0.0, 0.0);

				}

			}

			return color * openfl_Alphav;
		}
	")
	#if emscripten
	@:glFragmentSource("
		#pragma header

		void main(void) {

			#pragma body

			gl_FragColor = gl_FragColor.bgra;

		}
	")
	#else
	@:glFragmentSource("
		#pragma header

		void main(void) {

			#pragma body

		}
	")
	#end
	public function new(code:ByteArray = null)
	{
		super(code);
	}
}

class DefaultDisplayObjectShader extends DisplayObjectShader
{
	@:glFragmentBody("
		gl_FragColor = openfl_applyColorModifier(openfl_baseColor());
	")
	public function new(code:ByteArray = null)
	{
		super(code);
	}
}
