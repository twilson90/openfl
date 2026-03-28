package openfl.display._internal;

import openfl.geom.Matrix;
import openfl.display.BitmapData;
import openfl.utils.ObjectPool;
#if lime
import lime.math.ARGB;
#end

@:access(openfl.display._internal.Gradient)
class Fill
{
	public var color:Null<Int>;
	public var bitmap:BitmapData;
	public var bitmapSmooth:Bool;
	public var bitmapRepeat:Bool;
	public var matrix:Matrix;
	public var gradient:Gradient;
	public var shaderBuffer:ShaderBuffer;
	public var hasFill(get, never):Bool;
	public var hasTransparency(get, never):Bool;

	private static var __pool:ObjectPool<Fill> = new ObjectPool<Fill>(() -> new Fill(), (c) -> c.identity());

	public function new() {}

	public inline function get_hasFill():Bool
	{
		return gradient != null || color != null || bitmap != null || shaderBuffer != null;
	}

	public function get_hasTransparency():Bool
	{
		if (gradient != null)
		{
			for (a in gradient.alphas)
			{
				if (a < 1.0)
				{
					return true;
				}
			}
		}

		if (bitmap != null)
		{
			return bitmap.transparent;
		}

		if (color != null)
		{
			var argb:ARGB = color;
			var a = argb.a;
			return a < 255;
		}

		return false;
	}

	public function identity()
	{
		color = null;
		bitmap = null;
		bitmapSmooth = false;
		bitmapRepeat = false;
		shaderBuffer = null;
		matrix = null;
		if (gradient != null)
		{
			Gradient.__pool.release(gradient);
			gradient = null;
		}
	}

	public function copyFrom(other:Fill)
	{
		color = other.color;
		bitmap = other.bitmap;
		bitmapSmooth = other.bitmapSmooth;
		bitmapRepeat = other.bitmapRepeat;
		shaderBuffer = other.shaderBuffer;
		matrix = other.matrix;
		if (gradient != null && other.gradient == null)
		{
			Gradient.__pool.release(gradient);
		}
		else if (gradient == null && other.gradient != null)
		{
			gradient = Gradient.__pool.get();
			gradient.copyFrom(other.gradient);
		}
		else if (gradient != null && other.gradient != null)
		{
			gradient.copyFrom(other.gradient);
		}
	}

	public function equals(other:Fill)
	{
		return color == other.color
			&& matrix.equals(other.matrix)
			&& bitmap == other.bitmap
			&& bitmapSmooth == other.bitmapSmooth
			&& bitmapRepeat == other.bitmapRepeat
			&& shaderBuffer == other.shaderBuffer
			&& Gradient.__equals(gradient, other.gradient);
	}
}
