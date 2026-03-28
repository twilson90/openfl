package openfl.display._internal;

import openfl.utils.ByteArray;
import openfl.utils.ObjectPool;
import openfl.utils.ArrayUtil;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Matrix;

@:access(openfl.geom.Matrix)
@:access(openfl.geom.Rectangle)
class Gradient
{
	public var colors:Array<Int> = [];
	public var alphas:Array<Float> = [];
	public var ratios:Array<Int> = [];
	public var matrix:Matrix = new Matrix();
	public var type:GradientType;
	public var interpolationMethod:InterpolationMethod;
	public var spreadMethod:SpreadMethod;
	public var focalPointRatio:Float;

	private static var bitmapCache:Map<String, BitmapData> = new Map<String, BitmapData>();
	private static var bitmapCacheKeys:Array<String> = [];

	private static var __pool:ObjectPool<Gradient> = new ObjectPool<Gradient>(() -> new Gradient(), (c) -> c.identity());

	private static var MAX_GRADIENTS = 128;

	public function new(colors:Array<Int> = null, alphas:Array<Float> = null, ratios:Array<Int> = null, matrix:Matrix = null, type:GradientType = LINEAR,
			interpolationMethod:InterpolationMethod = RGB, spreadMethod:SpreadMethod = PAD, focalPointRatio:Float = 0)
	{
		setTo(colors, alphas, ratios, matrix, type, interpolationMethod, spreadMethod, focalPointRatio);
	}

	public function setTo(colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>, matrix:Matrix, type:GradientType,
			interpolationMethod:InterpolationMethod, spreadMethod:SpreadMethod, focalPointRatio:Float)
	{
		if (colors == null)
		{
			ArrayUtil.clear(this.colors);
		}
		else
		{
			ArrayUtil.copyFrom(this.colors, colors);
		}
		if (alphas == null)
		{
			ArrayUtil.clear(this.alphas);
		}
		else
		{
			ArrayUtil.copyFrom(this.alphas, alphas);
		}
		if (ratios == null)
		{
			ArrayUtil.clear(this.ratios);
		}
		else
		{
			ArrayUtil.copyFrom(this.ratios, ratios);
		}

		this.matrix.copyFrom(matrix != null ? matrix : Matrix.__identity);
		this.type = type;
		this.interpolationMethod = interpolationMethod;
		this.spreadMethod = spreadMethod;
		this.focalPointRatio = focalPointRatio;
	}

	public function identity()
	{
		ArrayUtil.clear(colors);
		ArrayUtil.clear(alphas);
		ArrayUtil.clear(ratios);
		matrix.identity();
		type = null;
		interpolationMethod = null;
		spreadMethod = null;
		focalPointRatio = 0;
	}

	public function getBitmap():BitmapData
	{
		var hash = getHash();
		if (bitmapCache.exists(hash)) return bitmapCache.get(hash);

		var bmd = new BitmapData(256, 1, true, 0);
		var pixels = new ByteArray();
		var index = 0;
		var lastIndex = ratios.length - 1;

		for (x in 0...256)
		{
			var r = x;

			while (index < lastIndex - 1 && r > ratios[index + 1])
				index++;

			var r0 = ratios[index];
			var r1 = ratios[index + 1];
			var c0 = colors[index];
			var c1 = colors[index + 1];
			var a0 = alphas[index];
			var a1 = alphas[index + 1];
			var f = (r - r0) / (r1 - r0);
			var aa = Std.int((a0 * 255 * (1 - f)) + (a1 * 255 * f));
			var rr = Std.int(((c0 >> 16 & 0xFF) * (1 - f)) + ((c1 >> 16 & 0xFF) * f));
			var gg = Std.int(((c0 >> 8 & 0xFF) * (1 - f)) + ((c1 >> 8 & 0xFF) * f));
			var bb = Std.int(((c0 & 0xFF) * (1 - f)) + ((c1 & 0xFF) * f));

			pixels.writeUnsignedInt((aa << 24) | (rr << 16) | (gg << 8) | bb);
		}

		pixels.position = 0;
		var rect = Rectangle.__pool.get();
		rect.setTo(0, 0, 256, 1);
		bmd.setPixels(rect, pixels);
		Rectangle.__pool.release(rect);

		bitmapCache.set(hash, bmd);
		bitmapCacheKeys.push(hash);

		if (bitmapCacheKeys.length > MAX_GRADIENTS)
		{
			var old = bitmapCacheKeys.shift();
			bitmapCache.remove(old);
		}

		return bmd;
	}

	public function copyFrom(other:Gradient)
	{
		setTo(other.colors, other.alphas, other.ratios, other.matrix, other.type, other.interpolationMethod, other.spreadMethod, other.focalPointRatio);
	}

	public function equals(other:Gradient):Bool
	{
		return arrayEquals(colors, other.colors)
			&& arrayEquals(alphas, other.alphas)
			&& arrayEquals(ratios, other.ratios)
			&& matrix.equals(other.matrix)
			&& type == other.type
			&& interpolationMethod == other.interpolationMethod
			&& spreadMethod == other.spreadMethod
			&& focalPointRatio == other.focalPointRatio;
	}

	private static function __equals(g1:Gradient, g2:Gradient):Bool
	{
		if (g1 == g2) return true;
		if (g1 == null || g2 == null) return false;
		return g1.equals(g2);
	}

	public function getHash():String
	{
		return colors.join(",") + ":" + alphas.join(",") + ":" + ratios.join(",") + ":" + matrix.toString() + ":" + type + ":" + interpolationMethod + ":"
			+ focalPointRatio + ":" + spreadMethod;
	}

	static private inline function arrayEquals<T>(a1:Array<T>, a2:Array<T>)
	{
		for (i in 0...a1.length)
		{
			if (a1[i] != a2[i]) return false;
		}
		return true;
	}

	static private inline function matrixEquals(m1:Matrix, m2:Matrix)
	{
		return m1.equals(m2);
	}
}
