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
		uniform bool openfl_HasVertexColors;
	")
	@:glVertexBody("
		openfl_Alphav = openfl_Alpha;
		openfl_TextureCoordv = vec3(openfl_TextureCoord.x * openfl_TextureCoord.z, openfl_TextureCoord.y * openfl_TextureCoord.z, openfl_TextureCoord.z);

		if (openfl_HasColorTransform) {
			openfl_ColorMultiplierv = openfl_ColorMultiplier;
			openfl_ColorOffsetv = openfl_ColorOffset / 255.0;
		}

		if (openfl_HasVertexColors) {
			openfl_VertexColorv = openfl_VertexColor;
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
		varying vec3 openfl_TextureCoordv;
		varying vec4 openfl_VertexColorv;

		uniform bool openfl_HasColorTransform;
        uniform int openfl_FillType;
        uniform int openfl_Linear;
        uniform float openfl_FocalPointRatio;
		uniform bool openfl_HasVertexColors;
		uniform sampler2D bitmap;

		vec4 multiplyAlpha(vec4 c) {
			return vec4(c.rgb * c.a, c.a);
		}
		vec4 unmultiplyAlpha(vec4 c) {
			return vec4(c.rgb / c.a, c.a);
		}

		vec4 linearToSRGB(vec4 c)
		{
			vec3 rgb = c.rgb;
			rgb = mix(1.055 * pow(rgb, vec3(1.0 / 2.4)) - 0.055, rgb * 12.92, vec3(lessThanEqual(rgb, vec3(0.0031308))));
			return vec4(rgb, c.a);
		}

		vec4 sRGBToLinear(vec4 c)
		{
			vec3 rgb = c.rgb;
			rgb = mix(pow((rgb + 0.055) * (1.0 / 1.055), vec3(2.4)), rgb * (1.0/12.92), vec3(lessThanEqual(rgb, vec3(0.04045))));
			return vec4(rgb, c.a);
		}

		vec4 openfl_baseColor()
		{
			vec4 color;
			if (openfl_FillType == 0)
			{
				// Solid Color
				color = multiplyAlpha(openfl_VertexColorv.bgra);
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
					float B = 2.0 * dot(rayDir, focal);
					float C = dot(focal, focal) - 1.0;
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

			if (openfl_Linear == 1) {
				color = linearToSRGB(color);
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

class DefaultGraphicsShader extends GraphicsShader
{
	@:glFragmentBody("
		gl_FragColor = openfl_applyColorModifier(openfl_baseColor());
	")
	public function new(code:ByteArray = null)
	{
		super(code);
	}
}
