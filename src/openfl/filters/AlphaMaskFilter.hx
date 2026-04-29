package openfl.filters;

#if !flash
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectRenderer;
import openfl.display.IBitmapDrawable;
import openfl.display.Shader;
import openfl.geom.Point;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.display.OpenGLRenderer;
#if lime
import lime._internal.graphics.ImageDataUtil;
#end

@:access(openfl.display.Bitmap)
@:access(openfl.display.BitmapData)
@:access(openfl.display.IBitmapDrawable)
@:access(openfl.display.DisplayObject)
@:access(openfl.geom.Rectangle)
@:access(openfl.geom.Matrix)
@:access(openfl.display.DisplayObjectRenderer)
@:access(openfl.display.OpenGLRenderer)
@:final class AlphaMaskFilter extends BitmapFilter
{
	@:noCompletion static private var __transparentBitmapData:BitmapData = new BitmapData(1, 1, true, 0x00000000);

	@:noCompletion private var __shader:AlphaMaskShader = new AlphaMaskShader();

	public var mask(get, set):IBitmapDrawable;

	@:noCompletion private var __mask:IBitmapDrawable;

	public function new(mask:IBitmapDrawable = null)
	{
		super();

		this.mask = mask;

		__numShaderPasses = 1;
		__needSecondBitmapData = false;
		// __preserveObject = true;
		__renderDirty = true;
	}

	public override function clone():BitmapFilter
	{
		return new AlphaMaskFilter(__mask);
	}

	@:noCompletion private override function __applyFilter(bitmapData:BitmapData, sourceBitmapData:BitmapData, sourceRect:Rectangle, destPoint:Point):BitmapData
	{
		// ImageDataUtil
		// TODO: Implement CPU version later if needed
		return sourceBitmapData;
	}

	@:noCompletion private override function __initShader(renderer:DisplayObjectRenderer, pass:Int, sourceBitmapData:BitmapData):Shader
	{
		#if !macro
		var glRenderer:OpenGLRenderer = cast renderer;
		var maskBD:BitmapData;
		var target:DisplayObject = null;
		if (Std.isOfType(__mask, BitmapData))
		{
			__shader.uMask.input = cast __mask;
		}
		else
		{
			var mask:DisplayObject = cast __mask;
			mask.__isMask = false;
			mask.__update(true, false);
			mask.__isMask = true;
			glRenderer.__updateCacheBitmap(mask, false);
			mask.__update(true, false);

			var target = mask.__maskTarget;

			var maskBitmap = Std.isOfType(mask.__cacheBitmap, Bitmap) && mask.__cacheBitmap == null ? cast mask : mask.__cacheBitmap;
			var targetBitmap = Std.isOfType(target.__cacheBitmap, Bitmap)
				&& target.__cacheBitmap == null ? cast target : target.__cacheBitmap;

			if (maskBitmap != null && targetBitmap != null)
			{
				var matrix = Matrix.__pool.get();
				computeMaskUVMatrix(targetBitmap, maskBitmap, matrix);
				__shader.uMask.input = maskBitmap.__bitmapData;
				// __shader.uMask.filter = maskBitmap.smoothing ? ANISOTROPIC16X : NEAREST;
				__shader.uMask.wrap = CLAMP;
				__shader.uMaskMatrix.value = matrixToGLArray(matrix);
				__shader.uMaskSize.value = [maskBitmap.__bitmapData.width, maskBitmap.__bitmapData.height];

				Matrix.__pool.release(matrix);
			}
			else
			{
				__shader.uMask.input = __transparentBitmapData;
				__shader.uMaskMatrix.value = matrixToGLArray(Matrix.__identity);
				__shader.uMaskSize.value = [1, 1];
			}
		}
		#end

		return __shader;
	}

	function computeMaskUVMatrix(target:Bitmap, mask:Bitmap, out:Matrix):Void
	{
		var maskBD = mask.__bitmapData;
		var targetBD = target.__bitmapData;

		out.identity();

		// UV -> target local pixels
		out.scale(targetBD.width, targetBD.height);

		// target local -> world
		out.concat(target.__renderTransform);

		// world -> mask local
		var invMask = Matrix.__pool.get();
		invMask.copyFrom(mask.__renderTransform);
		invMask.invert();
		out.concat(invMask);
		Matrix.__pool.release(invMask);

		out.scale(1 / maskBD.width, 1 / maskBD.height);
	}

	function matrixToGLArray(m:Matrix):Array<Float>
	{
		var arr = [m.a, m.b, 0.0, 0.0, m.c, m.d, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, m.tx, m.ty, 0.0, 1.0];
		return arr;
	}

	// Getter / Setter
	@:noCompletion private function get_mask():IBitmapDrawable
	{
		return __mask;
	}

	@:noCompletion private function set_mask(value:IBitmapDrawable):IBitmapDrawable
	{
		if (value != __mask)
		{
			__mask = value;
			__renderDirty = true;
		}
		return value;
	}
}

private class AlphaMaskShader extends BitmapFilterShader
{
	@:glVertexSource("
		attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;
		uniform vec2 openfl_TextureSize;
		uniform mat4 openfl_Matrix;
		uniform mat4 uMaskMatrix;

		varying vec2 vTextureCoord;
		varying vec2 vMaskUV;

		void main(void)
		{
			gl_Position = openfl_Matrix * openfl_Position;
			vTextureCoord = openfl_TextureCoord;
			vMaskUV = (uMaskMatrix * vec4(openfl_TextureCoord, 0.0, 1.0)).xy;
		}
	")
	@:glFragmentSource("
		uniform sampler2D openfl_Texture;
		uniform vec2 openfl_TextureSize;
		uniform sampler2D uMask;
		uniform vec2 uMaskSize;
		varying vec2 vTextureCoord;
		varying vec2 vMaskUV;

		void main(void)
		{
			vec4 color = texture2D(openfl_Texture, vTextureCoord);

			vec2 maskUV = vMaskUV;
			float inside =
				step(0.0, maskUV.x) *
				step(0.0, maskUV.y) *
				step(maskUV.x, 1.0) *
				step(maskUV.y, 1.0);
			float maskAlpha = texture2D(uMask, maskUV).a * inside;

			// premultiplied, need to multiply all components
			color *= maskAlpha;

			gl_FragColor = color;
		}
	")
	public function new()
	{
		super();
	}
}
#end
