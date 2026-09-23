package openfl.utils._internal;

import haxe.io.Bytes;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.geom.Point;
import openfl.geom.ColorTransform;

abstract FastHash(Int) from Int to Int
{
	private static var __bytes:Bytes;

	static inline var FNV_OFFSET_BASIS:Int = -2128831035;
	static inline var FNV_PRIME:Int = 16777619;

	// Distinguishes null from actual data.
	static inline var NULL_MARKER:Int = 0;

	private static function __init__():Void
	{
		__bytes = Bytes.alloc(8);
	}

	public inline function new()
	{
		this = FNV_OFFSET_BASIS;
	}

	public inline function clear()
	{
		this = FNV_OFFSET_BASIS;
	}

	public inline function addNull():FastHash
	{
		return __addByte(NULL_MARKER);
	}

	// Helper: add a single byte
	private inline function __addByte(b:Int):FastHash
	{
		this = (this ^ (b & 0xFF)) * FNV_PRIME;
		this &= 0xFFFFFFFF;
		return this;
	}

	@:op(A += B)
	public inline function addString(s:Null<String>):FastHash
	{
		if (s == null) return addNull();

		var bytes = Bytes.ofString(s);
		this = __addBytes(bytes, 0, bytes.length);
		return this;
	}

	@:op(A += B)
	public inline function addInt(v:Int):FastHash
	{
		var n = v;
		this = __addByte(n & 0xFF);
		n >>= 8;
		this = __addByte(n & 0xFF);
		n >>= 8;
		this = __addByte(n & 0xFF);
		n >>= 8;
		this = __addByte(n & 0xFF);
		return this;
	}

	@:op(A += B)
	public inline function addFloat(v:Float):FastHash
	{
		__bytes.setDouble(0, v);
		__addBytes(__bytes, 0, 8);
		return this;
	}

	@:op(A += B)
	public inline function addBool(v:Bool):FastHash
	{
		return __addByte(v ? 1 : 0);
	}

	@:op(A += B)
	public inline function addEnum(e:Null<EnumValue>):FastHash
	{
		if (e == null) return addNull();

		addInt(Type.enumIndex(e));
		return this;
	}

	@:op(A += B)
	public inline function addHash(other:FastHash):FastHash
	{
		addInt(cast other);
		return this;
	}

	@:op(A += B)
	public inline function addIntArray(other:Null<Array<Int>>):FastHash
	{
		if (other == null) return addNull();

		for (i in other)
			addInt(i);

		return this;
	}

	@:op(A += B)
	public inline function addFloatArray(other:Null<Array<Float>>):FastHash
	{
		if (other == null) return addNull();

		for (i in other)
			addFloat(i);

		return this;
	}

	@:op(A += B)
	public inline function addMatrix(other:Null<Matrix>):FastHash
	{
		if (other == null) return addNull();

		addFloat(other.a);
		addFloat(other.b);
		addFloat(other.c);
		addFloat(other.d);
		addFloat(other.tx);
		addFloat(other.ty);
		return this;
	}

	@:op(A += B)
	public inline function addRectangle(other:Null<Rectangle>):FastHash
	{
		if (other == null) return addNull();

		addFloat(other.x);
		addFloat(other.y);
		addFloat(other.width);
		addFloat(other.height);
		return this;
	}

	@:op(A += B)
	public inline function addPoint(other:Null<Point>):FastHash
	{
		if (other == null) return addNull();

		addFloat(other.x);
		addFloat(other.y);
		return this;
	}

	@:op(A += B)
	public inline function addColorTransform(other:Null<ColorTransform>):FastHash
	{
		if (other == null) return addNull();

		addFloat(other.redMultiplier);
		addFloat(other.greenMultiplier);
		addFloat(other.blueMultiplier);
		addFloat(other.alphaMultiplier);
		addFloat(other.redOffset);
		addFloat(other.greenOffset);
		addFloat(other.blueOffset);
		addFloat(other.alphaOffset);
		return this;
	}

	private inline function __addBytes(bytes:Bytes, offset:Int, length:Int):FastHash
	{
		var end = offset + length;

		for (i in offset...end)
			__addByte(bytes.get(i));

		return this;
	}

	public inline function toString():String
	{
		return '0x' + StringTools.hex(this, 8);
	}
}
