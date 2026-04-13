package openfl.display._internal;

#if !flash
import openfl.display.BitmapData;
import openfl.display.Shader;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class Context3DAlphaMaskShader extends Shader
{
	public static var opaqueBitmapData:BitmapData = new BitmapData(1, 1, false, 0);

	@:glVertexSource("
		attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;
		varying vec2 openfl_TextureCoordv;
		varying vec2 openfl_MaskCoordv;

		uniform mat4 openfl_Matrix;
		uniform mat4 openfl_MaskMatrix;
		uniform sampler2D openfl_Mask;

		void main(void) {

			openfl_TextureCoordv = openfl_TextureCoord;
			openfl_MaskCoordv = (openfl_MaskMatrix * openfl_Position).xy;
			gl_Position = openfl_Matrix * openfl_Position;

		}
	")
	@:glFragmentSource("
		varying vec2 openfl_TextureCoordv;
		varying vec2 openfl_MaskCoordv;

		uniform sampler2D openfl_Texture;

		void main(void) {

			vec4 color = texture2D (openfl_Texture, openfl_TextureCoordv);
			float maskAlpha = texture2D(openfl_Mask, openfl_MaskCoordv).a;

			gl_FragColor = vec4(color.rgb, color.a * maskAlpha);

		}
	")
	public function new()
	{
		super();
	}
}
#end
