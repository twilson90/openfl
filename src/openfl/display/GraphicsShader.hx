package openfl.display;

import openfl.utils.ByteArray;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class GraphicsShader extends Shader
{
	@:glVertexHeader("
		attribute float openfl_Alpha;
		attribute vec4 openfl_ColorMultiplier;
		attribute vec4 openfl_ColorOffset;
		attribute vec4 openfl_Position;
		attribute vec3 openfl_TextureCoord;
		attribute vec4 openfl_VertexColor;

		varying float openfl_Alphav;
		varying vec4 openfl_ColorMultiplierv;
		varying vec4 openfl_ColorOffsetv;
		varying vec3 openfl_TextureCoordv;
		varying vec4 openfl_VertexColorv;

		uniform mat4 openfl_Matrix;
		uniform bool openfl_HasColorTransform;
	")
	@:glVertexBody("
		openfl_Alphav = openfl_Alpha;
		openfl_TextureCoordv = vec3(openfl_TextureCoord.x * openfl_TextureCoord.z, openfl_TextureCoord.y * openfl_TextureCoord.z, openfl_TextureCoord.z);

		if (openfl_HasColorTransform) {

			openfl_ColorMultiplierv = openfl_ColorMultiplier;
			openfl_ColorOffsetv = openfl_ColorOffset / 255.0;

		}
		openfl_VertexColorv = openfl_VertexColor;

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
		varying vec3 openfl_TextureCoordv;
		varying vec4 openfl_VertexColorv;

		uniform bool openfl_HasColorTransform;
        uniform int openfl_FillType;
        uniform float openfl_FocalPointRatio;
		uniform sampler2D bitmap;

		vec4 openfl_baseColor()
		{
			vec4 color;
			if (openfl_FillType == 0)
			{
				// Solid Color
				color = openfl_VertexColorv;
			}
			else if (openfl_FillType == 1)
			{
				// Bitmap
				vec2 uv = openfl_TextureCoordv.xy / openfl_TextureCoordv.z;
				color = texture2D (bitmap, uv);
			}
			else if (openfl_FillType == 2)
			{
				// Linear Gradient
				vec2 uv = openfl_TextureCoordv.xy / openfl_TextureCoordv.z;
				float t = (uv.x + 1.0) * 0.5;
				color = texture2D(bitmap, vec2(t, 0.5));
			}
			else if (openfl_FillType == 3)
			{
				// Radial Gradient
				vec2 uv = openfl_TextureCoordv.xy / openfl_TextureCoordv.z;
				vec2 focal = vec2(openfl_FocalPointRatio, 0.0);
				vec2 dir = uv - focal;
				float distFocal = length(dir);
				float t;
				if (distFocal == 0.0) {
					t = 0.0;
				} else {
					vec2 rayDir = dir / distFocal;
					vec2 fc = focal;
					float B = 2.0 * dot(rayDir, fc);
					float C = dot(fc, fc) - 1.0;
					float edgeDist = (-B + sqrt(B*B - 4.0*C)) * 0.5;
					t = distFocal / edgeDist;
				}
				color = texture2D(bitmap, vec2(t, 0.0));

			}
			else if (openfl_FillType == 4)
			{
				// Custom Fill
				color = vec4( 0.0, 0.0, 0.0, 1.0 );
			}

			return color;

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
	@:glFragmentBody("
		gl_FragColor = openfl_applyColorModifier(openfl_baseColor());
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
