package openfl.display._internal;

#if !flash
import openfl.display.BitmapData;
import openfl.display.Shader;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class Context3DMaskShader extends Shader
{
	public static var opaqueBitmapData:BitmapData = new BitmapData(1, 1, false, 0);

	@:glFragmentSource("varying vec2 openfl_TextureCoordv;

		void main(void) {

			gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);

		}")
	@:glVertexSource("attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;
		varying vec2 openfl_TextureCoordv;

		uniform mat4 openfl_Matrix;

		void main(void) {

			openfl_TextureCoordv = openfl_TextureCoord;

			gl_Position = openfl_Matrix * openfl_Position;

		}")
	public function new()
	{
		super();
	}
}
#end
